import AppKit

/// Line numbers as a plain sibling view of the scroll view (NSRulerView overlays content on recent macOS).
final class GutterView: NSView {
    private weak var textView: NSTextView?
    private var attrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: Theme.gutter]
    }
    override var isFlipped: Bool { true }

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(frame: .zero)
        scrollView.contentView.postsBoundsChangedNotifications = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(refresh), name: NSText.didChangeNotification, object: textView)
        nc.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        // Layout finishes after init; the text view growing is our cue to redraw.
        textView.postsFrameChangedNotifications = true
        nc.addObserver(self, selector: #selector(refresh), name: NSView.frameDidChangeNotification, object: textView)
        nc.addObserver(self, selector: #selector(refresh), name: Theme.didChange, object: nil)
        DispatchQueue.main.async { [weak self] in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func refresh() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
        guard let tv = textView,
              let layout = tv.layoutManager, let container = tv.textContainer else { return }
        let text = tv.string as NSString
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

        var glyph = visible.location
        while glyph < NSMaxRange(visible) {
            let charIdx = layout.characterIndexForGlyph(at: glyph)
            let lineRange = text.lineRange(for: NSRange(location: charIdx, length: 0))
            let frag = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = convert(NSPoint(x: 0, y: frag.minY + tv.textContainerInset.height), from: tv).y
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: bounds.width - size.width - 8, y: y + (frag.height - size.height) / 2), withAttributes: attrs)
            glyph = NSMaxRange(layout.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil))
            line += 1
        }
        // A trailing empty line (file ends with \n) has no glyph; number it explicitly.
        if text.length > 0, text.character(at: text.length - 1) == 10, NSMaxRange(visible) >= layout.numberOfGlyphs {
            let extra = layout.extraLineFragmentRect
            let y = convert(NSPoint(x: 0, y: extra.minY + tv.textContainerInset.height), from: tv).y
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: bounds.width - size.width - 8, y: y + (extra.height - size.height) / 2), withAttributes: attrs)
        }
    }
}

/// Gutter + scroll view side by side.
final class EditorContainer: NSView {
    init(scrollView: NSScrollView, gutter: GutterView) {
        super.init(frame: .zero)
        for v in [gutter, scrollView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutter.topAnchor.constraint(equalTo: topAnchor),
            gutter.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutter.widthAnchor.constraint(equalToConstant: 48),
            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
