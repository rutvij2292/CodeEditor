import AppKit

/// Multi-caret / column-selection checks: pure model rules first, then the view (typing, delete, paste, movement, undo, drawing).
extension SelfTest {
    private static func rng(_ a: Int, _ l: Int = 0) -> NSRange { NSRange(location: a, length: l) }

    static func multiCaretChecks(w: ProjectWindow, dir: URL) {
        modelChecks()
        viewChecks(w: w, dir: dir)
    }

    private static func modelChecks() {
        typealias M = MultiCaret
        let t = "abc\nde\nfghij\n" as NSString
        let n = M.normalize([M.Sel(caret: 5), M.Sel(caret: 1), M.Sel(caret: 5), M.Sel(anchor: 0, head: 3), M.Sel(anchor: 2, head: 6)])
        check("mc normalize merges overlaps and duplicate carets", n.map(\.range) == [rng(0, 6)])
        check("mc normalize keeps touching selections apart", M.normalize(ranges: [rng(0, 2), rng(2, 2)]) == [rng(0, 2), rng(2, 2)])
        let ins = M.apply(M.insertEdits([rng(1), rng(5), rng(8)], "X"), to: t)
        check("mc insert text", ins.text == "aXbc\ndXe\nfXghij\n")
        check("mc insert carets shift", ins.carets == [2, 7, 11])
        let rep = M.apply(M.insertEdits([rng(0, 2), rng(4, 2)], "-"), to: t)
        check("mc replace selections", rep.text == "-c\n-\nfghij\n" && rep.carets == [1, 4])
        let back = M.deleteEdits([rng(1), rng(5), rng(0)], in: t, kind: .backward)
        check("mc backspace ranges (caret at 0 skipped)", back.map(\.range) == [rng(0, 1), rng(4, 1)])
        let adj = M.deleteEdits([rng(1), rng(2)], in: t, kind: .backward)
        check("mc backspace adjacent carets stay disjoint", adj.map(\.range) == [rng(0, 1), rng(1, 1)])
        check("mc backspace result", M.apply(adj, to: t).text == "c\nde\nfghij\n")
        let mixed = M.deleteEdits([rng(0, 2), rng(5)], in: t, kind: .backward)
        check("mc backspace selection plus caret", mixed.map(\.range) == [rng(0, 2), rng(4, 1)])
        check("mc delete forward", M.deleteEdits([rng(3), rng(13)], in: t, kind: .forward).map(\.range) == [rng(3, 1)])
        check("mc smart backspace hook", M.deleteEdits([rng(9)], in: t, kind: .backward, smartBackspace: { _ in rng(7, 2) }).map(\.range) == [rng(7, 2)])
        check("mc backspace removes empty pair", M.deleteEdits([rng(1)], in: "()x" as NSString, kind: .backward).map(\.range) == [rng(0, 2)])
        check("mc column box", M.columnRanges(in: t, anchorLoc: 1, anchorCol: 1, headLoc: 9, headCol: 3) == [rng(1, 2), rng(5, 1), rng(8, 2)])
        check("mc column reversed corners equal", M.columnRanges(in: t, anchorLoc: 9, anchorCol: 3, headLoc: 1, headCol: 1) == [rng(1, 2), rng(5, 1), rng(8, 2)])
        check("mc column zero width gives carets clipped to line ends", M.columnRanges(in: t, anchorLoc: 0, anchorCol: 4, headLoc: 5, headCol: 4) == [rng(3), rng(6)])
        check("mc column single line", M.columnRanges(in: t, anchorLoc: 8, anchorCol: 0, headLoc: 8, headCol: 2) == [rng(7, 2)])
        check("mc vertical down keeps column", M.vertical(t, from: 2, up: false, goal: nil).loc == 6)
        check("mc vertical goal column survives short line", M.vertical(t, from: 6, up: false, goal: 2).loc == 9 && M.vertical(t, from: 6, up: true, goal: 2).loc == 2)
        check("mc vertical edges", M.vertical(t, from: 1, up: true, goal: nil).loc == 0 && M.vertical(t, from: 9, up: false, goal: nil).loc == t.length)
        check("mc add carets below", M.addCarets([M.Sel(caret: 2)], in: t, up: false).map(\.head) == [2, 6])
        check("mc add carets merge when same spot", M.addCarets([M.Sel(caret: 2), M.Sel(caret: 6)], in: t, up: false).map(\.head) == [2, 6, 9])
        let moved = M.move([M.Sel(anchor: 1, head: 3), M.Sel(caret: 5)], extend: false, collapse: -1) { s in (M.step(t, from: s.head, forward: false), nil) }
        check("mc left collapses selection, moves caret", moved.map(\.head) == [1, 4])
        let ext = M.move([M.Sel(caret: 1), M.Sel(caret: 5)], extend: true) { s in (M.step(t, from: s.head, forward: true), nil) }
        check("mc shift-right extends every caret", ext.map(\.range) == [rng(1, 1), rng(5, 1)])
        check("mc next occurrence wraps and skips taken", M.nextOccurrence(of: "ab", in: "ab x ab x ab" as NSString, after: 11, excluding: [rng(0, 2), rng(10, 2)]) == rng(5, 2))
        check("mc distribute matching lines", M.distribute("a\nb\nc\n", count: 3) == ["a", "b", "c"])
        check("mc distribute mismatch falls back", M.distribute("a\nb", count: 3) == nil && M.distribute("a", count: 1) == nil)
    }

    private static func viewChecks(w: ProjectWindow, dir: URL) {
        let url = dir.appendingPathComponent("multicaret.txt")
        try? "one\ntwo\nthree\nfour\n".write(to: url, atomically: true, encoding: .utf8)
        w.open(url)
        guard let ed = w.current else { check("mc view: editor opens", false); return }
        let tv = ed.textView
        let um = tv.undoManager
        um?.groupsByEvent = false
        defer { um?.groupsByEvent = true }
        let base = "one\ntwo\nthree\nfour\n"
        func reset(_ ranges: [NSRange]) { reset(base, ranges) }
        func reset(_ text: String, _ ranges: [NSRange]) {
            tv.string = text
            um?.removeAllActions()
            tv.setMultiSels(ranges.map { MultiCaret.Sel($0) })
        }
        func carets() -> [Int] { tv.effectiveRanges.map(\.location) }
        func cmd(_ s: String) { tv.doCommand(by: Selector((s))) }
        let none = NSRange(location: NSNotFound, length: 0)

        reset([rng(3), rng(7), rng(13)])
        check("mc view: multiple carets active", tv.multiCaretActive)
        tv.insertText("!", replacementRange: none)
        check("mc view: typing hits all carets", tv.string == "one!\ntwo!\nthree!\nfour\n" && carets() == [4, 9, 16])
        um?.undo()
        check("mc view: multi-caret typing is ONE undo step", tv.string == base)
        reset([rng(3), rng(7)])
        tv.insertText("(", replacementRange: none)
        check("mc view: auto-pair at every caret", tv.string == "one()\ntwo()\nthree\nfour\n" && carets() == [4, 10])
        cmd("deleteBackward:")
        check("mc view: backspace removes the empty pair per caret", tv.string == base)
        reset([rng(3), rng(7)])
        cmd("deleteBackward:")
        check("mc view: backspace across carets", tv.string == "on\ntw\nthree\nfour\n")
        um?.undo()
        check("mc view: backspace undo is one step", tv.string == base)
        reset([rng(0), rng(4)])
        cmd("moveRight:")
        check("mc view: arrow moves every caret", carets() == [1, 5])
        cmd("moveDown:")
        check("mc view: down moves every caret", carets() == [5, 9])
        cmd("moveRightAndModifySelection:")
        check("mc view: shift-arrow selects at every caret", tv.effectiveRanges == [rng(5, 1), rng(9, 1)])
        cmd("moveToEndOfLine:")
        check("mc view: End goes to each line end", carets() == [7, 13])
        cmd("cancelOperation:")
        check("mc view: Esc collapses to one caret", tv.effectiveRanges.count == 1 && !tv.multiCaretActive)
        reset([rng(0), rng(4), rng(8)])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("A\nB\nC", forType: .string)
        tv.paste(nil)
        check("mc view: paste distributes lines across carets", tv.string == "Aone\nBtwo\nCthree\nfour\n")
        um?.undo()
        check("mc view: paste undo is one step", tv.string == base)
        reset([rng(0), rng(4)])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Z", forType: .string)
        tv.paste(nil)
        check("mc view: single-line paste goes to every caret", tv.string == "Zone\nZtwo\nthree\nfour\n")
        reset([rng(0, 3), rng(4, 3)])
        tv.copy(nil)
        check("mc view: copy joins selections with newlines", NSPasteboard.general.string(forType: .string) == "one\ntwo")
        tv.cut(nil)
        check("mc view: cut removes all selections", tv.string == "\n\nthree\nfour\n")
        reset("foo bar foo baz foo\n", [rng(1)])
        tv.selectNextOccurrence(nil)
        tv.selectNextOccurrence(nil)
        check("mc view: Ctrl+G adds next occurrence", tv.effectiveRanges == [rng(0, 3), rng(8, 3)])
        tv.selectNextOccurrence(nil)
        tv.unselectPreviousOccurrence(nil)
        check("mc view: Ctrl+Shift+G unselects last", tv.effectiveRanges.count == 2)
        tv.selectAllOccurrences(nil)
        check("mc view: select all occurrences", tv.effectiveRanges.count == 3)
        tv.insertText("x", replacementRange: none)
        check("mc view: type over all occurrences", tv.string == "x bar x baz x\n")
        reset([rng(1)])
        tv.addCaretBelow(nil); tv.addCaretBelow(nil)
        check("mc view: add caret below x2", carets() == [1, 5, 9])
        tv.addCaretAbove(nil)
        check("mc view: add caret above keeps existing", carets() == [1, 5, 9])
        reset("ab\ncdef\ngh\n", [rng(0)])
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        func midY(_ loc: Int) -> CGFloat {
            let g = tv.layoutManager!.glyphIndexForCharacter(at: loc)
            return tv.layoutManager!.lineFragmentRect(forGlyphAt: g, effectiveRange: nil).midY + tv.textContainerOrigin.y
        }
        let a = NSPoint(x: tv.textContainerOrigin.x + (tv.textContainer?.lineFragmentPadding ?? 0) + tv.charWidth * 1, y: midY(0))
        let b = NSPoint(x: a.x + tv.charWidth * 2, y: midY(8))
        check("mc view: option-drag column selection ranges", tv.columnSelection(from: a, to: b) == [rng(1, 1), rng(4, 2), rng(9, 1)])
        tv.toggleCaret(at: 4, base: [rng(0)])
        check("mc view: option-click adds a caret", carets() == [0, 4])
        tv.toggleCaret(at: 4, base: [rng(0), rng(4)])
        check("mc view: option-click on a caret removes it", carets() == [0])
        check("mc view: no blink timer or observers with a single caret", tv.multi.timer == nil && !tv.multi.observing)

        reset("alpha\nbeta\ngamma\n", [rng(2), rng(8), rng(13)])
        tv.frame = NSRect(x: 0, y: 0, width: 400, height: 120)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
        let rects = tv.visibleCaretRects(in: tv.bounds)
        check("mc view: all three carets have rects", rects.count == 3 && rects.allSatisfy { $0.height > 5 })
        if rects.count == 3, let rep = tv.bitmapImageRepForCachingDisplay(in: tv.bounds) {
            tv.cacheDisplay(in: tv.bounds, to: rep)
            if let out = AppEnv.value("CE_SELFTEST_MC_PNG"), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: out))
            }
            let sx = CGFloat(rep.pixelsWide) / tv.bounds.width, sy = CGFloat(rep.pixelsHigh) / tv.bounds.height
            let r = rects[1]
            let c = rep.colorAt(x: Int((r.minX + 1) * sx), y: Int(r.midY * sy))
            let bg = rep.colorAt(x: Int((r.minX + 40) * sx), y: Int(r.midY * sy))
            check("mc view: extra caret pixels differ from background", c != nil && c != bg)
        } else { check("mc view: render", false) }
        reset([rng(0)])
    }
}
