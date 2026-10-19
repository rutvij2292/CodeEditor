import AppKit

/// Ribbon + action buttons between two panes (ours|result or result|theirs).
private final class MergeGutter: NSView {
    enum Side { case left, right }
    enum Action { case apply, ignore }
    struct Item {
        var hunk: Int
        var sideY: CGFloat, sideH: CGFloat
        var resY: CGFloat, resH: CGFloat
        var color: NSColor
        var canApply: Bool, canIgnore: Bool
    }

    let side: Side
    var items: () -> [Item] = { [] }
    var onAction: ((Int, Action, NSEvent) -> Void)?
    override var isFlipped: Bool { true }

    init(side: Side) { self.side = side; super.init(frame: .zero); clipsToBounds = true }
    required init?(coder: NSCoder) { fatalError() }

    private func buttons(_ it: Item) -> [(Action, NSRect)] {
        var out: [(Action, NSRect)] = []
        let y = it.sideY + 1
        let apply = it.canApply, ignore = it.canIgnore
        if side == .left {
            var x: CGFloat = 3
            if apply { out.append((.apply, NSRect(x: x, y: y, width: 16, height: 16))); x += 18 }
            if ignore { out.append((.ignore, NSRect(x: x, y: y, width: 16, height: 16))) }
        } else {
            var x = bounds.width - 19
            if apply { out.append((.apply, NSRect(x: x, y: y, width: 16, height: 16))); x -= 18 }
            if ignore { out.append((.ignore, NSRect(x: x, y: y, width: 16, height: 16))) }
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
        let w = bounds.width, mid = w / 2
        let xs: CGFloat = side == .left ? 0 : w, xr: CGFloat = side == .left ? w : 0
        let glyph: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.labelColor]
        for it in items() {
            let sh = max(it.sideH, 2), rh = max(it.resH, 2)
            let p = NSBezierPath()
            p.move(to: NSPoint(x: xs, y: it.sideY))
            p.curve(to: NSPoint(x: xr, y: it.resY), controlPoint1: NSPoint(x: mid, y: it.sideY), controlPoint2: NSPoint(x: mid, y: it.resY))
            p.line(to: NSPoint(x: xr, y: it.resY + rh))
            p.curve(to: NSPoint(x: xs, y: it.sideY + sh), controlPoint1: NSPoint(x: mid, y: it.resY + rh), controlPoint2: NSPoint(x: mid, y: it.sideY + sh))
            p.close()
            it.color.withAlphaComponent(0.85).setFill()
            p.fill()
            DiffColors.separator.setStroke()
            p.lineWidth = 0.75
            p.stroke()
            for (action, r) in buttons(it) {
                let pill = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
                DiffColors.chrome.setFill(); pill.fill()
                DiffColors.separator.setStroke(); pill.stroke()
                let text = (action == .ignore ? "\u{00D7}" : (side == .left ? "\u{00BB}" : "\u{00AB}")) as NSString
                let size = text.size(withAttributes: glyph)
                text.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: glyph)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        for it in items() {
            for (action, r) in buttons(it) where r.contains(pt) { onAction?(it.hunk, action, event); return }
        }
    }
}

/// Three-pane merge: ours (read-only) | result (editable) | theirs (read-only), like PhpStorm's "Resolve Conflicts".
final class MergeView: NSView, NSTextStorageDelegate, NSTextViewDelegate {
    var onResolved: ((String) -> Void)?

    private struct MHunk {
        var base: String, ours: String, theirs: String
        var conflict: Bool
        var resolved = false
        var trivial: Bool { base == ours && ours == theirs }
        var oursLines: [String] = [], theirsLines: [String] = []
        var oursChecked: [Bool] = [], theirsChecked: [Bool] = []
        var theirsFirst = false
        var appliedEmpty = false
        var oursBoxes: Bool { !trivial && ours != base }
        var theirsBoxes: Bool { !trivial && theirs != base && (conflict || ours == base) }
    }
    private struct PickState {
        var ours: [Bool], theirs: [Bool], theirsFirst: Bool, resolved: Bool, appliedEmpty: Bool, text: String
    }
    private typealias Span = (start: Int, count: Int)

    private let oursPane = DiffPane(editable: false)
    private let result = DiffPane(editable: true)
    private let theirsPane = DiffPane(editable: false)
    private let leftGutter = MergeGutter(side: .left)
    private let rightGutter = MergeGutter(side: .right)
    private let toolbar = DiffFillView { DiffColors.chrome }
    private let titles = DiffFillView { DiffColors.chrome }
    private let oursTitle = DiffUI.label(), resultTitle = DiffUI.label(), theirsTitle = DiffUI.label()
    private let counter = DiffUI.label(12, weight: .medium)
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let yoursButton = NSButton(title: "Accept Yours", target: nil, action: nil)
    private let theirsButton = NSButton(title: "Accept Theirs", target: nil, action: nil)
    private let prevButton = NSButton(), nextButton = NSButton()
    private let nonConflictingPopup = NSPopUpButton(frame: .zero, pullsDown: true)
    private var oursRowHunk: [Int] = [], theirsRowHunk: [Int] = []

    private var hunks: [MHunk] = []
    private var hasBase = true
    private var edges: [Int] = [0]
    private var oursSpans: [Span] = [], theirsSpans: [Span] = []
    private var resultSpansCache: [Span]?
    private var programmaticHunk: Int?
    private var resetting = false
    private var syncing = false
    private var currentHunk = -1
    private var maxColumns = 0
    private var extensionName = ""
    private var highlighters: [DiffHighlighter] = []
    private var rehighlight: DispatchWorkItem?
    private var flashTimer: Timer?
    private var panes: [DiffPane] { [oursPane, result, theirsPane] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: setup

    private func build() {
        oursPane.scroll.hasVerticalScroller = false
        result.scroll.hasVerticalScroller = false
        let bodyViews: [NSView] = [oursPane.box, leftGutter, result.box, rightGutter, theirsPane.box]
        for v in [toolbar, titles] + bodyViews { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        for l in [oursTitle, resultTitle, theirsTitle] { titles.addSubview(l) }
        resultTitle.stringValue = "Result"
        counter.translatesAutoresizingMaskIntoConstraints = false

        for b in [yoursButton, theirsButton, applyButton] {
            b.bezelStyle = .rounded
            b.controlSize = .small
        }
        yoursButton.target = self; yoursButton.action = #selector(yoursTapped)
        theirsButton.target = self; theirsButton.action = #selector(theirsTapped)
        applyButton.target = self; applyButton.action = #selector(applyTapped)
        for (b, name, sel) in [(prevButton, "chevron.up", #selector(prevTapped)), (nextButton, "chevron.down", #selector(nextTapped))] {
            b.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            b.bezelStyle = .texturedRounded
            b.controlSize = .small
            b.target = self; b.action = sel
        }
        nonConflictingPopup.controlSize = .small
        nonConflictingPopup.font = .systemFont(ofSize: 11)
        nonConflictingPopup.addItems(withTitles: ["Apply Non-Conflicting", "Left", "Right", "All"])
        for (i, sel) in [(1, #selector(applyNonConflictingLeft)), (2, #selector(applyNonConflictingRight)), (3, #selector(applyNonConflictingAll))] {
            nonConflictingPopup.item(at: i)?.target = self
            nonConflictingPopup.item(at: i)?.action = sel
        }
        let leftStack = NSStackView(views: [yoursButton, theirsButton, nonConflictingPopup])
        let navStack = NSStackView(views: [counter, prevButton, nextButton])
        for s in [leftStack, navStack] { s.spacing = 6; s.translatesAutoresizingMaskIntoConstraints = false; toolbar.addSubview(s) }
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(applyButton)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: topAnchor), toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor), toolbar.heightAnchor.constraint(equalToConstant: 36),
            leftStack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 10),
            leftStack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            navStack.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            navStack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            applyButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10),
            applyButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            titles.topAnchor.constraint(equalTo: toolbar.bottomAnchor), titles.leadingAnchor.constraint(equalTo: leadingAnchor),
            titles.trailingAnchor.constraint(equalTo: trailingAnchor), titles.heightAnchor.constraint(equalToConstant: 26),
            oursPane.box.leadingAnchor.constraint(equalTo: leadingAnchor),
            leftGutter.leadingAnchor.constraint(equalTo: oursPane.box.trailingAnchor), leftGutter.widthAnchor.constraint(equalToConstant: 40),
            result.box.leadingAnchor.constraint(equalTo: leftGutter.trailingAnchor),
            rightGutter.leadingAnchor.constraint(equalTo: result.box.trailingAnchor), rightGutter.widthAnchor.constraint(equalToConstant: 40),
            theirsPane.box.leadingAnchor.constraint(equalTo: rightGutter.trailingAnchor),
            theirsPane.box.trailingAnchor.constraint(equalTo: trailingAnchor),
            result.box.widthAnchor.constraint(equalTo: oursPane.box.widthAnchor),
            theirsPane.box.widthAnchor.constraint(equalTo: oursPane.box.widthAnchor),
            oursTitle.leadingAnchor.constraint(equalTo: oursPane.box.leadingAnchor, constant: 10),
            oursTitle.trailingAnchor.constraint(equalTo: oursPane.box.trailingAnchor, constant: -10),
            resultTitle.leadingAnchor.constraint(equalTo: result.box.leadingAnchor, constant: 10),
            resultTitle.trailingAnchor.constraint(equalTo: result.box.trailingAnchor, constant: -10),
            theirsTitle.leadingAnchor.constraint(equalTo: theirsPane.box.leadingAnchor, constant: 10),
            theirsTitle.trailingAnchor.constraint(equalTo: theirsPane.box.trailingAnchor, constant: -10),
        ])
        for l in [oursTitle, resultTitle, theirsTitle] { l.centerYAnchor.constraint(equalTo: titles.centerYAnchor).isActive = true }
        for v in [oursPane.box, leftGutter, result.box, rightGutter, theirsPane.box] {
            v.topAnchor.constraint(equalTo: titles.bottomAnchor).isActive = true
            v.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        }

        let nc = NotificationCenter.default
        for p in panes {
            p.scroll.contentView.postsBoundsChangedNotifications = true
            nc.addObserver(self, selector: #selector(paneScrolled(_:)), name: NSView.boundsDidChangeNotification, object: p.scroll.contentView)
        }
        nc.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
        result.text.delegate = self
        result.text.textStorage?.delegate = self
        leftGutter.items = { [weak self] in self?.gutterItems(.left) ?? [] }
        rightGutter.items = { [weak self] in self?.gutterItems(.right) ?? [] }
        leftGutter.onAction = { [weak self] k, a, e in self?.gutterAction(k, .left, a, e) }
        rightGutter.onAction = { [weak self] k, a, e in self?.gutterAction(k, .right, a, e) }
        oursPane.text.bandSource = { [weak self] r in self?.sideBands(r, ours: true) ?? [] }
        theirsPane.text.bandSource = { [weak self] r in self?.sideBands(r, ours: false) ?? [] }
        result.text.bandSource = { [weak self] r in self?.resultBands(r) ?? [] }
        for (pane, isOurs) in [(oursPane, true), (theirsPane, false)] {
            pane.gutterExtra = 22
            pane.gutter.checkState = { [weak self] row in self?.lineCheckState(row, ours: isOurs) }
            pane.gutter.onMouse = { [weak self] row, x, _, phase in
                guard phase == .down, x < 22 else { return }
                self?.toggleLine(row, ours: isOurs)
            }
            pane.gutter.rowMenu = { [weak self] row in self?.hunkMenu(row: row, ours: isOurs) }
            pane.text.rowMenu = { [weak self] row in self?.hunkMenu(row: row, ours: isOurs) }
        }
        result.text.rowMenu = { [weak self] row in self?.resultMenu(row: row) }
        themeChanged()
    }

    // MARK: content

    private static func lineCount(_ s: String) -> Int {
        guard !s.isEmpty else { return 0 }
        var n = 0
        for b in s.utf8 where b == 10 { n += 1 }
        return s.utf8.last == 10 ? n : n + 1
    }

    private func spans(_ texts: [String]) -> [Span] {
        var line = 0
        return texts.map { t in let c = Self.lineCount(t); defer { line += c }; return (line, c) }
    }

    func show(base: String?, ours: String, theirs: String, oursTitle: String, theirsTitle: String, fileExtension: String) {
        extensionName = fileExtension
        // A second file replaces the first: drop the old result tracking before any text storage edit below, or the edit
        // handler runs old edges against the new hunks (index out of range when the new file has more hunks).
        resetting = true
        edges = [0]
        programmaticHunk = nil
        self.oursTitle.stringValue = oursTitle
        self.theirsTitle.stringValue = theirsTitle
        hasBase = base != nil
        hunks = Diff3.detailed(base: base, ours: ours, theirs: theirs).map {
            MHunk(base: $0.base, ours: $0.ours, theirs: $0.theirs, conflict: $0.isConflict)
        }
        for i in hunks.indices {
            var h = hunks[i]
            h.oursLines = DiffEngine.splitLines(h.ours)
            h.theirsLines = DiffEngine.splitLines(h.theirs)
            h.oursChecked = [Bool](repeating: !h.conflict && h.ours != h.base, count: h.oursLines.count)
            h.theirsChecked = [Bool](repeating: !h.conflict && h.theirs != h.base && h.ours == h.base, count: h.theirsLines.count)
            h.appliedEmpty = !h.conflict && !h.trivial && ((h.ours != h.base ? h.ours : h.theirs).isEmpty)
            hunks[i] = h
        }
        oursSpans = spans(hunks.map { $0.ours })
        theirsSpans = spans(hunks.map { $0.theirs })
        oursRowHunk = rowMap(oursSpans)
        theirsRowHunk = rowMap(theirsSpans)
        let initial = Diff3.detailed(base: base, ours: ours, theirs: theirs).map { $0.merged ?? (base != nil ? $0.base : $0.ours) }

        let maxLines = max(Self.lineCount(ours), Self.lineCount(theirs), initial.reduce(0) { $0 + Self.lineCount($1) })
        oursPane.setText(ours, maxLineNumber: maxLines)
        theirsPane.setText(theirs, maxLineNumber: maxLines)
        result.setText("", maxLineNumber: maxLines)
        loadResult(initial)
        maxColumns = 0
        for text in [ours, theirs] + initial { for line in text.split(separator: "\n", omittingEmptySubsequences: false) { maxColumns = max(maxColumns, DiffUI.columns(String(line))) } }
        oursPane.gutter.rowCount = Self.lineCount(ours)
        theirsPane.gutter.rowCount = Self.lineCount(theirs)
        highlighters = [oursPane, theirsPane].compactMap { DiffHighlighter(textView: $0.text, extension: fileExtension) }
        currentHunk = -1
        needsLayout = true
        layoutSubtreeIfNeeded()
        for p in panes { DiffUI.scroll(p.scroll.contentView, x: 0, y: 0) }
        if let first = navigationTargets().first { currentHunk = first; reveal(first, flash: false) }
        redrawAll()
    }

    /// Replaces the whole result with one text per hunk (no undo history, boundaries rebuilt).
    private func loadResult(_ texts: [String]) {
        resetting = true
        result.text.string = texts.joined()
        result.restyle()
        resetting = false
        edges = [0]
        for t in texts { edges.append(edges.last! + t.utf16.count) }
        invalidateResult()
        result.text.undoManager?.removeAllActions()
        rebuildResultHighlight()
        updateStatus()
    }

    private func invalidateResult() {
        resultSpansCache = nil
        result.gutter.rowCount = max(1, Self.lineCount(result.text.string) + (result.text.string.hasSuffix("\n") ? 1 : 0))
    }

    private func resultSpans() -> [Span] {
        if let c = resultSpansCache { return c }
        let s = result.text.string as NSString
        var newlines: [Int] = []
        for i in 0..<s.length where s.character(at: i) == 10 { newlines.append(i) }
        func lineIndex(_ off: Int) -> Int {
            var lo = 0, hi = newlines.count
            while lo < hi { let m = (lo + hi) / 2; if newlines[m] < off { lo = m + 1 } else { hi = m } }
            return lo
        }
        var out: [Span] = []
        for k in hunks.indices {
            let a = edges[k], b = edges[k + 1]
            let start = lineIndex(a)
            var count = lineIndex(b) - start
            if b > a, s.character(at: b - 1) != 10 { count += 1 }
            out.append((start, count))
        }
        resultSpansCache = out
        return out
    }

    private func resultText(_ k: Int) -> String {
        (result.text.string as NSString).substring(with: NSRange(location: edges[k], length: edges[k + 1] - edges[k]))
    }

    // MARK: bands

    private func sideBands(_ range: Range<Int>, ours: Bool) -> [DiffBand] {
        let spans = ours ? oursSpans : theirsSpans
        var out: [DiffBand] = []
        for (k, h) in hunks.enumerated() where !h.trivial {
            let text = ours ? h.ours : h.theirs
            guard text != h.base || h.conflict else { continue }
            let sp = spans[k]
            guard sp.start <= range.upperBound, sp.start + sp.count >= range.lowerBound else { continue }
            out.append(DiffBand(row: sp.start, count: sp.count, color: bandColor(h, text)))
        }
        return out
    }

    private func bandColor(_ h: MHunk, _ text: String) -> NSColor {
        if h.conflict { return DiffColors.conflict }
        if text.isEmpty { return DiffColors.removed }
        return h.base.isEmpty ? DiffColors.added : DiffColors.changed
    }

    private func resultBands(_ range: Range<Int>) -> [DiffBand] {
        let spans = resultSpans()
        var out: [DiffBand] = []
        for (k, h) in hunks.enumerated() where !h.trivial {
            let sp = spans[k]
            guard sp.start <= range.upperBound, sp.start + sp.count >= range.lowerBound else { continue }
            let color = (h.conflict && !h.resolved) ? DiffColors.conflict : DiffColors.changed
            out.append(DiffBand(row: sp.start, count: sp.count, color: color))
        }
        return out
    }

    private func gutterItems(_ side: MergeGutter.Side) -> [MergeGutter.Item] {
        let lh = DiffUI.lineHeight, inset = DiffUI.inset
        let rs = resultSpans()
        let sideSpans = side == .left ? oursSpans : theirsSpans
        let sidePane = side == .left ? oursPane : theirsPane
        let so = sidePane.scroll.contentView.bounds.origin.y, ro = result.scroll.contentView.bounds.origin.y
        let height = sidePane.scroll.contentView.bounds.height
        var out: [MergeGutter.Item] = []
        for (k, h) in hunks.enumerated() where !h.trivial {
            let text = side == .left ? h.ours : h.theirs
            guard text != h.base || h.conflict else { continue }
            let sy = inset + CGFloat(sideSpans[k].start) * lh - so, sh = CGFloat(sideSpans[k].count) * lh
            let ry = inset + CGFloat(rs[k].start) * lh - ro, rh = CGFloat(rs[k].count) * lh
            guard max(sy, ry) + max(sh, rh) >= 0, min(sy, ry) <= height else { continue }
            let current = resultText(k)
            let color = (h.conflict && !h.resolved) ? DiffColors.conflict : bandColor(h, text)
            out.append(.init(hunk: k, sideY: sy, sideH: sh, resY: ry, resH: rh, color: color,
                             canApply: current != text, canIgnore: current != h.base && text != h.base))
        }
        return out
    }

    // MARK: actions

    private func rowMap(_ spans: [Span]) -> [Int] {
        var out = [Int](repeating: -1, count: (spans.last.map { $0.start + $0.count } ?? 0))
        for (k, sp) in spans.enumerated() { for r in sp.start..<(sp.start + sp.count) where r < out.count { out[r] = k } }
        return out
    }

    private func gutterAction(_ k: Int, _ side: MergeGutter.Side, _ action: MergeGutter.Action, _ event: NSEvent) {
        switch action {
        case .ignore: revertToBase(k)
        case .apply:
            if event.modifierFlags.contains(.option) { applyBoth(k, theirsFirst: side == .right) }
            else if side == .left { applyOurs(k) } else { applyTheirs(k) }
        }
    }

    // MARK: picking (line level and hunk level)

    private func joined(_ lines: [String]) -> String {
        var text = ""
        for (i, l) in lines.enumerated() {
            text += l
            if i < lines.count - 1, l.utf8.last != 10 { text += "\n" }
        }
        return text
    }

    private func computedText(_ k: Int) -> String {
        let h = hunks[k]
        let o = zip(h.oursLines, h.oursChecked).filter { $0.1 }.map { $0.0 }
        let t = zip(h.theirsLines, h.theirsChecked).filter { $0.1 }.map { $0.0 }
        let lines: [String]
        if h.conflict { lines = h.theirsFirst ? t + o : o + t }
        else if h.oursBoxes { lines = o } else { lines = t }
        if lines.isEmpty { return h.appliedEmpty ? "" : h.base }
        return joined(lines)
    }

    private func snapshot(_ k: Int) -> PickState {
        let h = hunks[k]
        return PickState(ours: h.oursChecked, theirs: h.theirsChecked, theirsFirst: h.theirsFirst, resolved: h.resolved,
                         appliedEmpty: h.appliedEmpty, text: resultText(k))
    }

    private func restore(_ k: Int, _ s: PickState) {
        guard hunks.indices.contains(k) else { return }
        let cur = snapshot(k)
        result.text.undoManager?.registerUndo(withTarget: self) { $0.restore(k, cur) }
        hunks[k].oursChecked = s.ours; hunks[k].theirsChecked = s.theirs
        hunks[k].theirsFirst = s.theirsFirst; hunks[k].resolved = s.resolved; hunks[k].appliedEmpty = s.appliedEmpty
        setHunkText(k, s.text)
    }

    /// Changes check state of one hunk and rewrites its result text (undoable as one step).
    private func pick(_ k: Int, ours: [Bool]? = nil, theirs: [Bool]? = nil, theirsFirst: Bool? = nil, text override: String? = nil) {
        guard hunks.indices.contains(k) else { return }
        let prev = snapshot(k)
        let um = result.text.undoManager
        um?.registerUndo(withTarget: self) { $0.restore(k, prev) }
        if um?.isUndoing == false, um?.isRedoing == false { um?.setActionName("Apply Change") }
        if let o = ours { hunks[k].oursChecked = o }
        if let t = theirs { hunks[k].theirsChecked = t }
        if let f = theirsFirst { hunks[k].theirsFirst = f }
        hunks[k].appliedEmpty = override.map { $0.isEmpty } ?? false
        hunks[k].resolved = true
        setHunkText(k, override ?? computedText(k))
    }

    private func setHunkText(_ k: Int, _ text: String) {
        let tv = result.text
        let range = NSRange(location: edges[k], length: edges[k + 1] - edges[k])
        if let storage = tv.textStorage, (storage.string as NSString).substring(with: range) != text {
            tv.undoManager?.disableUndoRegistration()
            programmaticHunk = k
            storage.replaceCharacters(in: range, with: text)
            storage.setAttributes(DiffUI.baseAttributes, range: NSRange(location: range.location, length: (text as NSString).length))
            programmaticHunk = nil
            tv.undoManager?.enableUndoRegistration()
        }
        afterResultEdit()
    }

    func applyOurs(_ k: Int) {
        let h = hunks[k]
        pick(k, ours: h.oursLines.map { _ in true }, theirs: h.theirsLines.map { _ in false }, text: h.ours)
    }
    func applyTheirs(_ k: Int) {
        let h = hunks[k]
        pick(k, ours: h.oursLines.map { _ in false }, theirs: h.theirsLines.map { _ in true }, text: h.theirs)
    }
    func applyBoth(_ k: Int, theirsFirst: Bool) {
        let h = hunks[k]
        let text = theirsFirst ? joined(h.theirsLines + h.oursLines) : joined(h.oursLines + h.theirsLines)
        pick(k, ours: h.oursLines.map { _ in true }, theirs: h.theirsLines.map { _ in true }, theirsFirst: theirsFirst, text: text)
    }
    func revertToBase(_ k: Int) {
        let h = hunks[k]
        pick(k, ours: h.oursLines.map { _ in false }, theirs: h.theirsLines.map { _ in false }, text: h.base)
    }

    private func lineCheckState(_ row: Int, ours: Bool) -> Int? {
        let map = ours ? oursRowHunk : theirsRowHunk
        guard map.indices.contains(row), map[row] >= 0 else { return nil }
        let h = hunks[map[row]]
        guard ours ? h.oursBoxes : h.theirsBoxes else { return nil }
        let start = (ours ? oursSpans : theirsSpans)[map[row]].start
        let arr = ours ? h.oursChecked : h.theirsChecked
        return arr.indices.contains(row - start) ? (arr[row - start] ? 1 : 0) : nil
    }

    private func toggleLine(_ row: Int, ours: Bool) {
        let map = ours ? oursRowHunk : theirsRowHunk
        guard lineCheckState(row, ours: ours) != nil else { return }
        let k = map[row]
        let idx = row - (ours ? oursSpans : theirsSpans)[k].start
        if ours { var a = hunks[k].oursChecked; a[idx].toggle(); pick(k, ours: a) }
        else { var a = hunks[k].theirsChecked; a[idx].toggle(); pick(k, theirs: a) }
    }

    func setLine(ours: Bool, hunk k: Int, line: Int, checked: Bool) {
        if ours { var a = hunks[k].oursChecked; a[line] = checked; pick(k, ours: a) }
        else { var a = hunks[k].theirsChecked; a[line] = checked; pick(k, theirs: a) }
    }

    var currentResult: String { result.text.string }
    var remainingConflicts: Int { unresolved.count }

    func acceptAllOurs() { acceptAll(ours: true) }
    func acceptAllTheirs() { acceptAll(ours: false) }

    private func acceptAll(ours: Bool) {
        loadResult(hunks.map { ours ? $0.ours : $0.theirs })
        for i in hunks.indices {
            hunks[i].resolved = true
            hunks[i].oursChecked = hunks[i].oursLines.map { _ in ours }
            hunks[i].theirsChecked = hunks[i].theirsLines.map { _ in !ours }
            hunks[i].appliedEmpty = (ours ? hunks[i].ours : hunks[i].theirs).isEmpty
        }
        updateStatus()
        redrawAll()
    }

    func applyNonConflicting(left: Bool, right rightSide: Bool) {
        let um = result.text.undoManager
        um?.beginUndoGrouping()
        for k in hunks.indices {
            let h = hunks[k]
            guard !h.conflict, !h.trivial else { continue }
            if h.ours != h.base, left { applyOurs(k) }
            else if h.theirs != h.base, h.ours == h.base, rightSide { applyTheirs(k) }
        }
        um?.endUndoGrouping()
    }
    @objc private func applyNonConflictingLeft() { applyNonConflicting(left: true, right: false) }
    @objc private func applyNonConflictingRight() { applyNonConflicting(left: false, right: true) }
    @objc private func applyNonConflictingAll() { applyNonConflicting(left: true, right: true) }

    // MARK: context menus

    private func hunkMenu(row: Int, ours: Bool) -> NSMenu? {
        let map = ours ? oursRowHunk : theirsRowHunk
        guard map.indices.contains(row), map[row] >= 0, !hunks[map[row]].trivial else { return nil }
        return pickMenu(map[row])
    }

    private func resultMenu(row: Int) -> NSMenu? {
        let spans = resultSpans()
        guard let k = spans.firstIndex(where: { row >= $0.start && row < $0.start + max(1, $0.count) }), !hunks[k].trivial else { return nil }
        return pickMenu(k)
    }

    private func pickMenu(_ k: Int) -> NSMenu {
        let h = hunks[k]
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector, _ enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            item.tag = k
            item.isEnabled = enabled
            m.addItem(item)
        }
        add("Apply Ours", #selector(menuOurs(_:)), h.conflict || h.ours != h.base)
        add("Apply Theirs", #selector(menuTheirs(_:)), h.conflict || h.theirs != h.base)
        add("Apply Both (Ours then Theirs)", #selector(menuBothOT(_:)), h.conflict)
        add("Apply Both (Theirs then Ours)", #selector(menuBothTO(_:)), h.conflict)
        m.addItem(.separator())
        add("Revert to Base", #selector(menuBase(_:)))
        return m
    }
    @objc private func menuOurs(_ i: NSMenuItem) { applyOurs(i.tag) }
    @objc private func menuTheirs(_ i: NSMenuItem) { applyTheirs(i.tag) }
    @objc private func menuBothOT(_ i: NSMenuItem) { applyBoth(i.tag, theirsFirst: false) }
    @objc private func menuBothTO(_ i: NSMenuItem) { applyBoth(i.tag, theirsFirst: true) }
    @objc private func menuBase(_ i: NSMenuItem) { revertToBase(i.tag) }

    @objc private func yoursTapped() { acceptAllOurs() }
    @objc private func theirsTapped() { acceptAllTheirs() }
    @objc private func applyTapped() { onResolved?(result.text.string) }
    @objc private func prevTapped() { navigate(-1) }
    @objc private func nextTapped() { navigate(1) }

    // MARK: result tracking

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !resetting, edges.count > 1, edges.count == hunks.count + 1 else { return }
        let n = hunks.count
        if let k = programmaticHunk {
            for i in (k + 1)...n { edges[i] += delta }
            return
        }
        let s = editedRange.location, newLen = editedRange.length, e = s + newLen - delta
        if let owner = edges.dropLast().lastIndex(where: { $0 <= s }), hunks[owner].conflict { hunks[owner].resolved = true }
        for i in 1..<n {
            let p = edges[i]
            edges[i] = p <= s ? p : (p >= e ? p + delta : s + newLen)
        }
        edges[n] = textStorage.length
        for i in 1...n where edges[i] < edges[i - 1] { edges[i] = edges[i - 1] }
    }

    func textDidChange(_ notification: Notification) { afterResultEdit() }

    private func afterResultEdit() {
        invalidateResult()
        updateStatus()
        redrawAll()
        paneScrolledSync(result)
        rehighlight?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rebuildResultHighlight() }
        rehighlight = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private var resultHighlighter: DiffHighlighter?
    private func rebuildResultHighlight() {
        if let h = resultHighlighter { h.reparse() } else { resultHighlighter = DiffHighlighter(textView: result.text, extension: extensionName) }
    }

    // MARK: status & navigation

    private var unresolved: [Int] { hunks.indices.filter { hunks[$0].conflict && !hunks[$0].resolved } }

    private func updateStatus() {
        let n = unresolved.count
        counter.stringValue = n == 0 ? (hunks.contains { $0.conflict } ? "All conflicts resolved" : "No conflicts")
            : "\(n) conflict\(n == 1 ? "" : "s") remaining"
        counter.textColor = n == 0 ? DiffColors.secondary : NSColor.systemOrange
        applyButton.isEnabled = n == 0
    }

    private func navigationTargets() -> [Int] {
        let u = unresolved
        return u.isEmpty ? hunks.indices.filter { !hunks[$0].trivial } : u
    }

    func nextConflict() { navigate(1) }
    func previousConflict() { navigate(-1) }

    private func navigate(_ step: Int) {
        let targets = navigationTargets()
        guard !targets.isEmpty else { return }
        let next: Int?
        if step > 0 { next = targets.first { $0 > currentHunk } ?? targets.first } else { next = targets.last { $0 < currentHunk } ?? targets.last }
        guard let k = next else { return }
        currentHunk = k
        reveal(k, flash: true)
    }

    private func reveal(_ k: Int, flash doFlash: Bool) {
        let sp = resultSpans()[k]
        let clip = result.scroll.contentView
        let y0 = DiffUI.inset + CGFloat(sp.start) * DiffUI.lineHeight
        let h = CGFloat(sp.count) * DiffUI.lineHeight
        let target = h < clip.bounds.height ? y0 - (clip.bounds.height - h) / 2 : y0 - 40
        DiffUI.scroll(clip, x: clip.bounds.origin.x, y: target)
        if doFlash { flash(rows: sp.start..<(sp.start + max(1, sp.count))) }
    }

    private func flash(rows: Range<Int>) {
        flashTimer?.invalidate()
        var alpha: CGFloat = 1
        result.text.flash = (rows, 1)
        result.text.needsDisplay = true
        let tick = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            alpha -= 0.07
            self.result.text.flash = alpha > 0 ? (rows, alpha) : nil
            self.result.text.needsDisplay = true
            if alpha <= 0 { t.invalidate() }
        }
        tick.tolerance = 0.01
        RunLoop.main.add(tick, forMode: .common)
        flashTimer = tick
    }

    // MARK: scroll sync

    private func map(_ pos: CGFloat, from a: [Span], to b: [Span]) -> CGFloat {
        guard let la = a.last, let lb = b.last else { return pos }
        let endA = CGFloat(la.start + la.count), endB = CGFloat(lb.start + lb.count)
        if pos >= endA { return endB + (pos - endA) }
        for k in a.indices where a[k].count > 0 {
            let s = CGFloat(a[k].start), c = CGFloat(a[k].count)
            if pos >= s, pos < s + c { return CGFloat(b[k].start) + (pos - s) / c * CGFloat(b[k].count) }
        }
        return pos
    }

    private func spans(of pane: DiffPane) -> [Span] {
        pane === oursPane ? oursSpans : (pane === theirsPane ? theirsSpans : resultSpans())
    }

    @objc private func paneScrolled(_ n: Notification) {
        guard let clip = n.object as? NSClipView, let pane = panes.first(where: { $0.scroll.contentView === clip }) else { return }
        paneScrolledSync(pane)
    }

    private func paneScrolledSync(_ src: DiffPane) {
        guard !syncing, !hunks.isEmpty else { return }
        syncing = true
        let o = src.scroll.contentView.bounds.origin
        let pos = o.y / DiffUI.lineHeight
        let from = spans(of: src)
        for p in panes where p !== src {
            DiffUI.scroll(p.scroll.contentView, x: o.x, y: map(pos, from: from, to: spans(of: p)) * DiffUI.lineHeight)
        }
        syncing = false
        leftGutter.needsDisplay = true
        rightGutter.needsDisplay = true
    }

    // MARK: chrome

    private func redrawAll() {
        for p in panes { p.text.needsDisplay = true; p.gutter.needsDisplay = true }
        leftGutter.needsDisplay = true
        rightGutter.needsDisplay = true
    }

    @objc private func themeChanged() {
        for l in [oursTitle, resultTitle, theirsTitle] { l.textColor = Theme.foreground }
        for p in panes { p.restyle() }
        highlighters = [oursPane, theirsPane].compactMap { DiffHighlighter(textView: $0.text, extension: extensionName) }
        resultHighlighter = nil
        rebuildResultHighlight()
        updateStatus()
        for v in [toolbar, titles] { v.needsDisplay = true }
        redrawAll()
    }

    override func layout() {
        super.layout()
        oursPane.fit(rows: oursPane.gutter.rowCount, columns: maxColumns)
        theirsPane.fit(rows: theirsPane.gutter.rowCount, columns: maxColumns)
        result.fit(rows: result.gutter.rowCount, columns: maxColumns)
        leftGutter.needsDisplay = true
        rightGutter.needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 98 { // F7
            navigate(event.modifierFlags.contains(.shift) ? -1 : 1)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
