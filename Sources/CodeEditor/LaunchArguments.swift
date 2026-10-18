import AppKit

/// Command-line arguments Kode understands: `--project <path>` (or `--project=<path>`) opens exactly that folder.
/// Any other non-dash argument is a path to open (legacy behaviour); dash arguments (Cocoa flags) are ignored.
struct LaunchArguments: Equatable {
    var projects: [URL] = []
    var paths: [URL] = []

    /// Launched for one specific project (typically "Open Project in New Instance"): this process is a secondary instance.
    var isProjectLaunch: Bool { !projects.isEmpty }

    /// `args` excludes argv[0]. Relative paths resolve against `cwd`; `~` expands.
    static func parse(_ args: [String], cwd: String = FileManager.default.currentDirectoryPath) -> LaunchArguments {
        var result = LaunchArguments()
        func url(_ s: String) -> URL {
            let p = (s as NSString).expandingTildeInPath
            return URL(fileURLWithPath: p, relativeTo: URL(fileURLWithPath: cwd, isDirectory: true)).standardizedFileURL
        }
        func add(_ u: URL, to list: inout [URL]) { if !list.contains(u) { list.append(u) } }
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--project" {
                if i + 1 < args.count { add(url(args[i + 1]), to: &result.projects); i += 1 }
            } else if a.hasPrefix("--project=") {
                let v = String(a.dropFirst("--project=".count))
                if !v.isEmpty { add(url(v), to: &result.projects) }
            } else if !a.hasPrefix("-") {
                add(url(a), to: &result.paths)
            }
            i += 1
        }
        return result
    }

    static let current = parse(Array(CommandLine.arguments.dropFirst()))
}

/// Starts another Kode process for a project, or brings the instance that already has it to the front.
enum InstanceLauncher {
    /// Posted (distributed) so the owning instance raises the project's window.
    static let focusNotification = Notification.Name("com.teccel.CodeEditor.focusProject")

    /// `open -n -a Kode.app --args --project <path>` for a real bundle; the bare executable when run from `.build`.
    static func command(bundleURL: URL, executable: String, project: URL) -> (path: String, args: [String]) {
        if bundleURL.pathExtension == "app" {
            return ("/usr/bin/open", ["-n", "-a", bundleURL.path, "--args", "--project", project.path])
        }
        return (executable, ["--project", project.path])
    }

    @discardableResult
    static func launch(project: URL) -> Bool {
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let c = command(bundleURL: Bundle.main.bundleURL, executable: exe, project: project.standardizedFileURL)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: c.path)
        p.arguments = c.args
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); return true } catch { fputs("launch new instance failed: \(error)\n", stderr); return false }
    }

    /// Activates the owning process and asks it to raise the window for `project`.
    static func focus(pid: pid_t, project: URL) {
        NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
        DistributedNotificationCenter.default().postNotificationName(focusNotification, object: nil,
                                                                     userInfo: ["path": project.standardizedFileURL.path],
                                                                     deliverImmediately: true)
    }
}

extension AppDelegate {
    /// Decides whether `url` should open somewhere other than a new window here: focuses it when another instance already
    /// has it, or starts a new instance (forced, or when the "Open projects in" setting says so and this one is busy).
    /// Returns true when handled; false means "open it in this process as usual".
    func routeProject(_ url: URL, forceNewInstance: Bool = false) -> Bool {
        let url = url.standardizedFileURL
        if let w = windows.first(where: { $0.root == url }) {
            guard forceNewInstance else { return false }
            if !AppEnv.headless { w.window.makeKeyAndOrderFront(nil) }
            return true
        }
        if let pid = InstanceRegistry.owner(of: url) { InstanceLauncher.focus(pid: pid, project: url); return true }
        let busy = windows.contains { $0.root != nil }
        if forceNewInstance || (Prefs.openProjectsIn == "new" && busy) { return InstanceLauncher.launch(project: url) }
        return false
    }

    /// User-driven open (panel, recents, Finder): honours instance routing.
    func openProjectRouted(_ url: URL) {
        if !routeProject(url) { openProject(url) }
    }

    func openProjectInNewInstance(_ url: URL) {
        if !routeProject(url, forceNewInstance: true) { openProject(url) }
    }

    @objc func openProjectInNewInstancePanel(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open in New Instance"
        if panel.runModal() == .OK, let url = panel.url { openProjectInNewInstance(url) }
    }

    /// Raises the window when another instance asks for a project this process owns.
    func installInstanceSupport() {
        DistributedNotificationCenter.default().addObserver(forName: InstanceLauncher.focusNotification, object: nil, queue: .main) { [weak self] note in
            guard let path = note.userInfo?["path"] as? String,
                  let w = self?.windows.first(where: { $0.root?.path == path }) else { return }
            w.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
