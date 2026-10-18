import AppKit

/// A change marker shown as a bar at the gutter's right edge. `lines` is a 1-based half-open line range.
/// For `.deleted` the range is empty (`n..<n`): lines were removed just before line `n` (`n` may be lineCount + 1).
struct GutterMarker: Equatable {
    enum Kind { case added, modified, deleted }
    var lines: Range<Int>
    var kind: Kind
}

/// Line numbers, fold chevrons and change bars as a plain sibling view of the scroll view (NSRulerView overlays content on recent macOS).
final class GutterView: NSView {
    private weak var textView: NSTextView?
    private var codeView: CodeTextView? { textView as? CodeTextView }
    private static let barWidth: CGFloat = 3
    private static let barZone: CGFloat = 10       // right edge strip reserved for the change bars
    private static let chevronZone: CGFloat = 14   // fold chevron column left of the bars
    private static let leftPad: CGFloat = 8
    private static let iconZone: CGFloat = 14      // left edge strip for run/status icons
    private static let numberGap: CGFloat = 4
    override var isFlipped: Bool { true }
    static var narrow = AppEnv.value("CE_GUT_FULL") == nil
    static var labelCache = AppEnv.value("CE_GUT_NOCACHE") == nil

    /// Every invalidation goes through here (also feeds the bench's dirty-region model).
    private func invalidate(_ rect: NSRect? = nil) {
        guard let rect, Self.narrow else {
            if DirtyTracker.on { DirtyTracker.gutter = DirtyTracker.gutter.union(bounds) }
            needsDisplay = true
            return
        }
        if DirtyTracker.on { DirtyTracker.gutter = DirtyTracker.gutter.union(rect) }
        setNeedsDisplay(rect)
    }

    /// Full-width rect of the visible row that holds a logical line (nil if not on screen).
    private func rowRect(ofLine line: Int) -> NSRect? {
        guard let e = extent(ofLine: line) else { return nil }
        return NSRect(x: 0, y: e.0 - 1, width: bounds.width, height: e.1 - e.0 + 2)
    }

    /// Change markers (git etc.). Setting redraws.
    var markers: [GutterMarker] = [] { didSet { if markers != oldValue { markersChanged(from: oldValue) } } }
    /// Click on a marker bar; the rect is the marker's extent in this view's coordinates.
    var onMarkerClick: ((GutterMarker, NSRect) -> Void)?
    /// 1-based lines that get a ▶ run marker (HTTP client files) and the click handler.
    var playLines: Set<Int> = [] { didSet { if playLines != oldValue { invalidate() } } }
    var onPlayClick: ((Int) -> Void)?
    /// Run/status icons at the left edge, keyed by 1-based line (tests: TestGutter.swift). Setting redraws.
    var lineIcons: [Int: GutterLineIcon] = [:] { didSet { if lineIcons != oldValue { invalidate() } } }
    var onIconClick: ((Int) -> Void)?
    /// Called with the preferred width when the number of digits (or the font / prefs) changes.
    var onWidthChange: ((CGFloat) -> Void)?

    private(set) var preferredWidth: CGFloat = 40
    private var lineCount = 1
    /// One entry per visual row: the first logical line, the last one folded into the row, and its y extent.
    private struct Row { var line: Int; var endLine: Int; var y0: CGFloat; var y1: CGFloat; var firstHeight: CGFloat }
    private var rows: [Row] = []
    private var hoverY: CGFloat?
    private var trackingArea: NSTrackingArea?

    // Fonts follow the editor (Settings changes them live).
    private var fontKey = ""
    private var numberFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private var boldNumberFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    private var digitWidth: CGFloat = 7.2

    private var showsNumbers: Bool { Prefs.showLineNumbers }
    private var showsChevrons: Bool { Prefs.foldingEnabled }
    private var rightPad: CGFloat { Self.barZone + (showsChevrons ? Self.chevronZone : 0) }

    private func refreshFonts() {
        let base = textView?.font ?? Theme.font
        let key = "\(base.fontName)-\(base.pointSize)"
        guard key != fontKey else { return }
        fontKey = key
        labelCache.removeAll()
        numberFont = base.withSize(max(9, (base.pointSize - 1).rounded()))
        boldNumberFont = NSFontManager.shared.convert(numberFont, toHaveTrait: .boldFontMask)
        digitWidth = ("0" as NSString).size(withAttributes: [.font: numberFont]).width
    }

    /// Typeset line-number labels (CTLine + metrics), keyed by number and active state. Replaces per-frame
    /// NSString size/draw calls, which re-typeset every label on every redraw.
    private struct Label { let line: CTLine; let width: CGFloat; let ascent: CGFloat; let height: CGFloat }
    private var labelCache: [Int: Label] = [:]

    private func label(_ n: Int, active: Bool, attrs: [NSAttributedString.Key: Any], font: NSFont) -> Label {
        let key = n << 1 | (active ? 1 : 0)
        if let l = labelCache[key] { return l }
        if labelCache.count > 4096 { labelCache.removeAll(keepingCapacity: true) }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(n)", attributes: attrs))
        let l = Label(line: line, width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)), ascent: ceil(font.ascender),      // what NSString.draw / size(withAttributes:) use
                      height: ceil(font.ascender) - floor(font.descender) + ceil(font.leading))
        labelCache[key] = l
        return l
    }

    private func width(forDigits d: Int) -> CGFloat {
        refreshFonts()
        let numbers = showsNumbers ? ceil(CGFloat(max(3, d)) * digitWidth) + Self.leftPad + Self.numberGap : 4
        return numbers + rightPad
    }

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(frame: .zero)
        scrollView.contentView.postsBoundsChangedNotifications = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(textChanged), name: NSText.didChangeNotification, object: textView)
        nc.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        nc.addObserver(self, selector: #selector(selectionChanged), name: NSTextView.didChangeSelectionNotification, object: textView)
        // Layout finishes after init; the text view growing is our cue to redraw.
        textView.postsFrameChangedNotifications = true
        nc.addObserver(self, selector: #selector(refresh), name: NSView.frameDidChangeNotification, object: textView)
        nc.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
        nc.addObserver(self, selector: #selector(prefsChanged), name: Prefs.didChange, object: nil)
        nc.addObserver(self, selector: #selector(refresh), name: CodeTextView.foldsDidChangeNotification, object: textView)
        updateLineCount()
        preferredWidth = width(forDigits: String(lineCount).count)
        DispatchQueue.main.async { [weak self] in self?.updateLineCount(); self?.invalidate() }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func refresh() { invalidate() }
    @objc private func themeChanged() { labelCache.removeAll(); invalidate() }
    @objc private func prefsChanged() { fontKey = ""; updateLineCount(); invalidate() }

    /// Typing: numbers only change when the line count does; otherwise just the caret row (bold label). Layout shifts
    /// (wrap, fold, resize) arrive as frame / fold notifications, which redraw everything.
    @objc private func textChanged() {
        let before = lineCount
        updateLineCount()
        if lineCount != before { invalidate() } else { caretMoved() }
    }

    private var activeLine = 0
    @objc private func selectionChanged() { caretMoved() }
    private func caretMoved() {
        guard let tv = textView else { return }
        let caret = min(tv.selectedRange().location, tv.textStorage?.length ?? 0)
        let line = codeView?.folds.lineNumber(at: caret) ?? 0
        let old = activeLine
        activeLine = line
        guard Self.narrow, codeView != nil, !rows.isEmpty else { invalidate(); return }
        // Chevrons on the caret row depend on it too, so both rows are fully repainted.
        for l in (old == line ? [line] : [old, line]) { if let r = rowRect(ofLine: l) { invalidate(r) } }
    }

    private func markersChanged(from old: [GutterMarker]) {
        guard Self.narrow, !rows.isEmpty else { invalidate(); return }
        let removed = old.filter { !markers.contains($0) }, added = markers.filter { !old.contains($0) }
        for m in removed + added { if let r = markerRect(m) { invalidate(r) } }
    }

    /// Rect a marker occupies in the last drawn rows (nil when entirely off screen).
    private func markerRect(_ m: GutterMarker) -> NSRect? {
        guard let first = rows.first?.line, let last = rows.last?.endLine else { return nil }
        if m.kind == .deleted {
            guard m.lines.lowerBound >= first, m.lines.lowerBound <= last + 1, let y = wedgeY(before: m.lines.lowerBound) else { return nil }
            return NSRect(x: bounds.width - Self.barZone - 2, y: y - 6, width: Self.barZone + 2, height: 12)
        }
        guard m.lines.upperBound > first, m.lines.lowerBound <= last else { return nil }
        let a = max(m.lines.lowerBound, first), b = min(m.lines.upperBound - 1, last)
        guard let top = extent(ofLine: a)?.0, let bottom = extent(ofLine: b)?.1 else { return nil }
        return NSRect(x: bounds.width - Self.barZone - 2, y: top - 1, width: Self.barZone + 2, height: max(1, bottom - top) + 2)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseMoved(with event: NSEvent) {
        let old = hoverY
        hoverY = convert(event.locationInWindow, from: nil).y
        guard showsChevrons else { return }   // hover only affects chevrons
        guard old != nil else { invalidate(); return }   // hovering starts: chevrons of every row appear
        let oldLine = old.flatMap { rowLine(atY: $0) }, newLine = hoverY.flatMap { rowLine(atY: $0) }
        if oldLine == newLine { return }
        for l in [oldLine, newLine].compactMap({ $0 }) { if let r = rowRect(ofLine: l) { invalidate(r) } }
    }

    override func mouseExited(with event: NSEvent) { hoverY = nil; invalidate() }

    private func updateLineCount() {
        guard let tv = textView else { return }
        if let cv = codeView { lineCount = cv.folds.lineCount }
        else {
            let s = tv.string as NSString
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
        }
        let w = width(forDigits: String(lineCount).count)
        if w != preferredWidth {
            preferredWidth = w
            onWidthChange?(w)
        }
    }

    /// Y extent (view coordinates) of the given logical line from the last draw, if visible. A folded line maps to its row.
    private func extent(ofLine line: Int) -> (CGFloat, CGFloat)? {
        var lo = 0, hi = rows.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if line < rows[mid].line { hi = mid - 1 } else if line > rows[mid].endLine { lo = mid + 1 } else { return (rows[mid].y0, rows[mid].y1) }
        }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.palette.gutterBackground.setFill()
        dirtyRect.fill()
        rows.removeAll(keepingCapacity: true)
        guard let tv = textView,
              let layout = tv.layoutManager, let container = tv.textContainer else { return }
        refreshFonts()
        let text = (tv.textStorage?.mutableString ?? (tv.string as NSString)) as NSString   // no per-frame buffer copy
        let inset = tv.textContainerInset.height
        let fc = codeView?.folds
        let visible = layout.glyphRange(forBoundingRect: tv.visibleRect, in: container)
        var firstChar = text.length == 0 ? 0 : layout.characterIndexForGlyph(at: min(visible.location, max(0, layout.numberOfGlyphs - 1)))
        if let h = fc?.hiddenRange(containing: firstChar) { firstChar = h.start }     // the visible top is a folded row's tail

        // Number of the first visible line.
        var line = 1
        if let fc { line = fc.lineNumber(at: firstChar) } else {
            var i = 0
            while i < firstChar {
                let r = text.range(of: "\n", options: [], range: NSRange(location: i, length: firstChar - i))
                if r.location == NSNotFound { break }
                line += 1
                i = NSMaxRange(r)
            }
        }

        let caret = min(tv.selectedRange().location, text.length)
        let plain: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: Theme.palette.lineNumber]
        let active: [NSAttributedString.Key: Any] = [.font: boldNumberFont, .foregroundColor: Theme.palette.lineNumberActive]
        let textRight = bounds.width - rightPad
        let showNumbers = showsNumbers
        func drawLabel(_ n: Int, y0: CGFloat, height: CGFloat, isActive: Bool) {
            guard showNumbers, y0 + height >= dirtyRect.minY, y0 <= dirtyRect.maxY else { return }
            if Self.labelCache {
                let font = isActive ? boldNumberFont : numberFont
                let l = label(n, active: isActive, attrs: isActive ? active : plain, font: font)
                guard let ctx = NSGraphicsContext.current?.cgContext else { return }
                ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)   // flipped view
                let scale = ctx.ctm.a == 0 ? 1 : abs(ctx.ctm.a)
                let baseline = ((y0 + (height - l.height) / 2 + l.ascent) * scale).rounded(.down) / scale   // pixel-identical to NSString.draw
                ctx.textPosition = CGPoint(x: textRight - l.width, y: baseline)
                CTLineDraw(l.line, ctx)
                return
            }
            let label = "\(n)" as NSString
            let attrs = isActive ? active : plain
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: textRight - size.width, y: y0 + (height - size.height) / 2), withAttributes: attrs)
        }

        let endGlyph = NSMaxRange(visible)
        var pos = text.length == 0 ? 0 : text.lineRange(for: NSRange(location: min(firstChar, text.length - 1), length: 0)).location
        while text.length > 0, pos < text.length {
            let glyph = layout.glyphIndexForCharacter(at: pos)
            if glyph >= endGlyph, !rows.isEmpty { break }
            var st = 0, en = 0, ce = 0
            text.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: pos, length: 0))
            let frag = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = convert(NSPoint(x: 0, y: frag.minY + inset), from: tv).y
            var rowEnd = en, lastLineStart = st, endLine = line
            var isActive = caret >= st && caret <= ce
            if let fc {
                var curCE = ce
                while let h = fc.hiddenRange(startingAt: curCE), h.end > curCE {
                    var s2 = 0, e2 = 0, c2 = 0
                    text.getLineStart(&s2, end: &e2, contentsEnd: &c2, for: NSRange(location: min(h.end, text.length), length: 0))
                    rowEnd = e2; lastLineStart = s2; curCE = c2
                    if caret > h.start && caret <= c2 { isActive = true }
                }
                if rowEnd != en { endLine = fc.lineNumber(at: lastLineStart) }
            }
            var y1 = y + frag.height
            let lastGlyph = layout.glyphIndexForCharacter(at: max(st, rowEnd - 1))
            if lastGlyph > glyph {
                let lastFrag = layout.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
                y1 = max(y1, convert(NSPoint(x: 0, y: lastFrag.maxY + inset), from: tv).y)
            }
            drawLabel(line, y0: y, height: frag.height, isActive: isActive)
            rows.append(Row(line: line, endLine: endLine, y0: y, y1: y1, firstHeight: frag.height))
            pos = rowEnd
            line = endLine + 1
        }
        // A trailing empty line (file ends with \n, or empty file) has no glyph; number it explicitly.
        if text.length == 0 || (text.character(at: text.length - 1) == 10 && endGlyph >= layout.numberOfGlyphs) {
            let extra = layout.extraLineFragmentRect
            if extra.height > 0 {
                let y = convert(NSPoint(x: 0, y: extra.minY + inset), from: tv).y
                drawLabel(line, y0: y, height: extra.height, isActive: caret == text.length)
                rows.append(Row(line: line, endLine: line, y0: y, y1: y + extra.height, firstHeight: extra.height))
            }
        }
        drawChevrons(caret: caret)
        drawMarkers()
        drawPlayMarkers()
        drawLineIcons()
    }

    private func drawPlayMarkers() {
        guard !playLines.isEmpty else { return }
        NSColor(srgbRed: 0.30, green: 0.70, blue: 0.35, alpha: 1).setFill()
        for row in rows where playLines.contains(row.line) {
            let midY = row.y0 + row.firstHeight / 2
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 1.5, y: midY - 4)); p.line(to: NSPoint(x: 8, y: midY)); p.line(to: NSPoint(x: 1.5, y: midY + 4))
            p.close()
            p.fill()
        }
    }

    // MARK: fold chevrons

    private var chevronMidX: CGFloat { bounds.width - Self.barZone - Self.chevronZone / 2 }

    private func drawChevrons(caret: Int) {
        guard showsChevrons, let cv = codeView else { return }
        let caretLine = cv.folds.lineNumber(at: caret)
        let hovering = hoverY != nil
        let midX = chevronMidX
        for row in rows {
            guard let control = cv.foldControl(forLine: row.line) else { continue }
            let onCaretRow = caretLine >= row.line && caretLine <= row.endLine
            guard control.collapsed || onCaretRow || hovering else { continue }
            let midY = row.y0 + row.firstHeight / 2
            let isHot = hoverY.map { $0 >= row.y0 && $0 < row.y1 } ?? false
            let color = control.collapsed ? Theme.foreground.withAlphaComponent(isHot ? 0.95 : 0.7)
                                          : Theme.gutter.withAlphaComponent(isHot ? 1 : 0.8)
            color.setStroke()
            let p = NSBezierPath()
            p.lineWidth = 1.4
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            if control.collapsed {            // right-pointing
                p.move(to: NSPoint(x: midX - 2, y: midY - 3.5))
                p.line(to: NSPoint(x: midX + 2.5, y: midY))
                p.line(to: NSPoint(x: midX - 2, y: midY + 3.5))
            } else {                          // down-pointing
                p.move(to: NSPoint(x: midX - 3.5, y: midY - 2))
                p.line(to: NSPoint(x: midX, y: midY + 2.5))
                p.line(to: NSPoint(x: midX + 3.5, y: midY - 2))
            }
            p.stroke()
        }
    }

    /// The first logical line of the row under a y position of the last draw (test hook / click handling).
    func rowLine(atY y: CGFloat) -> Int? { rows.first { y >= $0.y0 && y < $0.y1 }?.line }

    // MARK: line icons

    private func drawLineIcons() {
        guard !lineIcons.isEmpty else { return }
        for row in rows {
            guard let icon = lineIcons[row.line] else { continue }
            let d: CGFloat = 9
            let box = NSRect(x: 3, y: row.y0 + (row.firstHeight - d) / 2, width: d, height: d)
            icon.draw(in: box)
        }
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
        guard !markers.isEmpty, let first = rows.first?.line, let last = rows.last?.endLine else { return }
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
            guard let top = extent(ofLine: max(m.lines.lowerBound, rows.first?.line ?? 0))?.0,
                  let bottom = extent(ofLine: min(m.lines.upperBound - 1, rows.last?.endLine ?? 0))?.1,
                  p.y >= top, p.y < bottom else { continue }
            return (m, NSRect(x: bounds.width - Self.barWidth - 1, y: top, width: Self.barWidth, height: bottom - top))
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if p.x < 11, !playLines.isEmpty, let line = rowLine(atY: p.y), playLines.contains(line) {
            onPlayClick?(line)
            return
        }
        if p.x < Self.iconZone, !lineIcons.isEmpty, let row = rows.first(where: { p.y >= $0.y0 && p.y < $0.y1 }), lineIcons[row.line] != nil {
            onIconClick?(row.line)
            return
        }
        if p.x >= bounds.width - Self.barZone, let (m, r) = marker(at: p) {
            onMarkerClick?(m, r)
            return
        }
        if showsChevrons, let cv = codeView, p.x >= bounds.width - Self.barZone - Self.chevronZone, p.x < bounds.width - Self.barZone + 2,
           let line = rowLine(atY: p.y), cv.foldControl(forLine: line) != nil {
            cv.toggleFold(atLine: line, recursive: event.modifierFlags.contains(.option))
            invalidate()
            return
        }
        super.mouseDown(with: event)
    }

    /// Test hook: layout of the last draw (first line of each row, y0, y1).
    var drawnLines: [(line: Int, y0: CGFloat, y1: CGFloat)] { rows.map { ($0.line, $0.y0, $0.y1) } }
    /// Test hook: rows including the last logical line folded into each.
    var drawnRows: [(line: Int, endLine: Int, y0: CGFloat, y1: CGFloat)] { rows.map { ($0.line, $0.endLine, $0.y0, $0.y1) } }
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


/// Status glyph in the gutter's left strip.
enum GutterLineIcon: Equatable {
    case run, running, passed, failed, skipped

    func draw(in r: NSRect) {
        let green = NSColor(calibratedRed: 0.25, green: 0.65, blue: 0.35, alpha: 1)
        let red = NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.25, alpha: 1)
        switch self {
        case .run, .running:
            (self == .run ? green : NSColor.systemOrange).setFill()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX + 1, y: r.minY)); p.line(to: NSPoint(x: r.maxX, y: r.midY)); p.line(to: NSPoint(x: r.minX + 1, y: r.maxY))
            p.close(); p.fill()
        case .passed, .failed, .skipped:
            let color = self == .passed ? green : (self == .failed ? red : NSColor.systemGray)
            color.setFill()
            NSBezierPath(ovalIn: r).fill()
            NSColor.white.setStroke()
            let m = NSBezierPath()
            m.lineWidth = 1.3
            m.lineCapStyle = .round
            switch self {
            case .passed:
                m.move(to: NSPoint(x: r.minX + 2.2, y: r.midY)); m.line(to: NSPoint(x: r.midX - 0.5, y: r.maxY - 2.6)); m.line(to: NSPoint(x: r.maxX - 2, y: r.minY + 2.4))
            case .failed:
                m.move(to: NSPoint(x: r.minX + 2.6, y: r.minY + 2.6)); m.line(to: NSPoint(x: r.maxX - 2.6, y: r.maxY - 2.6))
                m.move(to: NSPoint(x: r.maxX - 2.6, y: r.minY + 2.6)); m.line(to: NSPoint(x: r.minX + 2.6, y: r.maxY - 2.6))
            default:
                m.move(to: NSPoint(x: r.minX + 2.5, y: r.midY)); m.line(to: NSPoint(x: r.maxX - 2.5, y: r.midY))
            }
            m.stroke()
        }
    }
}
