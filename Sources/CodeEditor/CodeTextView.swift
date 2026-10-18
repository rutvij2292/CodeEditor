import AppKit

/// NSTextView with IDE-style editing actions. Expects a TextKit 1 stack from the caller.
final class CodeTextView: NSTextView {
    enum CommentStyle: Equatable { case line(String), block(String, String), none }

    var commentStyle: CommentStyle = .line("//")
    var indentUnit = "    "
    var useTabs = false
    var tabColumns = 4

    // Hooks for language features (completion popup, LSP actions). Set through EditorEvents.onOpen.
    /// Called first for every key press; return true to swallow the event (e.g. the completion popup's arrows/Return/Tab/Esc).
    var keyInterceptor: ((NSEvent) -> Bool)?
    var onTriggerCompletion: (() -> Void)?
    var onGoToDefinition: (() -> Void)?
    var onQuickDocumentation: (() -> Void)?
    var onParameterInfo: (() -> Void)?

    /// Fired when the text view loses first-responder status (completion popup closes).
    var onResignFirstResponder: (() -> Void)?
    override func resignFirstResponder() -> Bool {
        let r = super.resignFirstResponder()
        if r { onResignFirstResponder?() }
        return r
    }

    /// Fired before every single-range edit (range, replacement length in UTF-16) so tab-stop trackers can follow the text.
    var onWillChange: ((NSRange, Int) -> Void)?
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        folds.unfold(intersecting: affectedCharRange)      // any edit touching folded text unfolds it first
        let ok = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if ok { onWillChange?(affectedCharRange, (replacementString as NSString?)?.length ?? 0) }
        return ok
    }

    @objc func triggerCompletion(_ sender: Any?) { onTriggerCompletion?() }
    @objc func goToDefinition(_ sender: Any?) { onGoToDefinition?() }
    @objc func showQuickDocumentation(_ sender: Any?) { onQuickDocumentation?() }
    @objc func showParameterInfo(_ sender: Any?) { onParameterInfo?() }

    override func keyDown(with event: NSEvent) {
        if keyInterceptor?(event) == true { return }
        super.keyDown(with: event)
    }

    private typealias LineEdit = (loc: Int, len: Int, text: String)
    private var extendHistory: [NSRange] = []
    private var extendTarget: NSRange?
    private var occurrenceStack: [NSRange] = []
    /// Multi-caret bookkeeping (see MultiCaretView.swift).
    let multi = MultiCaretState()

    // Keyboard selection state (our own anchor: NSTextView's hidden anchor can go stale after programmatic selections).
    var navAnchor = 0, navHead = 0
    var navRange: NSRange?
    // Occurrence highlighting.
    struct Occurrence { var range: NSRange; var isWrite: Bool }
    var occurrences: [Occurrence] = []
    var occurrenceWork: DispatchWorkItem?

    /// The file's line terminator ("\r\n" when the loaded text contains one). Detected whenever `string` is assigned.
    var lineEnding = "\n"
    override var string: String { didSet { detectLineEnding() } }

    private func detectLineEnding() {
        lineEnding = (string as NSString).range(of: "\r\n").location != NSNotFound ? "\r\n" : "\n"
    }

    /// Posted (object: nil) after the soft-wrap preference changes; every CodeTextView re-applies it.
    static let softWrapDidChange = Notification.Name("CodeEditor.softWrapDidChange")
    static var softWrapEnabled: Bool { UserDefaults.standard.bool(forKey: "softWrap") }
    private var appliedSoftWrap: Bool?
    private var lastCaretLineRect: NSRect = .zero

    /// Code folding engine (TextKit 1 glyph hiding); see FoldController.
    private(set) var folds: FoldController!
    /// True while a keyboard command / mouse gesture moves the selection (snap to fold edges instead of unfolding).
    var userNavigating = false
    /// Overrides the file name used to pick the folding language (defaults to the owning tab's file name).
    var foldFileName: String?
    /// Fired after the folded set or the detected regions changed (session persistence, gutter redraw).
    var onFoldsChange: (() -> Void)?
    static let foldsDidChangeNotification = Notification.Name("CodeEditor.foldsDidChange")

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setup()
    }

    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        folds = FoldController(textView: self)
        folds.onFirstCompute = { [weak self] in self?.applyOpenFolds() }
        GitGutter.start()   // idempotent; registers before the owning tab fires its open hook
        applyThemeColors()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(applyThemeColors), name: Theme.didChange, object: nil)
        nc.addObserver(self, selector: #selector(softWrapPreferenceChanged), name: Self.softWrapDidChange, object: nil)
        nc.addObserver(self, selector: #selector(gpuPolicyInputsChanged), name: Prefs.didChange, object: nil)
        nc.addObserver(self, selector: #selector(gpuPolicyInputsChanged), name: PowerState.didChange, object: nil)
        nc.addObserver(self, selector: #selector(gpuPolicyInputsChanged), name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    }

    @objc private func gpuPolicyInputsChanged() { if Prefs.gpuAssist != "auto" { gpuCheck.reset() }; updateGPUAssist() }

    @objc private func applyThemeColors() {
        // Background only: selection must not wash out syntax colours.
        selectedTextAttributes = [.backgroundColor: Theme.palette.selection]
        insertionPointColor = Theme.palette.caret
        needsDisplay = true
    }

    // MARK: - Soft wrap

    @objc private func softWrapPreferenceChanged() { applySoftWrap(Self.softWrapEnabled) }

    @objc func toggleSoftWrap(_ sender: Any?) {
        UserDefaults.standard.set(!Self.softWrapEnabled, forKey: "softWrap")
        NotificationCenter.default.post(name: Self.softWrapDidChange, object: nil)
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleSoftWrap(_:)) { item.state = Self.softWrapEnabled ? .on : .off; return true }
        if let a = item.action, Self.foldActions.contains(a) { return Prefs.foldingEnabled && !folds.regions.isEmpty }
        return super.validateMenuItem(item)
    }

    func applySoftWrap(_ on: Bool) {
        guard let tc = textContainer else { return }
        appliedSoftWrap = on
        let sv = enclosingScrollView
        if on {
            isHorizontallyResizable = false
            autoresizingMask = [.width]
            tc.widthTracksTextView = true
            sv?.hasHorizontalScroller = false
            if let sv, sv.contentSize.width > 50 {   // before the first layout pass the scroll view is still 0 wide
                setFrameSize(NSSize(width: sv.contentSize.width, height: frame.height))
                sv.contentView.scroll(to: NSPoint(x: 0, y: sv.contentView.bounds.origin.y))
            }
            tc.containerSize = NSSize(width: max(10, frame.width - textContainerInset.width * 2), height: .greatestFiniteMagnitude)
        } else {
            tc.widthTracksTextView = false
            tc.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            isHorizontallyResizable = true
            autoresizingMask = []
            sv?.hasHorizontalScroller = true
        }
        layoutManager?.ensureLayout(for: tc)
        sizeToFit()
        needsDisplay = true
        sv?.reflectScrolledClipView(sv!.contentView)
        NotificationCenter.default.post(name: NSView.frameDidChangeNotification, object: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateGPUAssist()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if enclosingScrollView != nil, appliedSoftWrap == nil, Self.softWrapEnabled { applySoftWrap(true) }
    }

    // MARK: - Current line, indent guides, caret

    /// Colour for the caret-line band; the dark palette value is too faint to see, so derive it from the foreground.
    private var currentLineColor: NSColor {
        Theme.isDark ? Theme.foreground.withAlphaComponent(0.07) : Theme.palette.currentLine
    }

    private var guideColor: NSColor {
        Theme.isDark ? Theme.foreground.withAlphaComponent(0.12) : Theme.foreground.withAlphaComponent(0.13)
    }

    /// Rect (view coordinates, full visible width) of the caret's logical line, nil unless the selection is a single caret.
    private func caretLineRect() -> NSRect? {
        guard selectedRanges.count == 1, !multiCaretActive, selectedRange().length == 0,
              let lm = layoutManager else { return nil }
        let s = ns
        let loc = min(selectedRange().location, s.length)
        let origin = textContainerOrigin
        var rect: NSRect
        if s.length == 0 || (loc == s.length && s.character(at: s.length - 1) == 10) {
            rect = lm.extraLineFragmentRect
            if rect.height == 0 { return nil }
        } else {
            let lr = s.lineRange(for: NSRange(location: loc, length: 0))
            let g = lm.glyphRange(forCharacterRange: lr, actualCharacterRange: nil)
            guard g.length > 0 else { return nil }
            rect = lm.lineFragmentRect(forGlyphAt: g.location, effectiveRange: nil)
            if g.length > 1 { rect = rect.union(lm.lineFragmentRect(forGlyphAt: NSMaxRange(g) - 1, effectiveRange: nil)) }
        }
        rect.origin.y += origin.y
        rect.origin.x = visibleRect.minX
        rect.size.width = visibleRect.width
        return rect
    }

    override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        var r = charRange
        if folds.hasHidden, let n = folds.normalized([NSValue(range: charRange)], navigating: userNavigating, previous: selectedRanges.first?.rangeValue).first {
            r = n.rangeValue
        }
        super.setSelectedRange(r, affinity: affinity, stillSelecting: stillSelectingFlag)
        multiSelectionDidChange()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        var ranges = ranges
        defer { scheduleOccurrences(); multiSelectionDidChange() }
        if ranges.count > 1 { ranges = MultiCaret.normalize(ranges: ranges.map { $0.rangeValue }).map { NSValue(range: $0) } }   // merge duplicate / overlapping carets
        if folds.hasHidden {
            ranges = folds.normalized(ranges, navigating: userNavigating, previous: selectedRanges.first?.rangeValue)
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !lastCaretLineRect.isEmpty { setNeedsDisplay(lastCaretLineRect) }
        lastCaretLineRect = caretLineRect() ?? .zero
        if !lastCaretLineRect.isEmpty { setNeedsDisplay(lastCaretLineRect) }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if let band = caretLineRect() {
            let r = band.intersection(rect)
            if !r.isEmpty { currentLineColor.setFill(); r.fill() }
            lastCaretLineRect = band
        }
        drawIndentGuides(in: rect)
        drawOccurrences(in: rect)
    }

    /// Drawing-cost bookkeeping for GPUAssist's self-disable check (see GPUAssist.swift).
    var gpuCheck = GPUAssist.Check()
    private var gpuDraws = 0

    override func draw(_ dirtyRect: NSRect) {
        let auto = Prefs.gpuAssist == "auto"
        let t0 = auto ? CACurrentMediaTime() : 0
        super.draw(dirtyRect)
        drawExtraCarets(in: dirtyRect)
        drawFoldChips(in: dirtyRect)     // after the text: syntax backgrounds (comments) must not paint over the chips
        guard auto else { return }
        gpuCheck.record(ms: (CACurrentMediaTime() - t0) * 1000, area: Double(dirtyRect.width * dirtyRect.height), async: gpuAssistActive)
        gpuDraws += 1
        if gpuDraws % 16 == 0 || gpuCheck.syncN == GPUAssist.sampleCount { updateGPUAssist() }
    }

    var charWidth: CGFloat { ("0" as NSString).size(withAttributes: [.font: font ?? Theme.font]).width }

    /// Leading-whitespace width in columns of the line [st, ce); nil for blank lines.
    private func indentColumns(_ s: NSString, _ st: Int, _ ce: Int) -> Int? {
        var col = 0, i = st
        let n = max(1, tabColumns)
        while i < ce {
            let c = s.character(at: i)
            if c == 32 { col += 1 } else if c == 9 { col += n - col % n } else { return col }
            i += 1
        }
        return nil
    }

    /// Draws vertical guides at each indent level for the lines intersecting `rect`.
    func drawIndentGuides(in rect: NSRect) {
        guard let lm = layoutManager, let tc = textContainer else { return }
        let s = ns
        guard s.length > 0 else { return }
        let origin = textContainerOrigin
        let local = NSRect(x: rect.minX - origin.x, y: rect.minY - origin.y, width: rect.width, height: rect.height)
        let glyphs = lm.glyphRange(forBoundingRect: local, in: tc)
        guard glyphs.length > 0 else { return }
        let unit = indentUnit.contains("\t") ? max(1, tabColumns) : max(1, indentUnit.utf16.count)

        struct L { var y0: CGFloat; var y1: CGFloat; var cols: Int?; var st: Int; var en: Int }
        var lines: [L] = []
        var glyph = glyphs.location
        while glyph < NSMaxRange(glyphs) {
            let ch = lm.characterIndexForGlyph(at: glyph)
            var st = 0, en = 0, ce = 0
            s.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: ch, length: 0))
            let g = lm.glyphRange(forCharacterRange: NSRange(location: st, length: en - st), actualCharacterRange: nil)
            let f0 = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            var y1 = f0.maxY
            if g.length > 1 { y1 = lm.lineFragmentRect(forGlyphAt: NSMaxRange(g) - 1, effectiveRange: nil).maxY }
            lines.append(L(y0: f0.minY, y1: y1, cols: indentColumns(s, st, ce), st: st, en: en))
            glyph = max(NSMaxRange(g), glyph + 1)
            if folds.hasHidden, let h = folds.hiddenRange(startingAt: ce), h.end > ce {
                // The row continues past folded lines: skip them (and the closer's remainder) in one step.
                let next = folds.nextRowStart(from: st, in: s)
                glyph = max(glyph, next >= s.length ? lm.numberOfGlyphs : lm.glyphIndexForCharacter(at: next))
            }
        }
        guard !lines.isEmpty else { return }

        // Blank lines continue the guides of the surrounding indented lines (min of previous / next non-blank).
        func neighbour(from start: Int, step: Int, limit: Int) -> Int? {
            var pos = start, tries = 0
            while tries < limit {
                var st = 0, en = 0, ce = 0
                if step < 0 {
                    if pos <= 0 { return nil }
                    s.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: pos - 1, length: 0))
                } else {
                    if pos >= s.length { return nil }
                    s.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: pos, length: 0))
                }
                if let c = indentColumns(s, st, ce) { return c }
                pos = step < 0 ? st : en
                tries += 1
            }
            return nil
        }
        var prev = lines.first!.cols == nil ? neighbour(from: lines.first!.st, step: -1, limit: 400) : nil
        var prevs = [Int?](repeating: nil, count: lines.count)
        for i in 0..<lines.count {
            if let c = lines[i].cols { prev = c }
            prevs[i] = prev
        }
        var next = lines.last!.cols == nil ? neighbour(from: lines.last!.en, step: 1, limit: 400) : nil
        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            if let c = lines[i].cols { next = c }
            else if let p = prevs[i], let n = next { lines[i].cols = min(p, n) }
            else { lines[i].cols = 0 }
        }

        let cw = charWidth
        let baseX = origin.x + (textContainer?.lineFragmentPadding ?? 5)
        var rects: [CGRect] = []
        for l in lines {
            guard let c = l.cols, c > 0 else { continue }
            var col = 0
            while col < c {
                let x = (baseX + CGFloat(col) * cw).rounded(.down)
                rects.append(CGRect(x: x, y: l.y0 + origin.y, width: 1, height: l.y1 - l.y0))
                col += unit
            }
        }
        guard !rects.isEmpty, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setFillColor(guideColor.cgColor)
        ctx.fill(rects)
        ctx.restoreGState()
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        if multiCaretActive { return }      // multiple carets are drawn by drawExtraCarets
        var r = rect
        r.size.width = 2
        super.drawInsertionPoint(in: r, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        var r = invalidRect
        r.size.width += 1
        if DirtyTracker.on { DirtyTracker.text = DirtyTracker.text.union(r) }
        super.setNeedsDisplay(r, avoidAdditionalLayout: flag)
    }

    override var needsDisplay: Bool { didSet { if DirtyTracker.on, needsDisplay { DirtyTracker.text = DirtyTracker.text.union(bounds) } } }

    static func commentStyle(forExtension ext: String) -> CommentStyle {
        switch ext.lowercased() {
        case "php", "js", "jsx", "ts", "tsx", "mjs": return .line("//")
        case "css": return .block("/*", "*/")
        case "html", "htm", "vue", "xml": return .block("<!--", "-->")
        case "json": return .none
        case "sh", "bash", "yaml", "yml", "env", "py", "rb", "toml": return .line("#")
        default: return .line("//")
        }
    }

    // MARK: - Helpers

    var ns: NSString { (textStorage?.mutableString ?? NSMutableString(string: string)) as NSString }

    private func isWordUnit(_ c: unichar) -> Bool {
        c == 95 || Unicode.Scalar(UInt32(c)).map { CharacterSet.alphanumerics.contains($0) } ?? false
    }

    private func isBlank(_ c: unichar) -> Bool { c == 32 || c == 9 }

    private func wordRange(at loc: Int) -> NSRange? { languageWordRange(at: loc) }

    /// Whole lines touched by a range; a selection ending exactly at a line start does not touch that line.
    private func touchedLines(_ r: NSRange) -> NSRange {
        let s = ns
        let a = s.lineRange(for: NSRange(location: r.location, length: 0))
        if r.length == 0 { return a }
        let b = s.lineRange(for: NSRange(location: r.upperBound - 1, length: 0))
        return NSRange(location: a.location, length: b.upperBound - a.location)
    }

    private func forEachLine(in block: NSRange, _ body: (_ start: Int, _ contentsEnd: Int, _ end: Int) -> Void) {
        let s = ns
        var loc = block.location
        while loc < block.upperBound {
            var st = 0, en = 0, ce = 0
            s.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: loc, length: 0))
            body(st, ce, en)
            if en <= loc { break }
            loc = en
        }
    }

    @discardableResult
    private func replace(_ range: NSRange, with text: String) -> Bool {
        guard shouldChangeText(in: range, replacementString: text) else { return false }
        textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: typingAttributes))
        didChangeText()
        return true
    }

    /// Replaces a range as exactly one undo step (used by "Revert hunk"); selects nothing, caret goes to the end of the new text.
    func replaceUndoable(_ range: NSRange, with text: String) {
        grouped {
            if replace(range, with: text) { setSelectedRange(NSRange(location: range.location + text.utf16.count, length: 0)) }
        }
    }

    func grouped(_ body: () -> Void) {
        undoManager?.beginUndoGrouping()
        body()
        undoManager?.endUndoGrouping()
    }

    private func reveal(_ r: NSRange) { scrollRangeToVisible(r) }

    /// Applies ascending, non-overlapping edits as one replacement and maps the selection through them.
    private func applyEdits(_ edits: [LineEdit], selection: NSRange) {
        applyEdits(edits, selections: [selection])
    }

    private func applyEdits(_ edits: [LineEdit], selections: [NSRange]) {
        guard let first = edits.first, let last = edits.last else { return }
        let s = ns
        let start = first.loc, end = last.loc + last.len
        var out = "", pos = start
        for e in edits {
            out += s.substring(with: NSRange(location: pos, length: e.loc - pos))
            out += e.text
            pos = e.loc + e.len
        }
        func map(_ o: Int) -> Int {
            var r = o
            for e in edits where e.loc < o { r += e.text.utf16.count - min(e.len, o - e.loc) }
            return r
        }
        let mapped = selections.map { sel -> NSRange in
            let a = map(sel.location), b = map(sel.upperBound)
            return NSRange(location: a, length: max(0, b - a))
        }
        var ok = false
        grouped { ok = replace(NSRange(location: start, length: end - start), with: out) }
        if ok {
            if mapped.count == 1 { setSelectedRange(mapped[0]) }
            else { setMultiSels(mapped.map { MultiCaret.Sel($0) }) }
        }
    }

    /// Replaces several ascending, non-overlapping ranges in one undo step; `caret` is the new caret offset inside each replacement.
    func replaceRanges(_ items: [(range: NSRange, text: String, caret: Int)]) {
        guard !items.isEmpty else { return }
        grouped {
            guard shouldChangeText(inRanges: items.map { NSValue(range: $0.range) }, replacementStrings: items.map { $0.text }) else { return }
            textStorage?.beginEditing()
            for it in items.reversed() {
                textStorage?.replaceCharacters(in: it.range, with: NSAttributedString(string: it.text, attributes: typingAttributes))
            }
            textStorage?.endEditing()
            var carets: [NSValue] = [], shift = 0
            for it in items {
                carets.append(NSValue(range: NSRange(location: it.range.location + shift + it.caret, length: 0)))
                shift += it.text.utf16.count - it.range.length
            }
            didChangeText()
            setMultiSels(carets.map { MultiCaret.Sel(caret: $0.rangeValue.location) })
        }
    }

    // MARK: - Position

    func goToLine(_ line: Int, column: Int = 1) {
        let s = ns
        var loc = 0, n = 1
        while n < line, loc < s.length {
            loc = s.lineRange(for: NSRange(location: loc, length: 0)).upperBound
            n += 1
        }
        var st = 0, en = 0, ce = 0
        s.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: min(loc, s.length), length: 0))
        let caret = st + max(0, min(column - 1, ce - st))
        setSelectedRange(NSRange(location: caret, length: 0))
        centerCaret()
    }

    private func centerCaret() {
        guard let lm = layoutManager, let tc = textContainer, let sv = enclosingScrollView else {
            scrollRangeToVisible(selectedRange()); return
        }
        let glyph = lm.glyphRange(forCharacterRange: selectedRange(), actualCharacterRange: nil)
        lm.ensureLayout(forGlyphRange: glyph)
        var rect = lm.boundingRect(forGlyphRange: glyph, in: tc)
        rect.origin.y += textContainerInset.height
        let clip = sv.contentView
        let maxY = max(0, frame.height - clip.bounds.height)
        let y = min(max(0, rect.midY - clip.bounds.height / 2), maxY)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        sv.reflectScrolledClipView(clip)
    }

    var lineAndColumn: (line: Int, column: Int) {
        let s = ns
        let caret = min(selectedRange().location, s.length)
        var loc = 0, line = 1
        while true {
            var st = 0, en = 0, ce = 0
            s.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: loc, length: 0))
            if caret < en || ce == en { return (line, caret - st + 1) }
            line += 1
            loc = en
        }
    }

    // MARK: - Line actions

    @objc func duplicateLine(_ sender: Any?) {
        let s = ns
        let sel = selectedRange()
        grouped {
            if sel.length > 0 {
                let text = s.substring(with: sel)
                if replace(NSRange(location: sel.upperBound, length: 0), with: text) {
                    setSelectedRange(NSRange(location: sel.upperBound, length: sel.length))
                }
                return
            }
            let line = s.lineRange(for: NSRange(location: sel.location, length: 0))
            var st = 0, en = 0, ce = 0
            s.getLineStart(&st, end: &en, contentsEnd: &ce, for: line)
            if ce == en {
                // last line without terminator
                let text = lineEnding + s.substring(with: line)
                if replace(NSRange(location: en, length: 0), with: text) {
                    setSelectedRange(NSRange(location: sel.location + (en - st) + lineEnding.utf16.count, length: 0))
                }
            } else if replace(NSRange(location: en, length: 0), with: s.substring(with: line)) {
                setSelectedRange(NSRange(location: sel.location + (en - st), length: 0))
            }
        }
    }

    @objc func deleteLine(_ sender: Any?) {
        let s = ns
        var t = touchedLines(selectedRange())
        if t.length == 0 && t.location == 0 { return }
        if t.upperBound == s.length, t.location > 0 {
            let last = s.character(at: s.length - 1)
            if t.length == 0 || (last != 10 && last != 13) {
                var back = 1
                if s.character(at: t.location - 1) == 10, t.location >= 2, s.character(at: t.location - 2) == 13 { back = 2 }
                t = NSRange(location: t.location - back, length: t.length + back)
            }
        }
        grouped {
            if replace(t, with: "") { setSelectedRange(NSRange(location: t.location, length: 0)) }
        }
    }

    @objc func moveLineUp(_ sender: Any?) {
        let s = ns
        let sel = selectedRange()
        let t = touchedLines(sel)
        guard t.location > 0 else { return }
        let prev = s.lineRange(for: NSRange(location: t.location - 1, length: 0))
        let (pc, pt) = split(prev), (bc, bt) = split(t)
        let region = NSRange(location: prev.location, length: prev.length + t.length)
        let new = bc + (pt.isEmpty ? lineEnding : pt) + pc + bt
        let shift = -prev.length
        moveBlock(region, new, selection: NSRange(location: sel.location + shift, length: sel.length))
    }

    @objc func moveLineDown(_ sender: Any?) {
        let s = ns
        let sel = selectedRange()
        let t = touchedLines(sel)
        guard t.upperBound < s.length else { return }
        let next = s.lineRange(for: NSRange(location: t.upperBound, length: 0))
        let (nc, nt) = split(next), (bc, bt) = split(t)
        let region = NSRange(location: t.location, length: t.length + next.length)
        let new = nc + bt + bc + nt
        let shift = nc.utf16.count + bt.utf16.count
        moveBlock(region, new, selection: NSRange(location: sel.location + shift, length: sel.length))
    }

    private func moveBlock(_ region: NSRange, _ text: String, selection: NSRange) {
        grouped {
            if replace(region, with: text) {
                let end = region.location + text.utf16.count
                let loc = min(max(selection.location, region.location), end)
                setSelectedRange(NSRange(location: loc, length: min(selection.length, end - loc)))
            }
        }
    }

    /// Splits a block of whole lines into (content without the final terminator, final terminator).
    private func split(_ r: NSRange) -> (String, String) {
        let s = ns
        guard r.length > 0 else { return ("", "") }
        var st = 0, en = 0, ce = 0
        s.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: r.upperBound - 1, length: 0))
        let end = min(ce, r.upperBound)
        return (s.substring(with: NSRange(location: r.location, length: end - r.location)),
                s.substring(with: NSRange(location: end, length: r.upperBound - end)))
    }

    @objc func joinLines(_ sender: Any?) {
        let s = ns
        let sel = selectedRange()
        var t = touchedLines(sel)
        if splitLineCount(t) <= 1 {
            guard t.upperBound < s.length else { return }
            let next = s.lineRange(for: NSRange(location: t.upperBound, length: 0))
            t = NSRange(location: t.location, length: t.length + next.length)
        }
        var edits: [LineEdit] = []
        var lines: [(Int, Int, Int)] = []
        forEachLine(in: t) { lines.append(($0, $1, $2)) }
        for i in 0..<(lines.count - 1) {
            let (_, ce, en) = lines[i]
            var ws = en
            let nce = lines[i + 1].1
            while ws < nce, isBlank(s.character(at: ws)) { ws += 1 }
            let sep = ws == nce ? "" : " "
            edits.append((ce, ws - ce, sep))
        }
        guard let first = edits.first else { return }
        applyEdits(edits, selection: NSRange(location: first.loc, length: 0))
        setSelectedRange(NSRange(location: first.loc, length: 0))
    }

    private func splitLineCount(_ r: NSRange) -> Int {
        var n = 0
        forEachLine(in: r) { _, _, _ in n += 1 }
        return n
    }

    // MARK: - Comments

    @objc func toggleComment(_ sender: Any?) {
        let s = ns
        let sel = selectedRange()
        let t = touchedLines(sel)
        var lines: [(st: Int, ce: Int)] = []
        forEachLine(in: t) { st, ce, _ in lines.append((st, ce)) }
        if lines.isEmpty { lines = [(t.location, t.location)] }
        func firstNonBlank(_ l: (st: Int, ce: Int)) -> Int? {
            var i = l.st
            while i < l.ce, isBlank(s.character(at: i)) { i += 1 }
            return i < l.ce ? i : nil
        }
        func lastNonBlank(_ l: (st: Int, ce: Int)) -> Int {
            var e = l.ce
            while e > l.st, isBlank(s.character(at: e - 1)) { e -= 1 }
            return e
        }
        let live = lines.filter { firstNonBlank($0) != nil }
        guard !live.isEmpty else { return }
        var edits: [LineEdit] = []
        switch commentStyle {
        case .none: return
        case .line(let p):
            let pl = p.utf16.count
            func hasPrefix(_ l: (st: Int, ce: Int)) -> Bool {
                let f = firstNonBlank(l)!
                return f + pl <= l.ce && s.substring(with: NSRange(location: f, length: pl)) == p
            }
            if live.allSatisfy(hasPrefix) {
                for l in live {
                    let f = firstNonBlank(l)!
                    var n = pl
                    if f + n < l.ce, s.character(at: f + n) == 32 { n += 1 }
                    edits.append((f, n, ""))
                }
            } else {
                let indent = live.map { firstNonBlank($0)! - $0.st }.min()!
                for l in live { edits.append((l.st + indent, 0, p + " ")) }
            }
        case .block(let o, let c):
            let ol = o.utf16.count, cl = c.utf16.count
            func wrapped(_ l: (st: Int, ce: Int)) -> Bool {
                let f = firstNonBlank(l)!, e = lastNonBlank(l)
                return e - f >= ol + cl && s.substring(with: NSRange(location: f, length: ol)) == o
                    && s.substring(with: NSRange(location: e - cl, length: cl)) == c
            }
            if live.allSatisfy(wrapped) {
                for l in live {
                    let f = firstNonBlank(l)!, e = lastNonBlank(l)
                    var n = ol
                    if f + n < e, s.character(at: f + n) == 32 { n += 1 }
                    edits.append((f, n, ""))
                    var m = cl, st = e - cl
                    if st - 1 >= f + ol, s.character(at: st - 1) == 32 { m += 1; st -= 1 }
                    edits.append((st, m, ""))
                }
            } else {
                let indent = live.map { firstNonBlank($0)! - $0.st }.min()!
                for l in live {
                    edits.append((l.st + indent, 0, o + " "))
                    edits.append((lastNonBlank(l), 0, " " + c))
                }
            }
        }
        applyEdits(edits, selection: sel)
    }

    // MARK: - Selection

    @objc func extendSelection(_ sender: Any?) {
        let s = ns
        let r = selectedRange()
        if extendTarget != r { extendHistory.removeAll() }
        func larger(_ c: NSRange) -> Bool {
            c.location <= r.location && c.upperBound >= r.upperBound && c.length > r.length
        }
        var candidates: [NSRange] = []
        if let w = wordRange(at: r.location) { candidates.append(w) }
        var st = 0, en = 0, ce = 0
        s.getLineStart(&st, end: &en, contentsEnd: &ce, for: r)
        candidates.append(NSRange(location: st, length: ce - st))
        candidates.append(NSRange(location: 0, length: s.length))
        guard let next = candidates.first(where: larger) else { return }
        extendHistory.append(r)
        extendTarget = next
        setSelectedRange(next)
        reveal(next)
    }

    @objc func shrinkSelection(_ sender: Any?) {
        guard extendTarget == selectedRange(), let prev = extendHistory.popLast() else { return }
        extendTarget = extendHistory.isEmpty ? nil : prev
        setSelectedRange(prev)
    }

    @objc func toggleCase(_ sender: Any?) {
        var r = selectedRange()
        if r.length == 0 {
            guard let w = wordRange(at: r.location) else { return }
            r = w
        }
        let text = ns.substring(with: r)
        let out = text.contains(where: { $0.isLowercase }) ? text.uppercased() : text.lowercased()
        guard out != text else { return }
        grouped {
            if replace(r, with: out) { setSelectedRange(NSRange(location: r.location, length: out.utf16.count)) }
        }
    }

    // MARK: - Multi-occurrence

    var currentRanges: [NSRange] { effectiveRanges }

    private func syncStack(_ ranges: [NSRange]) {
        if occurrenceStack.isEmpty || !occurrenceStack.allSatisfy({ ranges.contains($0) }) { occurrenceStack = ranges }
    }

    @objc func selectNextOccurrence(_ sender: Any?) {
        let ranges = currentRanges
        guard let primary = ranges.first else { return }
        if ranges.count == 1 && primary.length == 0 {
            if let w = wordRange(at: primary.location) { setSelectedRange(w); occurrenceStack = [w] }
            return
        }
        syncStack(ranges)
        let s = ns
        guard let base = occurrenceStack.first, base.length > 0, let last = occurrenceStack.last else { return }
        let needle = s.substring(with: base)
        var from = last.upperBound
        for _ in 0...ranges.count {
            var f = s.range(of: needle, options: .literal, range: NSRange(location: from, length: s.length - from))
            if f.location == NSNotFound { f = s.range(of: needle, options: .literal) }
            if f.location == NSNotFound { return }
            if !ranges.contains(f) {
                occurrenceStack.append(f)
                multi.lastAdded = f
                setSelectedRanges((ranges + [f]).map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
                reveal(f)
                return
            }
            from = f.upperBound
        }
    }

    @objc func unselectPreviousOccurrence(_ sender: Any?) {
        let ranges = currentRanges
        guard ranges.count > 1 else { return }
        syncStack(ranges)
        guard let drop = occurrenceStack.popLast() else { return }
        let rest = ranges.filter { $0 != drop }
        setSelectedRanges(rest.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
        if occurrenceStack.isEmpty { occurrenceStack = rest }
    }

    @objc func selectAllOccurrences(_ sender: Any?) {
        let s = ns
        var base = selectedRange()
        if base.length == 0 {
            guard let w = wordRange(at: base.location) else { return }
            base = w
        }
        let needle = s.substring(with: base)
        var found: [NSRange] = []
        var from = 0
        while from < s.length {
            let f = s.range(of: needle, options: .literal, range: NSRange(location: from, length: s.length - from))
            if f.location == NSNotFound { break }
            found.append(f)
            from = f.upperBound
        }
        guard !found.isEmpty else { return }
        occurrenceStack = found
        setSelectedRanges(found.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
    }

    // MARK: - Reformat

    /// Safe re-indenter: only lines that begin a statement (previous code line ends with `{ } ; :`, or after a blank line)
    /// are re-indented from bracket depth; continuation lines (chains, multi-line arguments, arrays) and block-comment
    /// bodies are shifted by the same delta as their statement's first line so relative indentation is preserved.
    @objc func reformatCode(_ sender: Any?) {
        guard let edits = reformatEdits() else { return }
        applyEdits(edits.0, selection: edits.1)
    }

    private func columns(_ u: [UInt16], _ a: Int, _ b: Int) -> Int {
        var col = 0
        let n = max(1, tabColumns)
        for i in a..<b { col += u[i] == 9 ? n - col % n : 1 }
        return col
    }

    private func indentString(columns c: Int) -> String {
        if indentUnit.contains("\t") {
            let n = max(1, tabColumns)
            return String(repeating: "\t", count: c / n) + String(repeating: " ", count: c % n)
        }
        return String(repeating: " ", count: c)
    }

    /// Edits a reformat would make (exposed for tests).
    func reformatEdits() -> ([(loc: Int, len: Int, text: String)], NSRange)? {
        var lineComments = false
        switch commentStyle {
        case .block(let o, _): if o == "<!--" { return nil }
        case .line(let p): if p != "//" { return nil }; lineComments = true
        case .none: break
        }
        let u = Array(string.utf16)
        let len = u.count
        guard len > 0 else { return nil }
        let sel = selectedRange()
        let target = sel.length > 0 ? touchedLines(sel) : NSRange(location: 0, length: len)

        enum State: Equatable { case code, block, template, heredoc(String) }
        // openIndent: final indent (columns) of the line that opened the bracket; caseIndent: indent of statements inside a case.
        struct Frame { var isSwitch: Bool; var inCase: Bool; var openIndent: Int; var caseIndent: Int }
        var state = State.code
        var stack: [Frame] = []
        var pendingSwitch = false
        var edits: [LineEdit] = []
        func isIdent(_ c: UInt16) -> Bool { isWordUnit(c) }
        let ch = { (s: String) in s.utf16.first! }
        let slash = ch("/"), star = ch("*"), bs = ch("\\"), bt = ch("`"), lt = ch("<")
        let statementEnders: Set<UInt16> = [123, 125, 59, 58]   // { } ; :
        func startsWord(_ w: String, at p: Int, _ ce: Int) -> Bool {
            let wu = Array(w.utf16)
            guard p + wu.count <= ce, Array(u[p..<(p + wu.count)]) == wu else { return false }
            return p + wu.count == ce || !isIdent(u[p + wu.count])
        }

        var prevAllowsStart = true
        var delta = 0
        let unitCols = columns(Array(indentUnit.utf16), 0, indentUnit.utf16.count)
        var loc = 0
        let s = ns
        while loc < len {
            var st = 0, en = 0, ce = 0
            s.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: loc, length: 0))
            var ws = st
            while ws < ce, isBlank(u[ws]) { ws += 1 }
            var i = st
            let inTarget = st >= target.location && st < target.upperBound
            var lastSig: UInt16?
            var isLabel = false
            var finalCols = columns(u, st, ws)   // indent of this line after reformatting
            if case .heredoc(let id) = state {
                if startsWord(id, at: ws, ce) {
                    state = .code
                    i = ws + id.utf16.count
                } else { i = ce }
            } else if state == .block {
                if inTarget, ws < ce, delta != 0 {
                    let cur = columns(u, st, ws)
                    let new = indentString(columns: max(0, cur + delta))
                    finalCols = max(0, cur + delta)
                    if s.substring(with: NSRange(location: st, length: ws - st)) != new { edits.append((st, ws - st, new)) }
                }
            } else if state == .code, ws < ce {
                var closers = 0, k = ws
                while k < ce, u[k] == 125 || u[k] == 41 || u[k] == 93 { closers += 1; k += 1 }
                if let top = stack.last, top.isSwitch, startsWord("case", at: ws, ce) || startsWord("default", at: ws, ce) {
                    isLabel = true
                }
                if !inTarget { delta = 0 }
                else if prevAllowsStart || closers > 0 {
                    // Align closers with the line that opened their bracket; otherwise indent one level inside the
                    // innermost open bracket (case bodies one level inside their label).
                    var base = 0
                    if closers > 0 { base = stack.indices.contains(stack.count - closers) ? stack[stack.count - closers].openIndent : 0 }
                    else if let top = stack.last { base = isLabel ? top.openIndent + unitCols : (top.inCase ? top.caseIndent : top.openIndent + unitCols) }
                    finalCols = base
                    let want = indentString(columns: base)
                    delta = base - columns(u, st, ws)
                    if s.substring(with: NSRange(location: st, length: ws - st)) != want { edits.append((st, ws - st, want)) }
                } else if delta != 0 {
                    finalCols = max(0, columns(u, st, ws) + delta)
                    let new = indentString(columns: finalCols)
                    if s.substring(with: NSRange(location: st, length: ws - st)) != new { edits.append((st, ws - st, new)) }
                }
            } else if !inTarget { delta = 0 }
            if ws >= ce, state == .code { prevAllowsStart = true }   // blank line
            var sawCode = false
            while i < ce {
                let c = u[i]
                switch state {
                case .heredoc: i = ce; continue
                case .block:
                    if c == star, i + 1 < ce, u[i + 1] == slash { state = .code; i += 2; continue }
                case .template:
                    if c == bs { i += 2; continue }
                    if c == bt { state = .code; lastSig = c; sawCode = true }
                case .code:
                    if c == slash, i + 1 < ce {
                        if u[i + 1] == slash, lineComments { i = ce; continue }
                        if u[i + 1] == star { state = .block; i += 2; continue }
                    }
                    if isBlank(c) { i += 1; continue }
                    sawCode = true
                    lastSig = c
                    if c == 34 || c == 39 {
                        var j = i + 1
                        while j < ce, u[j] != c { j += u[j] == bs ? 2 : 1 }
                        i = j + 1
                        continue
                    }
                    if c == bt, lineComments { state = .template }
                    else if c == lt, lineComments, i + 2 < ce, u[i + 1] == lt, u[i + 2] == lt {
                        var j = i + 3
                        while j < ce, isBlank(u[j]) { j += 1 }
                        let quoted = j < ce && (u[j] == 34 || u[j] == 39)
                        if quoted { j += 1 }
                        let a = j
                        while j < ce, isIdent(u[j]) { j += 1 }
                        if j > a { state = .heredoc(String(utf16CodeUnits: Array(u[a..<j]), count: j - a)); i = ce; continue }
                    }
                    else if isIdent(c) {   // consume the whole word so `switch` inside identifiers is not matched
                        var j = i
                        while j < ce, isIdent(u[j]) { j += 1 }
                        if startsWord("switch", at: i, ce) { pendingSwitch = true }
                        lastSig = u[j - 1]
                        i = j
                        continue
                    }
                    else if c == 123 { stack.append(Frame(isSwitch: pendingSwitch, inCase: false, openIndent: finalCols, caseIndent: 0)); pendingSwitch = false }
                    else if c == 40 || c == 91 { stack.append(Frame(isSwitch: false, inCase: false, openIndent: finalCols, caseIndent: 0)) }
                    else if c == 125 || c == 41 || c == 93 { _ = stack.popLast() }
                    else if c == 59 { pendingSwitch = false }
                }
                i += 1
            }
            if isLabel, !stack.isEmpty { stack[stack.count - 1].inCase = true; stack[stack.count - 1].caseIndent = finalCols + unitCols }
            if sawCode, let l = lastSig { prevAllowsStart = statementEnders.contains(l) }
            if en <= loc { break }
            loc = en
        }
        return (edits, sel)
    }

    // MARK: - Overrides

    /// Replacement text and caret offset for a Return at `sel`.
    private func newlineEdit(for sel: NSRange) -> (text: String, caret: Int) {
        let s = ns
        let ls = s.lineRange(for: NSRange(location: sel.location, length: 0)).location
        var ws = ls
        while ws < sel.location, isBlank(s.character(at: ws)) { ws += 1 }
        let indent = s.substring(with: NSRange(location: ls, length: ws - ls))
        var p = sel.location
        while p > ls, isBlank(s.character(at: p - 1)) { p -= 1 }
        let prev: unichar? = p > ls ? s.character(at: p - 1) : nil
        let closers: [unichar: unichar] = [123: 125, 40: 41, 91: 93]
        var text = lineEnding + indent
        var caretOffset = text.utf16.count
        if let pv = prev, let close = closers[pv] {
            text += indentUnit
            caretOffset = text.utf16.count
            if sel.upperBound < s.length, s.character(at: sel.upperBound) == close { text += lineEnding + indent }
        }
        return (text, caretOffset)
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText() else { super.insertNewline(sender); return }
        let ranges = currentRanges.sorted { $0.location < $1.location }
        if ranges.count == 1 {
            let sel = ranges[0]
            let (text, caret) = newlineEdit(for: sel)
            grouped {
                if replace(sel, with: text) { setSelectedRange(NSRange(location: sel.location + caret, length: 0)) }
            }
            return
        }
        replaceRanges(ranges.map { r in let e = newlineEdit(for: r); return (r, e.text, e.caret) })
    }

    /// Union of whole lines touched by the given ranges as (start, contentsEnd) pairs, ascending and unique.
    private func touchedLineList(_ ranges: [NSRange]) -> [(st: Int, ce: Int)] {
        var seen = Set<Int>(), out: [(st: Int, ce: Int)] = []
        for r in ranges.sorted(by: { $0.location < $1.location }) {
            if r.length == 0 {
                let ls = ns.lineRange(for: NSRange(location: min(r.location, ns.length), length: 0))
                var st = 0, en = 0, ce = 0
                ns.getLineStart(&st, end: &en, contentsEnd: &ce, for: ls)
                if seen.insert(st).inserted { out.append((st, ce)) }
                continue
            }
            forEachLine(in: touchedLines(r)) { st, ce, _ in if seen.insert(st).inserted { out.append((st, ce)) } }
        }
        return out.sorted { $0.st < $1.st }
    }

    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText() else { super.insertTab(sender); return }
        let s = ns
        let ranges = currentRanges.sorted { $0.location < $1.location }
        let n = max(1, tabColumns)
        if ranges.contains(where: { $0.length > 0 }) {
            // Any selection indents the touched lines (blank lines are left alone).
            let edits: [LineEdit] = touchedLineList(ranges).filter { $0.ce > $0.st }.map { ($0.st, 0, indentUnit) }
            applyEdits(edits, selections: ranges)
            return
        }
        replaceRanges(ranges.map { r in
            let ls = s.lineRange(for: NSRange(location: min(r.location, s.length), length: 0)).location
            let col = r.location - ls
            let pad = useTabs ? "\t" : String(repeating: " ", count: n - col % n)
            return (r, pad, pad.utf16.count)
        })
    }

    override func insertBacktab(_ sender: Any?) {
        let s = ns
        let ranges = currentRanges.sorted { $0.location < $1.location }
        let n = max(1, tabColumns)
        var edits: [LineEdit] = []
        for (st, ce) in touchedLineList(ranges) {
            if st < ce, s.character(at: st) == 9 { edits.append((st, 1, "")); continue }
            var k = 0
            while k < n, st + k < ce, s.character(at: st + k) == 32 { k += 1 }
            if k > 0 { edits.append((st, k, "")) }
        }
        applyEdits(edits, selections: ranges)
    }

    static let pairs: [unichar: unichar] = [40: 41, 91: 93, 123: 125, 34: 34, 39: 39, 96: 96]

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""
        let u = Array(text.utf16)
        if multiCaretActive, replacementRange.location == NSNotFound {
            multiType(text)
            return
        }
        guard u.count == 1, selectedRanges.count == 1, !multiCaretActive, !hasMarkedText(), replacementRange.location == NSNotFound else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let c = u[0]
        let s = ns
        let sel = selectedRange()
        let next: unichar? = sel.upperBound < s.length ? s.character(at: sel.upperBound) : nil
        let isQuote = c == 34 || c == 39 || c == 96
        let isCloser = c == 41 || c == 93 || c == 125

        if sel.length == 0, (isCloser || isQuote), next == c {
            setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            return
        }
        guard let close = Self.pairs[c], !isCloserOnly(c) else {
            super.insertText(string, replacementRange: replacementRange)
            return
        }
        let closeStr = String(utf16CodeUnits: [close], count: 1)
        if sel.length > 0 {
            let inner = s.substring(with: sel)
            grouped {
                if replace(sel, with: text + inner + closeStr) {
                    setSelectedRange(NSRange(location: sel.location + 1, length: sel.length))
                }
            }
            return
        }
        let prev: unichar? = sel.location > 0 ? s.character(at: sel.location - 1) : nil
        if isQuote, let pv = prev, isWordUnit(pv) || pv == 92 || pv == c {
            super.insertText(string, replacementRange: replacementRange); return
        }
        var nextOK = next == nil
        if let nx = next {
            nextOK = nx == 32 || nx == 9 || nx == 10 || nx == 13 || [41, 93, 125, 44, 59, 62].contains(nx)
        }
        guard nextOK else { super.insertText(string, replacementRange: replacementRange); return }
        if replace(sel, with: text + closeStr) { setSelectedRange(NSRange(location: sel.location + 1, length: 0)) }
    }

    private func isCloserOnly(_ c: unichar) -> Bool { c == 41 || c == 93 || c == 125 }

    // MARK: - Folding hooks

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        if folds.hasHidden { for v in affectedRanges { folds.unfold(intersecting: v.rangeValue) } }
        return super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
    }

    override func doCommand(by selector: Selector) {
        if multiCaretActive, handleMultiCommand(selector) { return }
        let was = userNavigating
        userNavigating = true
        defer { userNavigating = was }
        let before = selectedRanges.first?.rangeValue
        super.doCommand(by: selector)
        snapAfterNavigation(previous: before)
    }

    /// AppKit moves the caret for some commands through paths we cannot override; re-snap afterwards.
    private func snapAfterNavigation(previous: NSRange?) {
        guard folds.hasHidden else { return }
        let now = selectedRanges
        let fixed = folds.normalized(now, navigating: true, previous: previous)
        if fixed != now {
            super.setSelectedRanges(fixed, affinity: selectionAffinity, stillSelecting: false)
            super.scrollRangeToVisible(selectedRange())
        }
    }

    override func paste(_ sender: Any?) { if !multiPaste() { super.paste(sender) } }
    override func copy(_ sender: Any?) { if !multiCopy() { super.copy(sender) } }
    override func cut(_ sender: Any?) { if !multiCut() { super.cut(sender) } }

    override func mouseDown(with event: NSEvent) {
        if handleOptionMouseDown(event) { return }
        if folds.hasHidden, let r = folds.hiddenRange(atChipPoint: convert(event.locationInWindow, from: nil)) {
            folds.expand(r, recursive: event.modifierFlags.contains(.option))
            return
        }
        let was = userNavigating
        userNavigating = true
        defer { userNavigating = was }
        let before = selectedRanges.first?.rangeValue
        super.mouseDown(with: event)
        snapAfterNavigation(previous: before)
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        if folds.hasHidden, !userNavigating { folds.unfold(intersecting: range) }
        super.scrollRangeToVisible(range)
    }

    override func showFindIndicator(for charRange: NSRange) {
        if folds.hasHidden { folds.unfold(intersecting: charRange) }
        super.showFindIndicator(for: charRange)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard folds.hasHidden, let lm = layoutManager, let tc = textContainer else { return }
        let glyphs = lm.glyphRange(forBoundingRect: visibleRect, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        for h in folds.hiddenRanges(overlapping: chars) {
            if let r = folds.chipRect(for: h) { addCursorRect(r, cursor: .pointingHand) }
        }
    }

    /// Draws the placeholder chip of every visible folded range.
    private func drawFoldChips(in rect: NSRect) {
        guard folds.hasHidden, let lm = layoutManager, let tc = textContainer else { return }
        let origin = textContainerOrigin
        let local = NSRect(x: rect.minX - origin.x, y: rect.minY - origin.y, width: rect.width, height: rect.height)
        let glyphs = lm.glyphRange(forBoundingRect: local, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let dark = Theme.isDark
        for h in folds.hiddenRanges(overlapping: chars) {
            guard let r = folds.chipRect(for: h), r.intersects(rect) else { continue }
            let fill = Theme.foreground.withAlphaComponent(dark ? 0.14 : 0.09)
            let stroke = Theme.foreground.withAlphaComponent(dark ? 0.22 : 0.16)
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            fill.setFill(); path.fill()
            stroke.setStroke(); path.lineWidth = 1; path.stroke()
            let font = folds.chipFont(at: h.start)
            let label = h.placeholder as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.foreground.withAlphaComponent(dark ? 0.75 : 0.6)]
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: r.minX + (r.width - size.width) / 2, y: r.minY + (r.height - size.height) / 2), withAttributes: attrs)
        }
    }

    /// Called by the fold engine after folds or regions changed.
    func foldsDidChange() {
        onFoldsChange?()
        NotificationCenter.default.post(name: Self.foldsDidChangeNotification, object: self)
    }

    // MARK: - Line / word navigation (PhpStorm semantics, own anchor tracking)

    private var singleSelection: Bool { selectedRanges.count == 1 && !multiCaretActive && !hasMarkedText() }

    override func moveToBeginningOfLine(_ sender: Any?) { if singleSelection { navigate(extend: false) { smartHome(from: $0) } } else { super.moveToBeginningOfLine(sender) } }
    override func moveToLeftEndOfLine(_ sender: Any?) { if singleSelection { navigate(extend: false) { smartHome(from: $0) } } else { super.moveToLeftEndOfLine(sender) } }
    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) { if singleSelection { navigate(extend: true) { smartHome(from: $0) } } else { super.moveToBeginningOfLineAndModifySelection(sender) } }
    override func moveToLeftEndOfLineAndModifySelection(_ sender: Any?) { if singleSelection { navigate(extend: true) { smartHome(from: $0) } } else { super.moveToLeftEndOfLineAndModifySelection(sender) } }
    override func moveToEndOfLine(_ sender: Any?) { if singleSelection { navigate(extend: false) { rowBounds(containing: $0).end } } else { super.moveToEndOfLine(sender) } }
    override func moveToRightEndOfLine(_ sender: Any?) { if singleSelection { navigate(extend: false) { rowBounds(containing: $0).end } } else { super.moveToRightEndOfLine(sender) } }
    override func moveToEndOfLineAndModifySelection(_ sender: Any?) { if singleSelection { navigate(extend: true) { rowBounds(containing: $0).end } } else { super.moveToEndOfLineAndModifySelection(sender) } }
    override func moveToRightEndOfLineAndModifySelection(_ sender: Any?) { if singleSelection { navigate(extend: true) { rowBounds(containing: $0).end } } else { super.moveToRightEndOfLineAndModifySelection(sender) } }

    override func moveWordLeft(_ sender: Any?) { if singleSelection { navigate(extend: false) { wordStop(from: $0, forward: false) } } else { super.moveWordLeft(sender) } }
    override func moveWordBackward(_ sender: Any?) { if singleSelection { navigate(extend: false) { wordStop(from: $0, forward: false) } } else { super.moveWordBackward(sender) } }
    override func moveWordRight(_ sender: Any?) { if singleSelection { navigate(extend: false) { wordStop(from: $0, forward: true) } } else { super.moveWordRight(sender) } }
    override func moveWordForward(_ sender: Any?) { if singleSelection { navigate(extend: false) { wordStop(from: $0, forward: true) } } else { super.moveWordForward(sender) } }
    override func moveWordLeftAndModifySelection(_ sender: Any?) { if singleSelection { navigate(extend: true) { wordStop(from: $0, forward: false) } } else { super.moveWordLeftAndModifySelection(sender) } }
    override func moveWordBackwardAndModifySelection(_ sender: Any?) { if singleSelection { navigate(extend: true) { wordStop(from: $0, forward: false) } } else { super.moveWordBackwardAndModifySelection(sender) } }
    override func moveWordRightAndModifySelection(_ sender: Any?) { if singleSelection { navigate(extend: true) { wordStop(from: $0, forward: true) } } else { super.moveWordRightAndModifySelection(sender) } }
    override func moveWordForwardAndModifySelection(_ sender: Any?) { if singleSelection { navigate(extend: true) { wordStop(from: $0, forward: true) } } else { super.moveWordForwardAndModifySelection(sender) } }

    override func moveToBeginningOfDocument(_ sender: Any?) { if singleSelection { navigate(extend: false) { _ in 0 } } else { super.moveToBeginningOfDocument(sender) } }
    override func moveToEndOfDocument(_ sender: Any?) { if singleSelection { navigate(extend: false) { _ in ns.length } } else { super.moveToEndOfDocument(sender) } }
    override func moveToBeginningOfDocumentAndModifySelection(_ sender: Any?) { if singleSelection { navigate(extend: true) { _ in 0 } } else { super.moveToBeginningOfDocumentAndModifySelection(sender) } }
    override func moveToEndOfDocumentAndModifySelection(_ sender: Any?) { if singleSelection { navigate(extend: true) { _ in ns.length } } else { super.moveToEndOfDocumentAndModifySelection(sender) } }

    /// Home / End keys move the caret like PhpStorm (they only scroll in a stock NSTextView).
    override func scrollToBeginningOfDocument(_ sender: Any?) { if singleSelection { navigate(extend: false) { smartHome(from: $0) } } else { super.scrollToBeginningOfDocument(sender) } }
    override func scrollToEndOfDocument(_ sender: Any?) { if singleSelection { navigate(extend: false) { rowBounds(containing: $0).end } } else { super.scrollToEndOfDocument(sender) } }

    /// Option-Backspace: delete back to the previous word stop.
    override func deleteWordBackward(_ sender: Any?) {
        let sel = selectedRange()
        guard singleSelection, sel.length == 0, sel.location > 0 else { super.deleteWordBackward(sender); return }
        let target = wordStop(from: sel.location, forward: false)
        let r = NSRange(location: target, length: sel.location - target)
        guard r.length > 0 else { return }
        grouped { if replace(r, with: "") { setSelectedRange(NSRange(location: r.location, length: 0)) } }
    }

    // MARK: Word selection

    override func selectionRange(forProposedRange proposed: NSRange, granularity: NSSelectionGranularity) -> NSRange {
        let base = super.selectionRange(forProposedRange: proposed, granularity: granularity)
        guard granularity == .selectByWord, ns.length > 0, proposed.location <= ns.length else { return base }
        let lo = min(proposed.location, ns.length - 1)
        let first = languageWordRange(at: lo, preferAfter: true)
        if proposed.length == 0 { return first ?? base }
        let last = languageWordRange(at: max(lo, min(proposed.upperBound, ns.length) - 1), preferAfter: false)
        let a = first?.location ?? base.location
        let b = last.map { NSMaxRange($0) } ?? NSMaxRange(base)
        return NSRange(location: a, length: max(0, b - a))
    }

    override func didChangeText() {
        super.didChangeText()
        multiTextDidChange()
        navRange = nil
        clearOccurrences()
        scheduleOccurrences()
    }

    override func deleteForward(_ sender: Any?) {
        let sel = selectedRange()
        if selectedRanges.count == 1, sel.length == 0, let h = folds.hiddenRange(startingAt: sel.location) {
            folds.unfold(intersecting: NSRange(location: h.start + 1, length: 0)); return     // Delete at a fold's edge expands it
        }
        super.deleteForward(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange()
        let s = ns
        if selectedRanges.count == 1, sel.length == 0, let h = folds.hidden.first(where: { $0.end == sel.location }) {
            folds.unfold(intersecting: NSRange(location: h.start + 1, length: 0)); return
        }
        // Smart Backspace: inside a line's leading whitespace, remove one indent level instead of one space.
        if !hasMarkedText(), currentRanges.allSatisfy({ $0.length == 0 }) {
            let carets = currentRanges.sorted { $0.location < $1.location }
            let smart = carets.map { smartIndentDeletion(at: $0.location) }
            if smart.contains(where: { $0 != nil }) {
                if carets.count == 1, let r = smart[0] {
                    grouped { if replace(r, with: "") { setSelectedRange(NSRange(location: r.location, length: 0)) } }
                    return
                }
                var items: [(range: NSRange, text: String, caret: Int)] = []
                var lastEnd = 0
                for (c, sm) in zip(carets, smart) {
                    var r = sm ?? singleCharBefore(c.location)
                    guard r.length > 0 else { continue }
                    if r.location < lastEnd { let e = r.upperBound; r = NSRange(location: lastEnd, length: max(0, e - lastEnd)) }
                    guard r.length > 0 else { continue }
                    items.append((r, "", 0)); lastEnd = r.upperBound
                }
                replaceRanges(items)
                return
            }
        }
        if selectedRanges.count == 1, sel.length == 0, sel.location > 0, sel.location < s.length, !hasMarkedText(),
           let close = Self.pairs[s.character(at: sel.location - 1)], s.character(at: sel.location) == close {
            let r = NSRange(location: sel.location - 1, length: 2)
            grouped { if replace(r, with: "") { setSelectedRange(NSRange(location: r.location, length: 0)) } }
            return
        }
        super.deleteBackward(sender)
    }
}


// MARK: - Navigation helpers, smart backspace, language-aware words, occurrence highlighting

extension CodeTextView {
    enum WordFlavor { case code, css, markup, blade }

    var wordFlavor: WordFlavor {
        let name = (foldFileName ?? (delegate as? EditorTab)?.url.lastPathComponent ?? "").lowercased()
        if name.hasSuffix(".blade.php") { return .blade }
        switch (name as NSString).pathExtension {
        case "css", "scss", "sass", "less": return .css
        case "html", "htm", "vue", "xml", "svg", "xhtml", "twig": return .markup
        default: return .code
        }
    }

    private func isAlnum(_ c: unichar) -> Bool {
        c == 95 || (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
            || (c > 127 && (Unicode.Scalar(UInt32(c)).map { CharacterSet.alphanumerics.contains($0) } ?? false))
    }

    func isIdentChar(_ c: unichar, _ f: WordFlavor) -> Bool {
        if isAlnum(c) { return true }
        switch f {
        case .code: return c == 36
        case .css: return c == 45
        case .markup: return c == 45 || c == 36
        case .blade: return c == 36
        }
    }

    /// The token around `loc` using the file type's word characters (`$var`, `.class`, `--custom-prop`, `v-model`, `@click`).
    func languageWordRange(at loc: Int, preferAfter: Bool = false) -> NSRange? {
        let s = string as NSString
        guard s.length > 0 else { return nil }
        let f = wordFlavor
        let loc = min(max(0, loc), s.length)
        var seed = loc
        let onNext = loc < s.length && isIdentChar(s.character(at: loc), f)
        let onPrev = loc > 0 && isIdentChar(s.character(at: loc - 1), f)
        if preferAfter { if !onNext { if onPrev { seed = loc - 1 } else { return nil } } }
        else if !onPrev { if onNext { seed = loc } else { return nil } }
        else { seed = loc - 1 }
        var a = seed, b = seed + 1
        while a > 0, isIdentChar(s.character(at: a - 1), f) { a -= 1 }
        while b < s.length, isIdentChar(s.character(at: b), f) { b += 1 }
        // A run made only of hyphens / dollars is punctuation, not a word.
        var hasAlnum = false
        for i in a..<b where isAlnum(s.character(at: i)) { hasAlnum = true; break }
        guard hasAlnum else { return nil }
        // Language prefixes: CSS `.` / `#`, markup directives `@` `:` `#`, Blade `@`.
        if a > 0 {
            let p = s.character(at: a - 1)
            switch f {
            case .css: if p == 46 || p == 35 { a -= 1 }
            case .blade: if p == 64 { a -= 1 }
            case .markup:
                if p == 64 || p == 58 || p == 35, a == 1 || [32, 9, 10, 13].contains(s.character(at: a - 2)) { a -= 1 }
            case .code: break
            }
        }
        return NSRange(location: a, length: b - a)
    }

    // MARK: Rows, home / end, word stops

    /// Start and content end of the visual row (a logical line plus the lines folded into it) containing `loc`.
    func rowBounds(containing loc: Int) -> (start: Int, end: Int) {
        let s = string as NSString
        func bounds(_ p: Int) -> (st: Int, ce: Int) {
            var st = 0, en = 0, ce = 0
            s.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: min(max(0, p), s.length), length: 0))
            return (st, ce)
        }
        var (start, end) = bounds(loc)
        guard folds.hasHidden else { return (start, end) }
        while let h = folds.hidden.first(where: { $0.end >= start && $0.end <= end && $0.start < start }) { start = bounds(h.start).st }
        while let h = folds.hiddenRange(startingAt: end), h.end > end { end = bounds(h.end).ce }
        return (start, end)
    }

    /// First press -> first non-blank character, next press -> column 0 (from inside the indent: column 0).
    func smartHome(from head: Int) -> Int {
        let s = string as NSString
        let (start, _) = rowBounds(containing: head)
        var st = 0, en = 0, ce = 0
        s.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: min(start, s.length), length: 0))
        var fnw = st
        while fnw < ce, s.character(at: fnw) == 32 || s.character(at: fnw) == 9 { fnw += 1 }
        if fnw >= ce { return start }                                  // blank line: column 0
        if head > start && head <= fnw { return start }                // inside the indent (or at its end): column 0
        return fnw
    }

    private enum CharClass { case space, ident, punct, newline }

    private func charClass(_ c: unichar, _ f: WordFlavor) -> CharClass {
        if c == 10 || c == 13 { return .newline }
        if c == 32 || c == 9 { return .space }
        return isIdentChar(c, f) ? .ident : .punct
    }

    /// Mac-style word stops: identifier runs (with `$`, `_`), punctuation runs and line breaks are separate stops.
    func wordStop(from p: Int, forward: Bool) -> Int {
        let s = string as NSString
        let f = wordFlavor
        var i = p
        if forward {
            guard i < s.length else { return i }
            if charClass(s.character(at: i), f) == .newline {
                if s.character(at: i) == 13, i + 1 < s.length, s.character(at: i + 1) == 10 { return i + 2 }
                return i + 1
            }
            while i < s.length, charClass(s.character(at: i), f) == .space { i += 1 }
            if i >= s.length || charClass(s.character(at: i), f) == .newline { return i }
            let cls = charClass(s.character(at: i), f)
            while i < s.length, charClass(s.character(at: i), f) == cls { i += 1 }
            return i
        }
        guard i > 0 else { return 0 }
        if charClass(s.character(at: i - 1), f) == .newline {
            i -= 1
            if s.character(at: i) == 10, i > 0, s.character(at: i - 1) == 13 { i -= 1 }
            return i
        }
        while i > 0, charClass(s.character(at: i - 1), f) == .space { i -= 1 }
        if i == 0 || charClass(s.character(at: i - 1), f) == .newline { return i }
        let cls = charClass(s.character(at: i - 1), f)
        while i > 0, charClass(s.character(at: i - 1), f) == cls { i -= 1 }
        return i
    }

    /// Moves / extends the selection from our own anchor so stale AppKit selection state cannot skew it.
    func navigate(extend: Bool, _ target: (Int) -> Int) {
        let r = selectedRange()
        var anchor = r.location, head = r.location
        if r.length > 0 {
            if let nr = navRange, nr == r { anchor = navAnchor; head = navHead } else { anchor = r.location; head = r.upperBound }
        }
        let t = min(max(0, target(head)), (string as NSString).length)
        let newAnchor = extend ? anchor : t
        let range = NSRange(location: min(newAnchor, t), length: abs(newAnchor - t))
        let was = userNavigating
        userNavigating = true
        setSelectedRange(range)
        scrollRangeToVisible(NSRange(location: t, length: 0))
        userNavigating = was
        navAnchor = newAnchor
        navHead = t
        navRange = selectedRange()
    }

    // MARK: Smart Backspace

    func smartIndentDeletion(at loc: Int) -> NSRange? {
        let s = string as NSString
        guard loc > 0, loc <= s.length else { return nil }
        let ls = s.lineRange(for: NSRange(location: loc, length: 0)).location
        guard ls < loc else { return nil }
        var i = ls
        while i < loc { let c = s.character(at: i); if c != 32 && c != 9 { return nil }; i += 1 }
        if s.character(at: loc - 1) == 9 { return NSRange(location: loc - 1, length: 1) }
        let n = max(1, tabColumns)
        var col = 0
        for j in ls..<loc { col += s.character(at: j) == 9 ? n - col % n : 1 }
        let target = ((col - 1) / n) * n
        var k = 0
        while k < col - target, loc - k - 1 >= ls, s.character(at: loc - k - 1) == 32 { k += 1 }
        return NSRange(location: loc - k, length: k)
    }

    func singleCharBefore(_ loc: Int) -> NSRange {
        let s = string as NSString
        guard loc > 0, loc <= s.length else { return NSRange(location: loc, length: 0) }
        if s.character(at: loc - 1) == 10, loc >= 2, s.character(at: loc - 2) == 13 { return NSRange(location: loc - 2, length: 2) }
        return s.rangeOfComposedCharacterSequence(at: loc - 1)
    }

    // MARK: Occurrence highlighting

    func clearOccurrences() {
        if !occurrences.isEmpty { occurrences = []; needsDisplay = true }
    }

    func scheduleOccurrences() {
        occurrenceWork?.cancel()
        guard Prefs.highlightOccurrences else { clearOccurrences(); return }
        let work = DispatchWorkItem { [weak self] in self?.computeOccurrences() }
        occurrenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func occurrenceColors() -> (read: NSColor, write: NSColor) {
        (Theme.palette.occurrenceRead, Theme.palette.occurrenceWrite)
    }

    /// 0 = code, 1 = comment, 2 = string, judged by the highlighter's colours (cheap, no re-lexing).
    private func lexicalKind(at i: Int) -> Int {
        guard let lm = layoutManager, i < (string as NSString).length else { return 0 }
        if let c = lm.temporaryAttribute(.foregroundColor, atCharacterIndex: i, effectiveRange: nil) as? NSColor {
            func same(_ a: NSColor?, _ b: NSColor) -> Bool { a?.usingColorSpace(.sRGB) == b.usingColorSpace(.sRGB) }
            for key in ["comment", "comment.doc", "comment.line"] where same(Theme.color(for: key), c) { return 1 }
            for key in ["string", "string.special"] where same(Theme.color(for: key), c) { return 2 }
        }
        return lineLexicalKind(at: i)
    }

    /// The light theme leaves strings uncoloured, so also scan the line: quotes before `i` (and `//` / `#`) decide.
    private func lineLexicalKind(at i: Int) -> Int {
        let s = string as NSString
        let ls = s.lineRange(for: NSRange(location: i, length: 0)).location
        var quote: unichar = 0
        var j = ls
        while j < i {
            let c = s.character(at: j)
            if quote != 0 {
                if c == 92 { j += 2; continue }
                if c == quote { quote = 0 }
            } else if c == 39 || c == 34 || c == 96 { quote = c }
            else if c == 35 || (c == 47 && j + 1 < s.length && s.character(at: j + 1) == 47) { return 1 }
            j += 1
        }
        return quote != 0 ? 2 : 0
    }

    func computeOccurrences() {
        let s = string as NSString
        guard Prefs.highlightOccurrences, s.length > 0, s.length <= 2_000_000, selectedRanges.count == 1, !multiCaretActive else { clearOccurrences(); return }
        let sel = selectedRange()
        let f = wordFlavor
        var token: NSRange?
        if sel.length == 0 {
            if let w = languageWordRange(at: sel.location) { token = w }
        } else if sel.length <= 200, let w = languageWordRange(at: sel.location, preferAfter: true), w == sel { token = w }
        guard let tok = token else { clearOccurrences(); return }
        let word = s.substring(with: tok)
        let kind = lexicalKind(at: tok.location)
        var found: [Occurrence] = []
        var from = 0
        while from < s.length, found.count < 5000 {
            let r = s.range(of: word, options: [.literal], range: NSRange(location: from, length: s.length - from))
            if r.location == NSNotFound { break }
            from = r.upperBound
            let beforeOK = r.location == 0 || !isIdentChar(s.character(at: r.location - 1), f)
            let afterOK = r.upperBound >= s.length || !isIdentChar(s.character(at: r.upperBound), f)
            guard beforeOK, afterOK, r != tok else { continue }
            if lexicalKind(at: r.location) != kind { continue }
            found.append(Occurrence(range: r, isWrite: isWriteUsage(s, r)))
        }
        occurrences = found
        needsDisplay = true
    }

    private func isWriteUsage(_ s: NSString, _ r: NSRange) -> Bool {
        var i = r.upperBound
        while i < s.length, s.character(at: i) == 32 || s.character(at: i) == 9 { i += 1 }
        func ch(_ k: Int) -> unichar { k < s.length ? s.character(at: k) : 0 }
        let c0 = ch(i), c1 = ch(i + 1), c2 = ch(i + 2)
        if c0 == 61 { return c1 != 61 && c1 != 62 }                                        // `=` but not `==` / `=>`
        if "+-*/.%|&^".utf16.contains(c0), c1 == 61 { return true }                        // `+=` `.=` ...
        if (c0 == 43 && c1 == 43) || (c0 == 45 && c1 == 45) { return true }                // `++` `--`
        if c0 == 63, c1 == 63, c2 == 61 { return true }                                    // `??=`
        if (c0 == 60 && c1 == 60 || c0 == 62 && c1 == 62), c2 == 61 { return true }        // `<<=` `>>=`
        var j = r.location - 1
        while j >= 0, s.character(at: j) == 32 || s.character(at: j) == 9 { j -= 1 }
        if j >= 1, (s.character(at: j) == 43 && s.character(at: j - 1) == 43) || (s.character(at: j) == 45 && s.character(at: j - 1) == 45) { return true }
        return false
    }

    func drawOccurrences(in rect: NSRect) {
        guard !occurrences.isEmpty, Prefs.highlightOccurrences, let lm = layoutManager, let tc = textContainer else { return }
        let origin = textContainerOrigin
        let local = NSRect(x: rect.minX - origin.x, y: rect.minY - origin.y, width: rect.width, height: rect.height)
        let glyphs = lm.glyphRange(forBoundingRect: local, in: tc)
        guard glyphs.length > 0 else { return }
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var lo = 0, hi = occurrences.count
        while lo < hi { let mid = (lo + hi) / 2; if NSMaxRange(occurrences[mid].range) < chars.location { lo = mid + 1 } else { hi = mid } }
        let (read, write) = occurrenceColors()
        var i = lo
        while i < occurrences.count, occurrences[i].range.location <= NSMaxRange(chars) {
            let occ = occurrences[i]
            i += 1
            if folds.hasHidden, folds.hiddenRange(containing: occ.range.location) != nil { continue }
            let g = lm.glyphRange(forCharacterRange: occ.range, actualCharacterRange: nil)
            (occ.isWrite ? write : read).setFill()
            lm.enumerateEnclosingRects(forGlyphRange: g, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { r, _ in
                let box = NSRect(x: r.minX + origin.x, y: r.minY + origin.y, width: r.width, height: r.height).insetBy(dx: -1, dy: 1)
                NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
            }
        }
    }
}
