import AppKit

/// The four built-in colour schemes. Capture names are produced by `Languages` (tree-sitter queries + our overrides).
extension Theme {
    private static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    // MARK: IntelliJ Light (PhpStorm default light scheme)

    static let intellijLight: Palette = {
        let fg = hex(0x080808), grey = hex(0x8C8C8C)
        let navy = hex(0x0033B3), teal = hex(0x00627A), purple = hex(0x871094), green = hex(0x067D17)
        let number = hex(0x1750EB), gold = hex(0x9E880D), maroon = hex(0x660E7A)
        return Palette(
            id: "intellijLight", name: "IntelliJ Light", isDark: false,
            background: hex(0xFFFFFF), foreground: fg, gutter: hex(0x999999),
            tabSelected: NSColor(white: 0, alpha: 0.06),
            selection: hex(0xA6D2FF), currentLine: hex(0xF5F8FE), indentGuide: hex(0xEBEBEB),
            syntax: [
                ("comment", s(grey, italic: true)), ("comment.line", s(grey, italic: true)),
                ("comment.doc", s(grey, italic: true)), ("comment.doc.tag", s(grey, italic: true, bold: true)),
                ("keyword", s(navy)), ("keyword.directive", s(gold)), ("constant.builtin", s(navy)), ("boolean", s(navy)),
                ("variable.builtin", s(navy)), ("module.builtin", s(navy)),
                ("variable.php", s(maroon)), ("variable.parameter", s(fg)), ("variable.parameter.php", s(maroon)), ("variable.parameter.named", s(fg)),
                ("type", s(fg)), ("type.builtin", s(navy)), ("constructor", s(fg)), ("namespace", s(fg)), ("module", s(fg)),
                ("function", s(teal)), ("function.method", s(teal)), ("function.method.static", s(teal, italic: true)),
                ("property", s(purple)), ("property.static", s(purple, italic: true)),
                ("constant", s(purple, bold: true)), ("constant.class", s(purple, bold: true)),
                ("attribute", s(hex(0x0000FF))), ("meta.annotation", s(gold)),
                ("tag", s(hex(0x000080))), ("tag.delimiter", s(hex(0x000080))), ("tag.error", s(hex(0xF50000))),
                ("string", s(green)), ("string.escape", s(hex(0x0037A6), bold: true)), ("escape", s(hex(0x0037A6), bold: true)),
                ("string.special", s(green)), ("string.special.key", s(purple)),
                ("number", s(number)),
                ("punctuation.special", s(navy)),
                ("label", s(navy)),
                ("markup.heading", s(navy, bold: true)), ("text.title", s(navy, bold: true)),
                ("markup.bold", s(fg, bold: true)), ("text.strong", s(fg, bold: true)),
                ("markup.italic", s(fg, italic: true)), ("text.emphasis", s(fg, italic: true)),
                ("markup.link", s(hex(0x0033B3))), ("text.uri", s(hex(0x0033B3))), ("text.reference", s(hex(0x0033B3))),
                ("markup.raw", s(green)), ("text.literal", s(green)),
                ("error", s(hex(0xF50000))),
            ],
            lineNumber: hex(0x999999), lineNumberActive: hex(0x4C4C4C), gutterBackground: hex(0xFFFFFF),
            selectionInactive: hex(0xD4D4D4), caret: hex(0x000000), matchingBracket: hex(0xD8E8FC),
            occurrenceRead: hex(0xE6E0F5), occurrenceWrite: hex(0xF8DCE6), wavyTypo: hex(0x3C9A3C),
            indentGuideActive: hex(0xD0D0D0),
            tabIndicator: hex(0x3574F0), treeSelectionActive: hex(0xD5E4FA), treeSelectionInactive: hex(0xDFE1E5),
            divider: hex(0xEBECF0), sidebarBackground: hex(0xF7F8FA), toolHeaderBackground: hex(0xF7F8FA),
            statusBarBackground: hex(0xF7F8FA), statusBarForeground: hex(0x6C707E))
    }()

    // MARK: Darcula (JetBrains "Dark")

    static let darcula: Palette = {
        let fg = hex(0xBCBEC4), grey = hex(0x7A7E85), kw = hex(0xCF8E6D), str = hex(0x6AAB73), num = hex(0x2AACB8)
        let fn = hex(0x56A8F5), prop = hex(0xC77DBB), gold = hex(0xB3AE60), doc = hex(0x5F826B), tag = hex(0xD5B778)
        return Palette(
            id: "darcula", name: "Darcula", isDark: true,
            background: hex(0x1E1F22), foreground: fg, gutter: hex(0x4B5059),
            tabSelected: NSColor(white: 1, alpha: 0.08),
            selection: hex(0x214283), currentLine: hex(0x26282E), indentGuide: hex(0x393B41),
            syntax: [
                ("comment", s(grey, italic: true)), ("comment.line", s(grey, italic: true)),
                ("comment.doc", s(doc, italic: true)), ("comment.doc.tag", s(hex(0x67A37C), italic: true, bold: true)),
                ("keyword", s(kw)), ("keyword.directive", s(gold)), ("constant.builtin", s(kw)), ("boolean", s(kw)),
                ("variable.builtin", s(kw)), ("module.builtin", s(kw)),
                ("variable.php", s(fg)), ("variable.parameter", s(fg)), ("variable.parameter.php", s(fg)), ("variable.parameter.named", s(fg)),
                ("type", s(fg)), ("type.builtin", s(kw)), ("constructor", s(fg)), ("namespace", s(fg)), ("module", s(fg)),
                ("function", s(fn)), ("function.method", s(fn)), ("function.method.static", s(fn, italic: true)),
                ("property", s(prop)), ("property.static", s(prop, italic: true)),
                ("constant", s(prop, italic: true)), ("constant.class", s(prop, italic: true)),
                ("attribute", s(fg)), ("meta.annotation", s(gold)),
                ("tag", s(tag)), ("tag.delimiter", s(tag)), ("tag.error", s(hex(0xF75464))),
                ("string", s(str)), ("string.escape", s(kw)), ("escape", s(kw)),
                ("string.special", s(str)), ("string.special.key", s(prop)),
                ("number", s(num)),
                ("punctuation.special", s(kw)),
                ("label", s(fg)),
                ("markup.heading", s(kw, bold: true)), ("text.title", s(kw, bold: true)),
                ("markup.bold", s(fg, bold: true)), ("text.strong", s(fg, bold: true)),
                ("markup.italic", s(fg, italic: true)), ("text.emphasis", s(fg, italic: true)),
                ("markup.link", s(fn)), ("text.uri", s(fn)), ("text.reference", s(fn)),
                ("markup.raw", s(str)), ("text.literal", s(str)),
                ("error", s(hex(0xF75464))),
            ],
            lineNumber: hex(0x4B5059), lineNumberActive: hex(0xA1A3AB), gutterBackground: hex(0x1E1F22),
            selectionInactive: hex(0x43454A), caret: hex(0xCED0D6), matchingBracket: hex(0x43454A),
            occurrenceRead: hex(0x3A3F4F), occurrenceWrite: hex(0x4B3A44), wavyTypo: hex(0x62B543),
            indentGuideActive: hex(0x4E5157),
            tabIndicator: hex(0x3574F0), treeSelectionActive: hex(0x2E436E), treeSelectionInactive: hex(0x43454A),
            divider: hex(0x393B40), sidebarBackground: hex(0x2B2D30), toolHeaderBackground: hex(0x2B2D30),
            statusBarBackground: hex(0x2B2D30), statusBarForeground: hex(0x9DA0A8))
    }()

    // MARK: Ours (previous dark palette)

    static let ourDark: Palette = {
        let comment = c(0.42, 0.46, 0.52), string = c(0.60, 0.78, 0.47), orange = c(0.86, 0.62, 0.40)
        let purple = c(0.78, 0.55, 0.88), blue = c(0.38, 0.68, 0.94), yellow = c(0.90, 0.78, 0.48)
        let red = c(0.88, 0.43, 0.46), cyan = c(0.34, 0.74, 0.78), grey = c(0.62, 0.65, 0.70)
        return Palette(
            id: "ourDark", name: "Ours", isDark: true,
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
                ("meta.annotation", s(orange)), ("function.method.static", s(blue, italic: true)),
            ],
            lineNumber: c(0.45, 0.47, 0.52), lineNumberActive: c(0.80, 0.82, 0.85), gutterBackground: c(0.118, 0.125, 0.145),
            selectionInactive: NSColor(white: 1, alpha: 0.09), caret: c(0.80, 0.82, 0.85),
            matchingBracket: NSColor(white: 1, alpha: 0.16),
            occurrenceRead: NSColor(srgbRed: 0.55, green: 0.45, blue: 0.85, alpha: 0.28),
            occurrenceWrite: NSColor(srgbRed: 0.90, green: 0.45, blue: 0.55, alpha: 0.28), wavyTypo: hex(0x62B543),
            indentGuideActive: NSColor(white: 1, alpha: 0.16),
            tabIndicator: hex(0x3574F0), treeSelectionActive: NSColor(white: 1, alpha: 0.14),
            treeSelectionInactive: NSColor(white: 1, alpha: 0.08), divider: NSColor(white: 1, alpha: 0.08),
            sidebarBackground: c(0.135, 0.142, 0.162), toolHeaderBackground: c(0.135, 0.142, 0.162),
            statusBarBackground: c(0.135, 0.142, 0.162), statusBarForeground: c(0.62, 0.65, 0.70))
    }()

    // MARK: Light Lite (Brent Roose's "PhpStorm Light Lite")

    static let lightLite: Palette = {
        let blue = hex(0x4285F4), red = hex(0xEA4334), green = hex(0x34A853)
        let fg = hex(0x222222), op = hex(0x555555)
        let comment = hex(0x454545), doc = hex(0x777777), commentBG = hex(0xFFFBF2)
        return Palette(
            id: "lightLite", name: "Light Lite", isDark: false,
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
                ("meta.annotation", s(green)), ("keyword.directive", s(green)),
            ],
            lineNumber: hex(0x555555), lineNumberActive: hex(0x000000), gutterBackground: hex(0xFFFFFF),
            selectionInactive: hex(0xEAEAEA), caret: hex(0x000000), matchingBracket: hex(0xE3EDFD),
            occurrenceRead: hex(0xEDE7F8), occurrenceWrite: hex(0xFBE3EA), wavyTypo: hex(0x34A853),
            indentGuideActive: hex(0xDDDDDD),
            tabIndicator: hex(0x4285F4), treeSelectionActive: hex(0xDDE8FA), treeSelectionInactive: hex(0xE6E6E6),
            divider: hex(0xE6E6E6), sidebarBackground: hex(0xF7F7F7), toolHeaderBackground: hex(0xF7F7F7),
            statusBarBackground: hex(0xF7F7F7), statusBarForeground: hex(0x666666))
    }()
}
