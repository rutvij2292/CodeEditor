import AppKit

struct Palette {
    let background: NSColor
    let foreground: NSColor
    let gutter: NSColor
    let tabSelected: NSColor
    /// Capture-name prefix -> colour. Longest matching prefix wins ("function.method" before "function").
    let syntax: [(String, NSColor)]
}

enum ThemeMode: String { case system, light, dark }

enum Theme {
    static let didChange = Notification.Name("CodeEditor.themeDidChange")
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    static let dark = Palette(
        background: c(0.118, 0.125, 0.145), foreground: c(0.80, 0.82, 0.85), gutter: c(0.45, 0.47, 0.52),
        tabSelected: NSColor(white: 1, alpha: 0.10),
        syntax: [
            ("comment", c(0.42, 0.46, 0.52)), ("string", c(0.60, 0.78, 0.47)), ("number", c(0.86, 0.62, 0.40)),
            ("constant", c(0.86, 0.62, 0.40)), ("keyword", c(0.78, 0.55, 0.88)), ("function", c(0.38, 0.68, 0.94)),
            ("type", c(0.90, 0.78, 0.48)), ("tag", c(0.88, 0.43, 0.46)), ("attribute", c(0.86, 0.62, 0.40)),
            ("property", c(0.88, 0.43, 0.46)), ("variable.builtin", c(0.88, 0.43, 0.46)),
            ("operator", c(0.34, 0.74, 0.78)), ("punctuation", c(0.62, 0.65, 0.70)),
        ])

    static let light = Palette(
        background: c(0.995, 0.995, 0.995), foreground: c(0.14, 0.15, 0.17), gutter: c(0.60, 0.62, 0.66),
        tabSelected: NSColor(white: 0, alpha: 0.08),
        syntax: [
            ("comment", c(0.55, 0.57, 0.60)), ("string", c(0.22, 0.55, 0.20)), ("number", c(0.80, 0.42, 0.10)),
            ("constant", c(0.80, 0.42, 0.10)), ("keyword", c(0.55, 0.20, 0.75)), ("function", c(0.10, 0.40, 0.80)),
            ("type", c(0.62, 0.45, 0.05)), ("tag", c(0.78, 0.20, 0.25)), ("attribute", c(0.80, 0.42, 0.10)),
            ("property", c(0.78, 0.20, 0.25)), ("variable.builtin", c(0.78, 0.20, 0.25)),
            ("operator", c(0.05, 0.55, 0.60)), ("punctuation", c(0.35, 0.38, 0.42)),
        ])

    private(set) static var mode: ThemeMode =
        ThemeMode(rawValue: UserDefaults.standard.string(forKey: "themeMode") ?? "") ?? .system
    private static var observation: NSKeyValueObservation?

    static var isDark: Bool { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    static var palette: Palette { isDark ? dark : light }
    static var background: NSColor { palette.background }
    static var foreground: NSColor { palette.foreground }
    static var gutter: NSColor { palette.gutter }

    /// Applies the saved (or CE_THEME) mode and starts following macOS appearance changes.
    static func start() {
        if let forced = AppEnv.value("CE_THEME").flatMap(ThemeMode.init(rawValue:)) { mode = forced }
        apply()
        observation = NSApp.observe(\.effectiveAppearance) { _, _ in
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    static func setMode(_ new: ThemeMode) {
        mode = new
        if !AppEnv.headless { UserDefaults.standard.set(new.rawValue, forKey: "themeMode") }
        apply()
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static func apply() {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static func color(for capture: String) -> NSColor? {
        var best: (Int, NSColor)?
        for (prefix, color) in palette.syntax where capture == prefix || capture.hasPrefix(prefix + ".") {
            if best == nil || prefix.count > best!.0 { best = (prefix.count, color) }
        }
        return best?.1
    }
}
