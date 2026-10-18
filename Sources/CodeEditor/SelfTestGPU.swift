import AppKit

/// CE_SELFTEST guards for the drawing-cost work: GPU-assist gating, incremental highlight painting, the gutter label cache.
enum SelfTestGPU {
    private static func pump(_ s: Double) { RunLoop.main.run(until: Date(timeIntervalSinceNow: s)) }

    static func run(tab: EditorTab?, dir: URL) {
        gating()
        guard let tab else { return }
        liveGating(tab)
        incrementalHighlight(tab)
        bracketDiff()
        gutterLabels(tab)
    }

    private static func gating() {
        func d(_ mode: String, lines: Int = 5000, saver: Bool = false, occluded: Bool = false, disabled: Bool = false, baseline: Bool = true) -> Bool {
            GPUAssist.decide(.init(mode: mode, lines: lines, powerSaver: saver, occluded: occluded, selfDisabled: disabled, baselineReady: baseline))
        }
        SelfTest.check("gpuAssist: auto is on for a big file", d("auto"))
        SelfTest.check("gpuAssist: auto is off for small files", !d("auto", lines: 1500) && !d("auto", lines: GPUAssist.autoMinLines))
        SelfTest.check("gpuAssist: auto is off in power saver", !d("auto", saver: true))
        SelfTest.check("gpuAssist: auto is off while the window is occluded", !d("auto", occluded: true))
        SelfTest.check("gpuAssist: auto is off once self-disabled", !d("auto", disabled: true))
        SelfTest.check("gpuAssist: auto waits for the sync baseline", !d("auto", baseline: false))
        SelfTest.check("gpuAssist: off is always off, on is always on", !d("off") && d("on", lines: 10, saver: true, occluded: true))

        let saved = UserDefaults.standard.object(forKey: "gpuAssist")
        Prefs.gpuAssist = "bogus"
        SelfTest.check("gpuAssist: invalid pref falls back to auto", Prefs.gpuAssist == "auto")
        Prefs.gpuAssist = "off"
        SelfTest.check("gpuAssist: pref round-trips", Prefs.gpuAssist == "off")
        SelfTest.check("gpuAssist: pref is covered by Restore Defaults", Prefs.allKeys.contains("gpuAssist"))
        if let saved { UserDefaults.standard.set(saved, forKey: "gpuAssist") } else { UserDefaults.standard.removeObject(forKey: "gpuAssist") }

        var slower = GPUAssist.Check()
        for _ in 0..<GPUAssist.sampleCount { slower.record(ms: 1, area: 100_000, async: false) }
        SelfTest.check("gpuAssist: stays enabled while async is not slower", { var c = slower; for _ in 0..<40 { c.record(ms: 0.5, area: 100_000, async: true) }; return !c.selfDisabled }())
        for _ in 0..<GPUAssist.sampleCount { slower.record(ms: 1.5, area: 100_000, async: true) }
        SelfTest.check("gpuAssist: self-disables when async draws slower than sync", slower.selfDisabled)
    }

    private static func liveGating(_ tab: EditorTab) {
        let tv = tab.textView
        let saved = UserDefaults.standard.object(forKey: "gpuAssist")
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: "gpuAssist") } else { UserDefaults.standard.removeObject(forKey: "gpuAssist") }
            PowerState.shared.simulated = nil
            tv.gpuCheck.reset()
            tv.updateGPUAssist()
        }
        guard tv.layer != nil else { SelfTest.check("gpuAssist: text view is layer backed", false); return }
        Prefs.gpuAssist = "off"; tv.gpuCheck.reset(); tv.updateGPUAssist()
        SelfTest.check("gpuAssist: pref off keeps the layer synchronous", !tv.gpuAssistActive)
        Prefs.gpuAssist = "on"; tv.updateGPUAssist()
        SelfTest.check("gpuAssist: pref on draws asynchronously", tv.gpuAssistActive)
        Prefs.gpuAssist = "auto"; tv.gpuCheck.reset(); tv.updateGPUAssist()
        SelfTest.check("gpuAssist: auto starts synchronous (collecting the baseline)", !tv.gpuAssistActive)
        for _ in 0..<GPUAssist.sampleCount { tv.gpuCheck.record(ms: 1, area: 100_000, async: false) }
        tv.updateGPUAssist()
        SelfTest.check("gpuAssist: auto turns on for a 5k-line file after the baseline", tv.gpuAssistActive)
        PowerState.shared.simulated = true
        tv.updateGPUAssist()
        SelfTest.check("gpuAssist: power saver turns it off", !tv.gpuAssistActive)
        PowerState.shared.simulated = nil
        tv.updateGPUAssist()
        SelfTest.check("gpuAssist: leaving power saver turns it back on", tv.gpuAssistActive)
        for _ in 0..<GPUAssist.sampleCount { tv.gpuCheck.record(ms: 2, area: 100_000, async: true) }
        tv.updateGPUAssist()
        SelfTest.check("gpuAssist: rolling check switches a slower async path off for good", !tv.gpuAssistActive && tv.gpuCheck.selfDisabled)
    }

    /// Incremental painting (only changed runs are touched) must leave exactly the colours a from-scratch paint gives.
    private static func incrementalHighlight(_ tab: EditorTab) {
        guard let hl = tab.highlighter else { SelfTest.check("highlight: tab has a highlighter", false); return }
        let tv = tab.textView
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        func colours() -> [NSColor?] {
            let g = lm.glyphRange(forBoundingRect: tv.visibleRect, in: tc)
            let r = lm.characterRange(forGlyphRange: g, actualGlyphRange: nil)
            return (r.location..<NSMaxRange(r)).map { lm.temporaryAttribute(.foregroundColor, atCharacterIndex: $0, effectiveRange: nil) as? NSColor }
        }
        let len = (tv.string as NSString).length
        tv.setSelectedRange(NSRange(location: len / 3, length: 0))
        tv.scrollRangeToVisible(tv.selectedRange())
        pump(0.3)
        let steps: [(String?, Bool)] = [("x", false), (nil, true), ("\n", false), ("// c", false), ("\"", false), (nil, true), ("(", false), (nil, true), ("/*", false)]
        for (text, del) in steps {
            if let text { tv.insertText(text, replacementRange: tv.selectedRange()) }
            if del { tv.deleteBackward(nil) }
            pump(0.05)
        }
        pump(0.4)
        let inc = colours()
        hl.forceFullRepaint()
        let full = colours()
        var bad = 0
        if inc.count == full.count { for i in 0..<inc.count where inc[i] != full[i] { bad += 1 } } else { bad = -1 }
        SelfTest.check("highlight: incremental repaint after edits matches a full repaint (\(bad) differing characters of \(full.count))", bad == 0 && full.count > 100)
        // Scrolling away and back repaints the exposed lines only; the result must still match.
        let sv = tab.scrollView
        for y in [CGFloat(9000), 400] {
            sv.contentView.scroll(to: NSPoint(x: 0, y: y)); sv.reflectScrolledClipView(sv.contentView)
            pump(0.2)
        }
        let inc2 = colours()
        hl.forceFullRepaint()
        let full2 = colours()
        var bad2 = 0
        if inc2.count == full2.count { for i in 0..<inc2.count where inc2[i] != full2[i] { bad2 += 1 } } else { bad2 = -1 }
        SelfTest.check("highlight: incremental repaint after scrolling matches a full repaint (\(bad2) differing)", bad2 == 0 && full2.count > 100)
        // Undo the noise for later checks.
        for _ in 0..<2 { tv.undoManager?.undo() }
    }

    private static func bracketDiff() {
        func model(_ s: String) -> BracketModel { BracketScanner.build(Array(s.utf16), spans: nil, spec: .php) }
        let base = "<?php f(a(b), [c]); g(h(i)); { x }"
        let m = model(base)
        let all = NSRange(location: 0, length: base.utf16.count)
        SelfTest.check("bracket diff: identical models report nothing", BracketModel.changedPositions(from: m, to: m, in: all, limit: 10) == [])
        // Typing an extra opener at the start shifts every later bracket one level deeper / unmatched.
        let typed = model("<?php ( f(a(b), [c]); g(h(i)); { x }")
        let moved = BracketModel.changedPositions(from: m, to: typed, in: NSRange(location: 0, length: 40), limit: 100) ?? []
        SelfTest.check("bracket diff: a new opener is reported", moved.contains(6))
        SelfTest.check("bracket diff: depth shifts of later brackets are reported", moved.count >= 5)
        SelfTest.check("bracket diff: over the limit falls back (nil)", BracketModel.changedPositions(from: m, to: typed, in: all, limit: 2) == nil)
        let narrow = BracketModel.changedPositions(from: m, to: typed, in: NSRange(location: 0, length: 6), limit: 10) ?? [1]
        SelfTest.check("bracket diff: only the requested range is considered", narrow.isEmpty)
    }

    /// The cached CTLine labels must look like the NSString ones they replace.
    private static func gutterLabels(_ tab: EditorTab) {
        guard let g = (tab.view.subviews.first as? EditorContainer)?.gutter else { return }
        tab.view.layoutSubtreeIfNeeded()
        func render() -> NSBitmapImageRep? {
            guard g.bounds.width > 0, g.bounds.height > 0, let rep = g.bitmapImageRepForCachingDisplay(in: g.bounds) else { return nil }
            g.cacheDisplay(in: g.bounds, to: rep)
            return rep
        }
        let saved = GutterView.labelCache
        defer { GutterView.labelCache = saved }
        GutterView.labelCache = false
        let a = render()
        GutterView.labelCache = true
        let b = render()
        guard let a, let b, let pa = a.bitmapData, let pb = b.bitmapData, a.bytesPerRow * a.pixelsHigh == b.bytesPerRow * b.pixelsHigh else {
            SelfTest.check("gutter: label cache renders", false); return
        }
        if let out = AppEnv.value("CE_GUT_DUMP") {
            try? a.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + "/gut-ns.png"))
            try? b.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + "/gut-ct.png"))
        }
        var diff = 0, maxDelta = 0
        let n = a.bytesPerRow * a.pixelsHigh
        for i in 0..<n where pa[i] != pb[i] { diff += 1; maxDelta = max(maxDelta, abs(Int(pa[i]) - Int(pb[i]))) }
        SelfTest.check("gutter: cached labels render like NSString labels (\(diff) of \(n) bytes differ, max delta \(maxDelta))", Double(diff) < Double(n) * 0.002)
    }
}
