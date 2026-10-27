import Foundation

/// CE_SELFTEST: Claude Data (scan of a fake ~/.claude, titles, activity flag, smart selections, removal through an injected trasher).
enum SelfTestClaudeData {
    static func run() {
        func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("ce-claudedata-\(ProcessInfo.processInfo.processIdentifier)")
        try? fm.removeItem(at: base)
        defer { try? fm.removeItem(at: base) }
        let savedHome = ClaudeData.home, savedTrasher = ClaudeData.trasher
        defer { ClaudeData.home = savedHome; ClaudeData.trasher = savedTrasher }
        ClaudeData.home = base.appendingPathComponent("home/.claude")
        let trash = base.appendingPathComponent("trash")
        try? fm.createDirectory(at: trash, withIntermediateDirectories: true)
        ClaudeData.trasher = { try fm.moveItem(at: $0, to: trash.appendingPathComponent(UUID().uuidString)) }

        let project = base.appendingPathComponent("My Project.v2")
        try? fm.createDirectory(at: project.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        try? "{}".write(to: project.appendingPathComponent(".claude/settings.local.json"), atomically: true, encoding: .utf8)
        let name = ClaudeData.projectDirName(for: project.path)
        check("claude data: folder name replaces every non-alphanumeric character", !name.contains("/") && !name.contains(".") && !name.contains(" ") && name.hasSuffix("My-Project-v2"))
        let dir = ClaudeData.home.appendingPathComponent("projects/\(name)")
        try? fm.createDirectory(at: dir.appendingPathComponent("memory"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: dir.appendingPathComponent("s-old"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: ClaudeData.home.appendingPathComponent("file-history/s-old"), withIntermediateDirectories: true)
        try? String(repeating: "x", count: 5000).write(to: ClaudeData.home.appendingPathComponent("file-history/s-old/h"), atomically: true, encoding: .utf8)
        func transcript(_ id: String, _ prompt: String, daysAgo: Double, pad: Int = 0) {
            let line1 = "{\"type\":\"mode\",\"mode\":\"normal\"}\n"
            let line2 = "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"<command-name>/clear</command-name>\"}}\n"
            let line3 = "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"\(prompt)\"}}\n" + String(repeating: "y", count: pad)
            let u = dir.appendingPathComponent(id + ".jsonl")
            try? (line1 + line2 + line3).write(to: u, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(-daysAgo * 86400)], ofItemAtPath: u.path)
        }
        transcript("s-old", "Fix the breadcrumb bar", daysAgo: 40, pad: 20_000)
        transcript("s-mid", "Add a jump menu", daysAgo: 10)
        transcript("s-now", "Currently running", daysAgo: 0)
        try? "# memory".write(to: dir.appendingPathComponent("memory/MEMORY.md"), atomically: true, encoding: .utf8)

        let snap = ClaudeData.scan(projectRoot: project)
        check("claude data: sessions are listed newest first", snap.sessions.map(\.id) == ["s-now", "s-mid", "s-old"])
        check("claude data: title is the first real prompt, not a command tag", snap.sessions.last?.title == "Fix the breadcrumb bar")
        check("claude data: a transcript touched just now is active", snap.sessions.first?.isActive == true && snap.sessions.last?.isActive == false)
        check("claude data: a session counts its subfolder and file-history", (snap.sessions.last?.urls.count ?? 0) == 3 && (snap.sessions.last?.bytes ?? 0) > 20_000)
        check("claude data: memory and the project's .claude folder are listed apart", snap.memory.map(\.name) == ["MEMORY.md"] && snap.local.map(\.name) == ["settings.local.json"])
        check("claude data: older-than selects only the old session", ClaudeData.olderThan(30, in: snap.sessions) == ["s-old"] && ClaudeData.olderThan(7, in: snap.sessions) == ["s-old", "s-mid"])
        check("claude data: all-but-newest never selects an active session", ClaudeData.allButNewest(0, in: snap.sessions) == ["s-mid", "s-old"])
        check("claude data: size filter", ClaudeData.largerThan(1, in: snap.sessions).isEmpty)
        if let out = AppEnv.value("CE_CLAUDEDATA_PNG") {
            var s = snap
            s.sessions[0].isActive = true
            ClaudeDataWindowController.render(s, picked: ["s-old", "s-mid"], to: out)
        }
        let res = ClaudeData.remove(sessions: snap.sessions.filter { $0.id == "s-old" })
        check("claude data: removal moves transcript, subfolder and side data to the trash", res.failed.isEmpty && res.freed > 20_000
              && !fm.fileExists(atPath: dir.appendingPathComponent("s-old.jsonl").path) && !fm.fileExists(atPath: ClaudeData.home.appendingPathComponent("file-history/s-old").path)
              && fm.fileExists(atPath: dir.appendingPathComponent("s-mid.jsonl").path) && fm.fileExists(atPath: dir.appendingPathComponent("memory/MEMORY.md").path))
    }
}
