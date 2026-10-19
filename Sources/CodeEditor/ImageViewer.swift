import AppKit

/// Read-only viewer tab for raster images (png, jpg, gif, webp, ...): checkerboard backdrop, fit-to-window or 100%,
/// with a one-line info bar (pixel size, file size).
final class ImageViewerView: NSView {
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "ico", "tif", "tiff", "heic", "icns"]

    static func canView(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    private let scroll = NSScrollView()
    private let imageView = NSImageView()
    private let info = NSTextField(labelWithString: "")
    private let zoomButton = NSButton(title: "Actual Size", target: nil, action: nil)
    private let image: NSImage?
    private var fit = true

    init(url: URL) {
        image = NSImage(contentsOf: url)
        super.init(frame: .zero)
        let bar = NSView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        info.translatesAutoresizingMaskIntoConstraints = false
        info.font = .systemFont(ofSize: 11)
        info.textColor = .secondaryLabelColor
        zoomButton.translatesAutoresizingMaskIntoConstraints = false
        zoomButton.bezelStyle = .recessed
        zoomButton.font = .systemFont(ofSize: 11)
        zoomButton.target = self; zoomButton.action = #selector(toggleZoom)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = imageView
        imageView.image = image
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignCenter
        wantsLayer = true
        addSubview(scroll); addSubview(bar); bar.addSubview(info); bar.addSubview(zoomButton)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor), bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 28),
            info.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12), info.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            zoomButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10), zoomButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if let rep = image?.representations.first, rep.pixelsWide > 0 {
            info.stringValue = "\(url.lastPathComponent)  ·  \(rep.pixelsWide) × \(rep.pixelsHigh) px  ·  "
                + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        } else {
            info.stringValue = image == nil ? "Cannot decode “\(url.lastPathComponent)”." : url.lastPathComponent
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func toggleZoom() {
        fit.toggle()
        zoomButton.title = fit ? "Actual Size" : "Fit to Window"
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let image else { return }
        let avail = scroll.contentSize
        var size = image.size
        if fit, size.width > 0, size.height > 0 {
            let s = min(1, (avail.width - 24) / size.width, (avail.height - 24) / size.height)
            size = NSSize(width: size.width * s, height: size.height * s)
        }
        imageView.frame = NSRect(x: 0, y: 0, width: max(size.width, avail.width), height: max(size.height, avail.height))
        imageView.imageScaling = fit ? .scaleProportionallyDown : .scaleNone
    }

    override func updateLayer() {
        layer?.backgroundColor = Self.checker().cgColor
    }
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
