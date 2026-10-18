import AppKit

/// Colour plus optional background / italic / bold for one syntax capture.
struct SyntaxStyle {
    var color: NSColor
    var background: NSColor? = nil
    var italic = false
    var bold = false
}

struct Palette {
    let id: String
    let name: String
    let isDark: Bool
    let background: NSColor
    let foreground: NSColor
    /// Line-number colour (kept under its historical name; `lineNumber` is the same value for new code).
    let gutter: NSColor
    let tabSelected: NSColor
    /// Text selection, current-line and indent-guide colours (for the editor view to adopt).
    let selection: NSColor
    let currentLine: NSColor
    let indentGuide: NSColor
    /// Capture-name prefix -> style. Longest matching prefix wins ("function.method" before "function").
    /// Captures without a matching prefix keep the plain foreground colour.
    let syntax: [(String, SyntaxStyle)]

    // MARK: Editor furniture
    let lineNumber: NSColor
    let lineNumberActive: NSColor
    let gutterBackground: NSColor
    let selectionInactive: NSColor
    let caret: NSColor
    /// Highlight of the bracket next to the caret and its partner (background).
    let matchingBracket: NSColor
    /// Occurrence highlights of the identifier under the caret: reads / writes (backgrounds, drawn as rounded boxes).
    let occurrenceRead: NSColor
    let occurrenceWrite: NSColor
    /// Wavy underline colour for typos / weak warnings.
    let wavyTypo: NSColor
    let indentGuideActive: NSColor

    // MARK: Chrome (tab strip, project tree, tool windows, status bar, dividers)
    let tabIndicator: NSColor
    let treeSelectionActive: NSColor
    let treeSelectionInactive: NSColor
    let divider: NSColor
    let sidebarBackground: NSColor
    let toolHeaderBackground: NSColor
    let statusBarBackground: NSColor
    let statusBarForeground: NSColor
}

enum ThemeMode: String { case system, light, dark }

enum Theme {
    static let didChange = Notification.Name("CodeEditor.themeDidChange")
    private static var fontCache: (name: String, size: Double, font: NSFont)?

    /// Editor font from `Prefs.editorFontName` / `Prefs.editorFontSize`. "" = JetBrains Mono (bundled), falling back to the
    /// system monospaced font; "System Monospaced" forces the latter. Recomputed when either changes; `Theme.didChange` is
    /// posted so editors, gutters and the tab strip restyle.
    static var font: NSFont {
        _ = prefsObserver
        let name = Prefs.editorFontName, size = Prefs.editorFontSize
        if let c = fontCache, c.name == name, c.size == size { return c.font }
        let font = resolveFont(name: name, size: size)
        fontCache = (name, size, font)
        return font
    }

    static let systemMonospacedName = "System Monospaced"

    static func resolveFont(name: String, size: Double) -> NSFont {
        let pt = CGFloat(size)
        FontRegistry.registerBundledFonts()
        if name == systemMonospacedName { return NSFont.monospacedSystemFont(ofSize: pt, weight: .regular) }
        let wanted = name.isEmpty ? FontRegistry.bundledFamily : name
        if wanted == FontRegistry.bundledFamily, let f = NSFont(name: "JetBrainsMono-Regular", size: pt) {
            return Prefs.editorLigatures ? f : withoutLigatures(f)
        }
        if let f = NSFont(name: wanted, size: pt) { return f }
        let d = NSFontDescriptor(fontAttributes: [.family: wanted])
        if let f = NSFont(descriptor: d, size: pt), f.familyName?.caseInsensitiveCompare(wanted) == .orderedSame { return f }
        return NSFont.monospacedSystemFont(ofSize: pt, weight: .regular)
    }

    /// JetBrains Mono's `->` / `=>` / `!=` shapes are contextual alternates (calt) plus ligatures (liga): switch both off.
    private static func withoutLigatures(_ f: NSFont) -> NSFont {
        let features: [[NSFontDescriptor.FeatureKey: Int]] = [
            [.typeIdentifier: kContextualAlternatesType, .selectorIdentifier: kContextualAlternatesOffSelector],
            [.typeIdentifier: kLigaturesType, .selectorIdentifier: kCommonLigaturesOffSelector],
            [.typeIdentifier: kLigaturesType, .selectorIdentifier: kRareLigaturesOffSelector],
        ]
        let d = f.fontDescriptor.addingAttributes([.featureSettings: features])
        return NSFont(descriptor: d, size: f.pointSize) ?? f
    }

    /// Typing / base attributes for editor text: font, colour, paragraph style, and ligatures off (PhpStorm's default;
    /// turn on with `Prefs.editorLigatures`).
    static func textAttributes(paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph, .ligature: Prefs.editorLigatures ? 1 : 0]
    }

    /// Restyles everything that listens to `didChange` when a font / line-height / colour-scheme preference changes.
    private static let prefsObserver: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: Prefs.didChange, object: nil, queue: .main) { note in
        guard let key = note.userInfo?["key"] as? String else { return }
        if ["colorScheme", "lightScheme", "darkScheme"].contains(key) {
            apply()
            NotificationCenter.default.post(name: didChange, object: nil)
        } else if ["editorFontName", "editorFontSize", "lineHeightMultiple", "editorLigatures"].contains(key) {
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    // MARK: Schemes

    static let lightSchemes: [(id: String, title: String)] = [("intellijLight", "IntelliJ Light"), ("lightLite", "Light Lite")]
    static let darkSchemes: [(id: String, title: String)] = [("darcula", "Darcula"), ("ourDark", "Ours")]

    static func scheme(id: String) -> Palette? {
        switch id {
        case "intellijLight": return intellijLight
        case "lightLite": return lightLite
        case "darcula": return darcula
        case "ourDark": return ourDark
        default: return nil
        }
    }

    /// Scheme id in effect: an explicit `Prefs.colorScheme`, else the per-appearance choice.
    static var schemeID: String {
        let explicit = Prefs.colorScheme
        if explicit != "auto", scheme(id: explicit) != nil { return explicit }
        if isDark { return darkSchemes.contains { $0.id == Prefs.darkScheme } ? Prefs.darkScheme : "darcula" }
        return lightSchemes.contains { $0.id == Prefs.lightScheme } ? Prefs.lightScheme : "intellijLight"
    }

    /// The dark / light palette currently chosen for each appearance (used by the terminal, previews...).
    static var dark: Palette { scheme(id: Prefs.darkScheme).flatMap { $0.isDark ? $0 : nil } ?? darcula }
    static var light: Palette { scheme(id: Prefs.lightScheme).flatMap { $0.isDark ? nil : $0 } ?? intellijLight }

    private(set) static var mode: ThemeMode =
        ThemeMode(rawValue: UserDefaults.standard.string(forKey: "themeMode") ?? "") ?? .system
    private static var observation: NSKeyValueObservation?

    static var isDark: Bool { NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    static var palette: Palette { scheme(id: schemeID) ?? (isDark ? darcula : intellijLight) }
    static var background: NSColor { palette.background }
    static var foreground: NSColor { palette.foreground }
    static var gutter: NSColor { palette.gutter }

    // MARK: Chrome helpers (adopt these from tab strip / tree / status bar / dividers)

    enum chrome {
        static var tabIndicator: NSColor { palette.tabIndicator }
        static var tabSelectedBackground: NSColor { palette.isDark ? palette.tabSelected : palette.background }
        static var treeSelectionActive: NSColor { palette.treeSelectionActive }
        static var treeSelectionInactive: NSColor { palette.treeSelectionInactive }
        static var divider: NSColor { palette.divider }
        static var sidebarBackground: NSColor { palette.sidebarBackground }
        static var toolHeaderBackground: NSColor { palette.toolHeaderBackground }
        static var statusBarBackground: NSColor { palette.statusBarBackground }
        static var statusBarForeground: NSColor { palette.statusBarForeground }
        /// Row height for the project tree (IntelliJ: 22 pt at the default font size).
        static let treeRowHeight: CGFloat = 22
        static let statusBarFont: NSFont = .systemFont(ofSize: 11)
        static let dividerThickness: CGFloat = 1
    }

    /// Applies the saved (or CE_THEME / CE_SCHEME) mode and starts following macOS appearance changes.
    static func start() {
        FontRegistry.registerBundledFonts()
        _ = prefsObserver
        if let forced = AppEnv.value("CE_THEME").flatMap(ThemeMode.init(rawValue:)) { mode = forced }
        if let forced = AppEnv.value("CE_SCHEME"), scheme(id: forced) != nil { Prefs.colorScheme = forced }
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
        // An explicitly chosen scheme also decides the appearance so window chrome matches the editor.
        if Prefs.colorScheme != "auto", let s = scheme(id: Prefs.colorScheme) {
            NSApp.appearance = NSAppearance(named: s.isDark ? .darkAqua : .aqua)
            return
        }
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

    // MARK: Colour helpers (shared with ThemePalettes.swift)

    static func hex(_ v: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }

    static func s(_ color: NSColor, bg: NSColor? = nil, italic: Bool = false, bold: Bool = false) -> SyntaxStyle {
        SyntaxStyle(color: color, background: bg, italic: italic, bold: bold)
    }
}
