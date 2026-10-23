import AppKit

/// Explorer design tokens (light values from the mockup; dark variants derived). Read at draw time so a theme switch needs no rebuild.
enum TreeStyle {
    static let rowHeight: CGFloat = 28
    static let indent: CGFloat = 16
    static let rowInset: CGFloat = 6
    static let chevronSlot: CGFloat = 14
    private static var dark: Bool { Theme.isDark }
    static var foreground: NSColor { Theme.hex(dark ? 0xDCDFE4 : 0x1F2328) }
    static var muted: NSColor { Theme.hex(dark ? 0x8B93A1 : 0x5D6470) }
    static var guide: NSColor { dark ? NSColor(white: 1, alpha: 0.09) : Theme.hex(0xE6E8EC) }
    static var hover: NSColor { dark ? NSColor(white: 1, alpha: 0.06) : Theme.hex(0xF1F3F5) }
    static var selection: NSColor { dark ? Theme.hex(0x2F6FEB, alpha: 0.40) : Theme.hex(0xCFE0FC) }
    static var focusRing: NSColor { Theme.hex(0x2F6FEB, alpha: dark ? 0.9 : 0.8) }
    static var selectionInactive: NSColor { dark ? NSColor(white: 1, alpha: 0.10) : Theme.hex(0xEEF0F3) }
    static var selectionText: NSColor { Theme.hex(dark ? 0xBBD3FF : 0x0B3A8C) }
    static let font = NSFont.systemFont(ofSize: 13)
    static let selectedFont = NSFont.systemFont(ofSize: 13, weight: .medium)
}

/// Thin chevron (stroke 1.8, round caps) drawn rather than the system disclosure triangle; points down when expanded.
final class ChevronView: NSView {
    var expanded = false { didSet { if expanded != oldValue { needsDisplay = true } } }
    var visible = true { didSet { if visible != oldValue { needsDisplay = true } } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard visible else { return }
        let s: CGFloat = 12 / 16
        let ox = (bounds.width - 12) / 2, oy = (bounds.height - 12) / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            expanded ? NSPoint(x: ox + (16 - y) * s, y: oy + x * s) : NSPoint(x: ox + x * s, y: oy + y * s)
        }
        let p = NSBezierPath()
        p.move(to: pt(6, 3.5)); p.line(to: pt(10.5, 8)); p.line(to: pt(6, 12.5))
        p.lineWidth = 1.8 * s; p.lineCapStyle = .round; p.lineJoinStyle = .round
        TreeStyle.muted.setStroke(); p.stroke()
    }
}

/// One row: [chevron slot][icon][name]. Selection restyles the name (medium weight, blue).
final class TreeCellView: NSTableCellView {
    let chevron = ChevronView()
    private var baseColor: NSColor = TreeStyle.foreground
    private var italic = false
    private var plainName = ""
    private(set) var customAttributed = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        let img = NSImageView(), text = NSTextField(labelWithString: "")
        for v in [chevron, img, text] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        text.lineBreakMode = .byTruncatingMiddle
        text.font = TreeStyle.font
        imageView = img; textField = text
        NSLayoutConstraint.activate([
            chevron.leadingAnchor.constraint(equalTo: leadingAnchor, constant: TreeStyle.rowInset),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: TreeStyle.chevronSlot), chevron.heightAnchor.constraint(equalToConstant: 16),
            img.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 6),
            img.centerYAnchor.constraint(equalTo: centerYAnchor),
            img.widthAnchor.constraint(equalToConstant: 16), img.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: img.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(name: String, color: NSColor, italic: Bool, attributed: NSAttributedString?) {
        plainName = name; baseColor = color; self.italic = italic
        customAttributed = attributed != nil
        guard let text = textField else { return }
        if let attributed { text.attributedStringValue = attributed } else { applySelected(false) }
    }

    /// Plain names only: speed-search highlights carry their own attributes.
    func applySelected(_ selected: Bool) {
        guard let text = textField, !customAttributed else { return }
        var font = selected ? TreeStyle.selectedFont : TreeStyle.font
        if italic, !selected { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        text.font = font
        text.stringValue = plainName
        text.textColor = selected ? TreeStyle.selectionText : (italic ? TreeStyle.muted : baseColor)
    }
}

/// Rounded inset selection, hover tint and indent guides, all drawn here (no layers, no per-row subviews).
final class TreeRowView: NSTableRowView {
    var level = 0
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    override func drawBackground(in dirtyRect: NSRect) {
        if isHovered, !isSelected {
            TreeStyle.hover.setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6).fill()
        }
        guard level > 0 else { return }
        TreeStyle.guide.setFill()
        // Guide k sits under the chevron of ancestor level k (chevron centre = inset + slot / 2).
        for k in 0..<level {
            let x = TreeStyle.indent * CGFloat(k) + TreeStyle.rowInset + TreeStyle.chevronSlot / 2
            NSRect(x: x.rounded() - 0.5, y: 0, width: 1, height: bounds.height).fill()
        }
    }

    /// Selection / hover pill: inset from both edges of what is actually visible (the row can be wider than the viewport).
    private var pillRect: NSRect {
        var r = bounds
        if let visible = enclosingScrollView?.contentSize.width, visible > 0 { r.size.width = min(r.width, visible) }
        return r.insetBy(dx: TreeStyle.rowInset, dy: 0)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        (isEmphasized ? TreeStyle.selection : TreeStyle.selectionInactive).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6).fill()
        if isEmphasized {   // tree has keyboard focus: outline the pill so the focus move (⌘1) is obvious
            let p = NSBezierPath(roundedRect: pillRect.insetBy(dx: 0.75, dy: 0.75), xRadius: 6, yRadius: 6)
            p.lineWidth = 1.5
            TreeStyle.focusRing.setStroke()
            p.stroke()
        }
    }

    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            for case let cell as TreeCellView in subviews { cell.applySelected(isSelected) }
        }
    }
}

/// Header icon button: 28 pt square, 6 pt radius hover tint.
final class TreeIconButton: NSButton {
    private var hovering = false {
        didSet { contentTintColor = hovering ? TreeStyle.foreground : TreeStyle.muted; needsDisplay = true }
    }

    init(drawing: @escaping (NSBezierPath) -> Void, tooltip: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        self.target = target; self.action = action
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
        image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            let p = NSBezierPath()
            drawing(p)
            p.lineWidth = 1.3; p.lineCapStyle = .round; p.lineJoinStyle = .round
            NSColor.black.setStroke(); p.stroke()
            return true
        }
        image?.isTemplate = true
        contentTintColor = TreeStyle.muted
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow], owner: self))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func draw(_ dirtyRect: NSRect) {
        if hovering {
            (Theme.isDark ? NSColor(white: 1, alpha: 0.10) : Theme.hex(0xE4E7EB)).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        super.draw(dirtyRect)
    }
}

/// The sidebar: "Explorer" header with New File / New Folder / Collapse All, a PROJECT label, then the tree.
final class FileTreePanel: NSView {
    private let title = NSTextField(labelWithString: "Explorer")
    private let section = NSTextField(labelWithString: "PROJECT")
    private var observer: NSObjectProtocol?

    init(tree: FileTreeController) {
        super.init(frame: .zero)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let kern = NSMutableAttributedString(string: "PROJECT", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .kern: 0.66, .foregroundColor: TreeStyle.muted])
        section.attributedStringValue = kern

        let newFile = TreeIconButton(drawing: { p in
            p.move(to: NSPoint(x: 9, y: 2)); p.line(to: NSPoint(x: 4.5, y: 2))
            p.curve(to: NSPoint(x: 4, y: 2.5), controlPoint1: NSPoint(x: 4.22, y: 2), controlPoint2: NSPoint(x: 4, y: 2.22))
            p.line(to: NSPoint(x: 4, y: 13.5))
            p.curve(to: NSPoint(x: 4.5, y: 14), controlPoint1: NSPoint(x: 4, y: 13.78), controlPoint2: NSPoint(x: 4.22, y: 14))
            p.line(to: NSPoint(x: 11.5, y: 14))
            p.curve(to: NSPoint(x: 12, y: 13.5), controlPoint1: NSPoint(x: 11.78, y: 14), controlPoint2: NSPoint(x: 12, y: 13.78))
            p.line(to: NSPoint(x: 12, y: 5)); p.close()
            p.move(to: NSPoint(x: 8, y: 7.5)); p.line(to: NSPoint(x: 8, y: 11.5))
            p.move(to: NSPoint(x: 6, y: 9.5)); p.line(to: NSPoint(x: 10, y: 9.5))
        }, tooltip: "New File", target: tree, action: #selector(FileTreeController.panelNewFile))
        let newFolder = TreeIconButton(drawing: { p in
            p.move(to: NSPoint(x: 2, y: 4.5))
            p.curve(to: NSPoint(x: 3.5, y: 3), controlPoint1: NSPoint(x: 2, y: 3.67), controlPoint2: NSPoint(x: 2.67, y: 3))
            p.line(to: NSPoint(x: 6.1, y: 3)); p.line(to: NSPoint(x: 7.5, y: 4.5)); p.line(to: NSPoint(x: 12.5, y: 4.5))
            p.curve(to: NSPoint(x: 14, y: 6), controlPoint1: NSPoint(x: 13.33, y: 4.5), controlPoint2: NSPoint(x: 14, y: 5.17))
            p.line(to: NSPoint(x: 14, y: 11.5))
            p.curve(to: NSPoint(x: 12.5, y: 13), controlPoint1: NSPoint(x: 14, y: 12.33), controlPoint2: NSPoint(x: 13.33, y: 13))
            p.line(to: NSPoint(x: 3.5, y: 13))
            p.curve(to: NSPoint(x: 2, y: 11.5), controlPoint1: NSPoint(x: 2.67, y: 13), controlPoint2: NSPoint(x: 2, y: 12.33))
            p.close()
            p.move(to: NSPoint(x: 8, y: 7)); p.line(to: NSPoint(x: 8, y: 11))
            p.move(to: NSPoint(x: 6, y: 9)); p.line(to: NSPoint(x: 10, y: 9))
        }, tooltip: "New Folder", target: tree, action: #selector(FileTreeController.panelNewFolder))
        let collapse = TreeIconButton(drawing: { p in
            p.move(to: NSPoint(x: 5, y: 3)); p.line(to: NSPoint(x: 8, y: 6)); p.line(to: NSPoint(x: 11, y: 3))
            p.move(to: NSPoint(x: 5, y: 13)); p.line(to: NSPoint(x: 8, y: 10)); p.line(to: NSPoint(x: 11, y: 13))
        }, tooltip: "Collapse All", target: tree, action: #selector(FileTreeController.panelCollapseAll))

        let reload = TreeIconButton(drawing: { p in
            p.appendArc(withCenter: NSPoint(x: 8, y: 8), radius: 5, startAngle: 40, endAngle: 330, clockwise: false)
            p.move(to: NSPoint(x: 12.8, y: 2.8)); p.line(to: NSPoint(x: 12.9, y: 6.1)); p.line(to: NSPoint(x: 9.7, y: 6.0))
        }, tooltip: KeymapStore.retip("Refresh (⌥⌘Y)"), target: tree, action: #selector(FileTreeController.panelReload))
        let buttons = NSStackView(views: [newFile, newFolder, reload, collapse])
        buttons.spacing = 2
        for v in [title, buttons, section, tree.scrollView] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        tree.scrollView.drawsBackground = false
        tree.scrollView.hasHorizontalScroller = false
        tree.scrollView.automaticallyAdjustsContentInsets = false
        tree.scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            buttons.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
            section.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            section.topAnchor.constraint(equalTo: topAnchor, constant: 58),
            tree.scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 78),
            tree.scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tree.scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tree.scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        observer = NotificationCenter.default.addObserver(forName: Theme.didChange, object: nil, queue: .main) { [weak self] _ in
            FileIcon.resetTreeIcons()
            self?.restyle()
            tree.outline.reloadData()
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    override func viewDidChangeEffectiveAppearance() { restyle() }

    private func restyle() {
        title.textColor = TreeStyle.foreground
        section.attributedStringValue = NSAttributedString(string: "PROJECT", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .kern: 0.66, .foregroundColor: TreeStyle.muted])
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.chrome.sidebarBackground.setFill(); bounds.fill()
        title.textColor = TreeStyle.foreground
    }
}
