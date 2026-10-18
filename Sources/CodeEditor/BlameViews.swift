import AppKit

// MARK: - Inline annotation

/// The dim italic "Author, 3 days ago · Summary" label placed after the caret line. A subview of the text view, so it scrolls
/// with the text and only intercepts the mouse over its own (small) frame.
final class BlameChip: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private(set) var text = ""
    private(set) var font: NSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    /// Baseline offset from the top of the line fragment (from the layout manager).
    var baseline: CGFloat = 12 { didSet { if baseline != oldValue { needsDisplay = true } } }
    private var clickable = false
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    var naturalWidth: CGFloat { ceil((text as NSString).size(withAttributes: attributes()).width) + 2 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(text: String, font: NSFont, clickable: Bool) {
        self.text = text; self.font = font; self.clickable = clickable
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func restyle(font: NSFont) { self.font = font; needsDisplay = true }

    private func attributes() -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingTail
        var a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.palette.gutter.withAlphaComponent(Theme.isDark ? 0.95 : 0.85),
                                                .paragraphStyle: p]
        if !font.fontDescriptor.symbolicTraits.contains(.italic) { a[.obliqueness] = 0.18 }
        return a
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = NSRect(x: 0, y: baseline - font.ascender, width: bounds.width, height: ceil(font.ascender - font.descender) + 2)
        (text as NSString).draw(with: r, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes())
    }

    override func resetCursorRects() { if clickable { addCursorRect(bounds, cursor: .pointingHand) } }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { if clickable { onClick?() } }
}

// MARK: - Annotate column

/// Strip between the line-number gutter and the text: author + date per commit run, tinted by age and author.
final class BlameAnnotateView: NSView {
    struct Row: Equatable {
        var line: Int          // 0-based buffer line
        var y0: CGFloat, y1: CGFloat
        var info: BlameLineInfo
        var label: String?     // drawn only on the first line of a commit run
    }

    private weak var controller: BlameController?
    private(set) var rows: [Row] = []
    private var font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
    override var isFlipped: Bool { true }

    private static let labelColumns = 23

    var preferredWidth: CGFloat {
        let w = ("0" as NSString).size(withAttributes: [.font: currentFont]).width
        return ceil(w * CGFloat(Self.labelColumns)) + 16
    }

    private var currentFont: NSFont {
        let size = max(8, (controller?.textView?.font?.pointSize ?? 13) - 2.5)
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    init(controller: BlameController) {
        self.controller = controller
        super.init(frame: .zero)
        font = currentFont
        let nc = NotificationCenter.default
        if let sv = controller.scrollView {
            nc.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: sv.contentView)
        }
        if let tv = controller.textView {
            tv.postsFrameChangedNotifications = true
            nc.addObserver(self, selector: #selector(refresh), name: NSView.frameDidChangeNotification, object: tv)
        }
        nc.addObserver(self, selector: #selector(refresh), name: Theme.didChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func refresh() { needsDisplay = true }
    func restyle() { font = currentFont; needsDisplay = true }

    override func layout() {
        super.layout()
        removeAllToolTips()
        addToolTip(bounds, owner: self, userData: nil)
    }

    func tint(for commit: BlameCommit, now: Date = Date()) -> NSColor {
        let days = max(0, now.timeIntervalSince(commit.date)) / 86400
        let strength = CGFloat(exp(-days / 150))
        let dark = Theme.isDark
        return NSColor(hue: Blame.hue(for: commit.author), saturation: dark ? 0.55 : 0.5, brightness: dark ? 0.8 : 0.95,
                       alpha: (dark ? 0.08 : 0.10) + 0.30 * strength)
    }

    /// Rows for the visible lines (also used by tests to compare against the text layout).
    func computeRows() -> [Row] {
        var out: [Row] = []
        guard let c = controller, let tv = c.textView, let lm = tv.layoutManager, let tc = tv.textContainer, c.canDrawStrip else { return out }
        let text = tv.string as NSString
        guard text.length > 0 else { return out }
        let inset = tv.textContainerOrigin.y
        let visible = lm.glyphRange(forBoundingRect: tv.visibleRect, in: tc)
        var glyph = visible.location
        let endGlyph = NSMaxRange(visible)
        var previous: BlameLineInfo?
        while glyph < endGlyph {
            let charIdx = lm.characterIndexForGlyph(at: glyph)
            let lineRange = text.lineRange(for: NSRange(location: charIdx, length: 0))
            let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let lineGlyphs = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let y0 = convert(NSPoint(x: 0, y: frag.minY + inset), from: tv).y
            var y1 = y0 + frag.height
            if lineGlyphs.length > 1 {
                let last = lm.lineFragmentRect(forGlyphAt: NSMaxRange(lineGlyphs) - 1, effectiveRange: nil)
                y1 = convert(NSPoint(x: 0, y: last.maxY + inset), from: tv).y
            }
            let line = c.lineIndex(ofChar: lineRange.location)
            let info = c.info(forBufferLine: line)
            if frag.height >= 2 {
                if previous == nil { previous = line > 0 ? c.info(forBufferLine: line - 1) : BlameLineInfo.none }
                var label: String?
                if info != previous {
                    switch info {
                    case .commit(let i):
                        if let m = c.commit(at: i) { label = Blame.abbreviatedAuthor(m.author) + "  " + Blame.shortDateText(m.date) }
                    case .uncommitted: label = "Not committed"
                    case .none: break
                    }
                }
                out.append(Row(line: line, y0: y0, y1: y1, info: info, label: label))
                previous = info
            }
            glyph = max(NSMaxRange(lineGlyphs), glyph + 1)
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
        rows = computeRows()
        guard let c = controller else { return }
        let dark = Theme.isDark
        let textColor = Theme.foreground.withAlphaComponent(dark ? 0.78 : 0.72)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let sepColor = Theme.palette.gutter.withAlphaComponent(0.25)
        let now = Date()
        for (n, r) in rows.enumerated() {
            var fill: NSColor?
            switch r.info {
            case .commit(let i): if let m = c.commit(at: i) { fill = tint(for: m, now: now) }
            case .uncommitted: fill = NSColor.systemGreen.withAlphaComponent(dark ? 0.22 : 0.25)
            case .none: break
            }
            let rect = NSRect(x: 0, y: r.y0, width: bounds.width - 1, height: r.y1 - r.y0)
            if let fill { fill.setFill(); rect.fill() }
            if let label = r.label {
                let size = (label as NSString).size(withAttributes: attrs)
                let first = n > 0 // separator above every run start (not above the very first visible row)
                if first { sepColor.setFill(); NSRect(x: 0, y: r.y0, width: bounds.width - 1, height: 1).fill() }
                let lineHeight = min(r.y1 - r.y0, size.height + 8)
                (label as NSString).draw(at: NSPoint(x: 7, y: r.y0 + (lineHeight - size.height) / 2), withAttributes: attrs)
            }
        }
        // right edge hairline
        Theme.palette.gutter.withAlphaComponent(0.2).setFill()
        NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height).fill()
    }

    private func row(at point: NSPoint) -> Row? { rows.first { point.y >= $0.y0 && point.y < $0.y1 } }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let r = row(at: p), case .commit(let i) = r.info else { return }
        controller?.showPopover(commitIndex: i, anchor: NSRect(x: 0, y: r.y0, width: bounds.width, height: r.y1 - r.y0), of: self)
    }

    /// Tooltip text for a point (the commit subject).
    func tooltip(at point: NSPoint) -> String? {
        guard let r = row(at: point), let c = controller else { return nil }
        switch r.info {
        case .commit(let i):
            guard let m = c.commit(at: i) else { return nil }
            return "\(m.summary)\n\(m.author) · \(m.shortHash) · \(Blame.longDateText(m.date))"
        case .uncommitted: return Blame.uncommittedText
        case .none: return nil
        }
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        tooltip(at: point) ?? ""
    }
}

// MARK: - Popover

/// Commit card: hash, author, dates, full message (scrollable), files count and actions. Standalone (renders without a window).
final class BlamePopoverView: NSView {
    var onCopyHash: (() -> Void)?
    var onCopyMessage: (() -> Void)?
    var onShowDiff: (() -> Void)?
    var onOpenLog: (() -> Void)?

    let commit: BlameCommit
    private let hashLabel = NSTextField(labelWithString: "")
    private let authorLabel = NSTextField(labelWithString: "")
    private let dateLabel = NSTextField(labelWithString: "")
    private let filesLabel = NSTextField(labelWithString: "")
    private let messageView = NSTextView()
    private let scroll = NSScrollView()
    private(set) var buttons: [NSButton] = []
    override var isFlipped: Bool { true }

    var messageText: String { messageView.string }
    var hashText: String { hashLabel.stringValue }
    var authorText: String { authorLabel.stringValue }
    var dateText: String { dateLabel.stringValue }
    var filesText: String { filesLabel.stringValue }
    var buttonTitles: [String] { buttons.map(\.title) }
    func press(_ title: String) { buttons.first { $0.title == title }?.performClick(nil) }

    init(commit: BlameCommit, you: (name: String, email: String)) {
        self.commit = commit
        let width: CGFloat = 480, pad: CGFloat = 12
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 250))
        appearance = nil
        func style(_ l: NSTextField, _ font: NSFont, _ color: NSColor) {
            l.font = font; l.textColor = color; l.lineBreakMode = .byTruncatingTail; addSubview(l)
        }
        style(hashLabel, .monospacedSystemFont(ofSize: 12, weight: .semibold), .labelColor)
        style(authorLabel, .systemFont(ofSize: 12), .labelColor)
        style(dateLabel, .systemFont(ofSize: 11), .secondaryLabelColor)
        style(filesLabel, .systemFont(ofSize: 11), .secondaryLabelColor)
        hashLabel.stringValue = commit.shortHash + (commit.boundary ? "  (boundary)" : "")
        let who = Blame.isYou(commit, you) ? "You (\(commit.author))" : commit.author
        authorLabel.stringValue = commit.mail.isEmpty ? who : "\(who)  <\(commit.mail)>"
        dateLabel.stringValue = "\(Blame.longDateText(commit.date))  ·  \(Blame.relativeText(from: commit.date))"
        filesLabel.stringValue = ""

        messageView.isEditable = false
        messageView.isSelectable = true
        messageView.drawsBackground = true
        messageView.backgroundColor = NSColor.textBackgroundColor
        messageView.textColor = NSColor.labelColor
        messageView.font = .systemFont(ofSize: 12)
        messageView.textContainerInset = NSSize(width: 6, height: 5)
        messageView.isVerticallyResizable = true
        messageView.isHorizontallyResizable = false
        messageView.autoresizingMask = [.width]
        messageView.textContainer?.widthTracksTextView = true
        messageView.string = commit.summary
        scroll.documentView = messageView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .lineBorder
        addSubview(scroll)

        for title in ["Copy Hash", "Copy Message", "Show Diff", "Open in Git Log"] {
            let b = NSButton(title: title, target: self, action: #selector(buttonPressed(_:)))
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11)
            b.sizeToFit()
            addSubview(b)
            buttons.append(b)
        }
        // layout (top to bottom)
        let inner = width - pad * 2
        hashLabel.frame = NSRect(x: pad, y: 10, width: inner, height: 17)
        authorLabel.frame = NSRect(x: pad, y: 29, width: inner, height: 16)
        dateLabel.frame = NSRect(x: pad, y: 47, width: inner, height: 15)
        scroll.frame = NSRect(x: pad, y: 68, width: inner, height: 120)
        filesLabel.frame = NSRect(x: pad, y: 194, width: inner, height: 15)
        var x = pad
        for b in buttons { b.frame = NSRect(x: x, y: 216, width: b.frame.width + 6, height: 24); x += b.frame.width + 6 }
        setFrameSize(NSSize(width: width, height: 250))
        messageView.frame = NSRect(x: 0, y: 0, width: inner - 2, height: 120)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Full message + files count (arrive asynchronously).
    func apply(info: GitCommitInfo) {
        messageView.string = info.message.isEmpty ? commit.summary : info.message
        filesLabel.stringValue = "\(info.fileCount) file\(info.fileCount == 1 ? "" : "s") changed in this commit"
            + (info.parents.count > 1 ? "  ·  merge" : "")
    }

    @objc private func buttonPressed(_ b: NSButton) {
        switch b.title {
        case "Copy Hash": onCopyHash?()
        case "Copy Message": onCopyMessage?()
        case "Show Diff": onShowDiff?()
        default: onOpenLog?()
        }
    }
}

/// The commit's diff of one file, shown inside the popover in place of the commit card.
final class BlameDiffView: NSView {
    var onBack: (() -> Void)?
    let diff = SideBySideDiffView(frame: NSRect(x: 0, y: 0, width: 920, height: 480))
    private let titleLabel = NSTextField(labelWithString: "")
    override var isFlipped: Bool { true }

    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 920, height: 520))
        let back = NSButton(title: "‹ Back", target: self, action: #selector(backPressed))
        back.bezelStyle = .rounded
        back.controlSize = .small
        back.frame = NSRect(x: 8, y: 6, width: 64, height: 24)
        addSubview(back)
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 82, y: 9, width: 820, height: 17)
        addSubview(titleLabel)
        diff.frame = NSRect(x: 0, y: 36, width: 920, height: 484)
        diff.autoresizingMask = [.width, .height]
        addSubview(diff)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(old: String, new: String, oldTitle: String, newTitle: String, fileExtension: String) {
        diff.show(old: old, new: new, oldTitle: oldTitle, newTitle: newTitle, fileExtension: fileExtension)
    }

    @objc private func backPressed() { onBack?() }
}
