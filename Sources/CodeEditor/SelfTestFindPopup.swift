import AppKit

/// CE_SELFTEST: the floating Find / Replace in Files popup (query -> results, options, cap, replace one / all, keys, hand-off).
/// Searches complete on the main queue, which the harness occupies, so the checks are a chain of steps that continue from
/// each search's completion callback.
enum SelfTestFindPopup {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("find popup: " + name, ok()) }

    private static func key(_ code: UInt16, _ chars: String, _ mods: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    private typealias Step = (@escaping () -> Void) -> Void

    static func run(w: ProjectWindow, then finish: @escaping () -> Void) {
        do {   // always-excluded files and folders (Prefs.findExcludes) become !patterns of the mask
            let m = FindGlobMask(FindGlobMask.merged("*.php", excludes: ".phpunit.result.cache, storage/logs"))
            SelfTest.check("find excludes: a listed dotfile is never searched", !FindGlobMask(FindGlobMask.merged("", excludes: ".phpunit.result.cache")).allows(".phpunit.result.cache")
                           && !FindGlobMask(FindGlobMask.merged("", excludes: ".phpunit.result.cache")).allows("tests/.phpunit.result.cache"))
            SelfTest.check("find excludes: a listed folder is skipped, other files stay", !m.allows("storage/logs/a.php") && m.allows("app/Models/User.php"))
            SelfTest.check("find excludes: merged text keeps the user's mask", FindGlobMask.merged("*.php", excludes: "a, b") == "*.php, !a, !b" && FindGlobMask.merged("", excludes: "") == "")
        }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ce-findpopup-\(getpid())")
        try? fm.createDirectory(at: dir.appendingPathComponent("src"), withIntermediateDirectories: true)
        func put(_ rel: String, _ text: String) { try? text.write(to: dir.appendingPathComponent(rel), atomically: true, encoding: .utf8) }
        put("src/a.txt", "one\nalpha foo beta\nthree\nFOO upper\n")
        put("src/b.vue", "<template>\n  <div>foo bar</div>\n  <p>food foo</p>\n</template>\n")
        put("src/c.php", "<?php\n$x = 'foo';\n")
        put("big.txt", (0..<150).map { "needle \($0)" }.joined(separator: "\n") + "\n")
        for i in 0..<3 { put("src/many\(i).txt", (0..<60).map { _ in "needle x" }.joined(separator: "\n") + "\n") }

        var opened: [FindMatch] = []
        var handedOff: (FindOptions, String?, Bool)?
        let engine = FindEngine(root: dir, files: { [] })
        let host = FindPopupHost(root: dir, engine: engine, openBuffer: { _ in nil },
                                 openMatch: { opened.append($0) }, openFilePaths: { [dir.appendingPathComponent("src/c.php").path] },
                                 openInFindWindow: { handedOff = ($0, $1, $2) })
        func read(_ rel: String) -> String { (try? String(contentsOf: dir.appendingPathComponent(rel))) ?? "" }

        var p: FindPopup!
        /// Runs `action` (which starts a search) and continues when the results are in.
        func searching(_ action: @escaping () -> Void) -> Step {
            return { next in
                p.onSearchDone = { p.onSearchDone = nil; next() }
                action()
            }
        }
        func opening(seed: String, replace: Bool) -> Step {
            return { next in
                p = FindPopup.present(over: w.window, host: host, seed: seed, replace: replace)
                p.onSearchDone = { p.onSearchDone = nil; next() }
            }
        }
        func plain(_ action: @escaping () -> Void) -> Step { return { next in action(); next() } }

        var steps: [Step] = []
        steps.append(opening(seed: "foo", replace: false))
        steps.append(plain {
            check("opens in find mode with title", FindPopup.isOpen && p.testTitle == "Find in Files" && !p.testReplaceBoxVisible)
            // case-insensitive literal: a.txt (foo + FOO), b.vue (foo, food, foo), c.php (foo)
            check("seed query gives results", p.results.count == 6)
            check("status text counts matches and files", p.statusText == "6 matches in 3 files")
            check("first row selected, preview shows its file", p.selectedRow == 0 && p.testPathLabel == "src/a.txt" && p.testPreviewText.contains("alpha foo beta"))
        })
        steps.append(searching { p.testToggle("case") })
        steps.append(plain { check("Match case narrows results", p.results.count == 5 && !p.results.contains { $0.lineText.contains("FOO") }) })
        steps.append(searching { p.testToggle("word") })
        steps.append(plain { check("Words excludes 'food'", p.results.count == 4) })
        steps.append(searching { p.testToggle("case"); p.testToggle("word"); p.testType("fo+"); p.testToggle("regex") })
        steps.append(plain { check("Regex toggle matches pattern", p.results.count >= 6) })
        steps.append(searching { p.testType("(") })
        steps.append(plain {
            check("bad regex shows an error, no results", p.results.isEmpty && !p.statusText.isEmpty && p.statusText != "No matches")
            p.testToggle("regex")
        })
        steps.append(searching { p.testType("foo"); p.testSetMask("*.vue") })
        steps.append(plain { check("file mask filters", !p.results.isEmpty && p.results.allSatisfy { $0.url.pathExtension == "vue" }) })
        steps.append(searching { p.testSetMask(nil); p.testSelectTab(3) })
        steps.append(plain { check("Scope tab limits to open files", !p.results.isEmpty && p.results.allSatisfy { $0.url.lastPathComponent == "c.php" }) })
        steps.append(searching { p.testSelectTab(2); p.testSetDirectory(dir.appendingPathComponent("src")); p.testType("needle") })
        steps.append(plain { check("Directory tab searches the chosen folder only", !p.results.isEmpty && p.results.allSatisfy { $0.url.path.contains("/src/") }) })
        steps.append(searching { p.testSelectTab(0) })
        steps.append(plain {
            check("status caps at 100+", p.statusText.hasPrefix("100+ matches in ") && p.statusText.contains("+ file"))
            check("list is capped", p.results.count <= FindPopup.listCap && p.results.count > 100)
        })

        // keyboard
        steps.append(searching { p.testType("foo") })
        steps.append(plain {
            _ = p.testKey(#selector(NSResponder.moveDown(_:)))
            check("Down moves the selection while focus stays in the query", p.selectedRow == 1)
            _ = p.testKey(#selector(NSResponder.moveUp(_:)))
            _ = p.testKey(#selector(NSResponder.moveUp(_:)))
            check("Up stops at the first row", p.selectedRow == 0)
            _ = p.testPerformKey(key(15, "R", [.command, .shift]))
            check("Cmd-Shift-R switches to replace mode", p.replaceMode && p.testTitle == "Replace in Files" && p.testReplaceBoxVisible)
            _ = p.testPerformKey(key(36, "\r", .command))
            check("Cmd-Return hands query and options to the Find window", handedOff?.0.query == "foo" && handedOff?.2 == true && !FindPopup.isOpen)
        })

        // Return opens the match and closes
        steps.append(opening(seed: "alpha", replace: false))
        steps.append { next in
            _ = p.testKey(#selector(NSResponder.insertNewline(_:)))
            check("Return closes the popup", !FindPopup.isOpen)
            DispatchQueue.main.async {
                check("Return opens the selected match", opened.last?.line == 2 && opened.last?.url.lastPathComponent == "a.txt")
                next()
            }
        }

        // pin keeps it open when opening a match
        steps.append(opening(seed: "alpha", replace: false))
        steps.append(plain {
            p.testToggle("pin")
            _ = p.testKey(#selector(NSResponder.insertNewline(_:)))
            check("pinned popup stays open after opening a match", FindPopup.isOpen && p.testPinned)
            p.testToggle("pin")
            FindPopup.dismiss()
            check("dismiss closes", !FindPopup.isOpen)
        })

        // Replace one
        var before = 0
        steps.append(opening(seed: "foo", replace: true))
        steps.append(searching { p.testToggle("case"); p.testSetReplacement("bar") })
        steps.append { next in
            check("replace mode shows replace field", p.replaceMode && p.testReplaceBoxVisible)
            before = p.results.count
            p.replaceSelected { next() }
        }
        steps.append(plain {
            check("Replace changes only the selected match", read("src/a.txt").contains("alpha bar beta") && read("src/b.vue").contains("foo bar") && read("src/c.php").contains("'foo'"))
            check("replaced match leaves the list", p.results.count == before - 1)
        })
        steps.append(searching {
            let undo = engine.undoLastReplace()
            check("replace one can be undone via the engine", undo.restored == 1 && read("src/a.txt").contains("alpha foo beta"))
            p.testType("foo")
        })

        // Replace all
        steps.append { next in p.replaceAll(confirm: false) { next() } }
        steps.append(plain {
            check("Replace All rewrites every match", read("src/a.txt").contains("alpha bar beta") && read("src/b.vue").contains("<div>bar bar</div>")
                  && read("src/c.php").contains("'bar'") && read("src/a.txt").contains("FOO upper"))
            check("Replace All empties the results", p.results.isEmpty)
            FindPopup.dismiss()
            check("Preserve case adapts replacement casing",
                  FindEngine.adaptCase("qux", to: "BAR") == "QUX" && FindEngine.adaptCase("qux", to: "Bar") == "Qux" && FindEngine.adaptCase("qux", to: "bar") == "qux")
        })
        steps.append(opening(seed: "bar", replace: true))
        steps.append(searching { p.testSetReplacement("qux"); p.testToggle("preserve") })
        steps.append { next in p.replaceAll(confirm: false) { next() } }
        steps.append(plain {
            check("Preserve case applies on Replace All", read("src/a.txt").contains("alpha qux beta"))
            FindPopup.dismiss()
            // Wiring: Cmd-Shift-F opens the popup, Cmd-Shift-R from it switches mode
            w.showFind(replace: false)
            check("showFind opens the popup", FindPopup.isOpen && !FindPopup.isReplaceMode)
            w.showFind(replace: true)
            check("showFind(replace:) from the popup switches to replace mode", FindPopup.isReplaceMode)
            FindPopup.dismiss()
            check("bottom Find panel is still registered", w.hasToolPanel("find"))
            try? fm.removeItem(at: dir)
        })

        func go(_ i: Int) {
            guard i < steps.count else { finish(); return }
            steps[i]({ go(i + 1) })
        }
        go(0)
    }
}
