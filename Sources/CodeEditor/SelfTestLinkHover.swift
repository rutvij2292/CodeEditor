import AppKit

/// CE_SELFTEST: Cmd-hover link look on PHP symbols (LSPLinkHighlight.swift) with the native PHP service, no language server.
/// The pointer keeps moving inside one word (a real mouse sends a mouseMoved every few ms): the link must still appear.
enum SelfTestLinkHover {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("linkhover: " + name, ok()) }

    static func run(w: ProjectWindow, then next: @escaping () -> Void) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-linkhover-\(getpid())")
        try? fm.removeItem(at: root)
        SelfTestNativePHP.buildFixture(root)
        let rel = "app/Http/Controllers/HoverController.php"
        let src = "<?php\nnamespace App\\Http\\Controllers;\n\nuse App\\Models\\Post;\n\nclass HoverController {\n    public function show() {\n        $p = Post::query();\n    }\n}\n"
        SelfTestNativePHP.put(root, rel, src)
        let url = root.appendingPathComponent(rel)
        w.open(url)
        func finish() {
            LSPSession.commandHeldOverride = nil
            try? fm.removeItem(at: root)
            next()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let session = LanguageServerManager.shared.sessions.values.first { $0.tab?.url.standardizedFileURL == url.standardizedFileURL }
            check("session exists for the php tab", session != nil)
            guard let s = session, let tv = s.textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return finish() }
            let off = (src as NSString).range(of: "Post::query").location + 1
            let r = lm.boundingRect(forGlyphRange: NSRange(location: lm.glyphIndexForCharacter(at: off), length: 1), in: tc)
            let o = tv.textContainerOrigin
            let base = NSPoint(x: r.midX + o.x, y: r.midY + o.y)
            check("point maps back to the word", s.offsetUnderPoint(base) == off)
            LSPSession.commandHeldOverride = true
            var moves = 0
            let t0 = Date()
            // 4 ms between moves, jiggling by a pixel inside the word, never pausing.
            Timer.scheduledTimer(withTimeInterval: 0.004, repeats: true) { timer in
                timer.tolerance = 0.001
                moves += 1
                if s.linkRange != nil || Date().timeIntervalSince(t0) > 4 {
                    timer.invalidate()
                    check("link appears while the pointer keeps moving inside the word", s.linkRange != nil)
                    check("one definition check served all \(moves) moves", s.linkRequests == 1)
                    check("link covers the whole word", s.linkRange == NSRange(location: off - 1, length: 4))
                    s.clearLinkHighlight()
                    return finish()
                }
                s.updateLinkHighlight(flags: [.command], point: NSPoint(x: base.x + CGFloat(moves % 2), y: base.y))
            }
        }
    }
}
