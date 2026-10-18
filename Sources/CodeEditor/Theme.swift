import AppKit

/// Colour plus optional background / italic / bold for one syntax capture.
struct SyntaxStyle {
    var color: NSColor
    var background: NSColor? = nil
    var italic = false
    var bold = false
}

struct Palette {
    let background: NSColor
    let foreground: NSColor
    let gutter: NSColor
    let tabSelected: NSColor
    /// Text selection, current-line and indent-guide colours (for the editor view to adopt).
    let selection: NSColor
    let currentLine: NSColor
    let indentGuide: NSColor
    /// Capture-name prefix -> style. Longest matching prefix wins ("function.method" before "function").
    /// Captures without a matching prefix keep the plain foreground colour.
    let syntax: [(String, SyntaxStyle)]
}

enum ThemeMode: String { case system, light, dark }

enum Theme {
    static let didChange = Notification.Name("CodeEditor.themeDidChange")
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    private static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private static func hex(_ v: UInt32) -> NSColor {
        c(CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
    }

    private static func s(_ color: NSColor, bg: NSColor? = nil, italic: Bool = false, bold: Bool = false) -> SyntaxStyle {
        SyntaxStyle(color: color, background: bg, italic: italic, bold: bold)
    }

    static let dark: Palette = {
        let comment = c(0.42, 0.46, 0.52), string = c(0.60, 0.78, 0.47), orange = c(0.86, 0.62, 0.40)
        let purple = c(0.78, 0.55, 0.88), blue = c(0.38, 0.68, 0.94), yellow = c(0.90, 0.78, 0.48)
        let red = c(0.88, 0.43, 0.46), cyan = c(0.34, 0.74, 0.78), grey = c(0.62, 0.65, 0.70)
        return Palette(
            background: c(0.118, 0.125, 0.145), foreground: c(0.80, 0.82, 0.85), gutter: c(0.45, 0.47, 0.52),
            tabSelected: NSColor(white: 1, alpha: 0.10),
            selection: NSColor(white: 1, alpha: 0.15), currentLine: NSColor(white: 1, alpha: 0.04),
            indentGuide: NSColor(white: 1, alpha: 0.07),
            syntax: [
                ("comment", s(comment, italic: true)), ("string", s(string)), ("number", s(orange)),
                ("constant", s(orange)), ("keyword", s(purple)), ("function", s(blue)),
                ("type", s(yellow)), ("tag", s(red)), ("attribute", s(orange)),
                ("property", s(red)), ("variable.builtin", s(red)), ("variable.parameter", s(c(0.90, 0.72, 0.60))),
                ("operator", s(cyan)), ("punctuation", s(grey)), ("punctuation.special", s(cyan)),
                ("string.escape", s(cyan)), ("escape", s(cyan)), ("string.special", s(cyan)),
                ("string.special.key", s(red)), ("string.special.symbol", s(orange)),
                ("constructor", s(yellow)), ("namespace", s(yellow)), ("module", s(yellow)), ("label", s(red)),
                ("boolean", s(orange)), ("markup.heading", s(red, bold: true)), ("text.title", s(red, bold: true)),
                ("markup.bold", s(orange, bold: true)), ("text.strong", s(orange, bold: true)),
                ("markup.italic", s(purple, italic: true)), ("text.emphasis", s(purple, italic: true)),
                ("markup.link", s(blue)), ("text.uri", s(cyan)), ("text.reference", s(blue)),
                ("markup.raw", s(string)), ("text.literal", s(string)),
                ("comment.doc", s(c(0.50, 0.55, 0.62), italic: true)),
                ("tag.delimiter", s(grey)), ("error", s(red)),
            ])
    }()

    /// Brent Roose's "PhpStorm Light Lite" look: minimal, only keywords / types / functions coloured.
    static let light: Palette = {
        let blue = hex(0x4285F4), red = hex(0xEA4334), green = hex(0x34A853)
        let fg = hex(0x222222), op = hex(0x555555)
        let comment = hex(0x454545), doc = hex(0x777777), commentBG = hex(0xFFFBF2)
        return Palette(
            background: hex(0xFFFFFF), foreground: fg, gutter: hex(0x555555),
            tabSelected: NSColor(white: 0, alpha: 0.08),
            selection: hex(0xDDDDDD), currentLine: hex(0xF7F7F7), indentGuide: hex(0xF0F0F0),
            syntax: [
                ("comment", s(comment, italic: true)),
                ("comment.line", s(comment, bg: commentBG, italic: true)),
                ("comment.doc", s(doc, italic: true)),
                ("keyword", s(blue)), ("constant.builtin", s(blue)), ("boolean", s(blue)),
                ("variable.builtin", s(blue)),
                ("type", s(red)), ("constructor", s(red)), ("namespace", s(red)), ("module", s(red)),
                ("function", s(green)), ("property", s(green)), ("attribute", s(green)),
                ("constant", s(green, bold: true)),
                ("tag", s(blue)), ("tag.delimiter", s(fg)),
                ("operator", s(op)),
                ("string.special.key", s(blue)), ("punctuation.json", s(green)),
                ("label", s(blue)),
                ("markup.heading", s(blue, bold: true)), ("text.title", s(blue, bold: true)),
                ("markup.bold", s(fg, bold: true)), ("text.strong", s(fg, bold: true)),
                ("markup.italic", s(fg, italic: true)), ("text.emphasis", s(fg, italic: true)),
                ("markup.link", s(blue)), ("text.uri", s(blue)), ("text.reference", s(blue)),
                ("markup.raw", s(green)), ("text.literal", s(green)),
                ("error", s(red)),
            ])
    }()

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

    static func style(for capture: String) -> SyntaxStyle? {
        var best: (Int, SyntaxStyle)?
        for (prefix, style) in palette.syntax where capture == prefix || capture.hasPrefix(prefix + ".") {
            if best == nil || prefix.count > best!.0 { best = (prefix.count, style) }
        }
        return best?.1
    }

    static func color(for capture: String) -> NSColor? { style(for: capture)?.color }
}
