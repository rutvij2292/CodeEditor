import AppKit
import UniformTypeIdentifiers

/// Draws one bitmap / PDF page centred at a scale; small images are enlarged with hard pixel edges (icons, favicons).
final class ImageCanvas: NSView {
    var rep: NSImageRep? { didSet { needsDisplay = true } }
    var scale: CGFloat = 1 { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let rep else { return }
        let w = CGFloat(rep.size.width) * scale, h = CGFloat(rep.size.height) * scale
        let r = NSRect(x: max(0, (bounds.width - w) / 2).rounded(), y: max(0, (bounds.height - h) / 2).rounded(), width: w, height: h)
        NSGraphicsContext.current?.imageInterpolation = scale >= 2 ? .none : .high
        rep.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5)).stroke()
    }
}

/// Read-only viewer tab for images (anything macOS can decode: png, jpg, gif, webp, bmp, ico, icns, tiff, heic, avif, ...) and
/// PDFs: checkerboard backdrop, Fit / Actual Size, a size picker for multi-size icons, page buttons for PDFs.
final class ImageViewerView: NSView {
    /// SVG stays a text file (it is code you edit); everything else the system reports as an image, plus PDF, opens here.
    static func canView(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty || ext == "svg" || ext == "svgz" { return false }
        if ext == "pdf" { return true }
        guard let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image)
    }

    private let scroll = NSScrollView()
    private let canvas = ImageCanvas()
    private let info = NSTextField(labelWithString: "")
    private let zoomButton = NSButton(title: "Actual Size", target: nil, action: nil)
    private let sizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let prevPage = NSButton(), nextPage = NSButton()
    private let pageLabel = NSTextField(labelWithString: "")
    private var reps: [NSImageRep] = []
    private var current = 0
    private var fit = true
    private let url: URL
    private let fileBytes: Int
    private var pdf: NSPDFImageRep? { reps.first as? NSPDFImageRep }

    // Test hooks.
    var sizeCount: Int { reps.count }
    var shownPixelWidth: Int { reps.indices.contains(current) ? reps[current].pixelsWide : 0 }
    var displayScale: CGFloat { canvas.scale }
    var infoText: String { info.stringValue }

    init(url: URL) {
        self.url = url
        fileBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        super.init(frame: .zero)
        loadReps()
        build()
        select(0)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func loadReps() {
        guard let data = try? Data(contentsOf: url) else { return }
        if url.pathExtension.lowercased() == "pdf" {
            if let r = NSPDFImageRep(data: data) { reps = [r] }
            return
        }
        // Multi-size containers (ico, icns, tiff) carry several bitmaps: keep the largest of each distinct size.
        let all = NSBitmapImageRep.imageReps(with: data)
        var best: [Int: NSImageRep] = [:]
        for r in all { if best[r.pixelsWide] == nil { best[r.pixelsWide] = r } }
        reps = best.keys.sorted(by: >).compactMap { best[$0] }
        if reps.isEmpty, let img = NSImage(data: data), let r = img.representations.first { reps = [r] }
    }

    private func build() {
        wantsLayer = true
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        info.translatesAutoresizingMaskIntoConstraints = false
        info.font = .systemFont(ofSize: 11); info.textColor = .secondaryLabelColor
        info.lineBreakMode = .byTruncatingTail
        zoomButton.bezelStyle = .recessed; zoomButton.font = .systemFont(ofSize: 11)
        zoomButton.target = self; zoomButton.action = #selector(toggleZoom)
        sizePopup.controlSize = .small; sizePopup.font = .systemFont(ofSize: 11)
        sizePopup.target = self; sizePopup.action = #selector(sizePicked)
        sizePopup.isHidden = reps.count < 2 || pdf != nil
        for r in reps { sizePopup.addItem(withTitle: "\(r.pixelsWide) × \(r.pixelsHigh)") }
        for (b, symbol, sel) in [(prevPage, "chevron.left", #selector(prevPageTapped)), (nextPage, "chevron.right", #selector(nextPageTapped))] {
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            b.bezelStyle = .recessed; b.isBordered = false; b.target = self; b.action = sel
            b.isHidden = (pdf?.pageCount ?? 0) < 2
        }
        pageLabel.font = .systemFont(ofSize: 11); pageLabel.textColor = .secondaryLabelColor
        pageLabel.isHidden = (pdf?.pageCount ?? 0) < 2
        let right = NSStackView(views: [prevPage, pageLabel, nextPage, sizePopup, zoomButton])
        right.spacing = 6
        for v in [right] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview(v) }
        bar.addSubview(info)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = canvas
        addSubview(scroll); addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor), bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 28),
            info.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12), info.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            info.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8),
            right.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10), right.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        // Window floor: nothing in here may demand width (see ProjectWindow / StatusBar).
        info.setContentCompressionResistancePriority(.init(250), for: .horizontal)
    }

    private func select(_ i: Int) {
        guard reps.indices.contains(i) else {
            info.stringValue = "Cannot decode “\(url.lastPathComponent)”."
            return
        }
        current = i
        canvas.rep = reps[i]
        sizePopup.selectItem(at: i)
        let r = reps[i]
        var text = "\(url.lastPathComponent)  ·  \(r.pixelsWide) × \(r.pixelsHigh) px  ·  " + ByteCountFormatter.string(fromByteCount: Int64(fileBytes), countStyle: .file)
        if reps.count > 1, pdf == nil { text += "  ·  \(reps.count) sizes" }
        if let p = pdf { text += "  ·  \(p.pageCount) page\(p.pageCount == 1 ? "" : "s")"; pageLabel.stringValue = "\(p.currentPage + 1) / \(p.pageCount)" }
        info.stringValue = text
        needsLayout = true
    }

    @objc private func sizePicked() { select(sizePopup.indexOfSelectedItem) }
    @objc private func toggleZoom() {
        fit.toggle()
        zoomButton.title = fit ? "Actual Size" : "Fit to Window"
        needsLayout = true
    }
    @objc private func prevPageTapped() { turnPage(-1) }
    @objc private func nextPageTapped() { turnPage(1) }
    private func turnPage(_ d: Int) {
        guard let p = pdf else { return }
        p.currentPage = min(max(0, p.currentPage + d), p.pageCount - 1)
        select(0)
        canvas.needsDisplay = true
    }

    override func layout() {
        super.layout()
        guard reps.indices.contains(current) else { return }
        let avail = scroll.contentSize
        let size = reps[current].size
        guard size.width > 0, size.height > 0 else { return }
        // Fit scales down to the window and up (to 16x) for tiny images such as favicons; Actual Size is 1:1.
        let fitScale = min((avail.width - 40) / size.width, (avail.height - 40) / size.height)
        canvas.scale = fit ? max(0.05, min(fitScale, 16)) : 1
        let content = NSSize(width: size.width * canvas.scale + 40, height: size.height * canvas.scale + 40)
        canvas.frame = NSRect(x: 0, y: 0, width: max(content.width, avail.width), height: max(content.height, avail.height))
    }

    override func updateLayer() { layer?.backgroundColor = Self.checker().cgColor }
    override var wantsUpdateLayer: Bool { true }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    private static func checker() -> NSColor {
        let dark = Theme.isDark
        let a: NSColor = dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.97, alpha: 1)
        let b: NSColor = dark ? NSColor(white: 0.21, alpha: 1) : NSColor(white: 0.92, alpha: 1)
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            a.setFill(); NSRect(x: 0, y: 0, width: 16, height: 16).fill()
            b.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill(); NSRect(x: 8, y: 8, width: 8, height: 8).fill()
            return true
        }
        return NSColor(patternImage: img)
    }
}
