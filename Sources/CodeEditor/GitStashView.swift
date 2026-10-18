import AppKit

/// Content of the Stash popover: "Stash Changes…" plus the stash list with Apply / Pop / Drop.
final class GitStashView: NSView {
    var onStash: (() -> Void)?
    var onApply: ((GitStash) -> Void)?
    var onPop: ((GitStash) -> Void)?
    var onDrop: ((GitStash) -> Void)?
    private let stack = NSStackView()
    private static let width: CGFloat = 400

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: Self.width),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func button(_ title: String, _ sel: Selector, tag: Int = 0) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.font = .systemFont(ofSize: 11)
        b.tag = tag
        return b
    }

    private var stashes: [GitStash] = []

    func show(stashes: [GitStash]) {
        self.stashes = stashes
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let head = button("Stash Changes…", #selector(stashTapped))
        head.controlSize = .regular
        stack.addArrangedSubview(head)
        let title = NSTextField(labelWithString: stashes.isEmpty ? "No stashes" : "Stashes")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = .secondaryLabelColor
        stack.addArrangedSubview(title)
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .short
        for (i, s) in stashes.enumerated() {
            let msg = NSTextField(labelWithString: s.message)
            msg.font = .systemFont(ofSize: 12)
            msg.lineBreakMode = .byTruncatingTail
            msg.setContentCompressionResistancePriority(.init(100), for: .horizontal)
            let when = NSTextField(labelWithString: rel.localizedString(for: s.date, relativeTo: Date()))
            when.font = .systemFont(ofSize: 10)
            when.textColor = .secondaryLabelColor
            let text = NSStackView(views: [msg, when])
            text.orientation = .vertical
            text.alignment = .leading
            text.spacing = 0
            text.setContentHuggingPriority(.init(1), for: .horizontal)
            msg.setContentHuggingPriority(.init(1), for: .horizontal)
            let drop = button("Drop", #selector(dropTapped(_:)), tag: i)
            drop.contentTintColor = .systemRed
            let row = NSStackView(views: [text, button("Apply", #selector(applyTapped(_:)), tag: i),
                                          button("Pop", #selector(popTapped(_:)), tag: i), drop])
            row.orientation = .horizontal
            row.spacing = 4
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: Self.width - 24).isActive = true
        }
        layoutSubtreeIfNeeded()
        setFrameSize(NSSize(width: Self.width, height: stack.fittingSize.height))
    }

    @objc private func stashTapped() { onStash?() }
    @objc private func applyTapped(_ b: NSButton) { if b.tag < stashes.count { onApply?(stashes[b.tag]) } }
    @objc private func popTapped(_ b: NSButton) { if b.tag < stashes.count { onPop?(stashes[b.tag]) } }
    @objc private func dropTapped(_ b: NSButton) { if b.tag < stashes.count { onDrop?(stashes[b.tag]) } }
}
