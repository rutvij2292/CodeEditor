import AppKit

/// Review window for an `openDiff` request: the existing side-by-side diff (proposed side editable) with Accept / Reject.
/// Closing the window without choosing rejects (the safe reading of "nothing was approved").
final class ClaudeDiffWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let view = SideBySideDiffView(frame: NSRect(x: 0, y: 0, width: 1100, height: 640))
    private var onOutcome: ((ClaudeBridge.DiffOutcome) -> Void)?
    private var decided = false

    init(diff: ClaudeBridge.PendingDiff, onOutcome: @escaping (ClaudeBridge.DiffOutcome) -> Void) {
        self.onOutcome = onOutcome
        let barHeight: CGFloat = 44
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 640 + barHeight),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        DialogMemory.remember(window, as: "ClaudeDiff")
        window.title = "Claude proposes changes \u{2013} \(diff.url.lastPathComponent)"
        window.delegate = self
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 640 + barHeight))
        view.frame = NSRect(x: 0, y: barHeight, width: content.bounds.width, height: content.bounds.height - barHeight)
        view.autoresizingMask = [.width, .height]
        view.isNewSideEditable = true
        view.show(old: diff.original, new: diff.proposed, oldTitle: "Current", newTitle: "Claude's proposal (editable)",
                  fileExtension: diff.url.pathExtension)
        let accept = NSButton(title: "Accept", target: self, action: #selector(acceptTapped))
        accept.keyEquivalent = "\r"
        accept.bezelStyle = .rounded
        let reject = NSButton(title: "Reject", target: self, action: #selector(rejectTapped))
        reject.keyEquivalent = "\u{1b}"
        reject.bezelStyle = .rounded
        let hint = NSTextField(labelWithString: diff.url.path)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingMiddle
        hint.setContentHuggingPriority(.init(1), for: .horizontal)
        hint.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let bar = NSStackView(views: [hint, reject, accept])
        bar.spacing = 10
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        bar.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: barHeight)
        bar.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(view)
        content.addSubview(bar)
        window.contentView = content
        window.center()
    }

    func show() {
        if NSApp.isActive { window.makeKeyAndOrderFront(nil) } else { window.orderFront(nil) }
    }

    func close() { window.close() }

    /// The bridge already settled the request (CLI closed the tab, connection dropped): do not report again.
    func detach() { decided = true; onOutcome = nil; window.delegate = nil }

    @objc private func acceptTapped() { accept() }
    @objc private func rejectTapped() { reject() }
    func accept() { decide(.accept(view.newText)) }
    func reject() { decide(.reject) }
    /// Text currently on the proposal side (what Accept would save).
    var proposalText: String { view.newText }

    private func decide(_ outcome: ClaudeBridge.DiffOutcome) {
        guard !decided else { return }
        decided = true
        let cb = onOutcome
        onOutcome = nil
        window.delegate = nil
        window.close()
        cb?(outcome)
    }

    func windowWillClose(_ notification: Notification) { decide(.reject) }
}
