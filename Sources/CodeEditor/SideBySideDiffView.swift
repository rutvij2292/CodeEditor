import AppKit

/// Thin strip showing where the changed blocks are; click to jump.
private final class DiffOverview: NSView {
    var blocks: [(rows: Range<Int>, color: () -> NSColor)] = []
    var rowCount = 0
    var viewport: (CGFloat, CGFloat) = (0, 1)
    var onClick: ((CGFloat) -> Void)?
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        DiffColors.chrome.setFill()
        bounds.fill()
        guard rowCount > 0 else { return }
        for b in blocks {
            let y = CGFloat(b.rows.lowerBound) / CGFloat(rowCount) * bounds.height
            let h = max(3, CGFloat(b.rows.count) / CGFloat(rowCount) * bounds.height)
            b.color().setFill()
            NSRect(x: 2, y: y, width: bounds.width - 4, height: h).fill()
        }
        NSColor.labelColor.withAlphaComponent(0.10).setFill()
        NSRect(x: 0, y: viewport.0 * bounds.height, width: bounds.width, height: max(4, viewport.1 * bounds.height)).fill()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(convert(event.locationInWindow, from: nil).y / max(1, bounds.height))
    }
}

/// Column between the panes: per-hunk » (old -> new) and « (new -> old) buttons.
private final class DiffArrowGutter: NSView {
    struct Block { var rows: Range<Int>; var color: NSColor }
    weak var scrollView: NSScrollView?
    var blocks: () -> [Block] = { [] }
    var showToNew = false, showToOld = false
    var onAction: ((Int, Bool) -> Void)?
    override var isFlipped: Bool { true }

    private func rects(_ block: Block) -> (toNew: NSRect?, toOld: NSRect?) {
        let off = scrollView?.contentView.bounds.origin.y ?? 0
        let y = DiffUI.inset + CGFloat(block.rows.lowerBound) * DiffUI.lineHeight - off
        let yy = y + (DiffUI.lineHeight - 16) / 2
        return (showToNew ? NSRect(x: 3, y: yy, width: 16, height: 16) : nil,
                showToOld ? NSRect(x: bounds.width - 19, y: yy, width: 16, height: 16) : nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
        DiffColors.separator.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
        guard showToNew || showToOld, let clip = scrollView?.contentView else { return }
        let off = clip.bounds.origin.y, lh = DiffUI.lineHeight
        let glyph: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.labelColor]
        for b in blocks() {
            let top = DiffUI.inset + CGFloat(b.rows.lowerBound) * lh - off
            let h = CGFloat(b.rows.count) * lh
            guard top + h >= 0, top <= bounds.height else { continue }
            b.color.withAlphaComponent(0.7).setFill()
            NSRect(x: 1, y: top, width: bounds.width - 2, height: h).fill()
            let r = rects(b)
            for (rect, text) in [(r.toNew, "\u{00BB}"), (r.toOld, "\u{00AB}")] {
                guard let rect else { continue }
                let pill = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                DiffColors.chrome.setFill(); pill.fill()
                DiffColors.separator.setStroke(); pill.stroke()
                let s = text as NSString
                let size = s.size(withAttributes: glyph)
                s.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: glyph)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        for (i, b) in blocks().enumerated() {
            let r = rects(b)
            if let a = r.toNew, a.contains(pt) { onAction?(i, true); return }
            if let a = r.toOld, a.contains(pt) { onAction?(i, false); return }
        }
    }
}

final class SideBySideDiffView: NSView, NSTextViewDelegate {
    enum PickMode { case none, stage }
    private enum Style { case none, added, removed, changed, filler }
    private enum Side { case old, new }

    private let left = DiffPane(editable: false)
    private let right = DiffPane(editable: false)
    private let header = DiffFillView { DiffColors.chrome }
    private let arrows = DiffArrowGutter()
    private let leftTitle = DiffUI.label()
    private let rightTitle = DiffUI.label()
    private let summary = DiffUI.label(11, weight: .regular)
    private let prevButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)
    private let overview = DiffOverview()
    private let toast = DiffUI.label(11, weight: .medium)
    private var arrowWidth: NSLayoutConstraint!
    private var equalWidth: NSLayoutConstraint!
    private var leftHidden: NSLayoutConstraint!

    private var rows: [DiffEngine.Row] = []
    private var blocks: [Range<Int>] = []
    private var blockOf: [Int] = []
    private var oldLines: [String] = [], newLines: [String] = []
    private var leftStyles: [Style] = [], rightStyles: [Style] = []
    private var intra: [(left: [NSRange], right: [NSRange])] = []
    private var maxColumns = 0
    private var current = -1
    private var syncing = false
    private var highlighters: [DiffHighlighter] = []
    private var flashTimer: Timer?
    private var extensionName = ""
    private var checked = Set<Int>()
    private var selection = Set<Int>()
    private var anchor: Int?
    private var editWork: DispatchWorkItem?
    private var pendingNew = false, pendingOld = false

    var changeCount: Int { blocks.count }
    var scrollY: CGFloat { right.scroll.contentView.bounds.origin.y }
    var currentChange: Int { current }

    var isNewSideEditable = false { didSet { right.text.isEditable = isNewSideEditable; right.text.allowsUndo = isNewSideEditable; updateArrows() } }
    var isOldSideEditable = false { didSet { left.text.isEditable = isOldSideEditable; left.text.allowsUndo = isOldSideEditable; updateArrows() } }
    var onNewSideEdited: ((String) -> Void)?
    var onOldSideEdited: ((String) -> Void)?
    var newText: String { right.text.string }
    var oldText: String { left.text.string }
    var pickMode: PickMode = .none { didSet { updatePickMode() } }
    var onCheckedChanged: (() -> Void)?
    var checkedLineCount: Int { checked.count }
    var changedLineCount: Int { rows.reduce(0) { $0 + ($1.kind == .equal ? 0 : 1) } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func build() {
        left.scroll.hasVerticalScroller = false
        arrows.scrollView = right.scroll
        for v in [header, left.box, arrows, right.box, overview, toast] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        for l in [leftTitle, rightTitle, summary, prevButton, nextButton] { header.addSubview(l) }
        for (b, symbol, tip, action) in [(prevButton, "chevron.up", "Previous change (⇧F7)", #selector(prevClicked)),
                                         (nextButton, "chevron.down", "Next change (F7)", #selector(nextClicked))] {
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            b.toolTip = tip
            b.isBordered = false
            b.bezelStyle = .texturedRounded
            b.imagePosition = .imageOnly
            b.target = self
            b.action = action
            b.translatesAutoresizingMaskIntoConstraints = false
            b.focusRingType = .none
        }
        summary.alignment = .right
        toast.alignment = .center
        toast.wantsLayer = true
        toast.layer?.cornerRadius = 6
        toast.alphaValue = 0
        arrowWidth = arrows.widthAnchor.constraint(equalToConstant: 1)
        equalWidth = right.box.widthAnchor.constraint(equalTo: left.box.widthAnchor)
        leftHidden = left.box.widthAnchor.constraint(equalToConstant: 0)
        leftHidden.isActive = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor), header.heightAnchor.constraint(equalToConstant: 28),
            left.box.topAnchor.constraint(equalTo: header.bottomAnchor), left.box.bottomAnchor.constraint(equalTo: bottomAnchor),
            left.box.leadingAnchor.constraint(equalTo: leadingAnchor),
            arrows.leadingAnchor.constraint(equalTo: left.box.trailingAnchor), arrowWidth,
            arrows.topAnchor.constraint(equalTo: left.box.topAnchor), arrows.bottomAnchor.constraint(equalTo: bottomAnchor),
            right.box.leadingAnchor.constraint(equalTo: arrows.trailingAnchor),
            right.box.topAnchor.constraint(equalTo: left.box.topAnchor), right.box.bottomAnchor.constraint(equalTo: bottomAnchor),
            equalWidth, leftHidden,
            overview.leadingAnchor.constraint(equalTo: right.box.trailingAnchor), overview.trailingAnchor.constraint(equalTo: trailingAnchor),
            overview.widthAnchor.constraint(equalToConstant: 14),
            overview.topAnchor.constraint(equalTo: left.box.topAnchor), overview.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftTitle.leadingAnchor.constraint(equalTo: left.box.leadingAnchor, constant: 10),
            leftTitle.trailingAnchor.constraint(equalTo: left.box.trailingAnchor, constant: -10),
            rightTitle.leadingAnchor.constraint(equalTo: right.box.leadingAnchor, constant: 10),
            rightTitle.trailingAnchor.constraint(equalTo: right.box.trailingAnchor, constant: -190),
            nextButton.trailingAnchor.constraint(equalTo: summary.leadingAnchor, constant: -4),
            prevButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 22), prevButton.widthAnchor.constraint(equalToConstant: 22),
            nextButton.centerYAnchor.constraint(equalTo: header.centerYAnchor), prevButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            summary.trailingAnchor.constraint(equalTo: overview.trailingAnchor, constant: -16),
            summary.widthAnchor.constraint(equalToConstant: 118),
            leftTitle.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            rightTitle.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            summary.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            toast.centerXAnchor.constraint(equalTo: centerXAnchor), toast.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
        ])
        let nc = NotificationCenter.default
        for (i, pane) in [left, right].enumerated() {
            pane.scroll.contentView.postsBoundsChangedNotifications = true
            nc.addObserver(self, selector: i == 0 ? #selector(leftScrolled) : #selector(rightScrolled),
                           name: NSView.boundsDidChangeNotification, object: pane.scroll.contentView)
            pane.text.delegate = self
            pane.text.rowMenu = { [weak self] row in self?.menu(forRow: row) }
            pane.gutter.rowMenu = { [weak self] row in self?.menu(forRow: row) }
            pane.gutter.isSelected = { [weak self] row in self?.selection.contains(row) ?? false }
        }
        left.gutter.onMouse = { [weak self] row, x, e, phase in self?.gutterMouse(row, x, e, phase, isRight: false) }
        right.gutter.onMouse = { [weak self] row, x, e, phase in self?.gutterMouse(row, x, e, phase, isRight: true) }
        right.gutter.checkState = { [weak self] row in self?.lineCheckState(row) }
        right.gutter.hunkCheckState = { [weak self] row in self?.hunkCheckState(row) }
        arrows.blocks = { [weak self] in self?.blocks.map { b in .init(rows: b, color: self?.blockColorSoft(b) ?? .clear) } ?? [] }
        arrows.onAction = { [weak self] b, toNew in self?.applyBlock(b, toNew: toNew) }
        left.text.bandSource = { [weak self] r in self?.bands(r, left: true) ?? [] }
        right.text.bandSource = { [weak self] r in self?.bands(r, left: false) ?? [] }
        left.gutter.numberForRow = { [weak self] i in self.flatMap { $0.rows.indices.contains(i) ? $0.rows[i].leftLine : nil } }
        right.gutter.numberForRow = { [weak self] i in self.flatMap { $0.rows.indices.contains(i) ? $0.rows[i].rightLine : nil } }
        nc.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
        overview.onClick = { [weak self] f in self?.jump(toFraction: f) }
        themeChanged()
    }

    // MARK: content

    func show(old: String, new: String, oldTitle: String, newTitle: String, fileExtension: String) {
        extensionName = fileExtension
        // A new file has nothing to compare against: show just the file, full width (PhpStorm).
        let single = old.isEmpty && !new.isEmpty
        equalWidth.isActive = !single
        leftHidden.isActive = single
        for v in [left.box, leftTitle, arrows] as [NSView] { v.isHidden = single }
        leftTitle.stringValue = oldTitle
        rightTitle.stringValue = newTitle
        editWork?.cancel()
        pendingNew = false; pendingOld = false
        current = -1
        selection = []; anchor = nil; checked = []
        let maxNumber = max(DiffEngine.splitLines(old).count, DiffEngine.splitLines(new).count)
        left.setText(old, maxLineNumber: maxNumber)
        right.setText(new, maxLineNumber: maxNumber)
        left.text.undoManager?.removeAllActions()
        right.text.undoManager?.removeAllActions()
        highlighters = [left, right].compactMap { DiffHighlighter(textView: $0.text, extension: fileExtension) }
        recompute()
        needsLayout = true
        layoutSubtreeIfNeeded()
        DiffUI.scroll(left.scroll.contentView, x: 0, y: 0)
        DiffUI.scroll(right.scroll.contentView, x: 0, y: 0)
        for p in [left, right] { p.gutter.needsDisplay = true; p.text.needsDisplay = true }
        // Land on the first change instead of the top of the file.
        if !blocks.isEmpty { current = 0; reveal(blocks[0], flash: false) }
    }

    /// Re-diffs the current pane texts and rebuilds alignment (text itself is untouched, so caret and undo survive).
    private func recompute() {
        let oldS = left.text.string, newS = right.text.string
        oldLines = DiffEngine.splitLines(oldS)
        newLines = DiffEngine.splitLines(newS)
        rows = DiffEngine.rows(old: oldS, new: newS)

        blocks = []
        blockOf = [Int](repeating: -1, count: rows.count)
        var start: Int?
        for (i, r) in rows.enumerated() {
            if r.kind != .equal { if start == nil { start = i } } else if let s = start { blocks.append(s..<i); start = nil }
        }
        if let s = start { blocks.append(s..<rows.count) }
        for (b, range) in blocks.enumerated() { for i in range { blockOf[i] = b } }
        updateSummary()
        prevButton.isEnabled = !blocks.isEmpty
        nextButton.isEnabled = !blocks.isEmpty

        leftStyles = rows.map { r in
            switch r.kind { case .equal: return .none; case .removed: return .removed; case .changed: return .changed; case .added: return .filler }
        }
        rightStyles = rows.map { r in
            switch r.kind { case .equal: return .none; case .added: return .added; case .changed: return .changed; case .removed: return .filler }
        }

        var leftGaps: [Int: Int] = [:], rightGaps: [Int: Int] = [:]
        var lPend = 0, rPend = 0, lTop = 0, rTop = 0
        for r in rows {
            if let l = r.leftLine { if lPend > 0 { if l == 1 { lTop = lPend } else { leftGaps[l - 1] = lPend } }; lPend = 0 } else { lPend += 1 }
            if let rr = r.rightLine { if rPend > 0 { if rr == 1 { rTop = rPend } else { rightGaps[rr - 1] = rPend } }; rPend = 0 } else { rPend += 1 }
        }
        left.setGaps(leftGaps, top: lTop)
        right.setGaps(rightGaps, top: rTop)

        maxColumns = 0
        for l in oldLines + newLines { maxColumns = max(maxColumns, DiffUI.columns(l)) }
        let maxNumber = max(oldLines.count, newLines.count)
        left.setGutterRows(rows.count, maxLineNumber: maxNumber)
        right.setGutterRows(rows.count, maxLineNumber: maxNumber)

        let lStarts = DiffUI.lineStarts(oldS as NSString), rStarts = DiffUI.lineStarts(newS as NSString)
        intra = []
        for r in rows where r.kind == .changed {
            guard let l = r.left, let rt = r.right, let ll = r.leftLine, let rl = r.rightLine,
                  ll - 1 < lStarts.count, rl - 1 < rStarts.count else { continue }
            let d = DiffEngine.intraLine(l, rt)
            let lo = lStarts[ll - 1], ro = rStarts[rl - 1]
            intra.append((d.a.map { let n = NSRange($0, in: l); return NSRange(location: n.location + lo, length: n.length) },
                          d.b.map { let n = NSRange($0, in: rt); return NSRange(location: n.location + ro, length: n.length) }))
        }
        for h in highlighters { h.reparse() }
        applyIntra()
        refreshOverview()
        if checked.contains(where: { $0 >= rows.count }) { checked = [] }
        selection = selection.filter { $0 < rows.count }
        for p in [left, right] { p.gutter.needsDisplay = true; p.text.needsDisplay = true }
        arrows.needsDisplay = true
        needsLayout = true
    }

    private func bands(_ range: Range<Int>, left isLeft: Bool) -> [DiffBand] {
        let styles = isLeft ? leftStyles : rightStyles
        var out: [DiffBand] = []
        for row in range.clamped(to: 0..<styles.count) {
            switch styles[row] {
            case .none: continue
            case .added: out.append(DiffBand(row: row, count: 1, color: DiffColors.added))
            case .removed: out.append(DiffBand(row: row, count: 1, color: DiffColors.removed))
            case .changed: out.append(DiffBand(row: row, count: 1, color: DiffColors.changed))
            case .filler: out.append(DiffBand(row: row, count: 1, color: Theme.background, hatch: true))
            }
        }
        if !selection.isEmpty {
            for row in range.clamped(to: 0..<rows.count) where selection.contains(row) {
                out.append(DiffBand(row: row, count: 1, color: DiffColors.selection.withAlphaComponent(0.28)))
            }
        }
        return out
    }

    private func applyIntra() {
        guard let ll = left.text.layoutManager, let rl = right.text.layoutManager else { return }
        let lc = left.text.textStorage?.length ?? 0, rc = right.text.textStorage?.length ?? 0
        ll.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: lc))
        rl.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: rc))
        for e in intra {
            for r in e.left where NSMaxRange(r) <= lc { ll.addTemporaryAttribute(.backgroundColor, value: DiffColors.changedStrong, forCharacterRange: r) }
            for r in e.right where NSMaxRange(r) <= rc { rl.addTemporaryAttribute(.backgroundColor, value: DiffColors.changedStrong, forCharacterRange: r) }
        }
    }

    private func blockColor(_ b: Range<Int>) -> NSColor {
        switch rows[b.lowerBound].kind {
        case .added: return DiffColors.addedStrong
        case .removed: return DiffColors.removedStrong
        default: return DiffColors.changedStrong
        }
    }

    private func blockColorSoft(_ b: Range<Int>) -> NSColor {
        guard rows.indices.contains(b.lowerBound) else { return .clear }
        switch rows[b.lowerBound].kind {
        case .added: return DiffColors.added
        case .removed: return DiffColors.removed
        default: return DiffColors.changed
        }
    }

    private func refreshOverview() {
        overview.rowCount = rows.count
        overview.blocks = blocks.map { b in (b, { [unowned self] in self.rows.indices.contains(b.lowerBound) ? self.blockColor(b) : .clear }) }
        overview.needsDisplay = true
    }

    @objc private func themeChanged() {
        summary.textColor = DiffColors.secondary
        leftTitle.textColor = Theme.foreground
        rightTitle.textColor = Theme.foreground
        toast.textColor = Theme.foreground
        toast.layer?.backgroundColor = DiffColors.chrome.cgColor
        for p in [left, right] { p.restyle(); p.gutter.needsDisplay = true }
        highlighters = [left, right].compactMap { DiffHighlighter(textView: $0.text, extension: extensionName) }
        applyIntra()
        header.needsDisplay = true
        arrows.needsDisplay = true
        overview.needsDisplay = true
    }

    // MARK: layout & sync

    override func layout() {
        super.layout()
        for p in [left, right] { p.fit(rows: rows.count, columns: maxColumns) }
        updateViewport()
    }

    @objc private func leftScrolled() { sync(from: left, to: right); arrows.needsDisplay = true }
    @objc private func rightScrolled() { sync(from: right, to: left); updateViewport(); arrows.needsDisplay = true }

    private func sync(from a: DiffPane, to b: DiffPane) {
        guard !syncing else { return }
        syncing = true
        let o = a.scroll.contentView.bounds.origin
        DiffUI.scroll(b.scroll.contentView, x: o.x, y: o.y)
        syncing = false
    }

    private func updateViewport() {
        let clip = right.scroll.contentView.bounds
        let total = max(1, right.text.frame.height)
        overview.viewport = (clip.origin.y / total, clip.height / total)
        overview.needsDisplay = true
    }

    // MARK: navigation

    func nextChange() { go(1) }
    func previousChange() { go(-1) }
    @objc private func prevClicked() { previousChange() }
    @objc private func nextClicked() { nextChange() }

    private func go(_ step: Int) {
        flushEdits()
        guard !blocks.isEmpty else { return }
        var i = current + step
        var wrapped = false
        if i >= blocks.count { i = 0; wrapped = true } else if i < 0 { i = blocks.count - 1; wrapped = true }
        current = i
        reveal(blocks[i])
        if wrapped { showToast(step > 0 ? "Wrapped to first change" : "Wrapped to last change") }
    }

    private func jump(toFraction f: CGFloat) {
        guard !blocks.isEmpty else { return }
        let row = Int(f * CGFloat(rows.count))
        let i = blocks.enumerated().min { abs($0.element.lowerBound - row) < abs($1.element.lowerBound - row) }!.offset
        current = i
        reveal(blocks[i])
    }

    private func updateSummary() {
        let n = blocks.count
        summary.stringValue = n == 0 ? "No differences" : current >= 0 && current < n ? "\(current + 1) of \(n) differences" : "\(n) difference\(n == 1 ? "" : "s")"
    }

    private func reveal(_ block: Range<Int>, flash shouldFlash: Bool = true) {
        let clip = right.scroll.contentView
        let y0 = DiffUI.inset + CGFloat(block.lowerBound) * DiffUI.lineHeight
        let h = CGFloat(block.count) * DiffUI.lineHeight
        let target = h < clip.bounds.height ? y0 - (clip.bounds.height - h) / 2 : y0 - 40
        updateSummary()
        DiffUI.scroll(clip, x: clip.bounds.origin.x, y: max(0, target))
        if shouldFlash { flash(block) }
    }

    private func flash(_ block: Range<Int>) {
        flashTimer?.invalidate()
        var alpha: CGFloat = 1
        let tick = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            alpha -= 0.07
            for p in [self.left, self.right] {
                p.text.flash = alpha > 0 ? (block, alpha) : nil
                p.text.needsDisplay = true
            }
            if alpha <= 0 { t.invalidate() }
        }
        tick.tolerance = 0.01
        RunLoop.main.add(tick, forMode: .common)
        flashTimer = tick
        for p in [left, right] { p.text.flash = (block, 1); p.text.needsDisplay = true }
    }

    private func showToast(_ message: String) {
        toast.stringValue = "  \(message)  "
        toast.alphaValue = 1
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 1.2
            toast.animator().alphaValue = 0
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 98 { // F7
            event.modifierFlags.contains(.shift) ? previousChange() : nextChange()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: editing & live re-diff

    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        if tv === right.text { pendingNew = true } else if tv === left.text { pendingOld = true } else { return }
        editWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushEdits() }
        editWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Runs any pending live re-diff now and fires the edit callbacks.
    private func flushEdits() {
        guard pendingNew || pendingOld else { return }
        editWork?.cancel()
        let (n, o) = (pendingNew, pendingOld)
        pendingNew = false; pendingOld = false
        rediffKeepingPosition()
        if n { onNewSideEdited?(newText) }
        if o { onOldSideEdited?(oldText) }
    }

    private func rediffKeepingPosition() {
        let clip = right.scroll.contentView
        let lh = DiffUI.lineHeight
        let oldTop = Int(max(0, (clip.bounds.origin.y - DiffUI.inset) / lh))
        let anchorRow = rows.indices.contains(oldTop) ? rows[oldTop] : nil
        selection = []; anchor = nil
        recompute()
        layoutSubtreeIfNeeded()
        if let a = anchorRow {
            let newTop = rows.firstIndex { ($0.rightLine != nil && $0.rightLine == a.rightLine) || ($0.leftLine != nil && $0.leftLine == a.leftLine && a.rightLine == nil) }
            if let t = newTop, t != oldTop {
                DiffUI.scroll(clip, x: clip.bounds.origin.x, y: clip.bounds.origin.y + CGFloat(t - oldTop) * lh)
            }
        }
    }

    private func updateArrows() {
        arrows.showToNew = isNewSideEditable
        arrows.showToOld = isOldSideEditable
        arrowWidth.constant = (isNewSideEditable || isOldSideEditable) ? 40 : 1
        arrows.needsDisplay = true
        needsLayout = true
    }

    // MARK: applying lines between sides

    /// `base` side's text with the rows in `take` replaced by the other side's version.
    private func compose(base: Side, take: Set<Int>) -> String {
        var out: [String] = []
        for (i, r) in rows.enumerated() {
            let o = r.leftLine.map { oldLines[$0 - 1] }, n = r.rightLine.map { newLines[$0 - 1] }
            if r.kind == .equal { out.append((base == .old ? o : n) ?? ""); continue }
            let other = take.contains(i)
            if let piece = ((base == .old) == other) ? n : o { out.append(piece) }
        }
        var text = ""
        for (i, piece) in out.enumerated() {
            text += piece
            if i < out.count - 1, piece.utf8.last != 10 { text += "\n" }
        }
        return text
    }

    func contentApplyingChecked() -> String {
        flushEdits()
        if checked.isEmpty { return oldText }
        if checked.count == changedLineCount { return newText }
        return compose(base: .old, take: checked)
    }

    private func setPaneText(_ pane: DiffPane, _ text: String) {
        let tv = pane.text
        let cur = tv.string as NSString, nw = text as NSString
        var pre = 0
        let maxPre = min(cur.length, nw.length)
        while pre < maxPre, cur.character(at: pre) == nw.character(at: pre) { pre += 1 }
        if pre > 0, UTF16.isLeadSurrogate(cur.character(at: pre - 1)) { pre -= 1 }
        var suf = 0
        while suf < maxPre - pre, cur.character(at: cur.length - 1 - suf) == nw.character(at: nw.length - 1 - suf) { suf += 1 }
        if suf > 0, UTF16.isTrailSurrogate(cur.character(at: cur.length - suf)) { suf -= 1 }
        let range = NSRange(location: pre, length: cur.length - pre - suf)
        let repl = nw.substring(with: NSRange(location: pre, length: nw.length - pre - suf))
        guard range.length > 0 || !repl.isEmpty else { return }
        if tv.shouldChangeText(in: range, replacementString: repl) {
            tv.textStorage?.replaceCharacters(in: range, with: repl)
            tv.didChangeText()
            tv.undoManager?.setActionName("Apply Changes")
        }
    }

    /// toNew: make the new side take the old side's version of `rowSet` (revert); otherwise the old side takes the new version.
    func applyRows(_ rowSet: Set<Int>, toNew: Bool) {
        flushEdits()
        let changed = rowSet.filter { rows.indices.contains($0) && rows[$0].kind != .equal }
        guard !changed.isEmpty else { return }
        if toNew {
            guard isNewSideEditable else { return }
            setPaneText(right, compose(base: .new, take: Set(changed)))
        } else {
            guard isOldSideEditable else { return }
            setPaneText(left, compose(base: .old, take: Set(changed)))
        }
        flushEdits()
    }

    func applyBlock(_ b: Int, toNew: Bool) {
        flushEdits()
        guard blocks.indices.contains(b) else { return }
        let picked = selection.intersection(Set(blocks[b]))
        applyRows(picked.isEmpty ? Set(blocks[b]) : picked, toNew: toNew)
    }

    func applySelection(toNew: Bool) { applyRows(selection, toNew: toNew) }

    // MARK: selection & checkboxes

    func selectRows(_ r: Set<Int>) {
        selection = r
        for p in [left, right] { p.gutter.needsDisplay = true; p.text.needsDisplay = true }
    }

    private func gutterMouse(_ row: Int, _ x: CGFloat, _ event: NSEvent, _ phase: DiffGutter.Phase, isRight: Bool) {
        guard rows.indices.contains(row) || phase == .up else { return }
        if phase == .up { return }
        if isRight, pickMode == .stage, phase == .down {
            if x >= right.gutter.hunkBoxX - 2, x < right.gutter.hunkBoxX + DiffGutter.boxSize + 3, blockOf[row] >= 0 {
                if blocks[blockOf[row]].lowerBound == row { toggleBlock(blockOf[row]) }
                return
            }
            if x >= right.gutter.lineBoxX - 2, x < right.gutter.lineBoxX + DiffGutter.boxSize + 3 {
                if rows[row].kind != .equal { toggleRow(row) }
                return
            }
        }
        switch phase {
        case .down:
            if event.modifierFlags.contains(.shift), let a = anchor { selection = Set(min(a, row)...max(a, row)) }
            else if event.modifierFlags.contains(.command) {
                if selection.contains(row) { selection.remove(row) } else { selection.insert(row) }
                anchor = row
            } else { selection = [row]; anchor = row }
        case .drag:
            if let a = anchor { selection = Set(min(a, row)...max(a, row)) }
        case .up: break
        }
        for p in [left, right] { p.gutter.needsDisplay = true; p.text.needsDisplay = true }
    }

    private func lineCheckState(_ row: Int) -> Int? {
        guard pickMode == .stage, rows.indices.contains(row), rows[row].kind != .equal else { return nil }
        return checked.contains(row) ? 1 : 0
    }

    private func hunkCheckState(_ row: Int) -> Int? {
        guard pickMode == .stage, rows.indices.contains(row), blockOf[row] >= 0, blocks[blockOf[row]].lowerBound == row else { return nil }
        let n = blocks[blockOf[row]].reduce(0) { $0 + (checked.contains($1) ? 1 : 0) }
        return n == 0 ? 0 : (n == blocks[blockOf[row]].count ? 1 : 2)
    }

    private func toggleRow(_ row: Int) {
        if checked.contains(row) { checked.remove(row) } else { checked.insert(row) }
        checkedChanged()
    }

    private func toggleBlock(_ b: Int) {
        let range = blocks[b]
        if range.allSatisfy({ checked.contains($0) }) { for i in range { checked.remove(i) } } else { for i in range { checked.insert(i) } }
        checkedChanged()
    }

    func setChecked(rows rowSet: Set<Int>, _ value: Bool) {
        for i in rowSet where rows.indices.contains(i) && rows[i].kind != .equal {
            if value { checked.insert(i) } else { checked.remove(i) }
        }
        checkedChanged()
    }

    func setAllChecked(_ value: Bool) {
        flushEdits()
        checked = value ? Set(rows.indices.filter { rows[$0].kind != .equal }) : []
        checkedChanged()
    }

    private func checkedChanged() {
        right.gutter.needsDisplay = true
        onCheckedChanged?()
    }

    private func updatePickMode() {
        let stage = pickMode == .stage
        right.gutter.hasHunkColumn = stage
        right.gutterExtra = stage ? 40 : 0
        right.gutter.needsDisplay = true
        needsLayout = true
    }

    // MARK: context menu

    private func menu(forRow row: Int) -> NSMenu? {
        guard rows.indices.contains(row) else { return nil }
        if !selection.contains(row) { selection = [row]; anchor = row; selectRows(selection) }
        guard selection.contains(where: { rows.indices.contains($0) && rows[$0].kind != .equal }) else { return nil }
        let m = NSMenu()
        func add(_ title: String, _ sel: Selector, enabled: Bool) {
            let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            item.target = self
            item.isEnabled = enabled
            m.addItem(item)
        }
        add("Apply Selected Lines to Right", #selector(menuApplyRight), enabled: isNewSideEditable)
        add("Apply Selected Lines to Left", #selector(menuApplyLeft), enabled: isOldSideEditable)
        add("Revert Selected Lines", #selector(menuRevert), enabled: isNewSideEditable || isOldSideEditable)
        if pickMode == .stage {
            m.addItem(.separator())
            add("Check Selected Lines", #selector(menuCheck), enabled: true)
            add("Uncheck Selected Lines", #selector(menuUncheck), enabled: true)
        }
        return m
    }

    @objc private func menuApplyRight() { applySelection(toNew: true) }
    @objc private func menuApplyLeft() { applySelection(toNew: false) }
    @objc private func menuRevert() { applySelection(toNew: isNewSideEditable) }
    @objc private func menuCheck() { setChecked(rows: selection, true) }
    @objc private func menuUncheck() { setChecked(rows: selection, false) }
}
