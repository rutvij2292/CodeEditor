import AppKit

/// Side pane of the SVG viewer: renders the live buffer with the system SVG renderer (no WebKit, nothing resident while the tab is in source mode).
/// Vector drawing stays crisp at every zoom; pinch / ⌘-scroll zooms, "Fit" and "100%" reset it, the background switches between checkerboard / light / dark.
final class SVGPreviewView: NSView {
    static let maxBytes = 5_000_000
    private let scroll = NSScrollView()
    private let canvas = SVGCanvasView()
    private let message = NSTextField(labelWithString: "")
    private let info = NSTextField(labelWithString: "")
    private let background = NSSegmentedControl(labels: ["Checker", "Light", "Dark"], trackingMode: .selectOne, target: nil, action: nil)
    private let fitButton = NSButton(title: "Fit", target: nil, action: nil)
    private let actualButton = NSButton(title: "100%", target: nil, action: nil)
    private var userZoomed = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        scroll.contentView = SVGCenteringClipView()
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.05; scroll.maxMagnification = 32
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        background.controlSize = .small; background.segmentStyle = .rounded; background.font = .systemFont(ofSize: 11)
        background.target = self; background.action = #selector(backgroundChanged)
        background.selectedSegment = SVGCanvasView.Background.allCases.firstIndex(of: Self.savedBackground) ?? 0
        for b in [fitButton, actualButton] {
            b.controlSize = .small; b.bezelStyle = .rounded; b.font = .systemFont(ofSize: 11); b.target = self
        }
        fitButton.action = #selector(fitTapped); actualButton.action = #selector(actualTapped)
        info.font = .systemFont(ofSize: 11); info.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: 13); message.textColor = .secondaryLabelColor
        message.alignment = .center; message.maximumNumberOfLines = 0; message.isHidden = true
        message.translatesAutoresizingMaskIntoConstraints = false
        for v in [background, fitButton, actualButton, info] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview(v) }
        addSubview(scroll); addSubview(bar); addSubview(message)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor), bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor), bar.heightAnchor.constraint(equalToConstant: 28),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.bottomAnchor.constraint(equalTo: bar.topAnchor),
            background.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8), background.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            fitButton.leadingAnchor.constraint(equalTo: background.trailingAnchor, constant: 8), fitButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            actualButton.leadingAnchor.constraint(equalTo: fitButton.trailingAnchor, constant: 4), actualButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            info.leadingAnchor.constraint(equalTo: actualButton.trailingAnchor, constant: 10), info.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            message.centerXAnchor.constraint(equalTo: centerXAnchor), message.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -40),
        ])
        canvas.background = Self.savedBackground
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    private static var savedBackground: SVGCanvasView.Background {
        SVGCanvasView.Background(rawValue: UserDefaults.standard.string(forKey: "svgPreviewBackground") ?? "") ?? .checker
    }

    /// The image currently shown (tests).
    var image: NSImage? { canvas.image }
    var magnification: CGFloat { scroll.magnification }

    func restyle() { layer?.backgroundColor = Theme.palette.background.cgColor; canvas.needsDisplay = true }

    func showMessage(_ text: String) {
        canvas.image = nil; canvas.needsDisplay = true
        message.stringValue = text; message.isHidden = false
        info.stringValue = ""
    }

    /// Renders `text`; invalid or unsupported SVG shows a message instead and keeps nothing stale.
    func show(svg text: String) {
        guard text.utf8.count <= Self.maxBytes else { showMessage("Preview is disabled for SVG files over 5 MB."); return }
        guard let data = text.data(using: .utf8), !data.isEmpty, let img = NSImage(data: data), img.size.width > 0, img.size.height > 0 else {
            showMessage(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Empty file" : "This SVG can’t be rendered (invalid or unsupported markup).")
            return
        }
        message.isHidden = true
        let first = canvas.image == nil
        canvas.image = img
        info.stringValue = "\(Int(img.size.width.rounded())) × \(Int(img.size.height.rounded()))"
        layoutSubtreeIfNeeded()
        if first || !userZoomed { fit() }
    }

    override func layout() {
        super.layout()
        if !userZoomed, canvas.image != nil { fit() }
    }

    private func fit() {
        guard let img = canvas.image else { return }
        let view = scroll.contentSize
        guard view.width > 1, view.height > 1 else { return }
        let pad: CGFloat = 32
        let s = min((view.width - pad) / img.size.width, (view.height - pad) / img.size.height)
        scroll.magnification = min(scroll.maxMagnification, max(scroll.minMagnification, s))
    }

    @objc private func fitTapped() { userZoomed = false; fit() }
    @objc private func actualTapped() { userZoomed = true; scroll.magnification = 1 }
    @objc private func backgroundChanged() {
        let b = SVGCanvasView.Background.allCases[max(0, background.selectedSegment)]
        canvas.background = b
        UserDefaults.standard.set(b.rawValue, forKey: "svgPreviewBackground")
    }
    override func magnify(with event: NSEvent) { userZoomed = true; super.magnify(with: event) }

    var textViewForFocus: NSView { scroll }
}

/// Keeps a small document centred in the clip view instead of pinned to the top-left.
private final class SVGCenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposed)
        guard let doc = documentView else { return r }
        if r.width > doc.frame.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if r.height > doc.frame.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}

final class SVGCanvasView: NSView {
    enum Background: String, CaseIterable { case checker, light, dark }
    var background = Background.checker { didSet { needsDisplay = true } }
    var image: NSImage? { didSet { frame.size = image?.size ?? NSSize(width: 10, height: 10); needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirty: NSRect) {
        guard let image else { return }
        let r = NSRect(origin: .zero, size: image.size)
        switch background {
        case .light: NSColor.white.setFill(); r.fill()
        case .dark: NSColor(white: 0.12, alpha: 1).setFill(); r.fill()
        case .checker:
            let cell: CGFloat = 8
            NSColor(white: 0.95, alpha: 1).setFill(); r.fill()
            NSColor(white: 0.82, alpha: 1).setFill()
            var y: CGFloat = 0, row = 0
            while y < r.height {
                var x: CGFloat = row % 2 == 0 ? 0 : cell
                while x < r.width { NSRect(x: x, y: y, width: min(cell, r.width - x), height: min(cell, r.height - y)).fill(); x += cell * 2 }
                y += cell; row += 1
            }
        }
        image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
