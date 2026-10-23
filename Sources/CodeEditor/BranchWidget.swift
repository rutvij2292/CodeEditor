import AppKit

/// Always-visible branch control in the window's title bar: "⎇ branch ▾  ↑2 ↓1 •" (dirty dot). Click opens the branch popup.
final class BranchWidget: NSView {
    var onClick: (() -> Void)?
    var onResize: (() -> Void)?

    private(set) var branch = ""
    private(set) var ahead = 0
    private(set) var behind = 0
    private(set) var dirty = false
    private(set) var detached = false
    private(set) var busyText: String?
    private var hovering = false
    private var pressed = false
    private var tracking: NSTrackingArea?

    static let height: CGFloat = 22

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: Self.height))
        toolTip = KeymapStore.retip("Branches (⌘⌥B)")
        setAccessibilityRole(.button)
        setAccessibilityLabel("Git branch")
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func update(branch: String, detached: Bool, ahead: Int, behind: Int, dirty: Bool) {
        self.branch = branch; self.detached = detached; self.ahead = ahead; self.behind = behind; self.dirty = dirty
        refresh()
    }

    func setBusy(_ text: String?) { busyText = text; refresh() }

    private func refresh() {
        let w = ceil(contentWidth()) + 20
        setFrameSize(NSSize(width: min(max(w, 70), 420), height: Self.height))
        onResize?()
        needsDisplay = true
        toolTip = KeymapStore.retip("Branch \(branch) — click for branches (⌘⌥B)")
        setAccessibilityValue(branch)
    }

    private var nameText: String { detached ? "HEAD " + branch : branch }
    private var arrowText: String {
        var parts: [String] = []
        if ahead > 0 { parts.append("↑\(ahead)") }
        if behind > 0 { parts.append("↓\(behind)") }
        return parts.joined(separator: " ")
    }

    private let nameFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private let smallFont = NSFont.systemFont(ofSize: 11)

    private func contentWidth() -> CGFloat {
        var w: CGFloat = 14 + 4                                  // ⎇ glyph
        w += (busyText ?? nameText as String).size(withAttributes: [.font: nameFont]).width + 4
        w += 10                                                  // ▾
        if busyText == nil {
            if !arrowText.isEmpty { w += 6 + arrowText.size(withAttributes: [.font: smallFont]).width }
            if dirty { w += 6 + 6 }
        }
        return w
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t); tracking = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { pressed = true; needsDisplay = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false; needsDisplay = true
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let fill = NSColor.labelColor.withAlphaComponent(pressed ? 0.16 : (hovering ? 0.10 : 0.05))
        fill.setFill()
        NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        let border = NSBezierPath(roundedRect: r.insetBy(dx: 0.25, dy: 0.25), xRadius: 6, yRadius: 6)
        border.lineWidth = 0.5
        border.stroke()

        var x: CGFloat = 8
        if let g = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold)) {
            let t = g.tinted(.secondaryLabelColor)
            let sz = t.size
            t.draw(in: NSRect(x: x, y: (bounds.height - sz.height) / 2, width: sz.width, height: sz.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        x += 18
        let text = (busyText ?? nameText) as NSString
        let nameColor: NSColor = busyText != nil ? .secondaryLabelColor : .labelColor
        let maxName = bounds.width - x - 8 - 10 - (busyText == nil && !arrowText.isEmpty ? 40 : 0) - (dirty ? 12 : 0)
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: nameColor, .paragraphStyle: para]
        let ts = text.size(withAttributes: attrs)
        let tw = min(ts.width, max(30, maxName))
        text.draw(in: NSRect(x: x, y: (bounds.height - ts.height) / 2, width: tw, height: ts.height), withAttributes: attrs)
        x += tw + 4
        if let chev = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 8, weight: .bold)) {
            let tinted = chev.tinted(.secondaryLabelColor)
            tinted.draw(in: NSRect(x: x, y: (bounds.height - 8) / 2, width: 9, height: 8), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        x += 14
        guard busyText == nil else { return }
        if !arrowText.isEmpty {
            let a: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: NSColor.secondaryLabelColor]
            let s = arrowText as NSString, sz = s.size(withAttributes: a)
            s.draw(at: NSPoint(x: x, y: (bounds.height - sz.height) / 2), withAttributes: a)
            x += sz.width + 6
        }
        if dirty {
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: (bounds.height - 6) / 2, width: 6, height: 6)).fill()
        }
    }

    // Snapshot support: render over an opaque title-bar-like backdrop.
    func snapshot(to path: String, dark: Bool) {
        let pad: CGFloat = 12
        let size = NSSize(width: frame.width + pad * 2, height: 38)
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.wantsLayer = true
        host.layer?.backgroundColor = (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.92, alpha: 1)).cgColor
        let saved = (superview, frame)
        removeFromSuperview()
        host.addSubview(self)
        setFrameOrigin(NSPoint(x: pad, y: (size.height - frame.height) / 2))
        appearance = host.appearance
        Verification.render(host, to: path)
        appearance = nil
        removeFromSuperview()
        saved.0?.addSubview(self)
        frame = saved.1
    }
}

private extension NSImage {
    func tinted(_ color: NSColor) -> NSImage {
        let resolved = NSColor(cgColor: color.cgColor) ?? color      // resolve dynamic colours in the drawing appearance
        let img = copy() as! NSImage
        img.lockFocus()
        resolved.set()
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

/// Non-modal message anchored under the branch widget: errors, progress results, and confirmations with buttons
/// (Smart Checkout / Force / Cancel, Delete…). Replaces modal alerts for the branch workflow.
final class BranchNotice: NSObject {
    struct Button {
        enum Style { case normal, primary, destructive }
        var title: String
        var style: Style = .normal
        var handler: () -> Void
    }

    nonisolated(unsafe) private static var popover: NSPopover?
    /// Last notice content view (headless verification renders it; popovers do not appear without a visible window).
    nonisolated(unsafe) private(set) static var lastView: NSView?
    nonisolated(unsafe) private(set) static var lastTitle = ""
    nonisolated(unsafe) private(set) static var lastButtons: [String] = []
    nonisolated(unsafe) private static var lastHandlers: [() -> Void] = []

    static func dismiss() { popover?.performClose(nil); popover = nil }

    /// Invokes the button with `title` of the last shown notice (test hook).
    static func press(_ title: String) {
        guard let i = lastButtons.firstIndex(of: title), i < lastHandlers.count else { return }
        let h = lastHandlers[i]
        dismiss()
        h()
    }

    static func show(title: String, message: String = "", files: [String] = [], buttons: [Button] = [], over anchor: NSView?) {
        dismiss()
        let width: CGFloat = 420
        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        var views: [NSView] = [titleLabel]
        if !message.isEmpty {
            let m = NSTextField(wrappingLabelWithString: message)
            m.font = .systemFont(ofSize: 12); m.textColor = .secondaryLabelColor
            m.maximumNumberOfLines = 8
            views.append(m)
        }
        if !files.isEmpty {
            let shown = files.prefix(8).joined(separator: "\n") + (files.count > 8 ? "\n… and \(files.count - 8) more" : "")
            let f = NSTextField(wrappingLabelWithString: shown)
            f.font = .monospacedSystemFont(ofSize: 11, weight: .regular); f.textColor = .labelColor
            views.append(f)
        }
        for v in views { (v as? NSTextField)?.preferredMaxLayoutWidth = width - 32 }
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        var handlers: [() -> Void] = []
        for (i, b) in buttons.enumerated() {
            let btn = NSButton(title: b.title, target: nil, action: nil)
            btn.bezelStyle = .rounded
            btn.controlSize = .regular
            if b.style == .primary { btn.keyEquivalent = "\r" }
            if b.style == .destructive { btn.hasDestructiveAction = true }
            btn.tag = i
            btn.target = Trampoline.shared
            btn.action = #selector(Trampoline.fire(_:))
            row.addArrangedSubview(btn)
            handlers.append(b.handler)
        }
        if !buttons.isEmpty {
            let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            row.insertArrangedSubview(spacer, at: 0)
            views.append(row)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        if !buttons.isEmpty { row.widthAnchor.constraint(equalToConstant: width - 32).isActive = true }
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        let host = NSView()
        host.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: host.leadingAnchor), stack.topAnchor.constraint(equalTo: host.topAnchor),
                                     stack.trailingAnchor.constraint(equalTo: host.trailingAnchor), stack.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        host.layoutSubtreeIfNeeded()
        host.frame = NSRect(origin: .zero, size: stack.fittingSize)

        lastView = host; lastTitle = title; lastButtons = buttons.map(\.title); lastHandlers = handlers
        Trampoline.shared.handlers = { i in
            guard i < handlers.count else { return }
            dismiss()
            handlers[i]()
        }
        guard !AppEnv.headless, let anchor, anchor.window != nil else { return }
        let vc = NSViewController(); vc.view = host
        let p = NSPopover()
        p.contentViewController = vc
        p.behavior = .transient
        p.animates = true
        popover = p
        p.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    private final class Trampoline: NSObject {
        nonisolated(unsafe) static let shared = Trampoline()
        var handlers: ((Int) -> Void)?
        @objc func fire(_ s: NSButton) { handlers?(s.tag) }
    }
}
