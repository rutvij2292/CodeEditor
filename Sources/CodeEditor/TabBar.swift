import AppKit

/// Minimal tab strip + content host. Replaces NSTabView, which draws a bezel and insets we don't want.
final class TabHost: NSView {
    struct Entry { let id: String; var title: String; let view: NSView }
    private let strip = NSStackView()
    private let content = NSView()
    private(set) var entries: [Entry] = []
    private(set) var selectedID: String?
    var onSelect: ((String) -> Void)?
    var onClose: ((String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.background.cgColor
        strip.orientation = .horizontal
        strip.spacing = 2
        strip.alignment = .centerY
        strip.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        for v in [strip, content] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: topAnchor),
            strip.leadingAnchor.constraint(equalTo: leadingAnchor),
            strip.heightAnchor.constraint(equalToConstant: 28),
            strip.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: strip.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func add(id: String, title: String, view: NSView) {
        entries.append(Entry(id: id, title: title, view: view))
        select(id)
    }

    func setTitle(_ title: String, for id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].title = title
        rebuildStrip()
    }

    func remove(_ id: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries.remove(at: i)
        if selectedID == id {
            selectedID = nil
            if let next = entries.indices.contains(i) ? entries[i] : entries.last { select(next.id) } else {
                content.subviews.forEach { $0.removeFromSuperview() }
                rebuildStrip()
            }
        } else { rebuildStrip() }
    }

    func select(_ id: String) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        selectedID = id
        content.subviews.forEach { $0.removeFromSuperview() }
        entry.view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(entry.view)
        NSLayoutConstraint.activate([
            entry.view.topAnchor.constraint(equalTo: content.topAnchor),
            entry.view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            entry.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            entry.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        rebuildStrip()
        onSelect?(id)
    }

    private func rebuildStrip() {
        strip.arrangedSubviews.forEach { strip.removeArrangedSubview($0); $0.removeFromSuperview() }
        for e in entries {
            let selected = e.id == selectedID
            let label = NSButton(title: e.title, target: self, action: #selector(tabClicked(_:)))
            label.identifier = NSUserInterfaceItemIdentifier(e.id)
            label.isBordered = false
            label.attributedTitle = NSAttributedString(string: e.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .regular),
                .foregroundColor: selected ? NSColor.white : Theme.gutter,
            ])
            let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!,
                                 target: self, action: #selector(closeClicked(_:)))
            close.identifier = NSUserInterfaceItemIdentifier(e.id)
            close.isBordered = false
            close.imageScaling = .scaleProportionallyDown
            close.contentTintColor = Theme.gutter
            close.widthAnchor.constraint(equalToConstant: 12).isActive = true
            let pair = NSStackView(views: [label, close])
            pair.spacing = 2
            pair.wantsLayer = true
            pair.layer?.cornerRadius = 5
            pair.layer?.backgroundColor = selected ? NSColor.white.withAlphaComponent(0.1).cgColor : nil
            pair.edgeInsets = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 6)
            strip.addArrangedSubview(pair)
        }
    }

    @objc private func tabClicked(_ s: NSButton) { if let id = s.identifier?.rawValue { select(id) } }
    @objc private func closeClicked(_ s: NSButton) { if let id = s.identifier?.rawValue { onClose?(id) } }
}
