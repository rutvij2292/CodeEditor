import AppKit

/// Everyday editing rules in a real editor view: Return keeps the line's indent, Tab / Backspace on indentation.
extension SelfTest {
    static func editingChecks(w: ProjectWindow, dir: URL) {
        for ext in ["vue", "html", "php", "js"] {
            let url = dir.appendingPathComponent("editing.\(ext)")
            let src = "<template>\n    <div>\n        <input\n            type=\"checkbox\"\n        />\n    </div>\n</template>\n"
            try? src.write(to: url, atomically: true, encoding: .utf8)
            w.open(url)
            guard let ed = w.current else { check("edit \(ext): opens", false); continue }
            let tv = ed.textView
            let ns = tv.string as NSString
            let end = ns.range(of: "/>").upperBound
            tv.setSelectedRange(NSRange(location: end, length: 0))
            tv.insertNewline(nil)
            let after = tv.string as NSString
            let c = tv.selectedRange().location
            let ls = after.lineRange(for: NSRange(location: c, length: 0)).location
            check("edit \(ext): Return after `/>` keeps the indent (\(c - ls))", c - ls == 8)
            // Tab on the blank line moves one stop, not several
            tv.insertTab(nil)
            let c2 = tv.selectedRange().location
            check("edit \(ext): Tab moves to the next stop (\(c2 - ls))", c2 - ls == 12)
            // Backspace on a whitespace-only line clears it in one press
            tv.deleteBackward(nil)
            let c3 = tv.selectedRange().location
            let after3 = tv.string as NSString
            let len3 = after3.length
            let ls3 = after3.lineRange(for: NSRange(location: c3, length: 0)).location
            check("edit \(ext): Backspace on a blank line clears its indentation at once (\(c3 - ls3))", c3 - ls3 == 0)
            tv.deleteBackward(nil)
            let c4 = tv.selectedRange().location
            let ls4 = (tv.string as NSString).lineRange(for: NSRange(location: c4, length: 0)).location
            check("edit \(ext): second Backspace joins the previous line (\(c4 - ls4))", c4 - ls4 == 10 && (tv.string as NSString).length == len3 - 1)
        }
        markupChecks(w: w, dir: dir)
        tabbedPickerChecks(w: w)
        singleTabChecks(w: w, dir: dir)
        engineHotChecks(dir: dir)
        phpReturnCheck(w: w, dir: dir)
        typingProbe(w: w)
        typedCompletionProbe(w: w)
        openLayoutTrial(w: w)
        typingLatencyProbe(w: w)
    }

    /// CE_TYPE_FILE=<file>: types 120 characters (and 10 Returns) in the middle of the file through the real controller and reports the
    /// main-thread time per keystroke, including the debounced hooks that run between keys (CE_BENCH=1 adds per-task totals).
    private static func typingLatencyProbe(w: ProjectWindow) {
        guard let path = AppEnv.value("CE_TYPE_FILE") else { return }
        w.open(URL(fileURLWithPath: path))
        guard let ed = w.current else { fputs("TYPE no editor\n", stderr); return }
        let tv = ed.textView
        func pump(_ t: Double) { RunLoop.current.run(until: Date().addingTimeInterval(t)) }
        pump(1.5)
        let ns = tv.string as NSString
        let line = Int(AppEnv.value("CE_TYPE_LINE") ?? "") ?? 58
        var loc = 0, n = 1
        while n < line, loc < ns.length { loc = NSMaxRange(ns.lineRange(for: NSRange(location: loc, length: 0))); n += 1 }
        tv.setSelectedRange(NSRange(location: loc, length: 0))
        _ = Perf.drain()
        func cpu() -> Double { var u = rusage(); getrusage(RUSAGE_SELF, &u); return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6 }
        let idle0 = cpu()
        for _ in 0..<40 { pump(0.05) }
        fputs(String(format: "TYPE idle CPU per 50 ms: %.2f ms\n", (cpu() - idle0) / 40 * 1000), stderr)
        let cpu0 = cpu()
        let ctl = CompletionSystem.controller(for: ed)
        var worst = 0.0, total = 0.0
        let text = Array("$value = $this->service->find($id); // typing")
        var count = 0
        for i in 0..<(Int(AppEnv.value("CE_TYPE_N") ?? "") ?? 130) {
            let t0 = CFAbsoluteTimeGetCurrent()
            if i % 13 == 12 { tv.insertNewline(nil) }
            else {
                let ch = String(text[i % text.count])
                if let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                             characters: ch, charactersIgnoringModifiers: ch, isARepeat: false, keyCode: 0) { _ = ctl?.handleKey(ev) }
                tv.insertText(ch, replacementRange: NSRange(location: NSNotFound, length: 0))
            }
            let tKey = CFAbsoluteTimeGetCurrent() - t0
            let t1 = CFAbsoluteTimeGetCurrent()
            pump(0.05)                                   // debounced work lands here; sleeping time is not counted below
            _ = t1
            worst = max(worst, tKey); total += tKey; count += 1
        }
        fputs(String(format: "TYPE %@ line %d: keystroke avg %.2f ms, worst %.2f ms\n", (path as NSString).lastPathComponent, line, total / Double(count) * 1000, worst * 1000), stderr)
        fputs(String(format: "TYPE process CPU per keystroke (all threads, incl. debounced work): %.2f ms\n", (cpu() - cpu0) / Double(count) * 1000), stderr)
        for (k, v) in Perf.drain().sorted(by: { $0.value.total > $1.value.total }) {
            fputs(String(format: "TYPE   %@ n=%d total %.1f ms max %.1f ms\n", k, v.count, v.total * 1000, v.max * 1000), stderr)
        }
        // Return at the end of every line (bottom up): where does the caret land?
        let lines = (tv.string as NSString).components(separatedBy: "\n")
        var starts: [Int] = [], pos = 0
        for l in lines { starts.append(pos); pos += (l as NSString).length + 1 }
        for idx in stride(from: lines.count - 1, through: 0, by: -1) {
            let l = lines[idx] as NSString
            let indent = l.length - (lines[idx].drop(while: { $0 == " " || $0 == "\t" }) as Substring).utf16.count
            tv.setSelectedRange(NSRange(location: starts[idx] + l.length, length: 0))
            tv.insertNewline(nil)
            pump(0.03)
            let cc = tv.selectedRange().location
            let lls = (tv.string as NSString).lineRange(for: NSRange(location: cc, length: 0)).location
            let col = cc - lls
            let trimmed = lines[idx].trimmingCharacters(in: .whitespaces)
            if col == 0, trimmed.isEmpty == false || idx > 0 { fputs("TYPE RETURN col 0 after line \(idx + 1) (indent \(indent)): \(lines[idx])\n", stderr) }
        }
    }

    /// Return in the middle of a PHP method keeps the indent, and the caret is still there after the editor's async hooks ran.
    private static func phpReturnCheck(w: ProjectWindow, dir: URL) {
        let url = dir.appendingPathComponent("UserController.php")
        let src = "<?php\n\nclass UserController\n{\n    public function index()\n    {\n        $a = 1;\n        $b = 2;\n    }\n}\n"
        try? src.write(to: url, atomically: true, encoding: .utf8)
        w.open(url)
        guard let ed = w.current else { check("php return: opens", false); return }
        let tv = ed.textView
        let ns = tv.string as NSString
        tv.setSelectedRange(NSRange(location: ns.range(of: "$a = 1;").upperBound, length: 0))
        tv.insertNewline(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let c = tv.selectedRange().location
        let ls = (tv.string as NSString).lineRange(for: NSRange(location: c, length: 0)).location
        check("php return: caret keeps the indent after async hooks (\(c - ls))", c - ls == 8)
        // the DRAWN caret: its x must be 8 columns right of the line start (stale layout drew it at column 0)
        if let lm = tv.layoutManager, let tc = tv.textContainer {
            if let m = AppEnv.value("CE_LBM"), let st = tv.textStorage {
                let ps = NSMutableParagraphStyle(); ps.setParagraphStyle(tv.defaultParagraphStyle ?? .default)
                ps.lineBreakMode = m == "clip" ? .byClipping : .byCharWrapping
                st.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: st.length))
                lm.ensureLayout(forCharacterRange: NSRange(location: 0, length: st.length))
            }
            fputs("CARET storage para attr at line: \(String(describing: tv.textStorage?.attribute(.paragraphStyle, at: ls, effectiveRange: nil)))\n", stderr)
            if let m = AppEnv.value("CE_ENSURE") {
                let full = tv.string as NSString
                let lr = full.lineRange(for: NSRange(location: ls, length: 0))
                if m == "A" { lm.ensureLayout(forCharacterRange: lr) }
                if m == "B" { lm.ensureLayout(for: tc) }
                if m == "C" { lm.ensureGlyphs(forCharacterRange: lr); lm.ensureLayout(forGlyphRange: lm.glyphRange(forCharacterRange: lr, actualCharacterRange: nil)) }
                if m == "D" { lm.invalidateLayout(forCharacterRange: lr, actualCharacterRange: nil); lm.ensureLayout(forCharacterRange: lr) }
            }
            let gi = lm.glyphIndexForCharacter(at: max(0, c - 1))
            let r = lm.boundingRect(forGlyphRange: NSRange(location: gi, length: 1), in: tc)
            let x0 = lm.boundingRect(forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: ls), length: 1), in: tc).minX
            let cw = ("M" as NSString).size(withAttributes: [.font: tv.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]).width
            for k in 0...min(9, (tv.string as NSString).length - ls - 1) {
                let g = lm.glyphIndexForCharacter(at: ls + k)
                fputs("CARET glyph \(k): char \((tv.string as NSString).character(at: ls + k)) loc \(lm.location(forGlyphAt: g)) used \(lm.lineFragmentUsedRect(forGlyphAt: g, effectiveRange: nil)) notShown \(lm.notShownAttribute(forGlyphAt: g))\n", stderr)
            }
            fputs("CARET container \(tc.size) tracks \(tc.widthTracksTextView) padding \(tc.lineFragmentPadding) tv frame \(tv.frame) nonContig \(lm.allowsNonContiguousLayout) para \(String(describing: tv.defaultParagraphStyle?.lineBreakMode.rawValue))\n", stderr)
            fputs("CARET layout: caret-1 glyph minX \(r.minX), line start \(x0), char width \(cw), insertion rect \(tv.firstRect(forCharacterRange: NSRange(location: c, length: 0), actualRange: nil))\n", stderr)
            let want = tv.textContainerOrigin.x + tc.lineFragmentPadding + 8 * tv.charWidth
            check("php return: caret is drawn 8 columns in (\(String(describing: tv.trailingBlankCaretX())) vs \(want))", abs((tv.trailingBlankCaretX() ?? -1) - want) < 0.5)
            _ = r; _ = x0; _ = cw
        }
    }

    /// Hot updates of the Vue / web file lists: saving changes nothing, creating / deleting a file does.
    private static func engineHotChecks(dir: URL) {
        let fm = FileManager.default
        let root = dir.appendingPathComponent("hot-\(getpid())")
        try? fm.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        func put(_ rel: String) { try? "<template><div/></template>\n".write(to: root.appendingPathComponent(rel), atomically: true, encoding: .utf8) }
        put("src/A.vue"); put("src/app.css")
        let rp = root.standardizedFileURL.path
        let vue = NVProject.shared(root: rp), web = NWProject.shared(root: rp)
        let a = rp + "/src/A.vue", b = rp + "/src/B.vue", css = rp + "/src/app.css", css2 = rp + "/src/b.css"
        check("hot: vue list starts with A", vue.vueFiles.map { ($0 as NSString).lastPathComponent } == ["A.vue"])
        _ = web.allCSSFiles
        vue.noteChanged([a]); web.noteChanged([css])
        check("hot: saving a known file keeps the lists", vue.vueFiles.count == 1 && web.allCSSFiles.count == 1)
        put("src/B.vue"); try? "a{}\n".write(to: root.appendingPathComponent("src/b.css"), atomically: true, encoding: .utf8)
        vue.noteChanged([b]); web.noteChanged([css2])
        check("hot: a created .vue appears", vue.vueFiles.map { ($0 as NSString).lastPathComponent } == ["A.vue", "B.vue"])
        check("hot: a created stylesheet appears", web.allCSSFiles.count == 2)
        try? fm.removeItem(at: root.appendingPathComponent("src/B.vue")); try? fm.removeItem(at: root.appendingPathComponent("src/b.css"))
        vue.noteChanged([b]); web.noteChanged([css2])
        check("hot: a deleted .vue disappears", vue.vueFiles.map { ($0 as NSString).lastPathComponent } == ["A.vue"])
        check("hot: a deleted stylesheet disappears", web.allCSSFiles.count == 1)
        try? fm.removeItem(at: root)
    }

    /// One visible tab by default; every open file stays open (Cmd-E), and the View toggle brings the full strip back.
    private static func singleTabChecks(w: ProjectWindow, dir: URL) {
        let was = Prefs.multipleTabs
        defer { Prefs.multipleTabs = was }
        let urls = ["one.txt", "two.txt", "three.txt"].map { dir.appendingPathComponent($0) }
        for u in urls { try? "x\n".write(to: u, atomically: true, encoding: .utf8); w.open(u) }
        Prefs.multipleTabs = false
        check("tabs: one visible tab by default (\(w.tabs.visibleTabIDs.count))", w.tabs.visibleTabIDs == [urls[2].standardizedFileURL.path])
        check("tabs: the strip row has no height in single-tab mode (\(w.tabs.stripHeight))", w.tabs.stripHeight == 0)
        check("tabs: the other files stay open", urls.allSatisfy { u in w.tabs.entries.contains { $0.id == u.standardizedFileURL.path } })
        w.open(urls[0])
        check("tabs: switching shows the new active tab only", w.tabs.visibleTabIDs == [urls[0].standardizedFileURL.path])
        w.window.contentView?.layoutSubtreeIfNeeded()
        fputs("TABDBG single: \(w.tabs.debugItemFrames)\n", stderr)
        Prefs.multipleTabs = true
        w.window.contentView?.layoutSubtreeIfNeeded()
        fputs("TABDBG multi: \(w.tabs.debugItemFrames)\n", stderr)
        check("tabs: the strip row is back with several tabs", w.tabs.stripHeight > 0)
        check("tabs: multiple-tabs mode shows every tab", Set(urls.map { $0.standardizedFileURL.path }).isSubset(of: Set(w.tabs.visibleTabIDs)))
    }

    /// Search Everywhere's tabbed picker: tabs switch the provider, and the non-project switch reaches it.
    private static func tabbedPickerChecks(w: ProjectWindow) {
        var sawNonProject = false
        let tabs = [PickerTab(title: "All") { q, np in sawNonProject = sawNonProject || np; return [PickerItem(title: "all:\(q)") {}] },
                    PickerTab(title: "Files") { q, _ in [PickerItem(title: "file:\(q)") {}] }]
        QuickPicker.presentTabbed(over: w.window, tabs: tabs, placeholder: "x")
        defer { QuickPicker.dismiss() }
        check("tabbed picker: tab titles", QuickPicker.tabTitles == ["All", "Files"])
        QuickPicker.type("ab")
        check("tabbed picker: first tab answers", QuickPicker.shownTitles == ["all:ab"])
        QuickPicker.selectTab(1)
        check("tabbed picker: switching tabs re-runs the query on the new tab", QuickPicker.selectedTabIndex == 1 && QuickPicker.shownTitles == ["file:ab"])
        _ = sawNonProject
    }

    private static func markupChecks(w: ProjectWindow, dir: URL) {
        for ext in ["vue", "html"] {
            let url = dir.appendingPathComponent("markup.\(ext)")
            let src = "<template>\n    <div>\n        \n\n    </div>\n</template>\n<script>\nconst a = 1 <b\n</script>\n"
            try? src.write(to: url, atomically: true, encoding: .utf8)
            w.open(url)
            guard let ed = w.current else { check("markup \(ext): opens", false); continue }
            let tv = ed.textView
            let ns0 = tv.string as NSString
            let blank = ns0.range(of: "        \n\n").location
            tv.setSelectedRange(NSRange(location: blank + 8, length: 0))
            for ch in "<h1>" { tv.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0)) }
            check("markup \(ext): typing `>` adds the end tag", tv.string.contains("        <h1></h1>\n"))
            check("markup \(ext): caret sits between the tags", (tv.string as NSString).substring(from: tv.selectedRange().location).hasPrefix("</h1>"))
            let ns = tv.string as NSString
            let inText = tv.selectedRange().location
            check("markup \(ext): no auto popup in element text", MarkupGate.isPlainText(ns, caret: inText, ext: ext))
            check("markup \(ext): popup still allowed after `<`", !MarkupGate.isPlainText("<template><di" as NSString, caret: 13, ext: ext))
            check("markup \(ext): popup allowed in an attribute", !MarkupGate.isPlainText("<template><div cl" as NSString, caret: 17, ext: ext))
            check("markup \(ext): popup allowed inside {{ }}", !MarkupGate.isPlainText("<template><p>{{ us" as NSString, caret: 18, ext: ext))
            check("markup \(ext): no end tag for void / self-closed", MarkupGate.tagToClose("<template><br" as NSString, caret: 13, ext: ext) == nil && MarkupGate.tagToClose("<template><x /" as NSString, caret: 14, ext: ext) == nil)
            // Tab expands a tag name that starts a line
            do {
                let t = tv.string as NSString
                tv.setSelectedRange(NSRange(location: t.length, length: 0))
                tv.insertText("\n        h2", replacementRange: NSRange(location: NSNotFound, length: 0))
                tv.insertTab(nil)
                let after = tv.string as NSString
                check("markup \(ext): Tab expands `h2` to <h2></h2>", after.range(of: "        <h2></h2>", options: .backwards).location != NSNotFound)
                check("markup \(ext): the caret is between the tags", after.substring(from: tv.selectedRange().location).hasPrefix("</h2>"))
            }
            // Return on an empty line keeps the surrounding indent
            let ns2 = tv.string as NSString
            let emptyLine = ns2.range(of: "</div>").location - 5       // the empty line above `    </div>`
            tv.setSelectedRange(NSRange(location: emptyLine, length: 0))
            tv.insertNewline(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            let c = tv.selectedRange().location
            let ls = (tv.string as NSString).lineRange(for: NSRange(location: c, length: 0)).location
            check("markup \(ext): Return on an empty line keeps the indent (\(c - ls))", c - ls == 8)
            // Return after an open tag indents; between the tags it also moves the end tag down
            do {
                let t = tv.string as NSString
                let at = t.range(of: "<h1></h1>").location + 4
                tv.setSelectedRange(NSRange(location: at, length: 0))
                tv.insertNewline(nil)
                check("markup \(ext): Return between tags expands them", tv.string.contains("        <h1>\n            \n        </h1>"))
                let cc = tv.selectedRange().location
                let l0 = (tv.string as NSString).lineRange(for: NSRange(location: cc, length: 0)).location
                check("markup \(ext): the caret is on the indented middle line (\(cc - l0))", cc - l0 == 12)
            }
        }
    }

    /// CE_OPEN_TRIAL=<file>: open cost and the document height the scroller sees right after opening vs after a full layout. The
    /// difference is the "scroll bar reaches the end, then more lines pop in" jump.
    private static func openLayoutTrial(w: ProjectWindow) {
        guard let path = AppEnv.value("CE_OPEN_TRIAL") else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        w.open(URL(fileURLWithPath: path))
        guard let ed = w.current, let lm = ed.textView.layoutManager else { return }
        for _ in 0..<5 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        let openMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        let before = ed.textView.frame.height
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {      // (queued work only runs once this block returns)
            ed.textView.sizeToFit()
            fputs("OPENTRIAL height 4 s after open (background layout): \(ed.textView.frame.height)\n", stderr)
            exit(0)
        }
        let t1 = CFAbsoluteTimeGetCurrent()
        if AppEnv.value("CE_OPEN_NOFORCE") == nil { lm.ensureLayout(for: ed.textView.textContainer!) }
        let layoutMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000
        ed.textView.sizeToFit()
        let after = ed.textView.frame.height
        let lines = (ed.textView.string as NSString).components(separatedBy: "\n").count
        fputs(String(format: "OPENTRIAL %@ lines %d nonContiguous %@: open %.0f ms, height at open %.0f, after full layout %.0f (error %.1f%%), full layout %.0f ms\n",
                     (path as NSString).lastPathComponent, lines, lm.allowsNonContiguousLayout ? "ON" : "off", openMs, before, after, abs(after - before) / max(after, 1) * 100, layoutMs), stderr)
    }

    /// CE_COMPL_FILE=<php file> CE_COMPL_TEXT=<text>: appends the text at the end of the file one key at a time (like typing) and prints the
    /// popup after each key. Shows what the user sees for e.g. `Route::po`.
    private static func typedCompletionProbe(w: ProjectWindow) {
        guard let path = AppEnv.value("CE_COMPL_FILE"), let text = AppEnv.value("CE_COMPL_TEXT") else { return }
        w.open(URL(fileURLWithPath: path))
        guard let ed = w.current, let c = CompletionSystem.controller(for: ed) else { fputs("COMPL no controller\n", stderr); return }
        let tv = ed.textView
        func pump(_ t: Double) { RunLoop.current.run(until: Date().addingTimeInterval(t)) }
        pump(1.0)
        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        tv.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
        for ch in text.map(String.init) {
            if let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: ch.first!.isUppercase ? [.shift] : [], timestamp: 0, windowNumber: 0, context: nil,
                                         characters: ch, charactersIgnoringModifiers: ch.lowercased(), isARepeat: false, keyCode: 0) { _ = c.handleKey(ev) }
            tv.insertText(ch, replacementRange: NSRange(location: NSNotFound, length: 0))
            pump(Double(AppEnv.value("CE_COMPL_PUMP") ?? "") ?? 0.9)
            fputs("COMPL after '\(ch)': open=\(c.isOpen) [\(c.candidateLabels.prefix(10).joined(separator: ", "))]\n", stderr)
        }
        pump(1.5)
        fputs("COMPL settled: open=\(c.isOpen) [\(c.candidateLabels.prefix(10).joined(separator: ", "))]\n", stderr)
    }

    /// Like `typedCompletionProbe`, but every key is its own main-queue block so provider results (delivered via `main.async`) land.
    static func asyncCompletionProbe(w: ProjectWindow) {
        guard let path = AppEnv.value("CE_COMPL_FILE"), let text = AppEnv.value("CE_COMPL_TEXT") else { finish() }
        w.open(URL(fileURLWithPath: path))
        let pause = Double(AppEnv.value("CE_COMPL_PUMP") ?? "") ?? 0.9
        var keys = text.map(String.init)
        func step() {
            guard let ed = w.current, let c = CompletionSystem.controller(for: ed) else { fputs("COMPL no controller\n", stderr); finish() }
            guard !keys.isEmpty else { fputs("COMPL settled: open=\(c.isOpen) [\(c.candidateLabels.prefix(10).joined(separator: ", "))]\n", stderr); finish() }
            let ch = keys.removeFirst()
            if let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: ch.first!.isUppercase ? [.shift] : [], timestamp: 0, windowNumber: 0, context: nil,
                                         characters: ch, charactersIgnoringModifiers: ch.lowercased(), isARepeat: false, keyCode: 0) { _ = c.handleKey(ev) }
            ed.textView.insertText(ch, replacementRange: NSRange(location: NSNotFound, length: 0))
            DispatchQueue.main.asyncAfter(deadline: .now() + pause) {
                fputs("COMPL after '\(ch)': open=\(c.isOpen) [\(c.candidateLabels.prefix(10).joined(separator: ", "))]\n", stderr)
                step()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard let ed = w.current else { finish() }
            ed.textView.setSelectedRange(NSRange(location: (ed.textView.string as NSString).length, length: 0))
            ed.textView.insertText("\n", replacementRange: NSRange(location: NSNotFound, length: 0))
            step()
        }
    }

    /// CE_IDLE_FILE=<file>: opens it, types ~200 characters, then idles for CE_IDLE_SECS (default 60) printing, per 10 s, CPU time, interrupt
    /// wakeups and billed energy (what Activity Monitor's Energy Impact is built from).
    static func idleProbe(w: ProjectWindow, file: String) {
        func usage() -> (cpu: Double, wake: UInt64, energy: UInt64) {
            var ri = rusage_info_v4()
            _ = withUnsafeMutablePointer(to: &ri) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0) } }
            return (Double(ri.ri_user_time + ri.ri_system_time) / 1e9, ri.ri_interrupt_wkups, ri.ri_billed_energy)
        }
        w.open(URL(fileURLWithPath: file))
        let secs = Int(AppEnv.value("CE_IDLE_SECS") ?? "") ?? 60
        var last = usage()
        var typed = 0
        let text = Array("$value = $this->service->find($id); // typing in the editor\n")
        func report(_ tag: String) {
            let u = usage()
            fputs(String(format: "IDLE %@: cpu %.3f s, wakeups %llu, energy %.1f mJ\n", tag, u.cpu - last.cpu, u.wake - last.wake, Double(u.energy - last.energy) / 1e6), stderr)
            last = u
        }
        func idle(_ n: Int) {
            guard n < secs / 10 else { finish() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { report("idle +\((n + 1) * 10) s"); idle(n + 1) }
        }
        func type() {
            guard let ed = w.current else { finish() }
            if typed >= 200 { report("typing 200 chars"); idle(0); return }
            ed.textView.insertText(String(text[typed % text.count]), replacementRange: NSRange(location: NSNotFound, length: 0))
            typed += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { type() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            report("open + settle")
            guard let ed = w.current else { finish() }
            ed.textView.setSelectedRange(NSRange(location: (ed.textView.string as NSString).length, length: 0))
            type()
        }
    }

    /// CE_TOA_FILE=<php file with `Request $request`>: types `$request->toA` through the real controller and prints the popup list.
    private static func typingProbe(w: ProjectWindow) {
        guard let path = AppEnv.value("CE_TOA_FILE") else { return }
        w.open(URL(fileURLWithPath: path))
        guard let ed = w.current, let c = CompletionSystem.controller(for: ed) else { fputs("PROBE no controller\n", stderr); return }
        let tv = ed.textView
        let ns = tv.string as NSString
        let r = ns.range(of: "Request $request")
        let brace = ns.range(of: "{", range: NSRange(location: r.location, length: ns.length - r.location))
        tv.setSelectedRange(NSRange(location: brace.location + 1, length: 0))
        tv.insertText("\n        $request->", replacementRange: NSRange(location: NSNotFound, length: 0))
        func pump(_ t: Double) { RunLoop.current.run(until: Date().addingTimeInterval(t)) }
        pump(0.3)
        c.trigger(manual: true)
        pump(0.8)
        fputs("PROBE after ->: open=\(c.isOpen) \(c.candidateLabels.count)\n", stderr)
        for ch in ["t", "o", "A"] {
            if let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: ch == "A" ? [.shift] : [], timestamp: 0, windowNumber: 0, context: nil,
                                         characters: ch, charactersIgnoringModifiers: ch.lowercased(), isARepeat: false, keyCode: 0) { _ = c.handleKey(ev) }
            tv.insertText(ch, replacementRange: NSRange(location: NSNotFound, length: 0))
            pump(0.8)
            fputs("PROBE typed \(ch): open=\(c.isOpen) \(c.candidateLabels.prefix(8).joined(separator: ", "))\n", stderr)
        }
    }
}
