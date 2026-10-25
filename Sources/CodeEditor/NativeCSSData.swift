import Foundation

/// Static CSS knowledge for the native service: property docs + keyword values, at-rules, pseudo classes / elements, functions, colors.
/// Stored as compact strings and parsed on first use (a few tens of KB, built once; dropped never because it is tiny).
enum NWCssData {
    /// One CSS property from the generated table (NativeWebDataGen.swift). Fields are read from the immortal literal on demand.
    struct Prop {
        let name: String
        let raw: Substring
        private func field(_ i: Int) -> Substring { raw.split(separator: "\u{1}", maxSplits: 4, omittingEmptySubsequences: false).dropFirst(i).first ?? "" }
        var doc: String { String(field(1)) }
        var syntax: String { String(field(3)) }
        var obsolete: Bool { field(4) == "x" }
        var values: [String] {
            var seen = Set<Substring>()
            return field(2).split(separator: " ").filter { seen.insert($0).inserted }.map(String.init)
        }
        var hasColor: Bool { raw.contains("<color>") }
        var hasImage: Bool { raw.contains("<image>") || raw.contains("<url>") || raw.contains("<bg-image>") }
        var hasNumeric: Bool { raw.contains("<length") || raw.contains("<number") || raw.contains("<percentage") || raw.contains("<time") || raw.contains("<angle") || raw.contains("<integer") }
    }

    /// name -> record, built once from the generated lines (names only are copied; the records stay literal substrings).
    struct PropTable {
        let index: [String: Substring]
        init() {
            var d: [String: Substring] = [:]
            d.reserveCapacity(NWWebDataGen.cssProperties.count + 8)
            for line in NWWebDataGen.cssProperties {
                guard let sep = line.firstIndex(of: "\u{1}") else { continue }
                d[String(line[line.startIndex..<sep])] = Substring(line)
            }
            index = d
        }
        subscript(_ name: String) -> Prop? { index[name].map { Prop(name: name, raw: $0) } }
        var keys: Dictionary<String, Substring>.Keys { index.keys }
    }
    static let props = PropTable()

    /// Property names: standard ones alphabetically, vendor-prefixed (`-webkit-`) and obsolete last.
    static let sortedPropNames: [String] = props.keys.sorted { a, b in
        let av = a.hasPrefix("-"), bv = b.hasPrefix("-")
        return av != bv ? !av : a < b
    }

    static func isProperty(_ name: String) -> Bool { props.index[name] != nil || name.hasPrefix("--") || name.hasPrefix("-webkit-") || name.hasPrefix("-moz-") || name.hasPrefix("-ms-") }

    static let globalValues = ["inherit", "initial", "unset", "revert", "revert-layer"]

    // color-valued properties (get named colors and color functions)
    static let colorProps: Set<String> = ["color", "background", "background-color", "border", "border-color", "border-top", "border-right", "border-bottom", "border-left",
                                          "border-top-color", "border-right-color", "border-bottom-color", "border-left-color", "outline", "outline-color", "fill", "stroke",
                                          "caret-color", "accent-color", "text-decoration", "text-decoration-color", "box-shadow", "text-shadow", "column-rule-color",
                                          "scrollbar-color", "-webkit-text-fill-color", "-webkit-tap-highlight-color", "mask", "flood-color", "stop-color", "lighting-color"]

    // MARK: at-rules

    private static let atSnippets: [String: String] = [
        "media": "media ${1:(min-width: 768px)} {\n\t$0\n}", "import": "import url(\"$0\");", "font-face": "font-face {\n\tfont-family: $1;\n\tsrc: url(\"$2\");\n\t$0\n}",
        "keyframes": "keyframes ${1:name} {\n\tfrom { $2 }\n\tto { $0 }\n}", "supports": "supports (${1:display: grid}) {\n\t$0\n}", "layer": "layer ${1:name};",
        "container": "container ${1:(min-width: 400px)} {\n\t$0\n}", "charset": "charset \"UTF-8\";", "namespace": "namespace $0;", "page": "page {\n\t$0\n}",
        "property": "property --${1:name} {\n\tsyntax: '<${2:length}>';\n\tinherits: ${3:false};\n\tinitial-value: ${4:0};\n}", "scope": "scope (${1:.card}) {\n\t$0\n}",
        "starting-style": "starting-style {\n\t$0\n}", "counter-style": "counter-style ${1:name} {\n\t$0\n}", "font-feature-values": "font-feature-values ${1:Font} {\n\t$0\n}",
        "view-transition": "view-transition {\n\tnavigation: auto;\n}",
    ]

    static let atRules: [(name: String, doc: String, snippet: String)] = NWWebDataGen.cssAtRules.compactMap { line in
        let f = line.split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
        guard let n = f.first, n.hasPrefix("@") else { return nil }
        let name = String(n.dropFirst())
        if name.hasPrefix("-") && !["-webkit-keyframes"].contains(name) { return nil }
        return (name, f.count > 1 ? String(f[1]) : "", atSnippets[name] ?? name)
    }

    // Tailwind / PostCSS / Sass / Less additions are offered by the Tailwind service and by file language.
    static let sassAtRules: [(String, String)] = [("mixin", "Defines a mixin."), ("include", "Includes a mixin."), ("use", "Loads a module."), ("forward", "Re-exports a module."),
                                                  ("extend", "Extends another selector."), ("function", "Defines a function."), ("return", "Returns a value from a function."),
                                                  ("if", "Conditional."), ("else", "Else branch."), ("each", "Loops over a list or map."), ("for", "Loops over a range."),
                                                  ("while", "Loops while a condition holds."), ("debug", "Prints a debug message."), ("warn", "Prints a warning."),
                                                  ("error", "Throws an error."), ("at-root", "Emits rules at the document root."), ("content", "Placeholder for a mixin block.")]

    // MARK: pseudo classes / elements

    /// Selector functions: inserted with a parenthesis pair.
    static let functionalPseudos: Set<String> = ["not", "is", "where", "has", "nth-child", "nth-last-child", "nth-of-type", "nth-last-of-type", "lang", "dir", "host", "host-context", "state",
                                                 "part", "slotted", "highlight", "cue", "cue-region", "matches", "-webkit-any", "-moz-any", "active-view-transition-type", "picker",
                                                 "view-transition-group", "view-transition-image-pair", "view-transition-new", "view-transition-old", "has-slotted", "target-current"]

    private static func pseudoList(_ lines: [String], colons: Int) -> [(name: String, doc: String)] {
        var out: [(String, String)] = []
        var seen = Set<String>()
        for line in lines {
            let f = line.split(separator: "\u{1}", maxSplits: 1, omittingEmptySubsequences: false)
            guard let n = f.first else { continue }
            var name = String(n.drop { $0 == ":" })
            if name.isEmpty || !seen.insert(name).inserted { continue }
            if functionalPseudos.contains(name) { name += "()" }
            out.append((name, f.count > 1 ? String(f[1]) : ""))
        }
        return out.sorted { a, b in
            let av = a.0.hasPrefix("-"), bv = b.0.hasPrefix("-")
            return av != bv ? !av : a.0 < b.0
        }
    }
    static let pseudoClasses: [(name: String, doc: String)] = pseudoList(NWWebDataGen.cssPseudoClasses, colons: 1)
    static let pseudoElements: [(name: String, doc: String)] = pseudoList(NWWebDataGen.cssPseudoElements, colons: 2)

    // MARK: functions, units, colors

    static let valueFunctions: [(String, String)] = [
        ("var()", "var(--name, fallback)"), ("calc()", "calc(a + b)"), ("min()", "min(a, b)"), ("max()", "max(a, b)"), ("clamp()", "clamp(min, preferred, max)"),
        ("rgb()", "rgb(r g b / a)"), ("rgba()", "rgba(r, g, b, a)"), ("hsl()", "hsl(h s l / a)"), ("hsla()", "hsla(h, s, l, a)"), ("hwb()", "hwb(h w b)"),
        ("oklch()", "oklch(l c h)"), ("oklab()", "oklab(l a b)"), ("lab()", "lab(l a b)"), ("lch()", "lch(l c h)"), ("color-mix()", "color-mix(in srgb, a, b)"),
        ("color()", "color(srgb r g b)"), ("light-dark()", "light-dark(light, dark)"), ("url()", "url(path)"), ("linear-gradient()", "linear-gradient(angle, stops)"),
        ("radial-gradient()", "radial-gradient(shape, stops)"), ("conic-gradient()", "conic-gradient(from angle, stops)"), ("repeating-linear-gradient()", "repeating-linear-gradient"),
        ("env()", "env(safe-area-inset-top)"), ("attr()", "attr(name)"), ("counter()", "counter(name)"), ("minmax()", "minmax(min, max)"), ("repeat()", "repeat(n, track)"),
        ("fit-content()", "fit-content(limit)"), ("translate()", "translate(x, y)"), ("scale()", "scale(x, y)"), ("rotate()", "rotate(angle)"), ("blur()", "blur(radius)"),
        ("cubic-bezier()", "cubic-bezier(a, b, c, d)"), ("steps()", "steps(n, jump)"),
    ]

    static let units = ["px", "rem", "em", "%", "vh", "vw", "vmin", "vmax", "dvh", "svh", "lvh", "dvw", "ch", "ex", "cm", "mm", "in", "pt", "pc", "fr", "deg", "rad", "turn", "s", "ms", "cqw", "cqh"]

    static let namedColors: [String: String] = {
        var d: [String: String] = [:]
        let table = """
        aliceblue f0f8ff antiquewhite faebd7 aqua 00ffff aquamarine 7fffd4 azure f0ffff beige f5f5dc bisque ffe4c4 black 000000 blanchedalmond ffebcd blue 0000ff blueviolet 8a2be2 \
        brown a52a2a burlywood deb887 cadetblue 5f9ea0 chartreuse 7fff00 chocolate d2691e coral ff7f50 cornflowerblue 6495ed cornsilk fff8dc crimson dc143c cyan 00ffff \
        darkblue 00008b darkcyan 008b8b darkgoldenrod b8860b darkgray a9a9a9 darkgreen 006400 darkgrey a9a9a9 darkkhaki bdb76b darkmagenta 8b008b darkolivegreen 556b2f \
        darkorange ff8c00 darkorchid 9932cc darkred 8b0000 darksalmon e9967a darkseagreen 8fbc8f darkslateblue 483d8b darkslategray 2f4f4f darkslategrey 2f4f4f \
        darkturquoise 00ced1 darkviolet 9400d3 deeppink ff1493 deepskyblue 00bfff dimgray 696969 dimgrey 696969 dodgerblue 1e90ff firebrick b22222 floralwhite fffaf0 \
        forestgreen 228b22 fuchsia ff00ff gainsboro dcdcdc ghostwhite f8f8ff gold ffd700 goldenrod daa520 gray 808080 green 008000 greenyellow adff2f grey 808080 \
        honeydew f0fff0 hotpink ff69b4 indianred cd5c5c indigo 4b0082 ivory fffff0 khaki f0e68c lavender e6e6fa lavenderblush fff0f5 lawngreen 7cfc00 lemonchiffon fffacd \
        lightblue add8e6 lightcoral f08080 lightcyan e0ffff lightgoldenrodyellow fafad2 lightgray d3d3d3 lightgreen 90ee90 lightgrey d3d3d3 lightpink ffb6c1 \
        lightsalmon ffa07a lightseagreen 20b2aa lightskyblue 87cefa lightslategray 778899 lightslategrey 778899 lightsteelblue b0c4de lightyellow ffffe0 lime 00ff00 \
        limegreen 32cd32 linen faf0e6 magenta ff00ff maroon 800000 mediumaquamarine 66cdaa mediumblue 0000cd mediumorchid ba55d3 mediumpurple 9370db mediumseagreen 3cb371 \
        mediumslateblue 7b68ee mediumspringgreen 00fa9a mediumturquoise 48d1cc mediumvioletred c71585 midnightblue 191970 mintcream f5fffa mistyrose ffe4e1 moccasin ffe4b5 \
        navajowhite ffdead navy 000080 oldlace fdf5e6 olive 808000 olivedrab 6b8e23 orange ffa500 orangered ff4500 orchid da70d6 palegoldenrod eee8aa palegreen 98fb98 \
        paleturquoise afeeee palevioletred db7093 papayawhip ffefd5 peachpuff ffdab9 peru cd853f pink ffc0cb plum dda0dd powderblue b0e0e6 purple 800080 rebeccapurple 663399 \
        red ff0000 rosybrown bc8f8f royalblue 4169e1 saddlebrown 8b4513 salmon fa8072 sandybrown f4a460 seagreen 2e8b57 seashell fff5ee sienna a0522d silver c0c0c0 \
        skyblue 87ceeb slateblue 6a5acd slategray 708090 slategrey 708090 snow fffafa springgreen 00ff7f steelblue 4682b4 tan d2b48c teal 008080 thistle d8bfd8 tomato ff6347 \
        turquoise 40e0d0 violet ee82ee wheat f5deb3 white ffffff whitesmoke f5f5f5 yellow ffff00 yellowgreen 9acd32
        """
        let t = table.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\\" }).map(String.init).filter { !$0.isEmpty }
        var i = 0
        while i + 1 < t.count { d[t[i]] = "#" + t[i + 1]; i += 2 }
        return d
    }()

    static let mediaFeatures = ["width", "min-width", "max-width", "height", "min-height", "max-height", "aspect-ratio", "orientation", "resolution", "prefers-color-scheme",
                                "prefers-reduced-motion", "prefers-contrast", "hover", "pointer", "any-hover", "display-mode", "min-resolution", "max-resolution", "forced-colors", "color", "scripting"]

    static let tagNames: Set<String> = Set(NWHtmlData.tags.map(\.name))

    /// Parses `#rgb`, `#rrggbb`, `#rrggbbaa` into 0...255 components + alpha 0...1.
    static func parseHex(_ s: String) -> (r: Int, g: Int, b: Int, a: Double)? {
        var h = s
        if h.hasPrefix("#") { h.removeFirst() }
        let digits = Array(h.utf8)
        guard digits.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) || ($0 >= 65 && $0 <= 70) }) else { return nil }
        func hex(_ a: Int, _ n: Int) -> Int { Int(String(h[h.index(h.startIndex, offsetBy: a)..<h.index(h.startIndex, offsetBy: a + n)]), radix: 16) ?? 0 }
        switch h.count {
        case 3: return (hex(0, 1) * 17, hex(1, 1) * 17, hex(2, 1) * 17, 1)
        case 4: return (hex(0, 1) * 17, hex(1, 1) * 17, hex(2, 1) * 17, Double(hex(3, 1) * 17) / 255)
        case 6: return (hex(0, 2), hex(2, 2), hex(4, 2), 1)
        case 8: return (hex(0, 2), hex(2, 2), hex(4, 2), Double(hex(6, 2)) / 255)
        default: return nil
        }
    }
}
