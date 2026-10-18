import AppKit

/// Per-text-view folding engine (TextKit 1).
///
/// Technique: folded text stays in the NSTextStorage (undo, find, copy, LSP and git all see real text). The layout manager
/// delegate swaps the glyphs of the hidden range for null glyphs (`NSGlyphProperty.null`) so they take no space, and turns
/// the first hidden character (always the line break at the end of the header line) into a custom-width "control glyph"
/// that reserves room for the placeholder chip. Hidden newlines get a zero-advance action, so the header line, the chip
/// and the closer's remainder all lay out on ONE line fragment. The chip itself is painted in `drawBackground`.
///
/// The delegate chains in both directions (it forwards everything it does not implement to whichever delegate was there
/// before, and later delegates such as BracketColorizer forward to it).
final class FoldController: NSObject, NSLayoutManagerDelegate {
    struct Region: Equatable {
        var start: Int          // hidden range start (end of the header line's text)
        var end: Int            // hidden range end (start of the closer / end of the last line)
        var kind: FoldKind
        var level: Int
        var placeholder: String
    }

    weak var textView: CodeTextView?
    private weak var layout: NSLayoutManager?
    private weak var forwardee: NSLayoutManagerDelegate?

    /// Every detected region, sorted by start ascending then end descending (outermost first).
    private(set) var regions: [Region] = []
    /// Collapsed regions (including ones nested in other collapsed regions), same order.
    private(set) var collapsed: [Region] = []
    /// Outermost collapsed regions: disjoint, sorted. This is what is actually hidden.
    private(set) var hidden: [Region] = []
    /// Bumped whenever `hidden` changes.
    private(set) var generation = 0

    var hasHidden: Bool { !hidden.isEmpty }

    // MARK: Setup

    init(textView: CodeTextView) {
        self.textView = textView
        super.init()
        layout = textView.layoutManager
        if let lm = layout {
            if let existing = lm.delegate, existing !== self { forwardee = existing }
            lm.delegate = self
        }
        let nc = NotificationCenter.default
        if let storage = textView.textStorage {
            nc.addObserver(self, selector: #selector(storageDidProcess(_:)), name: NSTextStorage.didProcessEditingNotification, object: storage)
        }
        nc.addObserver(self, selector: #selector(prefsChanged(_:)), name: Prefs.didChange, object: nil)
        nc.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let lm = layout, lm.delegate === self { lm.delegate = forwardee }
    }

    // MARK: Delegate forwarding

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (forwardee as AnyObject?)?.responds(to: aSelector) == true
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let f = forwardee as AnyObject?, f.responds(to: aSelector) { return f }
        return super.forwardingTarget(for: aSelector)
    }

    // MARK: Line index (lazy, rebuilt after edits)

    private var starts: [Int] = [0]
    private var startsDirty = true

    private func ensureLines() {
        guard startsDirty, let s = textView?.string as NSString? else { return }
        startsDirty = false
        starts.removeAll(keepingCapacity: true)
        starts.append(0)
        let len = s.length
        var buf = [unichar](repeating: 0, count: 16384)
        var pos = 0
        while pos < len {
            let n = min(buf.count, len - pos)
            s.getCharacters(&buf, range: NSRange(location: pos, length: n))
            for i in 0..<n where buf[i] == 10 { starts.append(pos + i + 1) }
            pos += n
        }
    }

    var lineCount: Int { ensureLines(); return starts.count }

    /// 1-based line number containing `offset`.
    func lineNumber(at offset: Int) -> Int {
        ensureLines()
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    /// Offset of the first character of a 1-based line (clamped).
    func lineStart(_ line: Int) -> Int {
        ensureLines()
        return starts[min(max(0, line - 1), starts.count - 1)]
    }

    private var length: Int { textView?.textStorage?.length ?? 0 }

    // MARK: Queries

    private func lowerBound(_ list: [Region], start: Int) -> Int {
        var lo = 0, hi = list.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if list[mid].start < start { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Hidden range containing the character at `c` (start <= c < end).
    func hiddenRange(containing c: Int) -> Region? {
        guard !hidden.isEmpty else { return nil }
        let i = lowerBound(hidden, start: c + 1) - 1          // last with start <= c
        guard i >= 0, c < hidden[i].end else { return nil }
        return hidden[i]
    }

    /// Hidden range that has `p` strictly inside (a caret there would sit in invisible text).
    func hiddenRange(strictlyInside p: Int) -> Region? {
        guard let h = hiddenRange(containing: p), p > h.start else { return nil }
        return h
    }

    func hiddenRange(startingAt p: Int) -> Region? {
        guard !hidden.isEmpty else { return nil }
        let i = lowerBound(hidden, start: p)
        return i < hidden.count && hidden[i].start == p ? hidden[i] : nil
    }

    /// Regions (all, outermost first) whose header text ends at `p`.
    func regions(startingAt p: Int) -> ArraySlice<Region> {
        var i = lowerBound(regions, start: p)
        let from = i
        while i < regions.count, regions[i].start == p { i += 1 }
        return regions[from..<i]
    }

    func isCollapsed(_ r: Region) -> Bool { collapsed.contains(r) }

    /// Offset where the visual row that begins at line-start `ls` ends (the start of the next row's first line),
    /// following folds that start on the row's last logical line.
    func nextRowStart(from ls: Int, in s: NSString) -> Int {
        var pos = ls
        while true {
            var st = 0, en = 0, ce = 0
            s.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: min(pos, s.length), length: 0))
            if let h = hiddenRange(startingAt: ce), h.end > ce { pos = h.end } else { return en }
        }
    }

    /// 1-based `start..<end+1` line ranges of the outermost collapsed regions (and nested collapsed ones).
    var foldedLineRanges: [Range<Int>] {
        collapsed.map { lineNumber(at: $0.start)..<(lineNumber(at: $0.end) + 1) }
    }

    // MARK: Collapsing

    func setCollapsed(_ new: [Region]) {
        let sorted = new.sorted { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }
        guard sorted != collapsed else { return }
        let oldHidden = hidden
        collapsed = sorted
        rebuildHidden()
        let changed = symmetricDifference(oldHidden, hidden)
        if !changed.isEmpty { invalidate(changed) }
        hiddenChanged()
    }

    private func rebuildHidden() {
        var out: [Region] = []
        for r in collapsed {
            if let last = out.last, r.start < last.end { continue }
            out.append(r)
        }
        hidden = out
    }

    private func symmetricDifference(_ a: [Region], _ b: [Region]) -> [Region] {
        let sa = Set(a.map { [$0.start, $0.end] }), sb = Set(b.map { [$0.start, $0.end] })
        return a.filter { !sb.contains([$0.start, $0.end]) } + b.filter { !sa.contains([$0.start, $0.end]) }
    }

    /// Regenerates glyphs / layout for the rows touched by the given hidden ranges.
    func invalidate(_ rs: [Region]) {
        guard let lm = layout, let tv = textView, let s = tv.textStorage?.string as NSString? else { return }
        for r in rs {
            let a = min(max(0, r.start), s.length), b = min(max(a, r.end), s.length)
            lm.invalidateGlyphs(forCharacterRange: NSRange(location: a, length: b - a), changeInLength: 0, actualCharacterRange: nil)
            let rowStart = s.lineRange(for: NSRange(location: a, length: 0)).location
            let rowEnd = s.lineRange(for: NSRange(location: min(b, max(0, s.length - 1)), length: 0)).upperBound
            lm.invalidateLayout(forCharacterRange: NSRange(location: rowStart, length: max(0, rowEnd - rowStart)), actualCharacterRange: nil)
        }
    }

    private func hiddenChanged(snap: Bool = true) {
        generation += 1
        guard let tv = textView else { return }
        if snap { snapSelectionAfterFold() }
        tv.needsDisplay = true
        tv.window?.invalidateCursorRects(for: tv)
        tv.foldsDidChange()
    }

    /// A caret / selection end left inside newly hidden text goes to the start of that fold (the header's end).
    private func snapSelectionAfterFold() {
        guard let tv = textView else { return }
        var changed = false
        let fixed = tv.selectedRanges.map { v -> NSValue in
            var r = v.rangeValue
            if let h = hiddenRange(strictlyInside: r.location) { let e = r.upperBound; r.location = h.start; r.length = max(0, e - h.start); changed = true }
            if r.length > 0, let h = hiddenRange(strictlyInside: r.upperBound) { r.length = h.end - r.location; changed = true }
            return NSValue(range: r)
        }
        if changed { tv.setSelectedRanges(fixed, affinity: tv.selectionAffinity, stillSelecting: false) }
    }

    func unfoldAll() { setCollapsed([]) }

    /// Expands one collapsed region (and, when `recursive`, every collapsed region nested inside it).
    func expand(_ r: Region, recursive: Bool = false) {
        setCollapsed(collapsed.filter { c in c != r && !(recursive && c.start >= r.start && c.end <= r.end) })
    }

    /// Collapses `r` (and, when `recursive`, every region nested inside it).
    func collapse(_ r: Region, recursive: Bool = false) {
        var set = collapsed
        for c in regions where c == r || (recursive && c.start >= r.start && c.end <= r.end) { if !set.contains(c) { set.append(c) } }
        setCollapsed(set)
    }

    /// The hidden range whose chip is under `p` (text-view coordinates).
    func hiddenRange(atChipPoint p: NSPoint) -> Region? {
        guard !hidden.isEmpty, let lm = layout, let tv = textView, let tc = tv.textContainer else { return nil }
        let origin = tv.textContainerOrigin
        let local = NSRect(x: p.x - origin.x - 40, y: p.y - origin.y - 2, width: 80, height: 4)
        let glyphs = lm.glyphRange(forBoundingRect: local, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        for h in hiddenRanges(overlapping: chars) {
            if let r = chipRect(for: h), r.insetBy(dx: -2, dy: 0).contains(p) { return h }
        }
        return nil
    }

    /// Expands every collapsed region that overlaps `range` (touching only the boundary does not count).
    @discardableResult
    func unfold(intersecting range: NSRange) -> Bool {
        let hit = collapsed.filter { r in
            range.length == 0 ? (range.location > r.start && range.location < r.end) : (range.location < r.end && range.upperBound > r.start)
        }
        guard !hit.isEmpty else { return false }
        setCollapsed(collapsed.filter { c in !hit.contains(c) })
        return true
    }

    // MARK: Selection normalisation

    /// Adjusts ranges so no caret / selection end rests inside hidden text. Keyboard / mouse navigation snaps to the fold's
    /// edges; anything else (find, go to line, programmatic selection) expands the fold instead.
    func normalized(_ ranges: [NSValue], navigating: Bool, previous: NSRange?) -> [NSValue] {
        guard !hidden.isEmpty else { return ranges }
        if !navigating {
            var any = false
            for v in ranges {
                let r = v.rangeValue
                if hiddenRange(strictlyInside: r.location) != nil || (r.length > 0 && hiddenRange(strictlyInside: r.upperBound) != nil) { any = true }
            }
            if any {
                for v in ranges {
                    let r = v.rangeValue
                    if let h = hiddenRange(strictlyInside: r.location) { unfold(intersecting: NSRange(location: h.start + 1, length: 0)) }
                    if r.length > 0, let h = hiddenRange(strictlyInside: r.upperBound) { unfold(intersecting: NSRange(location: h.start + 1, length: 0)) }
                }
            }
            return ranges
        }
        return ranges.map { v in
            var r = v.rangeValue
            let old = previous ?? r
            if r.length == 0 {
                if let h = hiddenRange(strictlyInside: r.location) {
                    r.location = r.location > old.location ? h.end : h.start
                }
            } else {
                let lo = r.location, hi = r.upperBound
                var newLo = lo, newHi = hi
                if let h = hiddenRange(strictlyInside: lo) { newLo = (lo > old.location && old.length > 0) ? h.end : h.start }
                if let h = hiddenRange(strictlyInside: hi) { newHi = (hi < old.upperBound && old.length > 0) ? h.start : h.end }
                if newHi < newLo { newHi = newLo }
                r = NSRange(location: newLo, length: newHi - newLo)
            }
            return NSValue(range: r)
        }
    }

    // MARK: Edits

    private var editVersion = 0

    @objc private func storageDidProcess(_ note: Notification) {
        guard let storage = note.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
        editVersion += 1
        startsDirty = true
        let r = storage.editedRange, delta = storage.changeInLength
        let oldLen = r.length - delta
        shiftRegions(loc: r.location, oldLen: oldLen, newLen: r.length)
        scheduleRecompute()
    }

    private func shiftRegions(loc: Int, oldLen: Int, newLen: Int) {
        guard !regions.isEmpty || !collapsed.isEmpty else { return }
        let eEnd = loc + oldLen, delta = newLen - oldLen
        func mapPoint(_ p: Int, isStart: Bool) -> Int {
            if p < loc || (p == loc && !(isStart && oldLen == 0)) { return p }
            if p >= eEnd { return p + delta }
            return loc + newLen                                     // inside the replaced text
        }
        regions = regions.compactMap { r in
            var n = r
            n.start = mapPoint(r.start, isStart: true)
            n.end = mapPoint(r.end, isStart: false)
            return n.end > n.start ? n : nil
        }
        guard !collapsed.isEmpty else { return }
        var dropped: [Region] = []
        collapsed = collapsed.compactMap { r in
            if eEnd <= r.start { var n = r; n.start += delta; n.end += delta; return n }
            if loc >= r.end { return r }
            dropped.append(Region(start: mapPoint(r.start, isStart: true), end: mapPoint(r.end, isStart: false), kind: r.kind, level: r.level, placeholder: r.placeholder))
            return nil
        }
        let oldHidden = hidden
        rebuildHidden()
        if oldHidden.count != hidden.count || !dropped.isEmpty {
            // Remaining invisible pieces of dissolved folds must be regenerated as visible text.
            invalidate(dropped.filter { $0.end > $0.start })
            if !dropped.isEmpty { hiddenChanged(snap: false) }
        }
    }

    // MARK: Computing regions

    private var computeWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "fold.compute", qos: .userInitiated)
    private var computedOnce = false
    /// Called once, after the first successful computation, with no restored folds pending (for "fold imports on open").
    var onFirstCompute: (() -> Void)?
    /// Set by the session store so `foldedLineRanges` restored before the first computation can be matched later.
    private var pendingRestore: [Range<Int>]?
    private(set) var restoredFromSession = false

    var isEnabled: Bool { Prefs.foldingEnabled && !isLarge }

    private var isLarge: Bool {
        if let tab = textView?.delegate as? EditorTab, tab.isLargeFile { return true }
        return length > 2_000_000
    }

    /// File name that picks the language: explicit override, else the owning tab's file.
    private var resolvedFileName: String {
        textView?.foldFileName ?? (textView?.delegate as? EditorTab)?.url.lastPathComponent ?? ""
    }

    func scheduleRecompute() {
        computeWork?.cancel()
        guard isEnabled else { return }
        let work = DispatchWorkItem { [weak self] in self?.startCompute() }
        computeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (computedOnce ? 0.15 : 0.05), execute: work)
    }

    private func startCompute() {
        guard isEnabled, let tv = textView else { return }
        let version = editVersion
        let name = resolvedFileName
        guard !name.isEmpty else { return }
        let text = Self.snapshot(tv)
        queue.async { [weak self] in
            let result = FoldRanges.compute(text: text, fileName: name)
            DispatchQueue.main.async { self?.install(result, version: version) }
        }
    }

    /// Test hook: synchronous computation + install.
    func computeNow() {
        guard isEnabled, let tv = textView else { return }
        install(FoldRanges.compute(text: Self.snapshot(tv), fileName: resolvedFileName), version: editVersion)
    }

    /// An immutable copy of the buffer (the text storage's string is live and mutable).
    private static func snapshot(_ tv: NSTextView) -> String {
        let ns = tv.string as NSString
        var units = [UInt16](repeating: 0, count: ns.length)
        units.withUnsafeMutableBufferPointer { if let b = $0.baseAddress { ns.getCharacters(b, range: NSRange(location: 0, length: ns.length)) } }
        return String(decoding: units, as: UTF16.self)
    }

    private func install(_ result: [FoldRange], version: Int) {
        guard isEnabled else { return }
        if version != editVersion { scheduleRecompute(); return }
        regions = result.map { Region(start: $0.hiddenStart, end: $0.hiddenEnd, kind: $0.kind, level: $0.level, placeholder: $0.placeholder) }
        // Keep collapsed folds that still match a region exactly; the rest dissolve.
        let keep = collapsed.filter { c in regions.contains { $0.start == c.start && $0.end == c.end } }
        if keep.count != collapsed.count { setCollapsed(keep) }
        let first = !computedOnce
        computedOnce = true
        if let pending = pendingRestore {
            pendingRestore = nil
            applyLineRanges(pending)
        } else if first, !restoredFromSession {
            onFirstCompute?()
        }
        textView?.foldsDidChange()
    }

    /// Replace the collapsed set from persisted 1-based half-open line ranges (matched against detected regions by lines).
    func restore(lineRanges: [Range<Int>]) {
        restoredFromSession = true
        if computedOnce { applyLineRanges(lineRanges) } else { pendingRestore = lineRanges }
    }

    private func applyLineRanges(_ ranges: [Range<Int>]) {
        var out: [Region] = []
        for r in ranges {
            let a = r.lowerBound, b = r.upperBound - 1
            if let m = regions.first(where: { lineNumber(at: $0.start) == a && lineNumber(at: $0.end) == b }) { out.append(m) }
        }
        setCollapsed(out)
    }

    // MARK: Preferences

    @objc private func prefsChanged(_ note: Notification) {
        let key = note.userInfo?["key"] as? String ?? ""
        switch key {
        case "foldingEnabled":
            if Prefs.foldingEnabled { scheduleRecompute() } else { computeWork?.cancel(); regions = []; unfoldAll(); textView?.foldsDidChange() }
        case "editorFontName", "editorFontSize", "lineHeightMultiple":
            invalidate(hidden)
        default: break
        }
    }

    @objc private func themeChanged() { textView?.needsDisplay = true }

    // MARK: Chips

    static let chipHPad: CGFloat = 5
    static let chipMargin: CGFloat = 2

    func chipFont(at charIndex: Int) -> NSFont {
        let f = textView?.textStorage?.attribute(.font, at: min(max(0, charIndex), max(0, length - 1)), effectiveRange: nil) as? NSFont
        return f ?? textView?.font ?? Theme.font
    }

    func chipWidth(for r: Region) -> CGFloat {
        let label = r.placeholder as NSString
        return ceil(label.size(withAttributes: [.font: chipFont(at: r.start)]).width) + Self.chipHPad * 2 + Self.chipMargin * 2
    }

    /// Chip rect (text-view coordinates) of a hidden range, nil when it is not laid out.
    func chipRect(for r: Region) -> NSRect? {
        guard let lm = layout, let tv = textView, r.start < lm.textStorage?.length ?? 0 else { return nil }
        let g = lm.glyphIndexForCharacter(at: r.start)
        guard g < lm.numberOfGlyphs else { return nil }
        let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
        let loc = lm.location(forGlyphAt: g)
        let origin = tv.textContainerOrigin
        let w = chipWidth(for: r)
        let font = chipFont(at: r.start)
        let h = min(frag.height - 2, ceil(font.ascender - font.descender) + 2)
        let x = origin.x + frag.minX + loc.x + Self.chipMargin
        let y = origin.y + frag.minY + (frag.height - h) / 2
        return NSRect(x: x, y: y, width: w - Self.chipMargin * 2, height: h)
    }

    /// Hidden ranges overlapping a character range (for drawing visible chips).
    func hiddenRanges(overlapping range: NSRange) -> [Region] {
        guard !hidden.isEmpty else { return [] }
        var i = max(0, lowerBound(hidden, start: range.location) - 1)
        var out: [Region] = []
        while i < hidden.count, hidden[i].start <= NSMaxRange(range) {
            if hidden[i].end >= range.location { out.append(hidden[i]) }
            i += 1
        }
        return out
    }

    // MARK: NSLayoutManagerDelegate

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard !hidden.isEmpty, glyphRange.length > 0 else { return 0 }
        let first = charIndexes[0], last = charIndexes[glyphRange.length - 1]
        let i0 = max(0, lowerBound(hidden, start: first + 1) - 1)
        guard i0 < hidden.count, hidden[i0].end > first || (i0 + 1 < hidden.count && hidden[i0 + 1].start <= last) else { return 0 }
        var p = Array(UnsafeBufferPointer(start: props, count: glyphRange.length))
        var touched = false
        var hi = i0
        for k in 0..<glyphRange.length {
            let c = charIndexes[k]
            while hi < hidden.count, hidden[hi].end <= c { hi += 1 }
            guard hi < hidden.count, c >= hidden[hi].start else { continue }
            touched = true
            if !p[k].contains(.controlCharacter) { p[k].insert(.null) }
        }
        guard touched else { return 0 }
        layoutManager.setGlyphs(glyphs, properties: p, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        if let h = hiddenRange(containing: charIndex) { return charIndex == h.start ? .whitespace : .zeroAdvancement }
        return action
    }

    func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int, for textContainer: NSTextContainer,
                       proposedLineFragment proposedRect: NSRect, glyphPosition: NSPoint, characterIndex charIndex: Int) -> NSRect {
        if let h = hiddenRange(startingAt: charIndex) { return NSRect(x: 0, y: 0, width: chipWidth(for: h), height: proposedRect.height) }
        return NSRect(x: 0, y: 0, width: 0, height: proposedRect.height)
    }
}
