import AppKit

/// A menu key equivalent. `key == ""` means "no shortcut". `mods` holds `NSEvent.ModifierFlags.rawValue` (cmd/opt/ctrl/shift only).
struct KeyBinding: Codable, Equatable {
    var key: String
    var mods: UInt

    static let unbound = KeyBinding(key: "", mods: 0)
    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: mods) }
    var isNone: Bool { key.isEmpty }

    init(key: String, mods: UInt) { self.key = key; self.mods = mods }
    init(key: String, flags: NSEvent.ModifierFlags) {
        self.key = key
        mods = key.isEmpty ? 0 : flags.intersection([.command, .option, .control, .shift]).rawValue
    }
    init(of item: NSMenuItem) { self.init(key: item.keyEquivalent, flags: item.keyEquivalentModifierMask) }

    /// "⌃⌥⇧⌘D" style text.
    var text: String {
        guard !key.isEmpty else { return "" }
        let i = NSMenuItem(title: "", action: nil, keyEquivalent: key)
        i.keyEquivalentModifierMask = flags
        return MainMenu.shortcutText(for: i)
    }

    /// The binding a key press would be recorded as; nil when it cannot be a menu shortcut (modifier-only, or a plain
    /// printable / editing key with no Command / Option / Control).
    static func from(event: NSEvent) -> KeyBinding? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key: String
        switch event.keyCode {
        case 51: key = "\u{7f}"
        case 36, 76: key = "\r"
        case 48: key = "\t"
        case 49: key = " "
        default:
            guard let c = event.charactersIgnoringModifiers, let s = c.unicodeScalars.first, s.value >= 0x20 else { return nil }
            key = String(c.unicodeScalars.prefix(1))
        }
        return from(key: key, flags: flags)
    }

    static func from(key rawKey: String, flags: NSEvent.ModifierFlags) -> KeyBinding? {
        guard let s = rawKey.unicodeScalars.first else { return nil }
        let isFunction = (0xF700...0xF70F).contains(s.value)          // arrows and F1-F12 may stand alone
        let key = s.properties.isAlphabetic ? rawKey.lowercased() : rawKey
        if flags.intersection([.command, .option, .control]).isEmpty && !isFunction { return nil }
        return KeyBinding(key: key, flags: flags)
    }
}

/// User keymap: overrides are stored as JSON in UserDefaults and applied to the built menu in one pass.
/// A menu item's identity is "selector|title" (stable across builds).
enum KeymapStore {
    static let defaultsKey = "keymapOverrides"
    /// Swappable so tests never touch the real preferences.
    static var defaults = UserDefaults.standard
    /// Shipped binding of every leaf command, captured the first time the menu is seen.
    private(set) static var factory: [String: KeyBinding] = [:]

    static func identity(of item: NSMenuItem) -> String? {
        guard let a = item.action else { return nil }
        return NSStringFromSelector(a) + "|" + item.title
    }

    static func load() -> [String: KeyBinding] {
        guard let data = defaults.data(forKey: defaultsKey),
              let dict = try? JSONDecoder().decode([String: KeyBinding].self, from: data) else { return [:] }
        return dict
    }

    static func save(_ overrides: [String: KeyBinding]) {
        if overrides.isEmpty { defaults.removeObject(forKey: defaultsKey); return }
        defaults.set(try? JSONEncoder().encode(overrides), forKey: defaultsKey)
    }

    /// Leaf command items of `menu` with their group path ("Edit"); "Open Recent" is a dynamic list and skipped.
    static func leaves(of menu: NSMenu) -> [(item: NSMenuItem, group: String)] {
        var out: [(NSMenuItem, String)] = []
        func walk(_ m: NSMenu, path: [String]) {
            for item in m.items where !item.isSeparatorItem {
                if let sub = item.submenu {
                    if sub.title != "Open Recent" { walk(sub, path: path + [item.title]) }
                    continue
                }
                out.append((item, path.joined(separator: " › ")))
            }
        }
        for top in menu.items { if let sub = top.submenu { walk(sub, path: [top.title]) } }
        return out
    }

    /// The single pass: overrides win, everything else is (re)set to its shipped binding.
    static func apply(to menu: NSMenu, overrides: [String: KeyBinding]? = nil) {
        let overrides = overrides ?? load()
        for (item, _) in leaves(of: menu) {
            guard let id = identity(of: item) else { continue }
            if factory[id] == nil { factory[id] = KeyBinding(of: item) }
            let target = overrides[id] ?? factory[id]!
            item.keyEquivalent = target.key
            item.keyEquivalentModifierMask = target.key.isEmpty ? [] : target.flags
        }
    }

    static func isOverridden(_ id: String) -> Bool { load()[id].map { $0 != factory[id] } ?? false }

    /// Records `binding` for `id` (an override equal to the shipped binding is dropped), unbinding `unbind` first, re-applies.
    static func set(_ id: String, _ binding: KeyBinding, unbinding unbind: [String] = [], menu: NSMenu? = NSApp.mainMenu) {
        var o = load()
        for other in unbind { o[other] = KeyBinding.unbound }
        o[id] = binding
        for k in Array(o.keys) where o[k] == factory[k] { o[k] = nil }
        save(o)
        if let menu { apply(to: menu, overrides: o) }
    }

    static func reset(_ id: String, menu: NSMenu? = NSApp.mainMenu) {
        var o = load(); o[id] = nil; save(o)
        if let menu { apply(to: menu, overrides: o) }
    }

    static func resetAll(menu: NSMenu? = NSApp.mainMenu) {
        save([:])
        if let menu { apply(to: menu, overrides: [:]) }
    }

    // MARK: conflicts

    struct Conflict: Equatable {
        enum Kind: Equatable { case command(id: String, path: String), system(String), fixed(String) }
        let kind: Kind
        var message: String {
            switch kind {
            case .command(_, let path): return "already used by \(path)"
            case .system(let s), .fixed(let s): return s
            }
        }
    }

    /// Shortcuts handled in code outside the menu (not remappable). They fire first when the matching view has focus.
    static let fixedShortcuts: [String: String] = [
        "⎋": "Escape returns focus to the editor / closes popups (fixed)",
        "⇧⎋": "Shift-Escape hides the focused tool window (fixed)",
        "⇧⌘[": "Shift-⌘[ / ] cycle tool-window tabs while a tool window has focus (fixed)",
        "⇧⌘]": "Shift-⌘[ / ] cycle tool-window tabs while a tool window has focus (fixed)",
        "⌘⌫": "⌘⌫ deletes the selected file while the project tree has focus (fixed)",
        "⌘N": "⌘N creates a file while the project tree has focus (fixed)",
        "⇧F6": "Shift-F6 renames while the project tree has focus (fixed)",
    ]

    static func conflicts(for binding: KeyBinding, excluding id: String, in menu: NSMenu) -> [Conflict] {
        guard !binding.isNone else { return [] }
        var out: [Conflict] = []
        for (item, group) in leaves(of: menu) {
            guard let other = identity(of: item), other != id, KeyBinding(of: item) == binding else { continue }
            out.append(Conflict(kind: .command(id: other, path: group + " › " + item.title)))
        }
        let t = binding.text
        if let s = Keymap.systemShortcuts[t] { out.append(Conflict(kind: .system(s))) }
        if let s = fixedShortcuts[t] { out.append(Conflict(kind: .fixed(s))) }
        return out
    }

    // MARK: tooltips

    /// Rewrites shortcut hints in tooltip text ("Commit… (⌘K)") after a remap: a shortcut that was the shipped binding of
    /// exactly one command becomes that command's current binding (or is dropped when unbound).
    static func retip(_ s: String) -> String {
        let o = load()
        guard !o.isEmpty else { return s }
        var out = s
        let byText = Dictionary(grouping: factory, by: { $0.value.text })
        for (id, b) in o {
            guard let f = factory[id], f != b, let same = byText[f.text], same.count == 1 else { continue }
            out = b.isNone ? out.replacingOccurrences(of: " (\(f.text))", with: "") : out.replacingOccurrences(of: f.text, with: b.text)
        }
        return out
    }
}
