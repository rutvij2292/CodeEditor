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

final class SideBySideDiffView: NSView {
    private enum Style { case none, added, removed, changed, filler }

    private let left = DiffPane(editable: false)
    private let right = DiffPane(editable: false)
    private let header = DiffFillView { DiffColors.chrome }
    private let divider = DiffFillView { DiffColors.separator }
    private let leftTitle = DiffUI.label()
    private let rightTitle = DiffUI.label()
    private let summary = DiffUI.label(11, weight: .regular)
    private let overview = DiffOverview()
    private let toast = DiffUI.label(11, weight: .medium)

    private var rows: [DiffEngine.Row] = []
    private var blocks: [Range<Int>] = []
    private var leftStyles: [Style] = [], rightStyles: [Style] = []
    private var intra: [(left: [NSRange], right: [NSRange])] = []
    private var maxColumns = 0
    private var current = -1
    private var syncing = false
    private var highlighters: [DiffHighlighter] = []
    private var flashTimer: Timer?
    private var extensionName = ""

    var changeCount: Int { blocks.count }

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    private func build() {
        left.scroll.hasVerticalScroller = false
        for v in [header, left.box, divider, right.box, overview, toast] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        for l in [leftTitle, rightTitle, summary] { header.addSubview(l) }
        summary.textColor = DiffColors.secondary
        summary.alignment = .right
        toast.alignment = .center
        toast.wantsLayer = true
        toast.layer?.cornerRadius = 6
        toast.drawsBackground = false
        toast.alphaValue = 0
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor), header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor), header.heightAnchor.constraint(equalToConstant: 28),
            left.box.topAnchor.constraint(equalTo: header.bottomAnchor), left.box.bottomAnchor.constraint(equalTo: bottomAnchor),
            left.box.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.leadingAnchor.constraint(equalTo: left.box.trailingAnchor), divider.widthAnchor.constraint(equalToConstant: 1),
            divider.topAnchor.constraint(equalTo: left.box.topAnchor), divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            right.box.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            right.box.topAnchor.constraint(equalTo: left.box.topAnchor), right.box.bottomAnchor.constraint(equalTo: bottomAnchor),
            right.box.widthAnchor.constraint(equalTo: left.box.widthAnchor),
            overview.leadingAnchor.constraint(equalTo: right.box.trailingAnchor), overview.trailingAnchor.constraint(equalTo: trailingAnchor),
            overview.widthAnchor.constraint(equalToConstant: 14),
            overview.topAnchor.constraint(equalTo: left.box.topAnchor), overview.bottomAnchor.constraint(equalTo: bottomAnchor),
            leftTitle.leadingAnchor.constraint(equalTo: left.box.leadingAnchor, constant: 10),
            leftTitle.trailingAnchor.constraint(equalTo: left.box.trailingAnchor, constant: -10),
            rightTitle.leadingAnchor.constraint(equalTo: right.box.leadingAnchor, constant: 10),
            rightTitle.trailingAnchor.constraint(equalTo: right.box.trailingAnchor, constant: -110),
            summary.trailingAnchor.constraint(equalTo: overview.trailingAnchor, constant: -16),
            summary.widthAnchor.constraint(equalToConstant: 96),
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
        }
        nc.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
        overview.onClick = { [weak self] f in self?.jump(toFraction: f) }
        themeChanged()
    }

    // MARK: content

    func show(old: String, new: String, oldTitle: String, newTitle: String, fileExtension: String) {
        extensionName = fileExtension
        leftTitle.stringValue = oldTitle
        rightTitle.stringValue = newTitle
        rows = DiffEngine.rows(old: old, new: new)
        current = -1

        blocks = []
        var start: Int?
        for (i, r) in rows.enumerated() {
            if r.kind != .equal { if start == nil { start = i } } else if let s = start { blocks.append(s..<i); start = nil }
        }
        if let s = start { blocks.append(s..<rows.count) }
        summary.stringValue = blocks.isEmpty ? "No differences" : "\(blocks.count) difference\(blocks.count == 1 ? "" : "s")"

        leftStyles = rows.map { r in
            switch r.kind { case .equal: return .none; case .removed: return .removed; case .changed: return .changed; case .added: return .filler }
        }
        rightStyles = rows.map { r in
            switch r.kind { case .equal: return .none; case .added: return .added; case .changed: return .changed; case .removed: return .filler }
        }

        var leftText = [String](), rightText = [String]()
        var leftOff = [Int](), rightOff = [Int]()
        var lo = 0, ro = 0
        maxColumns = 0
        for r in rows {
            let l = r.left ?? "", rt = r.right ?? ""
            leftText.append(l); rightText.append(rt)
            leftOff.append(lo); rightOff.append(ro)
            lo += l.utf16.count + 1; ro += rt.utf16.count + 1
            maxColumns = max(maxColumns, DiffUI.columns(l), DiffUI.columns(rt))
        }
        let maxNumber = rows.reduce(0) { max($0, $1.leftLine ?? 0, $1.rightLine ?? 0) }
        left.setText(leftText.joined(separator: "\n"), maxLineNumber: maxNumber)
        right.setText(rightText.joined(separator: "\n"), maxLineNumber: maxNumber)
        left.gutter.rowCount = rows.count; right.gutter.rowCount = rows.count
        left.gutter.numberForRow = { [weak self] i in self.flatMap { $0.rows.indices.contains(i) ? $0.rows[i].leftLine : nil } }
        right.gutter.numberForRow = { [weak self] i in self.flatMap { $0.rows.indices.contains(i) ? $0.rows[i].rightLine : nil } }
        left.text.bandSource = { [weak self] r in self?.bands(r, left: true) ?? [] }
        right.text.bandSource = { [weak self] r in self?.bands(r, left: false) ?? [] }

        intra = []
        for (i, r) in rows.enumerated() where r.kind == .changed {
            guard let l = r.left, let rt = r.right else { continue }
            let d = DiffEngine.intraLine(l, rt)
            intra.append((d.a.map { NSRange($0, in: l) }.map { NSRange(location: $0.location + leftOff[i], length: $0.length) },
                          d.b.map { NSRange($0, in: rt) }.map { NSRange(location: $0.location + rightOff[i], length: $0.length) }))
        }
        highlighters = [left, right].compactMap { DiffHighlighter(textView: $0.text, extension: fileExtension) }
        applyIntra()
        refreshOverview()
        needsLayout = true
        layoutSubtreeIfNeeded()
        DiffUI.scroll(left.scroll.contentView, x: 0, y: 0)
        DiffUI.scroll(right.scroll.contentView, x: 0, y: 0)
        for p in [left, right] { p.gutter.needsDisplay = true; p.text.needsDisplay = true }
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

    private func refreshOverview() {
        overview.rowCount = rows.count
        overview.blocks = blocks.map { b in (b, { [unowned self] in self.blockColor(b) }) }
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
        for v in [header, divider] { v.needsDisplay = true }
        overview.needsDisplay = true
    }

    // MARK: layout & sync

    override func layout() {
        super.layout()
        for p in [left, right] { p.fit(rows: rows.count, columns: maxColumns) }
        updateViewport()
    }

    @objc private func leftScrolled() { sync(from: left, to: right) }
    @objc private func rightScrolled() { sync(from: right, to: left); updateViewport() }

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

    private func go(_ step: Int) {
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

    private func reveal(_ block: Range<Int>) {
        let clip = right.scroll.contentView
        let y0 = DiffUI.inset + CGFloat(block.lowerBound) * DiffUI.lineHeight
        let h = CGFloat(block.count) * DiffUI.lineHeight
        let target = h < clip.bounds.height ? y0 - (clip.bounds.height - h) / 2 : y0 - 40
        DiffUI.scroll(clip, x: clip.bounds.origin.x, y: target)
        flash(block)
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
        RunLoop.main.add(tick, forMode: .common)
        flashTimer = tick
        for p in [left, right] { p.text.flash = (block, 1); p.text.needsDisplay = true }
    }

    private func showToast(_ message: String) {
        toast.stringValue = "  \(message)  "
        toast.drawsBackground = false
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
}
