import Foundation

/// Multi-instance logic: launch-argument parsing, the project registry (liveness, stale PIDs, primary role),
/// merge-safe recents and the Claude bridge's stale-lock handling across processes. No second process is started.
enum SelfTestInstances {
    /// A PID that existed and is gone.
    private static func deadPID() -> pid_t {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try? p.run()
        p.waitUntilExit()
        return p.processIdentifier
    }

    static func run() {
        let check = SelfTest.check
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("ce-instances-\(getpid())")
        try? fm.removeItem(at: tmp)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // Launch arguments
        let a = LaunchArguments.parse(["--project", "/tmp/a", "-NSDocumentRevisionsDebugMode", "/tmp/b", "--project=/tmp/c", "--project", "/tmp/a"], cwd: "/")
        check("args: --project values", a.projects.map(\.path) == ["/tmp/a", "/tmp/c"] && a.isProjectLaunch)
        check("args: plain paths kept, dash flags ignored", a.paths.map(\.path) == ["/tmp/b"])
        let rel = LaunchArguments.parse(["--project", "proj/x"], cwd: "/var")
        check("args: relative path resolves against cwd", rel.projects.first?.path == "/var/proj/x")
        check("args: dangling --project ignored", LaunchArguments.parse(["--project"]).projects.isEmpty)
        check("args: none is not a project launch", !LaunchArguments.parse([]).isProjectLaunch)

        // Launch command
        let app = InstanceLauncher.command(bundleURL: URL(fileURLWithPath: "/Applications/Kode.app"), executable: "/x/Kode", project: URL(fileURLWithPath: "/p/q"))
        check("launch: bundle uses open -n", app.path == "/usr/bin/open" && app.args == ["-n", "-a", "/Applications/Kode.app", "--args", "--project", "/p/q"])
        let bare = InstanceLauncher.command(bundleURL: URL(fileURLWithPath: "/x/.build/debug"), executable: "/x/.build/debug/Kode", project: URL(fileURLWithPath: "/p/q"))
        check("launch: bare binary gets --project", bare.path == "/x/.build/debug/Kode" && bare.args == ["--project", "/p/q"])

        // Registry
        let savedDir = InstanceRegistry.directory, savedPID = InstanceRegistry.pid
        InstanceRegistry.directory = tmp.appendingPathComponent("instances")
        InstanceRegistry.forceEnabled = true
        let me = savedPID
        let root = URL(fileURLWithPath: "/tmp/ce-proj-one")
        check("registry: unclaimed project has no owner", InstanceRegistry.owner(of: root) == nil)
        check("registry: claim succeeds", InstanceRegistry.claim(root) == .claimed)
        check("registry: own claim is not 'another instance'", InstanceRegistry.owner(of: root) == nil)
        check("registry: re-claim by same process is fine", InstanceRegistry.claim(root) == .claimed)

        InstanceRegistry.pid = 1                      // launchd: alive (EPERM), plays another instance
        check("registry: live foreign owner is detected", InstanceRegistry.owner(of: root) == me)
        check("registry: claim loses to live owner", InstanceRegistry.claim(root) == .heldBy(me))
        InstanceRegistry.release(root)                // not ours: no effect
        InstanceRegistry.pid = me
        check("registry: release by non-owner leaves entry", InstanceRegistry.claim(root) == .claimed
              && InstanceRegistry.liveProjects()[root.path] == me)

        InstanceRegistry.release(root)
        InstanceRegistry.pid = 1
        check("registry: released project is free again", InstanceRegistry.owner(of: root) == nil)
        check("registry: other instance can claim it", InstanceRegistry.claim(root) == .claimed)
        InstanceRegistry.pid = me
        check("registry: we see the other instance as owner", InstanceRegistry.owner(of: root) == 1)
        check("registry: we cannot take it", InstanceRegistry.claim(root) == .heldBy(1))

        // Stale PID
        let dead = deadPID()
        check("registry: dead pid is not alive", !InstanceRegistry.isAlive(dead) && InstanceRegistry.isAlive(me))
        InstanceRegistry.pid = 1
        InstanceRegistry.release(root)
        InstanceRegistry.pid = dead
        let root2 = URL(fileURLWithPath: "/tmp/ce-proj-two")
        InstanceRegistry.claim(root2)
        InstanceRegistry.pid = me
        check("registry: stale owner is ignored and cleaned", InstanceRegistry.owner(of: root2) == nil)
        check("registry: stale entry removed from listing", InstanceRegistry.liveProjects()[root2.path] == nil)
        InstanceRegistry.pid = dead
        InstanceRegistry.claim(root2)
        InstanceRegistry.pid = me
        check("registry: stale claim is taken over", InstanceRegistry.claim(root2) == .claimed)
        InstanceRegistry.releaseAll()
        check("registry: releaseAll frees own claims", InstanceRegistry.liveProjects().isEmpty)

        // Primary role (owns session restore)
        check("primary: first process becomes primary", InstanceRegistry.claimPrimary())
        InstanceRegistry.pid = 1
        check("primary: second live instance is not primary", !InstanceRegistry.claimPrimary())
        InstanceRegistry.pid = me
        InstanceRegistry.releasePrimary()
        InstanceRegistry.pid = dead
        _ = InstanceRegistry.claimPrimary()
        InstanceRegistry.pid = me
        check("primary: a crashed primary is taken over", InstanceRegistry.claimPrimary())
        InstanceRegistry.releasePrimary()
        InstanceRegistry.directory = savedDir
        InstanceRegistry.pid = savedPID
        InstanceRegistry.forceEnabled = false

        // Merge-safe recents
        check("recents: merge moves to front and dedupes", RecentProjects.merged(["/a", "/b", "/c"], adding: "/b") == ["/b", "/a", "/c"])
        check("recents: merge caps the list", RecentProjects.merged((0..<15).map { "/p\($0)" }, adding: "/new").count == RecentProjects.limit)
        let suiteName = "ce-selftest-recents-\(getpid())"
        let suite = UserDefaults(suiteName: suiteName)!
        let savedStore = RecentProjects.store, savedLock = RecentProjects.lockURL
        RecentProjects.store = suite
        RecentProjects.lockURL = tmp.appendingPathComponent("recents.lock")
        RecentProjects.forceEnabled = true
        var dirs: [URL] = []
        for i in 0..<10 {
            let d = tmp.appendingPathComponent("r\(i)")
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
            dirs.append(d)
        }
        DispatchQueue.concurrentPerform(iterations: dirs.count) { RecentProjects.add(dirs[$0]) }
        check("recents: concurrent adds all survive", Set(RecentProjects.all.map(\.path)) == Set(dirs.map(\.path)))
        // A writer holding a stale snapshot must not clobber another instance's later entry.
        suite.set(["/elsewhere"] + (suite.stringArray(forKey: "recentProjects") ?? []), forKey: "recentProjects")
        RecentProjects.add(dirs[0])
        check("recents: add re-reads stored list", (suite.stringArray(forKey: "recentProjects") ?? []).contains("/elsewhere"))
        RecentProjects.clear()
        check("recents: clear empties", RecentProjects.all.isEmpty)
        RecentProjects.store = savedStore
        RecentProjects.lockURL = savedLock
        RecentProjects.forceEnabled = false
        UserDefaults.standard.removePersistentDomain(forName: suiteName)

        // Claude bridge: stale-lock sweep must keep another LIVE instance's lock and drop only dead ones.
        let savedLockDir = ClaudeBridge.lockDirectory
        let lockDir = tmp.appendingPathComponent("ide")
        try? fm.createDirectory(at: lockDir, withIntermediateDirectories: true)
        ClaudeBridge.lockDirectory = lockDir
        func lock(_ name: String, pid: Int, ide: String = ClaudeBridge.ideName) {
            let body: [String: Any] = ["pid": pid, "workspaceFolders": ["/x"], "ideName": ide, "transport": "ws", "authToken": "t"]
            try? JSONSerialization.data(withJSONObject: body).write(to: lockDir.appendingPathComponent(name))
        }
        lock("11111.lock", pid: 1)
        lock("22222.lock", pid: Int(dead))
        lock("33333.lock", pid: Int(dead), ide: "SomeOtherIDE")
        ClaudeBridge.removeStaleLocks()
        check("bridge: live instance's lock kept", fm.fileExists(atPath: lockDir.appendingPathComponent("11111.lock").path))
        check("bridge: dead instance's lock removed", !fm.fileExists(atPath: lockDir.appendingPathComponent("22222.lock").path))
        check("bridge: other IDEs' locks untouched", fm.fileExists(atPath: lockDir.appendingPathComponent("33333.lock").path))
        ClaudeBridge.lockDirectory = savedLockDir
    }
}
