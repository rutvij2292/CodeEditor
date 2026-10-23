import AppKit

/// CE_SELFTEST: Claude prompt composer (tokens, slash scan, history, image paste, keys, send / draft) and Fix with Claude prompts.
enum SelfTestComposer {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("composer: " + name, ok()) }

    private static func key(_ code: UInt16, _ mods: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil,
                         characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
    }

    static func run(w: ProjectWindow) {
        let fm = FileManager.default
        let L = ClaudeComposerLogic.self

        // tokens
        let t1 = L.token(in: "fix @app/Us" as NSString, caret: 11)
        check("@ token", t1 == .file(query: "app/Us", range: NSRange(location: 4, length: 7)))
        check("/ token at start", L.token(in: "/rev" as NSString, caret: 4) == .slash(query: "rev", range: NSRange(location: 0, length: 4)))
        check("/ mid-line is not a command", L.token(in: "a /rev" as NSString, caret: 6) == nil)
        check("/ at line start after newline", L.token(in: "x\n/co" as NSString, caret: 5) == .slash(query: "co", range: NSRange(location: 2, length: 3)))
        check("no token after space", L.token(in: "@a " as NSString, caret: 3) == nil)
        let applied = L.apply("@app/User.php", to: "fix @app/Us now", token: t1!)
        check("apply keeps tail, caret after mention", applied.text == "fix @app/User.php  now".replacingOccurrences(of: "  ", with: " ") || applied.text == "fix @app/User.php now")
        check("apply caret", applied.caret == "fix @app/User.php ".utf16.count)

        // slash scan
        let base = fm.temporaryDirectory.appendingPathComponent("ce-composer-\(getpid())")
        let proj = base.appendingPathComponent("proj"), home = base.appendingPathComponent("home")
        func put(_ url: URL, _ text: String) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        put(proj.appendingPathComponent(".claude/commands/review.md"), "---\ndescription: Review the diff\n---\nBody")
        put(proj.appendingPathComponent(".claude/commands/git/ship.md"), "# Ship it\nmore")
        put(home.appendingPathComponent(".claude/commands/review.md"), "user version")
        put(home.appendingPathComponent(".claude/commands/notes.md"), "Plain first line")
        put(proj.appendingPathComponent(".claude/skills/pdf-tools/SKILL.md"), "---\nname: pdf-tools\ndescription: \"Work with PDFs\"\n---\nx")
        put(home.appendingPathComponent(".claude/skills/graphify/SKILL.md"), "---\nname: graphify\ndescription: Build a graph\n---\n")
        let entries = L.scanSlashEntries(root: proj, home: home)
        let names = entries.map(\.name)
        check("slash names (project wins duplicates, nested = colon)", names == ["git:ship", "graphify", "notes", "pdf-tools", "review"])
        check("frontmatter description", entries.first { $0.name == "review" }?.detail == "Review the diff" && entries.first { $0.name == "review" }?.isProject == true)
        check("heading description", entries.first { $0.name == "git:ship" }?.detail == "Ship it")
        check("plain first line description", entries.first { $0.name == "notes" }?.detail == "Plain first line")
        check("skill description unquoted", entries.first { $0.name == "pdf-tools" }?.detail == "Work with PDFs" && entries.first { $0.name == "pdf-tools" }?.isSkill == true)
        check("slash filter", L.filter(entries, query: "rev").first?.name == "review" && L.filter(entries, query: "").count == 5)
        try? fm.removeItem(at: base)

        // history
        PromptHistory.reset()
        for i in 0..<60 { PromptHistory.push("prompt \(i)") }
        PromptHistory.push("prompt 30")
        check("history capped at 50, newest first, deduped", PromptHistory.entries.count == 50 && PromptHistory.entries[0] == "prompt 30" && PromptHistory.entries.filter { $0 == "prompt 30" }.count == 1)
        PromptHistory.push("   ")
        check("blank not stored", PromptHistory.entries.count == 50)
        var cur = HistoryCursor()
        let h = ["c", "b", "a"]
        check("history up/down walk", cur.step(older: true, entries: h) == "c" && cur.step(older: true, entries: h) == "b" && cur.step(older: false, entries: h) == "c"
              && cur.step(older: false, entries: h) == "" && cur.step(older: false, entries: h) == nil && !cur.browsing)

        // image
        let img = NSImage(size: NSSize(width: 8, height: 8)); img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill(); img.unlockFocus()
        if let png = L.pngData(from: img), let url = L.saveImage(png) {
            check("pasted image saved as png", fm.fileExists(atPath: url.path) && url.pathExtension == "png" && url.path.contains(L.imageDirName) && (try? Data(contentsOf: url))?.starts(with: [0x89, 0x50]) == true)
            try? fm.removeItem(at: url)
        } else { check("pasted image saved as png", false) }

        // Fix with Claude prompts
        let code = (1...30).map { "line \($0)" }.joined(separator: "\n")
        let p = FixWithClaude.problemPrompt(path: "app/A.php", line: 12, column: 5, severity: 1, message: "Undefined variable $x", source: "intelephense", code: "P1008", fileText: code)
        check("problem prompt has file:line:col, message, snippet", p.contains("app/A.php:12:5 error: Undefined variable $x [intelephense P1008]") && p.contains("app/A.php:6-18") && p.contains("line 12") && !p.contains("line 19"))
        let tr = TestResult(name: "test_it", className: "UserTest", file: "/p/tests/UserTest.php", line: 10, status: .failed, message: "Failed asserting that 1 matches 2.\n/p/tests/UserTest.php:15", time: 0.1)
        let tp = FixWithClaude.testPrompt(tr, path: "tests/UserTest.php", fileText: code)
        check("test prompt has name, location, output, snippet", tp.contains("UserTest::test_it") && tp.contains("tests/UserTest.php:15") && tp.contains("Failed asserting") && tp.contains("tests/UserTest.php:9-21"))
        check("snippet clamps to file", FixWithClaude.snippet(of: "a\nb", around: 99)?.text == "a\nb" && FixWithClaude.snippet(of: "a", around: 0) == nil)
        check("terminal selection prompt fences output", FixWithClaude.selectionPrompt("boom ``` x").contains("````"))
        let dp = FixWithClaude.diffReviewPrompt(branch: "feat/x", changes: [], stat: " a.php | 2 +-")
        check("diff prompt names branch and git diff", dp.contains("feat/x") && dp.contains("git diff HEAD") && dp.contains("a.php | 2 +-"))

        // composer popup (headless: panel never becomes key)
        var sent: [String] = []
        var accept = false
        var started: [String] = []
        let host = ClaudeComposerHost(root: w.root ?? base,
                                      searchFiles: { q in q.isEmpty ? ["open/File.php"] : ["app/\(q).php", "my dir/\(q).php"] },
                                      slashEntries: { entries },
                                      send: { sent.append($0); return accept },
                                      startAgentAndSend: { started.append($0) })
        PromptHistory.reset()
        let c = ClaudeComposer.present(over: w.window, host: host, prefill: "@a.php:3-4 ")
        check("opens with prefill", ClaudeComposer.isOpen && c.string == "@a.php:3-4 ")
        c.setString("see @Us"); c.testCaretToEnd(); c.setString("see @Us")
        check("@ lists files", c.testListVisible && c.testSuggestionTitles.count == 2 && c.testSelectedRow == 0)
        check("down arrow moves selection", c.handleKey(key(125)) && c.testSelectedRow == 1)
        check("tab accepts, quoting names with spaces", c.handleKey(key(48)) && c.string == "see @\"my dir/Us.php\" " && !c.testListVisible)
        c.setString("/rev")
        check("/ lists commands", c.testListVisible && c.testSuggestionTitles.first == "/review")
        check("esc closes the list first", c.handleKey(key(53)) && !c.testListVisible && ClaudeComposer.isOpen)
        c.setString("/rev")
        check("return accepts command", c.handleKey(key(36)) && c.string == "/review ")
        // Esc keeps the draft
        c.setString("my draft")
        check("esc closes and keeps draft", c.handleKey(key(53)) && !ClaudeComposer.isOpen && PromptHistory.draft == "my draft")
        var c2 = ClaudeComposer.present(over: w.window, host: host, prefill: nil)
        check("reopen restores draft", c2.string == "my draft")
        // no agent -> not sent, kept, start path
        check("cmd-return without agent tab asks instead of sending", c2.handleKey(key(36, .command)) && sent == ["my draft"] && ClaudeComposer.isOpen && PromptHistory.entries.isEmpty)
        c2.startAndSend("my draft")
        check("start-and-send hands prompt to host, records history, closes", started == ["my draft"] && !ClaudeComposer.isOpen && PromptHistory.entries == ["my draft"] && PromptHistory.draft == "")
        // agent present
        accept = true; sent = []
        c2 = ClaudeComposer.present(over: w.window, host: host, prefill: "second prompt")
        _ = c2.handleKey(key(36, .command))
        check("cmd-return sends and closes", sent == ["second prompt"] && !ClaudeComposer.isOpen && PromptHistory.entries == ["second prompt", "my draft"])
        // history keys on an empty box
        c2 = ClaudeComposer.present(over: w.window, host: host, prefill: nil)
        check("empty box starts empty", c2.string == "")
        check("up shows last prompt, again older", c2.handleKey(key(126)) && c2.string == "second prompt" && c2.handleKey(key(126)) && c2.string == "my draft")
        check("down goes back to newer then empty", c2.handleKey(key(125)) && c2.string == "second prompt" && c2.handleKey(key(125)) && c2.string == "")
        c2.setString("typed")
        check("up inside typed text is not history", !c2.handleKey(key(126)) && c2.string == "typed")
        c2.setString("")
        check("empty prompt is never sent", { sent = []; c2.send(); return sent.isEmpty }())
        ClaudeComposer.dismiss()
        check("released after close", !ClaudeComposer.isOpen && ClaudeComposer.shared == nil)
        PromptHistory.reset()
    }
}
