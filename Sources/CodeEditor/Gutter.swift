import AppKit

/// A change marker shown as a bar at the gutter's right edge. `lines` is a 1-based half-open line range.
/// For `.deleted` the range is empty (`n..<n`): lines were removed just before line `n` (`n` may be lineCount + 1).
struct GutterMarker: Equatable {
    enum Kind { case added, modified, deleted }
    var lines: Range<Int>
    var kind: Kind
}

/// Line numbers as a plain sibling view of the scroll view (NSRulerView overlays content on recent macOS).
final class GutterView: NSView {
    private weak var textView: NSTextView?
    private static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    private static let digitWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
    private static let barWidth: CGFloat = 3
    private static let rightPad: CGFloat = 10      // text right edge -> gutter right edge (room for the bars)
    private static let leftPad: CGFloat = 8
    override var isFlipped: Bool { true }

    /// Change markers (git etc.). Setting redraws.
    var markers: [GutterMarker] = [] { didSet { if markers != oldValue { needsDisplay = true } } }
    /// Click on a marker bar; the rect is the marker's extent in this view's coordinates.
    var onMarkerClick: ((GutterMarker, NSRect) -> Void)?
    /// Called with the preferred width when the number of digits changes.
    var onWidthChange: ((CGFloat) -> Void)?

    private(set) var preferredWidth: CGFloat = GutterView.width(forDigits: 3)
    private var lineCount = 1
    private var lineInfos: [(line: Int, y0: CGFloat, y1: CGFloat)] = []

    private static func width(forDigits d: Int) -> CGFloat {
        ceil(CGFloat(max(3, d)) * digitWidth) + leftPad + rightPad
    }

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(frame: .zero)
        scrollView.contentView.postsBoundsChangedNotifications = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(textChanged), name: NSText.didChangeNotification, object: textView)
        nc.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        nc.addObserver(self, selector: #selector(refresh), name: NSTextView.didChangeSelectionNotification, object: textView)
        // Layout finishes after init; the text view growing is our cue to redraw.
        textView.postsFrameChangedNotifications = true
        nc.addObserver(self, selector: #selector(refresh), name: NSView.frameDidChangeNotification, object: textView)
        nc.addObserver(self, selector: #selector(refresh), name: Theme.didChange, object: nil)
        updateLineCount()
        DispatchQueue.main.async { [weak self] in self?.updateLineCount(); self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func refresh() { needsDisplay = true }
    @objc private func textChanged() { updateLineCount(); needsDisplay = true }

    private func updateLineCount() {
        guard let s = textView?.string as NSString? else { return }
        var n = 1, pos = 0
        let len = s.length
        var buf = [unichar](repeating: 0, count: 8192)
        while pos < len {
            let chunk = min(buf.count, len - pos)
            s.getCharacters(&buf, range: NSRange(location: pos, length: chunk))
            for i in 0..<chunk where buf[i] == 10 { n += 1 }
            pos += chunk
        }
        lineCount = n
        let w = Self.width(forDigits: String(n).count)
        if w != preferredWidth {
            preferredWidth = w
            onWidthChange?(w)
        }
    }

    /// Y extent (view coordinates) of the given logical line from the last draw, if visible.
    private func extent(ofLine line: Int) -> (CGFloat, CGFloat)? {
        guard let first = lineInfos.first, line >= first.line, line - first.line < lineInfos.count else { return nil }
        let i = lineInfos[line - first.line]
        return (i.y0, i.y1)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
        lineInfos.removeAll(keepingCapacity: true)
        guard let tv = textView,
              let layout = tv.layoutManager, let container = tv.textContainer else { return }
        let text = tv.string as NSString
        let inset = tv.textContainerInset.height
        let visible = layout.glyphRange(forBoundingRect: tv.visibleRect, in: container)
        let firstChar = layout.characterIndexForGlyph(at: visible.location)

        var line = 1
        var i = 0
        while i < firstChar {
            let r = text.range(of: "\n", options: [], range: NSRange(location: i, length: firstChar - i))
            if r.location == NSNotFound { break }
            line += 1
            i = NSMaxRange(r)
        }

        let caret = min(tv.selectedRange().location, text.length)
        let plain: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: Theme.gutter]
        let active: [NSAttributedString.Key: Any] = [.font: Self.boldFont, .foregroundColor: Theme.foreground]
        let textRight = bounds.width - Self.rightPad
        func drawLabel(_ n: Int, y0: CGFloat, height: CGFloat, isActive: Bool) {
            let label = "\(n)" as NSString
            let attrs = isActive ? active : plain
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: textRight - size.width, y: y0 + (height - size.height) / 2), withAttributes: attrs)
        }

        var glyph = visible.location
        let endGlyph = NSMaxRange(visible)
        while glyph < endGlyph {
            let charIdx = layout.characterIndexForGlyph(at: glyph)
            let lineRange = text.lineRange(for: NSRange(location: charIdx, length: 0))
            let frag = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = convert(NSPoint(x: 0, y: frag.minY + inset), from: tv).y
            let lineGlyphs = layout.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            var y1 = y + frag.height
            if lineGlyphs.length > 1 {
                let lastFrag = layout.lineFragmentRect(forGlyphAt: NSMaxRange(lineGlyphs) - 1, effectiveRange: nil)
                y1 = convert(NSPoint(x: 0, y: lastFrag.maxY + inset), from: tv).y
            }
            var st = 0, en = 0, ce = 0
            text.getLineStart(&st, end: &en, contentsEnd: &ce, for: lineRange)
            let isActive = caret >= st && caret <= ce
            drawLabel(line, y0: y, height: frag.height, isActive: isActive)
            lineInfos.append((line, y, y1))
            glyph = max(NSMaxRange(lineGlyphs), glyph + 1)
            line += 1
        }
        // A trailing empty line (file ends with \n, or empty file) has no glyph; number it explicitly.
        if text.length == 0 || (text.character(at: text.length - 1) == 10 && endGlyph >= layout.numberOfGlyphs) {
            let extra = layout.extraLineFragmentRect
            if extra.height > 0 {
                let y = convert(NSPoint(x: 0, y: extra.minY + inset), from: tv).y
                drawLabel(line, y0: y, height: extra.height, isActive: caret == text.length)
                lineInfos.append((line, y, y + extra.height))
            }
        }
        drawMarkers()
    }

    // MARK: markers

    static func color(for kind: GutterMarker.Kind) -> NSColor {
        switch kind {
        case .added: return NSColor(srgbRed: 0.30, green: 0.70, blue: 0.35, alpha: 1)
        case .modified: return NSColor(srgbRed: 0.27, green: 0.53, blue: 0.96, alpha: 1)
        case .deleted: return NSColor(srgbRed: 0.90, green: 0.32, blue: 0.32, alpha: 1)
        }
    }

    private func wedgeY(before line: Int) -> CGFloat? {
        if let e = extent(ofLine: line) { return e.0 }
        if let e = extent(ofLine: line - 1) { return e.1 }
        return nil
    }

    private func drawMarkers() {
        guard !markers.isEmpty, let first = lineInfos.first?.line, let last = lineInfos.last?.line else { return }
        let x = bounds.width - Self.barWidth - 1
        for m in markers {
            Self.color(for: m.kind).setFill()
            if m.kind == .deleted {
                guard m.lines.lowerBound >= first, m.lines.lowerBound <= last + 1, let y = wedgeY(before: m.lines.lowerBound) else { continue }
                let p = NSBezierPath()
                p.move(to: NSPoint(x: bounds.width, y: y - 4))
                p.line(to: NSPoint(x: bounds.width - 5, y: y))
                p.line(to: NSPoint(x: bounds.width, y: y + 4))
                p.close()
                p.fill()
                continue
            }
            guard m.lines.upperBound > first, m.lines.lowerBound <= last else { continue }
            let a = max(m.lines.lowerBound, first), b = min(m.lines.upperBound - 1, last)
            guard let top = extent(ofLine: a)?.0, let bottom = extent(ofLine: b)?.1 else { continue }
            NSRect(x: x, y: top, width: Self.barWidth, height: max(1, bottom - top)).fill()
        }
    }

    /// Marker (and its rect in view coordinates) under a point, if any.
    func marker(at p: NSPoint) -> (GutterMarker, NSRect)? {
        for m in markers {
            if m.kind == .deleted {
                guard let y = wedgeY(before: m.lines.lowerBound), abs(p.y - y) <= 5 else { continue }
                return (m, NSRect(x: bounds.width - 8, y: y - 5, width: 8, height: 10))
            }
            guard let top = extent(ofLine: max(m.lines.lowerBound, lineInfos.first?.line ?? 0))?.0,
                  let bottom = extent(ofLine: min(m.lines.upperBound - 1, lineInfos.last?.line ?? 0))?.1,
                  p.y >= top, p.y < bottom else { continue }
            return (m, NSRect(x: bounds.width - Self.barWidth - 1, y: top, width: Self.barWidth, height: bottom - top))
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.x >= bounds.width - Self.rightPad, let (m, r) = marker(at: p) {
            onMarkerClick?(m, r)
            return
        }
        super.mouseDown(with: event)
    }

    /// Test hook: layout of the last draw (line number, y0, y1).
    var drawnLines: [(line: Int, y0: CGFloat, y1: CGFloat)] { lineInfos }
}

/// Gutter + scroll view side by side.
final class EditorContainer: NSView {
    let gutter: GutterView
    init(scrollView: NSScrollView, gutter: GutterView) {
        self.gutter = gutter
        super.init(frame: .zero)
        for v in [gutter, scrollView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        let width = gutter.widthAnchor.constraint(equalToConstant: gutter.preferredWidth)
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutter.topAnchor.constraint(equalTo: topAnchor),
            gutter.bottomAnchor.constraint(equalTo: bottomAnchor),
            width,
            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        gutter.onWidthChange = { w in width.constant = w }
    }
    required init?(coder: NSCoder) { fatalError() }
}
