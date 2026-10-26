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
            let ls3 = after3.lineRange(for: NSRange(location: c3, length: 0)).location
            check("edit \(ext): Backspace on a blank line clears its indentation at once (\(c3 - ls3))", c3 - ls3 == 0)
            tv.deleteBackward(nil)
            let c4 = tv.selectedRange().location
            let ls4 = (tv.string as NSString).lineRange(for: NSRange(location: c4, length: 0)).location
            check("edit \(ext): second Backspace joins the previous line (\(c4 - ls4))", c4 - ls4 == 11 || (tv.string as NSString).length == after3.length - 1)
        }
        typingProbe(w: w)
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
