import AppKit

/// CE_SELFTEST=1: headless checks of project-window logic; prints PASS/FAIL lines and exits non-zero on failure.
enum SelfTest {
    private static var failures = 0

    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) {
        let result = ok()
        if !result { failures += 1 }
        fputs((result ? "PASS " : "FAIL ") + name + "\n", stderr)
    }

    static func run(app: AppDelegate) {
        guard AppEnv.value("CE_SELFTEST") != nil else { return }
        DispatchQueue.main.async { runChecks(app: app) }
    }

    private static func finish() -> Never {
        fputs(failures == 0 ? "ALL PASSED\n" : "\(failures) FAILED\n", stderr)
        exit(failures == 0 ? 0 : 1)
    }

    private static func runChecks(app: AppDelegate) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ce-selftest-\(getpid())")
        try? fm.createDirectory(at: dir.appendingPathComponent("app/Http"), withIntermediateDirectories: true)
        let files = ["app/Http/UserController.php": "<?php\nclass UserController {}\n", "app/Cache.php": "<?php\n",
                     "resources/app.js": "const a = 1\n", "style.css": "a { color: red }\n"]
        for (rel, text) in files {
            let url = dir.appendingPathComponent(rel)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }

        let w = app.openProject(dir)
        check("project root set", w.root == dir.standardizedFileURL)
        check("opening same project reuses window", app.openProject(dir) === w)

        let a = dir.appendingPathComponent("app/Http/UserController.php")
        let b = dir.appendingPathComponent("resources/app.js")
        let c = dir.appendingPathComponent("style.css")
        w.open(a); w.open(b); w.open(c)
        check("three tabs open", w.tabs.entries.count == 3)
        check("last opened is selected", w.tabs.selectedID == c.standardizedFileURL.path)
        w.open(a)
        check("reopening selects existing tab", w.tabs.entries.count == 3 && w.tabs.selectedID == a.standardizedFileURL.path)

        w.goBack()
        check("back goes to previous tab", w.tabs.selectedID == c.standardizedFileURL.path)
        w.goBack()
        check("back twice", w.tabs.selectedID == b.standardizedFileURL.path)
        w.goForward()
        check("forward returns", w.tabs.selectedID == c.standardizedFileURL.path)

        w.selectTab(offset: 1)
        check("next tab wraps", w.tabs.selectedID == a.standardizedFileURL.path)
        w.selectTab(offset: -1)
        check("previous tab wraps", w.tabs.selectedID == c.standardizedFileURL.path)

        let editor = w.current!
        editor.textView.string += "/* edit */"
        editor.textView.didChangeText()
        check("edit marks tab dirty", editor.isDirty && w.tabs.entries.first { $0.id == w.tabs.selectedID }?.title.hasPrefix("●") == true)
        editor.save()
        check("save clears dirty and writes disk", !editor.isDirty && ((try? String(contentsOf: c)) ?? "").contains("/* edit */"))

        try? "a { color: blue }\n".write(to: c, atomically: true, encoding: .utf8)
        editor.reloadIfChangedOnDisk()
        check("clean buffer reloads external change", editor.textView.string.contains("blue"))

        w.close(c.standardizedFileURL.path)
        check("close removes tab", w.tabs.entries.count == 2 && w.editors[c.standardizedFileURL.path] == nil)

        let index = ProjectIndex(root: dir)
        // The scan completes on the main queue, which we are occupying: continue from its callback.
        index.refresh(force: true) {
            indexChecks(index)
            laterChecks(w: w, a: a, dir: dir)
            try? fm.removeItem(at: dir)
            finish()
        }
    }

    private static func indexChecks(_ index: ProjectIndex) {
        check("index lists project files", index.files.count == 4)
        check("fuzzy search ranks UserController first", index.search("usercon", limit: 5).first?.path == "app/Http/UserController.php")
        check("fuzzy search subsequence", index.search("ac", limit: 5).contains { $0.path == "app/Cache.php" })
        check("no match returns empty", index.search("zzzq", limit: 5).isEmpty)
    }

    private static func laterChecks(w: ProjectWindow, a: URL, dir: URL) {
        let before = Theme.isDark
        Theme.setMode(.dark); check("dark mode applies", Theme.isDark)
        Theme.setMode(.light); check("light mode applies", !Theme.isDark)
        Theme.setMode(.system); _ = before

        check("menu has expected top-level menus",
              ["File", "Edit", "Code", "Navigate", "View"].allSatisfy { t in NSApp.mainMenu?.items.contains { $0.title == t } == true })
        check("Go to File is Cmd-Shift-O", shortcut("Go to File…") == "⇧⌘O")
        check("Recent Files is Cmd-E", shortcut("Recent Files") == "⌘E")
        check("Duplicate Line is Cmd-D", shortcut("Duplicate Line") == "⌘D")
        check("Find Action is Cmd-Shift-A", shortcut("Find Action…") == "⇧⌘A")
        check("Move Line Up is Opt-Shift-Up", shortcut("Move Line Up") == "⌥⇧↑")
        check("File Structure is Cmd-F12", shortcut("File Structure") == "⌘F12")

        RecentFiles.add(a, in: dir)
        check("recent projects not persisted in headless mode", !RecentProjects.all.contains(dir))
    }

    private static func shortcut(_ title: String) -> String {
        func find(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if item.title == title { return item }
                if let sub = item.submenu, let hit = find(sub) { return hit }
            }
            return nil
        }
        return NSApp.mainMenu.flatMap(find).map(MainMenu.shortcutText(for:)) ?? "missing"
    }
}
