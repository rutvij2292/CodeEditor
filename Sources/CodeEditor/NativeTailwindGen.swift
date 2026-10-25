import Foundation

typealias NWDecls = [(String, String)]

struct NWUtil {
    var decls: NWDecls
    var selSuffix = ""          // e.g. " > :not([hidden]) ~ :not([hidden])" (space-x, divide), "::placeholder"
    var extra = ""              // text emitted before the rule (keyframes)
}

struct NWFamily {
    let prefix: String
    /// `value` is the part after `prefix-` ("" for the bare prefix). `neg` = leading `-`.
    let resolve: (NWTailwind, String, Bool) -> NWUtil?
    /// Value names offered by completion (nil: none). `bare` = the prefix alone is a class.
    let keys: ((NWTailwind) -> [String])?
    let bare: Bool
    var negatable = false
}

// MARK: - Value helpers

extension NWTailwind {
    static let colorKeywords: Set<String> = ["transparent", "currentcolor", "inherit"]

    /// `[...]` -> css value (underscores to spaces, type hint removed); `(--x)` -> var(--x). nil when not arbitrary.
    func arbitrary(_ s: String) -> (value: String, hint: String)? {
        var inner: String
        if s.hasPrefix("["), s.hasSuffix("]"), s.count > 2 { inner = String(s.dropFirst().dropLast()) }
        else if s.hasPrefix("(--"), s.hasSuffix(")") { return ("var(" + s.dropFirst().dropLast() + ")", "") }
        else if s.hasPrefix("(") && s.hasSuffix(")") && s.count > 2, let colon = s.firstIndex(of: ":") { return ("var(" + s[s.index(after: colon)...].dropLast() + ")", String(s[s.index(after: s.startIndex)..<colon])) }
        else { return nil }
        var hint = ""
        if let colon = inner.firstIndex(of: ":"), !inner.hasPrefix("url("), !inner.contains("("), !inner[inner.startIndex..<colon].contains("-") || ["font-family", "absolute-size", "relative-size"].contains(String(inner[inner.startIndex..<colon])) {
            let h = String(inner[inner.startIndex..<colon])
            if h.allSatisfy({ $0.isLetter || $0 == "-" }) { hint = h; inner = String(inner[inner.index(after: colon)...]) }
        } else if let colon = inner.firstIndex(of: ":"), !inner.hasPrefix("url("), ["length", "color", "percentage", "number", "image", "position", "size", "url", "angle", "ratio", "shadow", "family-name", "line-width", "integer"].contains(String(inner[inner.startIndex..<colon])) {
            hint = String(inner[inner.startIndex..<colon]); inner = String(inner[inner.index(after: colon)...])
        }
        var out = ""
        var it = inner.makeIterator()
        var prev: Character?
        while let ch = it.next() {
            if ch == "_" { out.append(prev == "\\" ? "_" : " ") }
            else if ch == "\\", prev != "\\" { }
            else { out.append(ch) }
            prev = ch
        }
        return (out, hint)
    }

    func isColorish(_ v: String) -> Bool {
        let l = v.lowercased()
        if l.hasPrefix("#") { return NWCssData.parseHex(l) != nil }
        for p in ["rgb(", "rgba(", "hsl(", "hsla(", "hwb(", "oklch(", "oklab(", "lab(", "lch(", "color(", "color-mix(", "light-dark("] where l.hasPrefix(p) { return true }
        return NWCssData.namedColors[l] != nil || NWTailwind.colorKeywords.contains(l)
    }

    func spacingMap(_ key: String) -> [String: String] {
        if let m = maps[key], !m.isEmpty { return m }
        return maps["spacing"] ?? [:]
    }

    static func negate(_ v: String) -> String {
        if v == "0px" || v == "0" || v.hasPrefix("calc(") && v.hasSuffix("* -1)") { return v }
        if v.hasPrefix("-") { return String(v.dropFirst()) }
        if v.hasPrefix("calc(") || v.hasPrefix("var(") || v.contains(" ") { return "calc(\(v) * -1)" }
        return "-" + v
    }

    static func fraction(_ s: String) -> String? {
        let p = s.split(separator: "/")
        guard p.count == 2, let a = Double(p[0]), let b = Double(p[1]), b != 0, a >= 0 else { return nil }
        let pct = a / b * 100
        if pct == pct.rounded() { return "\(Int(pct))%" }
        return String(format: "%.6f", pct).replacingOccurrences(of: "0+$", with: "", options: .regularExpression) + "%"
    }

    /// Spacing-scale value by name: theme, arbitrary, v4 numeric multiples, fractions and the extras.
    func spacing(_ name: String, key: String = "spacing", neg: Bool = false, extras: [String: String] = [:], fractions: Bool = false) -> String? {
        var v: String?
        if let a = arbitrary(name) { v = a.value }
        else if let e = extras[name] { v = e }
        else if let t = spacingMap(key)[name] { v = t }
        else if version >= 4, let n = Double(name), n >= 0, spacingBase != nil || maps["spacing"]?["1"] != nil {
            v = "calc(var(--spacing) * \(name))"
            _ = n
        }
        else if fractions, let f = NWTailwind.fraction(name) { v = f }
        guard var value = v else { return nil }
        if neg { value = NWTailwind.negate(value) }
        return value
    }

    // MARK: colors

    func colorValue(_ name: String) -> String? { colors[name] }

    /// Resolves `red-500`, `red-500/50`, `[#fff]`, `[#fff]/50`, `(--c)` to a css color (and whether it came from the theme).
    private func colorParts(_ full: String) -> (base: String, themeName: String?, alpha: String?)? {
        var base = full, mod: String?
        if let slash = topLevelSlash(full) { base = String(full[full.startIndex..<slash]); mod = String(full[full.index(after: slash)...]) }
        var themeName: String?
        var value: String?
        if let a = arbitrary(base) {
            guard a.hint == "color" || a.hint.isEmpty && isColorish(a.value) || a.value.hasPrefix("var(") && a.hint.isEmpty && false else { return nil }
            value = a.value
        } else if let c = colors[base] { value = c; themeName = base }
        guard let v = value else { return nil }
        var alpha: String?
        if let m = mod {
            if let a = arbitrary(m) { alpha = a.value }
            else if let n = Double(m), n >= 0, n <= 100 { alpha = formatAlpha(n / 100) }
            else if m.hasSuffix("%") { alpha = m }
            else { return nil }
        }
        return (v, themeName, alpha)
    }

    func topLevelSlash(_ s: String) -> String.Index? {
        var depth = 0
        var last: String.Index?
        for i in s.indices {
            let c = s[i]
            if c == "[" || c == "(" { depth += 1 } else if c == "]" || c == ")" { depth -= 1 }
            else if c == "/", depth == 0 { last = i }
        }
        return last
    }

    func formatAlpha(_ v: Double) -> String {
        var s = String(format: "%.3f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    func rgbTriplet(_ hex: String) -> String? {
        guard let c = NWCssData.parseHex(hex), c.a == 1 else { return nil }
        return "\(c.r) \(c.g) \(c.b)"
    }

    /// Declarations setting `props` to the color named by `full`; `opVar` = the v3 opacity custom property name (nil for plain output).
    func colorDecls(_ full: String, props: [String], opVar: String?) -> NWDecls? {
        guard let p = colorParts(full) else { return nil }
        let lower = p.base.lowercased()
        func set(_ v: String) -> NWDecls { props.map { ($0, v) } }
        if version >= 4 {
            let ref = p.themeName.map { "var(--color-\($0))" } ?? p.base
            if let a = p.alpha { return set("color-mix(in oklab, \(ref) \(a.hasSuffix("%") ? a : (Double(a).map { String(Int(($0 * 100).rounded())) + "%" } ?? a)), transparent)") }
            return set(ref)
        }
        if let a = p.alpha {
            if let t = rgbTriplet(p.base) { return set("rgb(\(t) / \(a))") }
            if lower == "transparent" || lower == "currentcolor" || lower == "inherit" { return set(p.base) }
            if p.base.contains("<alpha-value>") { return set(p.base.replacingOccurrences(of: "<alpha-value>", with: a)) }
            return set("color-mix(in srgb, \(p.base) \(a.hasSuffix("%") ? a : (Double(a).map { String(Int(($0 * 100).rounded())) + "%" } ?? a)), transparent)")
        }
        if let ov = opVar {
            if let t = rgbTriplet(p.base) { return [("--tw-\(ov)", "1")] + props.map { ($0, "rgb(\(t) / var(--tw-\(ov), 1))") } }
            if p.base.contains("<alpha-value>") { return [("--tw-\(ov)", "1")] + set(p.base.replacingOccurrences(of: "<alpha-value>", with: "var(--tw-\(ov), 1)")) }
        }
        return set(p.base.replacingOccurrences(of: "<alpha-value>", with: "1"))
    }

    // MARK: theme-or-arbitrary values

    func themed(_ key: String, _ name: String) -> String? {
        if let a = arbitrary(name) { return a.value }
        if name.isEmpty { return maps[key]?["DEFAULT"] }
        return maps[key]?[name]
    }

    func refValue(_ key: String, _ name: String, v4Var: String) -> String? {
        guard let v = themed(key, name) else { return nil }
        if version >= 4, arbitrary(name) == nil, let m = maps[key], m[name.isEmpty ? "DEFAULT" : name] != nil { return "var(--\(v4Var)\(name.isEmpty ? "" : "-" + name))" }
        return v
    }
}

// MARK: - Families

enum NWFamilies {
    static let all: [NWFamily] = {
        var f: [NWFamily] = []

        func spacingFam(_ prefix: String, _ props: [String], key: String = "spacing", neg: Bool = false, extras: [String: String] = [:], fractions: Bool = false, twelfths: Bool = true, bare: Bool = false) {
            f.append(NWFamily(prefix: prefix, resolve: { tw, v, n in
                guard let val = tw.spacing(v, key: key, neg: n, extras: extras, fractions: fractions) else { return nil }
                return NWUtil(decls: props.map { ($0, val) })
            }, keys: { tw in Array(tw.spacingMap(key).keys) + Array(extras.keys) + (fractions ? (twelfths ? NWFamilies.fractionKeys : NWFamilies.fractionKeys.filter { !$0.hasSuffix("/12") }) : []) },
            bare: bare, negatable: neg))
        }
        let auto = ["auto": "auto"]
        // padding / margin / gap / inset / scroll
        for (s, props) in [("", ["padding"]), ("x", ["padding-left", "padding-right"]), ("y", ["padding-top", "padding-bottom"]), ("t", ["padding-top"]), ("r", ["padding-right"]),
                           ("b", ["padding-bottom"]), ("l", ["padding-left"]), ("s", ["padding-inline-start"]), ("e", ["padding-inline-end"])] {
            spacingFam("p" + s, props, key: "padding")
        }
        for (s, props) in [("", ["margin"]), ("x", ["margin-left", "margin-right"]), ("y", ["margin-top", "margin-bottom"]), ("t", ["margin-top"]), ("r", ["margin-right"]),
                           ("b", ["margin-bottom"]), ("l", ["margin-left"]), ("s", ["margin-inline-start"]), ("e", ["margin-inline-end"])] {
            spacingFam("m" + s, props, key: "margin", neg: true, extras: auto)
        }
        for (s, props) in [("", ["scroll-margin"]), ("x", ["scroll-margin-left", "scroll-margin-right"]), ("y", ["scroll-margin-top", "scroll-margin-bottom"]), ("t", ["scroll-margin-top"]),
                           ("r", ["scroll-margin-right"]), ("b", ["scroll-margin-bottom"]), ("l", ["scroll-margin-left"])] {
            spacingFam("scroll-m" + s, props, neg: true)
        }
        for (s, props) in [("", ["scroll-padding"]), ("x", ["scroll-padding-left", "scroll-padding-right"]), ("y", ["scroll-padding-top", "scroll-padding-bottom"]), ("t", ["scroll-padding-top"]),
                           ("r", ["scroll-padding-right"]), ("b", ["scroll-padding-bottom"]), ("l", ["scroll-padding-left"])] {
            spacingFam("scroll-p" + s, props)
        }
        spacingFam("gap", ["gap"], key: "gap"); spacingFam("gap-x", ["column-gap"], key: "gap"); spacingFam("gap-y", ["row-gap"], key: "gap")
        let insetExtras = ["auto": "auto", "full": "100%"]
        spacingFam("inset", ["inset"], key: "inset", neg: true, extras: insetExtras, fractions: true)
        spacingFam("inset-x", ["left", "right"], key: "inset", neg: true, extras: insetExtras, fractions: true)
        spacingFam("inset-y", ["top", "bottom"], key: "inset", neg: true, extras: insetExtras, fractions: true)
        for side in ["top", "right", "bottom", "left"] { spacingFam(side, [side], key: "inset", neg: true, extras: insetExtras, fractions: true) }
        spacingFam("start", ["inset-inline-start"], key: "inset", neg: true, extras: insetExtras, fractions: true)
        spacingFam("end", ["inset-inline-end"], key: "inset", neg: true, extras: insetExtras, fractions: true)
        spacingFam("indent", ["text-indent"], neg: true)
        let wExtras = ["auto": "auto", "full": "100%", "screen": "100vw", "svw": "100svw", "lvw": "100lvw", "dvw": "100dvw", "min": "min-content", "max": "max-content", "fit": "fit-content"]
        let hExtras = ["auto": "auto", "full": "100%", "screen": "100vh", "svh": "100svh", "lvh": "100lvh", "dvh": "100dvh", "min": "min-content", "max": "max-content", "fit": "fit-content", "lh": "1lh"]
        spacingFam("w", ["width"], key: "width", extras: wExtras, fractions: true)
        spacingFam("h", ["height"], key: "height", extras: hExtras, fractions: true, twelfths: false)
        spacingFam("size", ["width", "height"], key: "size", extras: ["auto": "auto", "full": "100%", "min": "min-content", "max": "max-content", "fit": "fit-content"], fractions: true)
        spacingFam("min-w", ["min-width"], key: "minWidth", extras: ["full": "100%", "min": "min-content", "max": "max-content", "fit": "fit-content", "screen": "100vw", "auto": "auto"])
        spacingFam("min-h", ["min-height"], key: "minHeight", extras: ["full": "100%", "screen": "100vh", "min": "min-content", "max": "max-content", "fit": "fit-content", "svh": "100svh", "dvh": "100dvh", "auto": "auto"])
        spacingFam("max-h", ["max-height"], key: "maxHeight", extras: ["none": "none", "full": "100%", "screen": "100vh", "min": "min-content", "max": "max-content", "fit": "fit-content", "svh": "100svh", "dvh": "100dvh"])
        spacingFam("basis", ["flex-basis"], key: "flexBasis", extras: ["auto": "auto", "full": "100%"], fractions: true)
        spacingFam("translate-x", ["--tw-translate-x"], neg: true, extras: ["full": "100%"], fractions: true)
        spacingFam("translate-y", ["--tw-translate-y"], neg: true, extras: ["full": "100%"], fractions: true)
        f.append(NWFamily(prefix: "max-w", resolve: { tw, v, _ in
            if v.hasPrefix("screen-"), let s = tw.maps["screens"]?[String(v.dropFirst(7))] { return NWUtil(decls: [("max-width", s)]) }
            if let m = tw.maps["maxWidth"]?[v] ?? tw.arbitrary(v)?.value { return NWUtil(decls: [("max-width", tw.version >= 4 && tw.arbitrary(v) == nil && ["xs", "sm", "md", "lg", "xl", "2xl", "3xl", "4xl", "5xl", "6xl", "7xl"].contains(v) ? "var(--container-\(v))" : m)]) }
            if tw.version >= 4, let s = tw.spacing(v, key: "spacing") { return NWUtil(decls: [("max-width", s)]) }
            return nil
        }, keys: { tw in Array(tw.map("maxWidth").keys) + tw.map("screens").keys.map { "screen-" + $0 } }, bare: false))
        // translate / space helpers: the real transform declarations
        let transformChain = "translate(var(--tw-translate-x), var(--tw-translate-y)) rotate(var(--tw-rotate)) skewX(var(--tw-skew-x)) skewY(var(--tw-skew-y)) scaleX(var(--tw-scale-x)) scaleY(var(--tw-scale-y))"
        f = f.map { fam in
            guard fam.prefix.hasPrefix("translate-") else { return fam }
            return NWFamily(prefix: fam.prefix, resolve: { tw, v, n in
                guard var u = fam.resolve(tw, v, n) else { return nil }
                if tw.version < 4 { u.decls.append(("transform", transformChain)) }
                return u
            }, keys: fam.keys, bare: false, negatable: true)
        }
        for (axis, prop) in [("x", "margin-left"), ("y", "margin-top")] {
            f.append(NWFamily(prefix: "space-" + axis, resolve: { tw, v, n in
                if v == "reverse" { return NWUtil(decls: [("--tw-space-\(axis)-reverse", "1")], selSuffix: " > :not([hidden]) ~ :not([hidden])") }
                guard let val = tw.spacing(v, key: "space", neg: n) else { return nil }
                let (a, b) = axis == "x" ? ("margin-right", "margin-left") : ("margin-bottom", "margin-top")
                _ = prop
                return NWUtil(decls: [("--tw-space-\(axis)-reverse", "0"), (a, "calc(\(val) * var(--tw-space-\(axis)-reverse))"), (b, "calc(\(val) * calc(1 - var(--tw-space-\(axis)-reverse)))")],
                              selSuffix: " > :not([hidden]) ~ :not([hidden])")
            }, keys: { tw in Array(tw.spacingMap("space").keys) + ["reverse"] }, bare: false, negatable: true))
        }

        // theme value families
        func themeFam(_ prefix: String, _ key: String, _ props: [String], bare: Bool = false, neg: Bool = false, v4: String? = nil, transform: ((String) -> String)? = nil) {
            f.append(NWFamily(prefix: prefix, resolve: { tw, v, n in
                guard var val = v4.flatMap({ tw.refValue(key, v, v4Var: $0) }) ?? tw.themed(key, v) else { return nil }
                if let t = transform { val = t(val) }
                if n { val = NWTailwind.negate(val) }
                return NWUtil(decls: props.map { ($0, val) })
            }, keys: { tw in tw.map(key).keys.filter { $0 != "DEFAULT" } }, bare: bare, negatable: neg))
        }
        let corners: [(String, [String])] = [("", ["border-radius"]), ("t", ["border-top-left-radius", "border-top-right-radius"]), ("r", ["border-top-right-radius", "border-bottom-right-radius"]),
                                              ("b", ["border-bottom-right-radius", "border-bottom-left-radius"]), ("l", ["border-top-left-radius", "border-bottom-left-radius"]),
                                              ("tl", ["border-top-left-radius"]), ("tr", ["border-top-right-radius"]), ("br", ["border-bottom-right-radius"]), ("bl", ["border-bottom-left-radius"]),
                                              ("s", ["border-start-start-radius", "border-end-start-radius"]), ("e", ["border-start-end-radius", "border-end-end-radius"]),
                                              ("ss", ["border-start-start-radius"]), ("se", ["border-start-end-radius"]), ("ee", ["border-end-end-radius"]), ("es", ["border-end-start-radius"])]
        for (s, props) in corners { themeFam("rounded" + (s.isEmpty ? "" : "-" + s), "borderRadius", props, bare: true, v4: "radius") }
        themeFam("opacity", "opacity", ["opacity"])
        themeFam("z", "zIndex", ["z-index"], neg: true)
        themeFam("order", "order", ["order"], neg: true)
        themeFam("duration", "transitionDuration", ["transition-duration"], bare: true)
        themeFam("delay", "transitionDelay", ["transition-delay"])
        themeFam("ease", "transitionTimingFunction", ["transition-timing-function"], bare: true, v4: "ease")
        themeFam("aspect", "aspectRatio", ["aspect-ratio"], v4: "aspect")
        themeFam("columns", "columns", ["columns"], v4: "container")
        themeFam("leading", "lineHeight", ["line-height"], v4: "leading")
        themeFam("tracking", "letterSpacing", ["letter-spacing"], neg: true, v4: "tracking")
        themeFam("underline-offset", "textUnderlineOffset", ["text-underline-offset"], neg: true)
        themeFam("outline-offset", "outlineOffset", ["outline-offset"], neg: true)
        themeFam("grid-cols", "gridTemplateColumns", ["grid-template-columns"])
        themeFam("grid-rows", "gridTemplateRows", ["grid-template-rows"])
        themeFam("col", "gridColumn", ["grid-column"])
        themeFam("row", "gridRow", ["grid-row"])
        themeFam("col-start", "gridColumnStart", ["grid-column-start"]); themeFam("col-end", "gridColumnEnd", ["grid-column-end"])
        themeFam("row-start", "gridRowStart", ["grid-row-start"]); themeFam("row-end", "gridRowEnd", ["grid-row-end"])
        themeFam("rotate", "rotate", ["--tw-rotate"], neg: true)
        themeFam("scale", "scale", ["--tw-scale-x", "--tw-scale-y"])
        themeFam("scale-x", "scale", ["--tw-scale-x"]); themeFam("scale-y", "scale", ["--tw-scale-y"])
        themeFam("skew-x", "skew", ["--tw-skew-x"], neg: true); themeFam("skew-y", "skew", ["--tw-skew-y"], neg: true)
        // transforms: append the transform line in v3
        f = f.map { fam in
            guard ["rotate", "scale", "scale-x", "scale-y", "skew-x", "skew-y"].contains(fam.prefix) else { return fam }
            return NWFamily(prefix: fam.prefix, resolve: { tw, v, n in
                guard var u = fam.resolve(tw, v, n) else { return nil }
                if tw.version < 4 { u.decls.append(("transform", transformChain)) }
                else if fam.prefix == "rotate", let r = u.decls.first?.1 { u.decls = [("rotate", r)] }
                else if fam.prefix == "scale", let r = u.decls.first?.1 { u.decls = [("scale", r)] }
                return u
            }, keys: fam.keys, bare: false, negatable: fam.negatable)
        }
        // grid: spans and starts from numbers
        f.append(NWFamily(prefix: "col-span", resolve: { tw, v, _ in
            if v == "full" { return NWUtil(decls: [("grid-column", "1 / -1")]) }
            if let n = Int(v), n > 0 { return NWUtil(decls: [("grid-column", "span \(n) / span \(n)")]) }
            return tw.arbitrary(v).map { NWUtil(decls: [("grid-column", "span " + $0.value + " / span " + $0.value)]) }
        }, keys: { _ in (1...12).map(String.init) + ["full"] }, bare: false))
        f.append(NWFamily(prefix: "row-span", resolve: { tw, v, _ in
            if v == "full" { return NWUtil(decls: [("grid-row", "1 / -1")]) }
            if let n = Int(v), n > 0 { return NWUtil(decls: [("grid-row", "span \(n) / span \(n)")]) }
            return tw.arbitrary(v).map { NWUtil(decls: [("grid-row", "span " + $0.value + " / span " + $0.value)]) }
        }, keys: { _ in (1...6).map(String.init) + ["full"] }, bare: false))
        for (p, prop) in [("col-start", "grid-column-start"), ("col-end", "grid-column-end"), ("row-start", "grid-row-start"), ("row-end", "grid-row-end")] {
            f.append(NWFamily(prefix: p, resolve: { tw, v, n in
                if v == "auto" { return NWUtil(decls: [(prop, "auto")]) }
                if let k = Int(v) { return NWUtil(decls: [(prop, n ? "-\(k)" : "\(k)")]) }
                return tw.arbitrary(v).map { NWUtil(decls: [(prop, $0.value)]) }
            }, keys: { _ in (1...13).map(String.init) + ["auto"] }, bare: false, negatable: true))
        }
        f.append(NWFamily(prefix: "grid-cols", resolve: { tw, v, _ in
            if let val = tw.maps["gridTemplateColumns"]?[v] ?? tw.arbitrary(v)?.value { return NWUtil(decls: [("grid-template-columns", val)]) }
            if tw.version >= 4, let n = Int(v), n > 0 { return NWUtil(decls: [("grid-template-columns", "repeat(\(n), minmax(0, 1fr))")]) }
            return nil
        }, keys: { tw in Array(tw.map("gridTemplateColumns").keys) }, bare: false))
        f.append(NWFamily(prefix: "grid-rows", resolve: { tw, v, _ in
            if let val = tw.maps["gridTemplateRows"]?[v] ?? tw.arbitrary(v)?.value { return NWUtil(decls: [("grid-template-rows", val)]) }
            if tw.version >= 4, let n = Int(v), n > 0 { return NWUtil(decls: [("grid-template-rows", "repeat(\(n), minmax(0, 1fr))")]) }
            return nil
        }, keys: { tw in Array(tw.map("gridTemplateRows").keys) }, bare: false))
        f.append(NWFamily(prefix: "line-clamp", resolve: { tw, v, _ in
            guard let n = tw.themed("lineClamp", v) ?? (tw.version >= 4 ? Int(v).map(String.init) : nil) else { return nil }
            return NWUtil(decls: [("overflow", "hidden"), ("display", "-webkit-box"), ("-webkit-box-orient", "vertical"), ("-webkit-line-clamp", n)])
        }, keys: { tw in Array(tw.map("lineClamp").keys) }, bare: false))
        f.append(NWFamily(prefix: "animate", resolve: { tw, v, _ in
            guard let val = tw.themed("animation", v) else { return nil }
            var extra = ""
            let name = val.split(separator: " ").first.map(String.init) ?? ""
            if let kf = NWFamilies.keyframes[name], tw.arbitrary(v) == nil { extra = kf + "\n\n" }
            return NWUtil(decls: [("animation", tw.version >= 4 && tw.arbitrary(v) == nil ? "var(--animate-\(v))" : val)], extra: extra)
        }, keys: { tw in Array(tw.map("animation").keys) }, bare: false))

        // font size / weight / family
        f.append(NWFamily(prefix: "text", resolve: { tw, v, _ in
            var name = v, lh: String?
            if let slash = tw.topLevelSlash(v) { name = String(v[v.startIndex..<slash]); lh = String(v[v.index(after: slash)...]) }
            if let entry = tw.maps["fontSize"]?[name], tw.arbitrary(name) == nil {
                let parts = entry.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                var out: NWDecls = [("font-size", tw.version >= 4 ? "var(--text-\(name))" : parts[0])]
                if let l = lh {
                    out.append(("line-height", tw.themed("lineHeight", l) ?? tw.spacing(l, key: "spacing") ?? l))
                } else if parts.count > 1, !parts[1].isEmpty {
                    out.append(("line-height", tw.version >= 4 ? "var(--tw-leading, var(--text-\(name)--line-height))" : parts[1]))
                }
                return NWUtil(decls: out)
            }
            if let a = tw.arbitrary(name), a.hint == "length" || a.hint == "absolute-size" || a.hint == "relative-size" || a.hint.isEmpty && !tw.isColorish(a.value) && !a.value.hasPrefix("var(") || a.hint.isEmpty && a.value.hasPrefix("var(") && false {
                return NWUtil(decls: [("font-size", a.value)] + (lh.map { [("line-height", tw.themed("lineHeight", $0) ?? $0)] } ?? []))
            }
            return nil
        }, keys: { tw in Array(tw.map("fontSize").keys) }, bare: false))
        f.append(NWFamily(prefix: "font", resolve: { tw, v, _ in
            if let w = tw.maps["fontWeight"]?[v] { return NWUtil(decls: [("font-weight", tw.version >= 4 ? "var(--font-weight-\(v))" : w)]) }
            if let fam = tw.maps["fontFamily"]?[v] { return NWUtil(decls: [("font-family", tw.version >= 4 ? "var(--font-\(v))" : fam)]) }
            if let a = tw.arbitrary(v) {
                if a.hint == "family-name" || a.value.contains(",") || a.value.contains("'") || a.value.contains("\"") { return NWUtil(decls: [("font-family", a.value)]) }
                if Double(a.value) != nil || a.hint == "number" || a.hint == "weight" { return NWUtil(decls: [("font-weight", a.value)]) }
                return NWUtil(decls: [("font-family", a.value)])
            }
            return nil
        }, keys: { tw in Array(tw.map("fontWeight").keys) + Array(tw.map("fontFamily").keys) }, bare: false))

        // widths shared with colors
        func width(_ key: String, _ name: String, _ tw: NWTailwind) -> String? {
            if name.isEmpty { return tw.maps[key]?["DEFAULT"] }
            if let a = tw.arbitrary(name) { return a.hint == "length" || a.hint == "line-width" || a.hint.isEmpty && !tw.isColorish(a.value) && Double(a.value.filter { $0.isNumber || $0 == "." }) != nil && !a.value.hasPrefix("var(") ? a.value : nil }
            return tw.maps[key]?[name]
        }
        // borders: width (theme) or color
        for (s, wprops, cprops) in [("", ["border-width"], ["border-color"]), ("x", ["border-left-width", "border-right-width"], ["border-left-color", "border-right-color"]),
                                    ("y", ["border-top-width", "border-bottom-width"], ["border-top-color", "border-bottom-color"]), ("t", ["border-top-width"], ["border-top-color"]),
                                    ("r", ["border-right-width"], ["border-right-color"]), ("b", ["border-bottom-width"], ["border-bottom-color"]), ("l", ["border-left-width"], ["border-left-color"]),
                                    ("s", ["border-inline-start-width"], ["border-inline-start-color"]), ("e", ["border-inline-end-width"], ["border-inline-end-color"])] {
            let prefix = s.isEmpty ? "border" : "border-" + s
            f.append(NWFamily(prefix: prefix, resolve: { tw, v, _ in
                if let w = width("borderWidth", v, tw) {
                    return NWUtil(decls: wprops.map { ($0, w) } + (wprops.count == 1 && s.isEmpty ? [] : []) + [("border-style", "solid")].filter { _ in false })
                }
                return tw.colorDecls(v, props: cprops, opVar: "border-opacity").map { NWUtil(decls: $0) }
            }, keys: { tw in Array(tw.map("borderWidth").keys.filter { $0 != "DEFAULT" }) + Array(tw.colors.keys) }, bare: true))
        }
        // divide
        for axis in ["x", "y"] {
            f.append(NWFamily(prefix: "divide-" + axis, resolve: { tw, v, n in
                if v == "reverse" { return NWUtil(decls: [("--tw-divide-\(axis)-reverse", "1")], selSuffix: " > :not([hidden]) ~ :not([hidden])") }
                guard let w = width("divideWidth", v, tw) ?? width("borderWidth", v, tw) else { return nil }
                let rev = "--tw-divide-\(axis)-reverse"
                let (a, b) = axis == "x" ? ("border-right-width", "border-left-width") : ("border-bottom-width", "border-top-width")
                return NWUtil(decls: [(rev, "0"), (a, "calc(\(w) * var(\(rev)))"), (b, "calc(\(w) * calc(1 - var(\(rev))))")], selSuffix: " > :not([hidden]) ~ :not([hidden])")
            }, keys: { tw in Array(tw.map("divideWidth").keys.filter { $0 != "DEFAULT" }) + ["reverse"] }, bare: true))
        }
        f.append(NWFamily(prefix: "divide", resolve: { tw, v, _ in
            tw.colorDecls(v, props: ["border-color"], opVar: "divide-opacity").map { NWUtil(decls: $0, selSuffix: " > :not([hidden]) ~ :not([hidden])") }
        }, keys: { tw in Array(tw.colors.keys) }, bare: false))
        f.append(NWFamily(prefix: "placeholder", resolve: { tw, v, _ in
            tw.colorDecls(v, props: ["color"], opVar: "placeholder-opacity").map { NWUtil(decls: $0, selSuffix: "::placeholder") }
        }, keys: { tw in Array(tw.colors.keys) }, bare: false))
        // colors
        func colorFam(_ prefix: String, _ props: [String], op: String?) {
            f.append(NWFamily(prefix: prefix, resolve: { tw, v, _ in tw.colorDecls(v, props: props, opVar: op).map { NWUtil(decls: $0) } },
                              keys: { tw in Array(tw.colors.keys) }, bare: false))
        }
        colorFam("bg", ["background-color"], op: "bg-opacity")
        colorFam("accent", ["accent-color"], op: nil); colorFam("caret", ["caret-color"], op: nil)
        colorFam("decoration", ["text-decoration-color"], op: nil)
        f.append(NWFamily(prefix: "bg", resolve: { tw, v, _ in
            guard let a = tw.arbitrary(v) else { return nil }
            if a.hint == "url" || a.hint == "image" || a.value.hasPrefix("url(") || a.value.contains("gradient(") { return NWUtil(decls: [("background-image", a.value)]) }
            if a.hint == "length" || a.hint == "size" { return NWUtil(decls: [("background-size", a.value)]) }
            if a.hint == "position" { return NWUtil(decls: [("background-position", a.value)]) }
            if a.hint == "color" || tw.isColorish(a.value) { return nil }
            return NWUtil(decls: [("background-color", a.value)])
        }, keys: nil, bare: false))
        // text color (after font size)
        f.append(NWFamily(prefix: "text", resolve: { tw, v, _ in tw.colorDecls(v, props: ["color"], opVar: "text-opacity").map { NWUtil(decls: $0) } },
                          keys: { tw in Array(tw.colors.keys) }, bare: false))
        f.append(NWFamily(prefix: "fill", resolve: { tw, v, _ in tw.colorDecls(v, props: ["fill"], opVar: nil).map { NWUtil(decls: $0) } }, keys: { tw in Array(tw.colors.keys) }, bare: false))
        f.append(NWFamily(prefix: "stroke", resolve: { tw, v, _ in
            if let w = width("strokeWidth", v, tw) { return NWUtil(decls: [("stroke-width", w)]) }
            return tw.colorDecls(v, props: ["stroke"], opVar: nil).map { NWUtil(decls: $0) }
        }, keys: { tw in Array(tw.colors.keys) + Array(tw.map("strokeWidth").keys) }, bare: false))
        f.append(NWFamily(prefix: "decoration", resolve: { tw, v, _ in
            width("textDecorationThickness", v, tw).map { NWUtil(decls: [("text-decoration-thickness", $0)]) }
        }, keys: { tw in Array(tw.map("textDecorationThickness").keys) }, bare: false))
        f.append(NWFamily(prefix: "outline", resolve: { tw, v, _ in
            if let w = width("outlineWidth", v, tw) { return NWUtil(decls: [("outline-width", w)]) }
            return tw.colorDecls(v, props: ["outline-color"], opVar: nil).map { NWUtil(decls: $0) }
        }, keys: { tw in Array(tw.colors.keys) + Array(tw.map("outlineWidth").keys) }, bare: false))
        // ring
        let ringShadow: (String) -> NWDecls = { w in
            [("--tw-ring-offset-shadow", "var(--tw-ring-inset) 0 0 0 var(--tw-ring-offset-width) var(--tw-ring-offset-color)"),
             ("--tw-ring-shadow", "var(--tw-ring-inset) 0 0 0 calc(\(w) + var(--tw-ring-offset-width)) var(--tw-ring-color)"),
             ("box-shadow", "var(--tw-ring-offset-shadow), var(--tw-ring-shadow), var(--tw-shadow, 0 0 #0000)")]
        }
        f.append(NWFamily(prefix: "ring", resolve: { tw, v, _ in
            if let w = width("ringWidth", v, tw) { return NWUtil(decls: ringShadow(w)) }
            if v == "inset" { return NWUtil(decls: [("--tw-ring-inset", "inset")]) }
            return tw.colorDecls(v, props: ["--tw-ring-color"], opVar: "ring-opacity").map { NWUtil(decls: $0) }
        }, keys: { tw in Array(tw.colors.keys) + Array(tw.map("ringWidth").keys.filter { $0 != "DEFAULT" }) + ["inset"] }, bare: true))
        f.append(NWFamily(prefix: "ring-offset", resolve: { tw, v, _ in
            if let w = width("ringOffsetWidth", v, tw) { return NWUtil(decls: [("--tw-ring-offset-width", w), ("box-shadow", "var(--tw-ring-offset-shadow), var(--tw-ring-shadow), var(--tw-shadow, 0 0 #0000)")].filter { $0.0 != "box-shadow" }) }
            return tw.colorDecls(v, props: ["--tw-ring-offset-color"], opVar: nil).map { NWUtil(decls: $0) }
        }, keys: { tw in Array(tw.colors.keys) + Array(tw.map("ringOffsetWidth").keys) }, bare: false))
        // shadow
        f.append(NWFamily(prefix: "shadow", resolve: { tw, v, _ in
            var val = tw.version >= 4 && tw.arbitrary(v) == nil && tw.maps["boxShadow"]?[v.isEmpty ? "DEFAULT" : v] != nil ? "var(--shadow-\(v))" : nil
            let raw = tw.themed("boxShadow", v)
            if val == nil { val = raw }
            if let a = tw.arbitrary(v), a.hint == "color" || tw.isColorish(a.value) { return NWUtil(decls: [("--tw-shadow-color", a.value), ("--tw-shadow", "var(--tw-shadow-colored)")]) }
            guard let value = val, let r = raw else {
                return tw.colorDecls(v, props: ["--tw-shadow-color"], opVar: nil).map { NWUtil(decls: $0 + [("--tw-shadow", "var(--tw-shadow-colored)")]) }
            }
            let colored = r.replacingOccurrences(of: "(rgb\\([^)]*\\)|#[0-9a-fA-F]{3,8})", with: "var(--tw-shadow-color)", options: .regularExpression)
            return NWUtil(decls: [("--tw-shadow", value), ("--tw-shadow-colored", colored), ("box-shadow", "var(--tw-ring-offset-shadow, 0 0 #0000), var(--tw-ring-shadow, 0 0 #0000), var(--tw-shadow)")])
        }, keys: { tw in Array(tw.map("boxShadow").keys.filter { $0 != "DEFAULT" }) + Array(tw.colors.keys) }, bare: true))
        // v3 opacity utilities (deprecated in v3.4, removed in v4)
        for (p, v) in [("bg", "bg"), ("text", "text"), ("border", "border"), ("divide", "divide"), ("placeholder", "placeholder"), ("ring", "ring"), ("ring-offset", "ring-offset")] where p != "ring-offset" {
            f.append(NWFamily(prefix: p + "-opacity", resolve: { tw, val, _ in
                guard tw.version < 4, let o = tw.themed("opacity", val) else { return nil }
                return NWUtil(decls: [("--tw-\(v)-opacity", o)], selSuffix: p == "divide" ? " > :not([hidden]) ~ :not([hidden])" : (p == "placeholder" ? "::placeholder" : ""))
            }, keys: { tw in tw.version < 4 ? Array(tw.map("opacity").keys) : [] }, bare: false))
        }
        // gradient stops
        for (p, key) in [("from", "from"), ("via", "via"), ("to", "to")] {
            f.append(NWFamily(prefix: p, resolve: { tw, v, _ in
                guard let cd = tw.colorDecls(v, props: ["--c"], opVar: nil), let color = cd.first(where: { $0.0 == "--c" })?.1 else { return nil }
                let transparent: String = {
                    if let t = tw.rgbTriplet(color) { return "rgb(\(t) / 0)" }
                    return "transparent"
                }()
                switch key {
                case "from": return NWUtil(decls: [("--tw-gradient-from", "\(color) var(--tw-gradient-from-position)"), ("--tw-gradient-to", "\(transparent) var(--tw-gradient-to-position)"),
                                                   ("--tw-gradient-stops", "var(--tw-gradient-from), var(--tw-gradient-to)")])
                case "via": return NWUtil(decls: [("--tw-gradient-to", "\(transparent) var(--tw-gradient-to-position)"),
                                                  ("--tw-gradient-stops", "var(--tw-gradient-from), \(color) var(--tw-gradient-via-position), var(--tw-gradient-to)")])
                default: return NWUtil(decls: [("--tw-gradient-to", "\(color) var(--tw-gradient-to-position)")])
                }
            }, keys: { tw in Array(tw.colors.keys) }, bare: false))
        }
        // filters
        func filterFam(_ prefix: String, _ key: String, _ fn: String, backdrop: Bool, neg: Bool = false, bare: Bool = true) {
            let pre = backdrop ? "backdrop-" : ""
            let chain = backdrop ? "var(--tw-backdrop-blur) var(--tw-backdrop-brightness) var(--tw-backdrop-contrast) var(--tw-backdrop-grayscale) var(--tw-backdrop-hue-rotate) var(--tw-backdrop-invert) var(--tw-backdrop-opacity) var(--tw-backdrop-saturate) var(--tw-backdrop-sepia)"
                : "var(--tw-blur) var(--tw-brightness) var(--tw-contrast) var(--tw-grayscale) var(--tw-hue-rotate) var(--tw-invert) var(--tw-saturate) var(--tw-sepia) var(--tw-drop-shadow)"
            f.append(NWFamily(prefix: (backdrop ? "backdrop-" : "") + prefix, resolve: { tw, v, n in
                guard var val = tw.themed(key, v) else { return nil }
                if n { val = NWTailwind.negate(val) }
                let variable = "--tw-" + pre + fn
                return NWUtil(decls: [(variable, "\(fn)(\(val))"), (backdrop ? "backdrop-filter" : "filter", chain)])
            }, keys: { tw in Array(tw.map(key).keys.filter { $0 != "DEFAULT" }) }, bare: bare, negatable: neg))
        }
        for backdrop in [false, true] {
            filterFam("blur", "blur", "blur", backdrop: backdrop)
            filterFam("brightness", "brightness", "brightness", backdrop: backdrop, bare: false)
            filterFam("contrast", "contrast", "contrast", backdrop: backdrop, bare: false)
            filterFam("grayscale", "grayscale", "grayscale", backdrop: backdrop)
            filterFam("hue-rotate", "hueRotate", "hue-rotate", backdrop: backdrop, neg: true, bare: false)
            filterFam("invert", "invert", "invert", backdrop: backdrop)
            filterFam("saturate", "saturate", "saturate", backdrop: backdrop, bare: false)
            filterFam("sepia", "sepia", "sepia", backdrop: backdrop)
        }
        f.append(NWFamily(prefix: "backdrop-opacity", resolve: { tw, v, _ in
            tw.themed("opacity", v).map { NWUtil(decls: [("--tw-backdrop-opacity", "opacity(\($0))"), ("backdrop-filter", "var(--tw-backdrop-blur) var(--tw-backdrop-brightness) var(--tw-backdrop-contrast) var(--tw-backdrop-grayscale) var(--tw-backdrop-hue-rotate) var(--tw-backdrop-invert) var(--tw-backdrop-opacity) var(--tw-backdrop-saturate) var(--tw-backdrop-sepia)")]) }
        }, keys: { tw in Array(tw.map("opacity").keys) }, bare: false))
        f.append(NWFamily(prefix: "content", resolve: { tw, v, _ in
            tw.arbitrary(v).map { NWUtil(decls: [("--tw-content", $0.value), ("content", "var(--tw-content)")]) }
        }, keys: nil, bare: false))
        f.append(NWFamily(prefix: "list", resolve: { tw, v, _ in
            tw.arbitrary(v).map { NWUtil(decls: [("list-style-type", $0.value)]) }
        }, keys: nil, bare: false))
        f.append(NWFamily(prefix: "perspective", resolve: { tw, v, _ in tw.arbitrary(v).map { NWUtil(decls: [("perspective", $0.value)]) } }, keys: nil, bare: false))
        f.append(NWFamily(prefix: "flex", resolve: { tw, v, _ in
            if let a = tw.arbitrary(v) { return NWUtil(decls: [("flex", a.value)]) }
            if let n = Double(v), n >= 0 { return NWUtil(decls: [("flex", "\(v) \(v) 0%")]) }
            return nil
        }, keys: nil, bare: false))
        f.append(NWFamily(prefix: "grow", resolve: { tw, v, _ in tw.arbitrary(v).map { NWUtil(decls: [("flex-grow", $0.value)]) } }, keys: nil, bare: false))
        f.append(NWFamily(prefix: "shrink", resolve: { tw, v, _ in tw.arbitrary(v).map { NWUtil(decls: [("flex-shrink", $0.value)]) } }, keys: nil, bare: false))
        for (axis, other) in [("x", "y"), ("y", "x")] {
            f.append(NWFamily(prefix: "border-spacing-" + axis, resolve: { tw, v, _ in
                tw.spacing(v).map { NWUtil(decls: [("--tw-border-spacing-\(axis)", $0), ("border-spacing", "var(--tw-border-spacing-x) var(--tw-border-spacing-y)")]) }
            }, keys: { tw in Array(tw.spacingMap("spacing").keys) }, bare: false))
            _ = other
        }
        f.append(NWFamily(prefix: "border-spacing", resolve: { tw, v, _ in
            tw.spacing(v).map { NWUtil(decls: [("--tw-border-spacing-x", $0), ("--tw-border-spacing-y", $0), ("border-spacing", "var(--tw-border-spacing-x) var(--tw-border-spacing-y)")]) }
        }, keys: { tw in Array(tw.spacingMap("spacing").keys) }, bare: false))
        return f.enumerated().sorted { a, b in
            if a.element.prefix.count != b.element.prefix.count { return a.element.prefix.count > b.element.prefix.count }
            return a.offset < b.offset
        }.map(\.element)
    }()

    /// Fractions Tailwind generates for widths, insets and the like: halves .. twelfths.
    static let fractionKeys: [String] = {
        var out: [String] = []
        for d in [2, 3, 4, 5, 6, 12] { for n in 1..<d { out.append("\(n)/\(d)") } }
        return out
    }()

    static let keyframes: [String: String] = [
        "spin": "@keyframes spin {\n  to {\n    transform: rotate(360deg);\n  }\n}",
        "ping": "@keyframes ping {\n  75%, 100% {\n    transform: scale(2);\n    opacity: 0;\n  }\n}",
        "pulse": "@keyframes pulse {\n  50% {\n    opacity: .5;\n  }\n}",
        "bounce": "@keyframes bounce {\n  0%, 100% {\n    transform: translateY(-25%);\n    animation-timing-function: cubic-bezier(0.8, 0, 1, 1);\n  }\n  50% {\n    transform: none;\n    animation-timing-function: cubic-bezier(0, 0, 0.2, 1);\n  }\n}",
    ]
}
