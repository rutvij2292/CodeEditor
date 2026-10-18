import AppKit
import SwiftTreeSitter

enum DiffColors {
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    private static var dark: Bool { Theme.isDark }
    static var added: NSColor { dark ? rgb(0.15, 0.28, 0.19) : rgb(0.86, 0.95, 0.86) }
    static var addedStrong: NSColor { dark ? rgb(0.20, 0.44, 0.27) : rgb(0.62, 0.85, 0.64) }
    static var removed: NSColor { dark ? rgb(0.32, 0.17, 0.19) : rgb(0.98, 0.87, 0.87) }
    static var removedStrong: NSColor { dark ? rgb(0.55, 0.24, 0.27) : rgb(0.95, 0.68, 0.68) }
    static var changed: NSColor { dark ? rgb(0.16, 0.23, 0.34) : rgb(0.87, 0.92, 0.99) }
    static var changedStrong: NSColor { dark ? rgb(0.22, 0.36, 0.57) : rgb(0.64, 0.78, 0.96) }
    static var conflict: NSColor { dark ? rgb(0.42, 0.24, 0.14) : rgb(1.0, 0.90, 0.76) }
    static var hatch: NSColor { dark ? NSColor(white: 1, alpha: 0.09) : NSColor(white: 0, alpha: 0.10) }
    static var chrome: NSColor { dark ? rgb(0.15, 0.16, 0.18) : rgb(0.93, 0.94, 0.95) }
    static var separator: NSColor { dark ? NSColor(white: 1, alpha: 0.12) : NSColor(white: 0, alpha: 0.15) }
    static var secondary: NSColor { dark ? rgb(0.60, 0.63, 0.68) : rgb(0.40, 0.42, 0.46) }
    static var selection: NSColor { NSColor.selectedContentBackgroundColor }
    static var flash: NSColor { dark ? NSColor(white: 1, alpha: 1) : NSColor(srgbRed: 1, green: 0.8, blue: 0.1, alpha: 1) }
}

struct DiffBand {
    var row: Int
    var count: Int
    var color: NSColor
    var hatch = false
}

/// Text view that paints per-row background bands (fixed line height, one text line per row)
/// without any per-row views or attributes, so 20k-line files stay cheap.
final class DiffTextView: NSTextView {
    var lineHeight: CGFloat = 16
    var bandSource: ((Range<Int>) -> [DiffBand])?
    var flash: (rows: Range<Int>, alpha: CGFloat)?
    var rowMenu: ((Int) -> NSMenu?)?

    func row(at event: NSEvent) -> Int {
        let p = convert(event.locationInWindow, from: nil)
        return Int(floor((p.y - DiffUI.inset) / lineHeight))
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let custom = rowMenu?(row(at: event)) else { return super.menu(for: event) }
        if let base = super.menu(for: event), !base.items.isEmpty {
            let items = base.items
            base.removeAllItems()
            custom.addItem(.separator())
            for i in items { custom.addItem(i) }
        }
        return custom
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        let inset = DiffUI.inset
        let first = max(0, Int(floor((rect.minY - inset) / lineHeight)))
        let last = max(first, Int(ceil((rect.maxY - inset) / lineHeight)))
        for band in bandSource?(first..<(last + 1)) ?? [] {
            let y = inset + CGFloat(band.row) * lineHeight
            let h = band.count == 0 ? 3 : CGFloat(band.count) * lineHeight
            let r = NSRect(x: rect.minX, y: band.count == 0 ? y - 1 : y, width: rect.width, height: h).intersection(rect)
            guard !r.isEmpty else { continue }
            band.color.setFill()
            r.fill()
            if band.hatch { drawHatch(in: r) }
        }
        if let f = flash, f.alpha > 0 {
            let y = inset + CGFloat(f.rows.lowerBound) * lineHeight
            let r = NSRect(x: rect.minX, y: y, width: rect.width, height: CGFloat(f.rows.count) * lineHeight).intersection(rect)
            DiffColors.flash.withAlphaComponent(0.35 * f.alpha).setFill()
            r.fill()
        }
    }

    private func drawHatch(in r: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        r.clip()
        let step: CGFloat = 7
        let path = NSBezierPath()
        var x = floor((r.minX - r.maxY) / step) * step
        while x < r.maxX {
            path.move(to: NSPoint(x: x, y: r.maxY + 1))
            path.line(to: NSPoint(x: x + (r.maxY - r.minY) + 2, y: r.minY - 1))
            x += step
        }
        DiffColors.hatch.setStroke()
        path.lineWidth = 1
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Right-aligned line numbers for a fixed-line-height pane, optionally with checkboxes,
/// row selection and mouse hooks.
final class DiffGutter: NSView {
    enum Phase { case down, drag, up }
    weak var scrollView: NSScrollView?
    var rowCount = 0
    var numberForRow: (Int) -> Int? = { $0 + 1 }
    /// nil = no checkbox on that row, otherwise 0 off / 1 on / 2 mixed.
    var checkState: ((Int) -> Int?)?
    var hunkCheckState: ((Int) -> Int?)?
    var isSelected: ((Int) -> Bool)?
    var onMouse: ((Int, CGFloat, NSEvent, Phase) -> Void)?
    var rowMenu: ((Int) -> NSMenu?)?
    var hasHunkColumn = false
    var hunkBoxX: CGFloat { 4 }
    var lineBoxX: CGFloat { hasHunkColumn ? 22 : 4 }
    static let boxSize: CGFloat = 12
    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        clipsToBounds = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: Theme.didChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func refresh() { needsDisplay = true }

    func row(at point: NSPoint) -> Int {
        Int(floor((point.y + (scrollView?.contentView.bounds.origin.y ?? 0) - DiffUI.inset) / DiffUI.lineHeight))
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
        guard let clip = scrollView?.contentView, rowCount > 0 else { return }
        let lh = DiffUI.lineHeight, off = clip.bounds.origin.y
        let first = max(0, Int(floor((off - DiffUI.inset) / lh)))
        let last = min(rowCount - 1, Int(ceil((off + bounds.height - DiffUI.inset) / lh)))
        guard first <= last else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: Theme.gutter,
        ]
        for row in first...last {
            let y = DiffUI.inset + CGFloat(row) * lh - off
            if isSelected?(row) == true {
                DiffColors.selection.withAlphaComponent(0.55).setFill()
                NSRect(x: 0, y: y, width: bounds.width, height: lh).fill()
            }
            if let h = hunkCheckState?(row) { drawBox(h, at: NSPoint(x: hunkBoxX, y: y + (lh - Self.boxSize) / 2), hunk: true) }
            if let c = checkState?(row) { drawBox(c, at: NSPoint(x: lineBoxX, y: y + (lh - Self.boxSize) / 2), hunk: false) }
            guard let n = numberForRow(row) else { continue }
            let label = "\(n)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: bounds.width - size.width - 8, y: y + (lh - size.height) / 2), withAttributes: attrs)
        }
    }

    private func drawBox(_ state: Int, at p: NSPoint, hunk: Bool) {
        let r = NSRect(origin: p, size: NSSize(width: Self.boxSize, height: Self.boxSize))
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: hunk ? 6 : 3, yRadius: hunk ? 6 : 3)
        if state == 0 {
            Theme.background.setFill(); path.fill()
            NSColor.secondaryLabelColor.setStroke()
        } else {
            NSColor.controlAccentColor.setFill(); path.fill()
            NSColor.controlAccentColor.setStroke()
        }
        path.lineWidth = 1
        path.stroke()
        guard state != 0 else { return }
        let mark = NSBezierPath()
        if state == 2 {
            mark.move(to: NSPoint(x: r.minX + 3, y: r.midY)); mark.line(to: NSPoint(x: r.maxX - 3, y: r.midY))
        } else {
            mark.move(to: NSPoint(x: r.minX + 3, y: r.midY)); mark.line(to: NSPoint(x: r.minX + 5.2, y: r.maxY - 3.2))
            mark.line(to: NSPoint(x: r.maxX - 2.8, y: r.minY + 3.2))
        }
        mark.lineWidth = 1.6
        NSColor.white.setStroke()
        mark.stroke()
    }

    private func forward(_ event: NSEvent, _ phase: Phase) {
        let p = convert(event.locationInWindow, from: nil)
        onMouse?(row(at: p), p.x, event, phase)
    }
    override func mouseDown(with event: NSEvent) { forward(event, .down) }
    override func mouseDragged(with event: NSEvent) { forward(event, .drag) }
    override func mouseUp(with event: NSEvent) { forward(event, .up) }
    override func menu(for event: NSEvent) -> NSMenu? { rowMenu?(row(at: convert(event.locationInWindow, from: nil))) }
}

/// Plain filled view whose colour is re-evaluated on every draw (follows light/dark changes).
final class DiffFillView: NSView {
    var color: () -> NSColor
    init(_ color: @escaping () -> NSColor) { self.color = color; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { color().setFill(); bounds.fill() }
}

final class DiffPane {
    let scroll = NSScrollView()
    let text: DiffTextView
    let gutter: DiffGutter
    let box = NSView()
    private let gutterWidth: NSLayoutConstraint
    private var baseGutterWidth: CGFloat = 44
    var gutterExtra: CGFloat = 0 { didSet { gutterWidth.constant = baseGutterWidth + gutterExtra } }
    /// Filler rows are expressed as paragraph spacing before a line (text stays the real file content).
    private(set) var gaps: [Int: Int] = [:]
    private(set) var topGap = 0

    init(editable: Bool) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = false
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        text = DiffTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        text.lineHeight = DiffUI.lineHeight
        text.isEditable = editable
        text.isSelectable = true
        text.isRichText = false
        text.allowsUndo = editable
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.textContainerInset = NSSize(width: 4, height: DiffUI.inset)
        text.isHorizontallyResizable = true
        text.isVerticallyResizable = true
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.defaultParagraphStyle = DiffUI.paragraph
        text.typingAttributes = DiffUI.baseAttributes
        text.backgroundColor = Theme.background
        text.insertionPointColor = Theme.foreground
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.background
        gutter = DiffGutter(scrollView: scroll)
        for v in [gutter, scroll] { v.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(v) }
        gutterWidth = gutter.widthAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: box.leadingAnchor), gutter.topAnchor.constraint(equalTo: box.topAnchor),
            gutter.bottomAnchor.constraint(equalTo: box.bottomAnchor), gutterWidth,
            scroll.leadingAnchor.constraint(equalTo: gutter.trailingAnchor), scroll.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: box.topAnchor), scroll.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
    }

    func setText(_ s: String, maxLineNumber: Int) {
        text.string = s
        restyle()
        baseGutterWidth = CGFloat(max(3, String(maxLineNumber).count)) * 7 + 18
        gutterWidth.constant = baseGutterWidth + gutterExtra
    }

    func setGutterRows(_ rows: Int, maxLineNumber: Int) {
        gutter.rowCount = rows
        baseGutterWidth = CGFloat(max(3, String(maxLineNumber).count)) * 7 + 18
        gutterWidth.constant = baseGutterWidth + gutterExtra
    }

    func setGaps(_ gaps: [Int: Int], top: Int) {
        self.gaps = gaps
        topGap = top
        restyle()
    }

    func restyle() {
        guard let storage = text.textStorage else { return }
        storage.beginEditing()
        storage.setAttributes(DiffUI.baseAttributes, range: NSRange(location: 0, length: storage.length))
        if !gaps.isEmpty {
            let starts = DiffUI.lineStarts(storage.string as NSString)
            for (line, gap) in gaps where line > 0 && line < starts.count {
                let end = line + 1 < starts.count ? starts[line + 1] : storage.length
                let p = NSMutableParagraphStyle()
                p.minimumLineHeight = DiffUI.lineHeight
                p.maximumLineHeight = DiffUI.lineHeight
                p.paragraphSpacingBefore = CGFloat(gap) * DiffUI.lineHeight
                storage.addAttribute(.paragraphStyle, value: p, range: NSRange(location: starts[line], length: end - starts[line]))
            }
        }
        storage.endEditing()
        let inset = NSSize(width: 4, height: DiffUI.inset + CGFloat(topGap) * DiffUI.lineHeight)
        if text.textContainerInset != inset { text.textContainerInset = inset }
        text.typingAttributes = DiffUI.baseAttributes
        text.backgroundColor = Theme.background
        text.insertionPointColor = Theme.foreground
        scroll.backgroundColor = Theme.background
        text.needsDisplay = true
    }

    /// Keeps document size >= content so horizontal scrolling is identical across panes.
    func fit(rows: Int, columns: Int) {
        let clip = scroll.contentView.bounds.size
        let w = max(clip.width, CGFloat(columns) * DiffUI.charWidth + 40)
        let h = max(clip.height, CGFloat(rows) * DiffUI.lineHeight + 2 * DiffUI.inset)
        text.minSize = NSSize(width: w, height: h)
        if abs(text.frame.width - w) > 0.5 || text.frame.height < h { text.setFrameSize(NSSize(width: w, height: max(h, text.frame.height))) }
    }
}

enum DiffUI {
    static let inset: CGFloat = 6
    static let lineHeight: CGFloat = ceil(NSLayoutManager().defaultLineHeight(for: Theme.font))
    static let charWidth: CGFloat = Theme.font.maximumAdvancement.width

    static var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = lineHeight
        p.maximumLineHeight = lineHeight
        return p
    }
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: Theme.font, .foregroundColor: Theme.foreground, .paragraphStyle: paragraph]
    }

    static func lineStarts(_ s: NSString) -> [Int] {
        var out = [0]
        for i in 0..<s.length where s.character(at: i) == 10 { out.append(i + 1) }
        if out.last == s.length, s.length > 0 { out.removeLast() }
        return out
    }

    static func columns(_ s: String) -> Int { s.utf16.count + 3 * s.utf8.reduce(0) { $0 + ($1 == 9 ? 1 : 0) } }

    static func label(_ size: CGFloat = 12, weight: NSFont.Weight = .medium) -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: size, weight: weight)
        l.lineBreakMode = .byTruncatingMiddle
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    static func scroll(_ clip: NSClipView, x: CGFloat, y: CGFloat) {
        let doc = clip.documentView?.frame ?? .zero
        let maxX = max(0, doc.width - clip.bounds.width), maxY = max(0, doc.height - clip.bounds.height)
        clip.setBoundsOrigin(NSPoint(x: min(max(0, x), maxX), y: min(max(0, y), maxY)))
        (clip.superview as? NSScrollView)?.reflectScrolledClipView(clip)
    }
}

/// Own copy of Highlighter's logic so it can colour any text view (diff panes) without touching it.
final class DiffHighlighter {
    private let parser = Parser()
    private let query: Query?
    private weak var textView: NSTextView?

    init?(textView: NSTextView, extension ext: String) {
        guard let config = Languages.configuration(forExtension: ext) else { return nil }
        self.textView = textView
        query = config.queries[.highlights]
        do { try parser.setLanguage(config.language) } catch { return nil }
        reparse()
    }

    func reparse() {
        guard let textView, let layout = textView.layoutManager, let query,
              let tree = parser.parse(textView.string) else { return }
        let text = textView.string
        let full = NSRange(location: 0, length: (text as NSString).length)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        let context = SwiftTreeSitter.Predicate.Context(string: text)
        for named in query.execute(in: tree).resolve(with: context).highlights() {
            guard let color = Theme.color(for: named.name), NSMaxRange(named.range) <= full.length else { continue }
            layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: named.range)
        }
    }
}
