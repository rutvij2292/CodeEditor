import AppKit

/// CE_SELFTEST: keymap overrides (store, single apply pass, conflicts, recording, reset, tooltips, Settings pane).
enum SelfTestKeymap {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    private static func event(_ chars: String, _ mods: NSEvent.ModifierFlags, code: UInt16 = 0) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)
    }

    static func run(app: AppDelegate) {
        let saved = KeymapStore.defaults
        let suite = "ce-keymap-selftest"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        KeymapStore.defaults = UserDefaults(suiteName: suite)!
        defer { KeymapStore.defaults = saved; UserDefaults.standard.removePersistentDomain(forName: suite) }

        let menu = MainMenu.build(app: app)
        func item(_ title: String) -> NSMenuItem? { KeymapStore.leaves(of: menu).first { $0.item.title == title }?.item }
        guard let commit = item("Commit…"), let push = item("Push…"), let commitID = KeymapStore.identity(of: commit),
              let pushID = KeymapStore.identity(of: push) else { check("keymap: menu has Commit… and Push…", false); return }
        check("keymap: shipped Commit… is ⌘K", MainMenu.shortcutText(for: commit) == "⌘K")

        // Recording: modifiers required, function keys may stand alone, letters normalise.
        let j = KeyBinding.from(key: "J", flags: [.command, .option, .control])
        check("keymap: letters are lower-cased with their modifiers", j == KeyBinding(key: "j", flags: [.command, .option, .control]) && j?.text == "⌃⌥⌘J")
        check("keymap: plain letter rejected", KeyBinding.from(key: "a", flags: []) == nil)
        check("keymap: shift-only letter rejected", KeyBinding.from(key: "a", flags: .shift) == nil)
        check("keymap: bare F5 accepted", KeyBinding.from(key: String(UnicodeScalar(UInt32(NSF5FunctionKey))!), flags: [])?.text == "F5")
        if let e = event("j", [.command, .option, .control], code: 38) { check("keymap: key event records ⌃⌥⌘J", KeyBinding.from(event: e) == j) }
        else { check("keymap: could synthesize a key event", false) }
        guard let b = j else { return }

        // Apply pass + persistence.
        check("keymap: unused binding has no conflicts", KeymapStore.conflicts(for: b, excluding: commitID, in: menu).isEmpty)
        KeymapStore.set(commitID, b, menu: menu)
        check("keymap: override changes the menu item", KeyBinding(of: commit) == b && MainMenu.shortcutText(for: commit) == "⌃⌥⌘J")
        check("keymap: override persisted as JSON", KeymapStore.load()[commitID] == b && KeymapStore.isOverridden(commitID))
        let rebuilt = MainMenu.build(app: app)       // a fresh build picks the override up in its apply pass
        check("keymap: rebuilt menu keeps the override",
              KeymapStore.leaves(of: rebuilt).first { $0.item.title == "Commit…" }.map { KeyBinding(of: $0.item) == b } == true)
        check("keymap: entries report customised", Keymap.entries(from: menu).first { $0.id == commitID }?.isCustom == true)
        check("keymap: tooltip text follows the remap", KeymapStore.retip("Commit… (⌘K)") == "Commit… (⌃⌥⌘J)")
        check("keymap: other tooltip text untouched", KeymapStore.retip("Update Project (⌘T)") == "Update Project (⌘T)")

        // Conflicts: commands, system shortcuts, fixed handlers.
        let old = KeyBinding(key: "k", flags: .command)
        let cs = KeymapStore.conflicts(for: KeyBinding(key: "k", flags: [.command, .shift]), excluding: commitID, in: menu)
        check("keymap: conflict names the other command", cs.contains { if case .command(let id, _) = $0.kind { return id == pushID }; return false })
        check("keymap: freed shipped shortcut no longer conflicts", KeymapStore.conflicts(for: old, excluding: pushID, in: menu).isEmpty)
        check("keymap: system shortcut flagged", KeymapStore.conflicts(for: KeyBinding(key: " ", flags: .command), excluding: pushID, in: menu)
                .contains { if case .system = $0.kind { return true }; return false })
        check("keymap: fixed tree shortcut flagged", KeymapStore.conflicts(for: KeyBinding(key: "n", flags: .command), excluding: pushID, in: menu)
                .contains { if case .fixed = $0.kind { return true }; return false })

        // Reassign: Push takes Commit's current shortcut.
        KeymapStore.set(pushID, b, unbinding: [commitID], menu: menu)
        check("keymap: reassign moves the shortcut", KeyBinding(of: push) == b && KeyBinding(of: commit).isNone)
        check("keymap: removed shortcut is empty text", MainMenu.shortcutText(for: commit).isEmpty)

        // Reset one / all.
        KeymapStore.reset(commitID, menu: menu)
        check("keymap: reset restores the shipped shortcut", MainMenu.shortcutText(for: commit) == "⌘K")
        KeymapStore.resetAll(menu: menu)
        check("keymap: reset all restores everything", MainMenu.shortcutText(for: push) == "⇧⌘K" && KeymapStore.load().isEmpty)

        // Settings pane.
        let pane = KeymapPane()
        pane.menuProvider = { menu }
        _ = pane.view
        check("keymap: pane lists commands", Keymap.entries(from: menu).count > 100)
        pane.commit(b, forID: commitID, title: "Commit…")
        check("keymap: pane commit applies", KeyBinding(of: commit) == b)
        pane.commit(KeyBinding(key: "n", flags: .command), forID: commitID, title: "Commit…")   // fixed conflict: refused headless
        check("keymap: conflicting commit refused headless", KeyBinding(of: commit) == b)

        if let path = AppEnv.value("CE_KEYMAP_PNG") {
            pane.view.frame = NSRect(origin: .zero, size: SettingsWindowController.contentSize)
            pane.view.layoutSubtreeIfNeeded()
            if let rep = pane.view.bitmapImageRepForCachingDisplay(in: pane.view.bounds) {
                pane.view.cacheDisplay(in: pane.view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
        KeymapStore.resetAll(menu: menu)
    }
}
