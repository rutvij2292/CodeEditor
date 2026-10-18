import AppKit

/// CE_SELFTEST=1: headless checks of project-window logic; prints PASS/FAIL lines and exits non-zero on failure.
enum SelfTest {
    static var failures = 0

    static func check(_ name: String, _ ok: @autoclosure () -> Bool) {
        let result = ok()
        if !result { failures += 1 }
        fputs((result ? "PASS " : "FAIL ") + name + "\n", stderr)
    }

    static func run(app: AppDelegate) {
        guard AppEnv.value("CE_SELFTEST") != nil else { return }
        DispatchQueue.main.async { runChecks(app: app) }
    }

    static func finish() -> Never {
        fputs(failures == 0 ? "ALL PASSED\n" : "\(failures) FAILED\n", stderr)
        exit(failures == 0 ? 0 : 1)
    }

    private static func runChecks(app: AppDelegate) {
        let fm = FileManager.default
        LocalHistory.root = fm.temporaryDirectory.appendingPathComponent("ce-selftest-history-\(getpid())")
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
        check("edit marks tab dirty", editor.isDirty && w.tabs.entries.first { $0.id == w.tabs.selectedID }?.isDirty == true)
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
            humpSearchChecks(in: fm.temporaryDirectory.appendingPathComponent("ce-hump-\(getpid())")) {
                laterChecks(w: w, a: a, dir: dir)
                projectChecks(app: app, w: w, dir: dir) {
                    fastTierChecks()
                    try? fm.removeItem(at: dir)
                    try? fm.removeItem(at: LocalHistory.root)
                    SelfTestPerf.run(app: app)
                    finish()
                }
            }
        }
    }

    /// Go to File ranking like PhpStorm: camel-hump queries match file NAMES (TaController -> TaTrackController), app code beats tests/docs.
    private static func humpSearchChecks(in root: URL, then next: @escaping () -> Void) {
        let fm = FileManager.default
        let files = ["app/Http/Controllers/TaTrackController.php", "app/Http/Controllers/Auth/LoginController.php",
                     "app/Http/Controllers/UserController.php", "tests/Feature/TaTrackControllerTest.php", "tests/Feature/UserControllerTest.php",
                     "docs/Controllers/TaTrackController.md", "app/Services/TaTrackService.php", "app/Models/TaTrack.php",
                     "app/Http/Controllers/TemporaryWorkplanEvaluationExportController.php", "resources/js/Pages/TaTrack/Index.vue"]
        for rel in files {
            let url = root.appendingPathComponent(rel)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data())
        }
        let index = ProjectIndex(root: root)
        index.refresh(force: true) {
            func top(_ q: String) -> String? { index.search(q, limit: 3).first?.path }
            check("camel hump: TaController -> TaTrackController.php", top("TaController") == "app/Http/Controllers/TaTrackController.php")
            check("camel hump: TaTrackCont ranks app above tests/docs", top("TaTrackCont") == "app/Http/Controllers/TaTrackController.php")
            check("lowercase prefix: tatrackserv", top("tatrackserv") == "app/Services/TaTrackService.php")
            check("hump initials: wpevalexp", top("wpevalexp") == "app/Http/Controllers/TemporaryWorkplanEvaluationExportController.php")
            check("TaController finds the tests too, after the app file",
                  index.search("TaController", limit: 5).map(\.path).contains("tests/Feature/TaTrackControllerTest.php"))
            check("no match returns nothing", index.search("zzqx", limit: 5).isEmpty)
            try? fm.removeItem(at: root)
            next()
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

        check("Commit is Cmd-K", shortcut("Commit…") == "⌘K")
        check("Push is Cmd-Shift-K", shortcut("Push…") == "⇧⌘K")

        // Indentation: detection, .editorconfig precedence, tab-stop width.
        let four = "<?php\nclass A\n{\n    function a()\n    {\n        return 1;\n    }\n    function b()\n    {\n        return 2;\n    }\n}\n"
        let two = "{\n  \"a\": {\n    \"b\": {\n      \"c\": 1\n    },\n    \"d\": {\n      \"e\": 2\n    }\n  }\n}\n"
        let tabbed = "<?php\nclass A\n{\n\tfunction a()\n\t{\n\t\treturn 1;\n\t}\n}\n"
        check("detects 4 spaces", IndentSettings.detect(four) == IndentSettings(useTabs: false, size: 4))
        check("detects 2 spaces", IndentSettings.detect(two) == IndentSettings(useTabs: false, size: 2))
        check("detects tabs", IndentSettings.detect(tabbed)?.useTabs == true)
        check("flat file has no detection", IndentSettings.detect("a\nb\nc\n") == nil)
        let cfgDir = dir.appendingPathComponent("cfg")
        try? FileManager.default.createDirectory(at: cfgDir, withIntermediateDirectories: true)
        try? "root = true\n[*]\nindent_style = space\nindent_size = 2\n[*.php]\nindent_size = 4\n[*.{js,ts}]\nindent_style = tab\ntab_width = 8\n"
            .write(to: cfgDir.appendingPathComponent(".editorconfig"), atomically: true, encoding: .utf8)
        check("editorconfig php=4 spaces", IndentSettings.resolve(for: cfgDir.appendingPathComponent("a.php"), text: two) == IndentSettings(useTabs: false, size: 4))
        check("editorconfig default=2 spaces", IndentSettings.resolve(for: cfgDir.appendingPathComponent("a.css"), text: four) == IndentSettings(useTabs: false, size: 2))
        check("editorconfig js=tabs width 8", IndentSettings.resolve(for: cfgDir.appendingPathComponent("x.js"), text: four) == IndentSettings(useTabs: true, size: 8))
        check("no config + no signal = 4 spaces", IndentSettings.resolve(for: dir.appendingPathComponent("zz.php"), text: "x\n") == .standard)

        let tabFile = dir.appendingPathComponent("tabbed.php")
        try? tabbed.write(to: tabFile, atomically: true, encoding: .utf8)
        w.open(tabFile)
        if let tabEditor = w.current {
            let column = ("0" as NSString).size(withAttributes: [.font: Theme.font]).width
            let interval = tabEditor.textView.defaultParagraphStyle?.defaultTabInterval ?? 0
            check("tab file uses tabs", tabEditor.indent.useTabs && tabEditor.textView.indentUnit == "\t")
            check("tab stop = 4 columns wide", abs(interval - 4 * column) < 0.01)
            tabEditor.applyIndent(IndentSettings(useTabs: false, size: 2))
            check("switching to 2 spaces updates unit and tab stop",
                  tabEditor.textView.indentUnit == "  " && abs((tabEditor.textView.defaultParagraphStyle?.defaultTabInterval ?? 0) - 2 * column) < 0.01)
        } else { check("tab file opened", false) }

        RecentFiles.add(a, in: dir)
        check("recent projects not persisted in headless mode", !RecentProjects.all.contains(dir))
    }

    static func shortcut(_ title: String) -> String {
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
