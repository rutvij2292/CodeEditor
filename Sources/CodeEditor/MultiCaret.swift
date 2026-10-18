import Foundation

/// Pure multi-caret model: selections with direction, range transforms for edits, column (box) selection,
/// vertical movement and clipboard distribution. No AppKit view code, so every rule here is unit-testable
/// (see SelfTestMultiCaret). UTF-16 offsets throughout, matching NSString / NSTextView.
enum MultiCaret {
    /// A selection with direction: `anchor` stays put, `head` moves. `goal` is the remembered column for vertical moves.
    struct Sel: Equatable {
        var anchor: Int
        var head: Int
        var goal: Int?
        init(anchor: Int, head: Int, goal: Int? = nil) { self.anchor = anchor; self.head = head; self.goal = goal }
        init(caret: Int) { self.init(anchor: caret, head: caret) }
        init(_ r: NSRange) { self.init(anchor: r.location, head: r.upperBound) }
        var range: NSRange { NSRange(location: min(anchor, head), length: abs(head - anchor)) }
        var isEmpty: Bool { anchor == head }
        var lower: Int { min(anchor, head) }
        var upper: Int { max(anchor, head) }
    }

    /// Replacement of `range` with `text`; `caret` is the caret offset inside the replacement afterwards.
    struct Edit: Equatable {
        var range: NSRange
        var text: String
        var caret: Int
        init(_ range: NSRange, _ text: String, caret: Int? = nil) {
            self.range = range; self.text = text; self.caret = caret ?? text.utf16.count
        }
    }

    // MARK: Normalisation

    /// Sorts by position and merges duplicates and overlapping selections (touching non-empty ones stay separate).
    static func normalize(_ sels: [Sel]) -> [Sel] {
        let sorted = sels.sorted { $0.lower != $1.lower ? $0.lower < $1.lower : $0.upper < $1.upper }
        var out: [Sel] = []
        for s in sorted {
            if let last = out.last, s.lower < last.upper || (s.lower == last.lower && (s.isEmpty || last.isEmpty)) {
                let lo = min(last.lower, s.lower), hi = max(last.upper, s.upper)
                let forward = s.head >= s.anchor
                out[out.count - 1] = forward ? Sel(anchor: lo, head: hi) : Sel(anchor: hi, head: lo)
            } else {
                out.append(s)
            }
        }
        return out
    }

    static func normalize(ranges: [NSRange]) -> [NSRange] { normalize(ranges.map(Sel.init)).map(\.range) }

    // MARK: Edits

    /// Ascending, non-overlapping edits applied to `text`: the new string and the resulting caret offsets (in new coordinates).
    static func apply(_ edits: [Edit], to text: NSString) -> (text: String, carets: [Int]) {
        var out = "", pos = 0, shift = 0
        var carets: [Int] = []
        for e in edits {
            out += text.substring(with: NSRange(location: pos, length: e.range.location - pos))
            out += e.text
            pos = e.range.upperBound
            carets.append(e.range.location + shift + e.caret)
            shift += e.text.utf16.count - e.range.length
        }
        out += text.substring(from: pos)
        return (out, carets)
    }

    /// Typing `text` over every selection.
    static func insertEdits(_ ranges: [NSRange], _ text: String) -> [Edit] { ranges.map { Edit($0, text) } }

    enum DeleteKind { case backward, forward, wordBackward }

    /// Deletion ranges: non-empty selections are removed, empty carets delete one unit (or a word / smart-indent chunk).
    /// Overlaps between neighbouring deletions are trimmed so the result is ascending and disjoint.
    static func deleteEdits(_ ranges: [NSRange], in text: NSString, kind: DeleteKind,
                            pairs: [unichar: unichar] = [40: 41, 91: 93, 123: 125, 34: 34, 39: 39, 96: 96],
                            smartBackspace: ((Int) -> NSRange?)? = nil,
                            wordStop: ((Int) -> Int)? = nil) -> [Edit] {
        var items: [NSRange] = []
        for r in ranges {
            if r.length > 0 { items.append(r); continue }
            let loc = r.location
            switch kind {
            case .backward:
                if let sm = smartBackspace?(loc), sm.length > 0 { items.append(sm); break }
                guard loc > 0 else { break }
                if loc < text.length, let close = pairs[text.character(at: loc - 1)], text.character(at: loc) == close {
                    items.append(NSRange(location: loc - 1, length: 2)); break      // empty auto-pair goes as a unit
                }
                items.append(text.rangeOfComposedCharacterSequence(at: loc - 1))
            case .forward:
                guard loc < text.length else { break }
                items.append(text.rangeOfComposedCharacterSequence(at: loc))
            case .wordBackward:
                guard loc > 0 else { break }
                let t = wordStop?(loc) ?? loc - 1
                if t < loc { items.append(NSRange(location: t, length: loc - t)) }
            }
        }
        var out: [Edit] = []
        var lastEnd = 0
        for r in items.sorted(by: { $0.location < $1.location }) {
            let lo = max(r.location, lastEnd)
            guard r.upperBound > lo else { continue }
            out.append(Edit(NSRange(location: lo, length: r.upperBound - lo), "", caret: 0))
            lastEnd = r.upperBound
        }
        return out
    }

    // MARK: Movement

    /// Moves every selection. Without `extend`, a non-empty selection collapses to its edge when `collapse` is -1 (left) / +1 (right).
    static func move(_ sels: [Sel], extend: Bool, collapse: Int = 0, target: (Sel) -> (loc: Int, goal: Int?)) -> [Sel] {
        normalize(sels.map { s in
            if !extend, !s.isEmpty, collapse != 0 {
                let p = collapse < 0 ? s.lower : s.upper
                return Sel(caret: p)
            }
            let t = target(s)
            return extend ? Sel(anchor: s.anchor, head: t.loc, goal: t.goal) : Sel(anchor: t.loc, head: t.loc, goal: t.goal)
        })
    }

    static func step(_ text: NSString, from loc: Int, forward: Bool) -> Int {
        if forward { return loc >= text.length ? text.length : NSMaxRange(text.rangeOfComposedCharacterSequence(at: loc)) }
        return loc <= 0 ? 0 : text.rangeOfComposedCharacterSequence(at: loc - 1).location
    }

    /// One logical line up/down keeping the column (`goal` remembers it across short lines). First/last line go to the text edge.
    static func vertical(_ text: NSString, from loc: Int, up: Bool, goal: Int?) -> (loc: Int, goal: Int) {
        let loc = min(max(0, loc), text.length)
        var st = 0, en = 0, ce = 0
        text.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: loc, length: 0))
        let col = goal ?? (loc - st)
        if up {
            guard st > 0 else { return (0, col) }
            var pst = 0, pen = 0, pce = 0
            text.getLineStart(&pst, end: &pen, contentsEnd: &pce, for: NSRange(location: st - 1, length: 0))
            return (pst + min(col, pce - pst), col)
        }
        guard en < text.length else { return (text.length, col) }
        var nst = 0, nen = 0, nce = 0
        text.getLineStart(&nst, end: &nen, contentsEnd: &nce, for: NSRange(location: en, length: 0))
        return (nst + min(col, nce - nst), col)
    }

    /// Adds a caret one line above / below every selection head (duplicates merge).
    static func addCarets(_ sels: [Sel], in text: NSString, up: Bool) -> [Sel] {
        normalize(sels + sels.compactMap { s in
            let v = vertical(text, from: s.head, up: up, goal: s.goal)
            guard lineColumn(text, v.loc).lineStart != lineColumn(text, s.head).lineStart else { return nil }   // no line there
            return Sel(anchor: v.loc, head: v.loc, goal: v.goal)
        })
    }

    // MARK: Column (box) selection

    /// Line start and column (characters from the line start) of an offset.
    static func lineColumn(_ text: NSString, _ loc: Int) -> (lineStart: Int, column: Int) {
        let l = min(max(0, loc), text.length)
        let st = text.lineRange(for: NSRange(location: l, length: 0)).location
        return (st, l - st)
    }

    /// Per-line ranges of a rectangle between two corners (lines given by any offset on them, columns in characters).
    /// Lines shorter than the left edge get a caret at their end; zero width yields carets only.
    static func columnRanges(in text: NSString, anchorLoc: Int, anchorCol: Int, headLoc: Int, headCol: Int) -> [NSRange] {
        let a = lineColumn(text, anchorLoc).lineStart, h = lineColumn(text, headLoc).lineStart
        let top = min(a, h), bottom = max(a, h)
        let c0 = max(0, min(anchorCol, headCol)), c1 = max(0, max(anchorCol, headCol))
        var out: [NSRange] = []
        var ls = top
        while true {
            var st = 0, en = 0, ce = 0
            text.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: ls, length: 0))
            let len = ce - st
            let s = st + min(c0, len), e = st + min(c1, len)
            out.append(NSRange(location: s, length: e - s))
            if st >= bottom || en <= st || en >= text.length && ce == en { break }
            ls = en
        }
        return out
    }

    // MARK: Occurrences

    /// The next occurrence of `needle` after `from` (wrapping once) that is not already selected.
    static func nextOccurrence(of needle: String, in text: NSString, after from: Int, excluding taken: [NSRange]) -> NSRange? {
        guard !needle.isEmpty else { return nil }
        var pos = min(from, text.length)
        for _ in 0...taken.count {
            var f = text.range(of: needle, options: .literal, range: NSRange(location: pos, length: text.length - pos))
            if f.location == NSNotFound { f = text.range(of: needle, options: .literal) }
            if f.location == NSNotFound { return nil }
            if !taken.contains(f) { return f }
            pos = f.upperBound
        }
        return nil
    }

    // MARK: Clipboard

    /// Lines to hand one-per-caret when pasting, nil unless the line count equals the caret count
    /// (a single trailing newline is ignored).
    static func distribute(_ clip: String, count: Int) -> [String]? {
        guard count > 1 else { return nil }
        var lines = clip.components(separatedBy: "\n")
        if lines.count == count + 1, lines.last == "" { lines.removeLast() }
        return lines.count == count ? lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 } : nil
    }
}
