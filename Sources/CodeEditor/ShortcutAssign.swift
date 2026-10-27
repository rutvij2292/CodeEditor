import AppKit

/// Find Action ⌥↩ on a row: "press the new keys" without opening Settings. One-shot key monitor + a small HUD, removed as soon as
/// a binding is recorded or Escape is pressed (nothing stays resident). Conflicts are resolved like the Keymap pane does.
enum ShortcutAssign {
    private static var monitor: Any?
    private static var hud: NSPanel?

    static func begin(for item: NSMenuItem, over window: NSWindow?) {
        guard !AppEnv.headless, let id = KeymapStore.identity(of: item), let window else { return }
        finish()
        let label = NSTextField(labelWithString: "Press the new shortcut for “\(item.title)”  ·  Esc cancels")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.sizeToFit()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: label.frame.width + 40, height: 44), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let bg = NSVisualEffectView(frame: panel.contentView!.bounds)
        bg.material = .hudWindow; bg.state = .active; bg.wantsLayer = true; bg.layer?.cornerRadius = 10
        bg.autoresizingMask = [.width, .height]
        label.frame.origin = NSPoint(x: 20, y: (44 - label.frame.height) / 2)
        bg.addSubview(label)
        panel.contentView?.addSubview(bg)
        panel.setFrameOrigin(NSPoint(x: window.frame.midX - panel.frame.width / 2, y: window.frame.maxY - 120))
        panel.orderFront(nil)
        hud = panel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { finish(); return nil }                       // Escape
            guard let binding = KeyBinding.from(event: event) else { NSSound.beep(); return nil }
            finish()
            commit(binding, id: id, title: item.title)
            return nil
        }
    }

    private static func finish() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        hud?.orderOut(nil)
        hud = nil
    }

    private static func commit(_ binding: KeyBinding, id: String, title: String) {
        guard let menu = NSApp.mainMenu else { return }
        let conflicts = KeymapStore.conflicts(for: binding, excluding: id, in: menu)
        var unbind: [String] = []
        if !conflicts.isEmpty {
            let hasCommand = conflicts.contains { if case .command = $0.kind { return true }; return false }
            let alert = NSAlert()
            alert.messageText = "\(binding.text) is already in use"
            alert.informativeText = conflicts.map { "• " + $0.message }.joined(separator: "\n")
                + (hasCommand ? "\n\nReassign it to “\(title)” and remove it from the other command?" : "\n\nUse it anyway?")
            alert.addButton(withTitle: hasCommand ? "Reassign" : "Use Anyway")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            unbind = conflicts.compactMap { if case .command(let other, _) = $0.kind { return other }; return nil }
        }
        KeymapStore.set(id, binding, unbinding: unbind, menu: menu)
    }
}
