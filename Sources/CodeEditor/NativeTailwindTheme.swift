import Foundation

/// Resolved Tailwind configuration for one project (theme maps, prefix, dark mode, v4 custom utilities / variants).
/// Built lazily by `NWTailwindLoader` from tailwind.config.* or the CSS `@theme` blocks; no node process is involved.
final class NWTailwind {
    var version = 3
    var prefix = ""
    var important: String?                  // "true" or a selector
    var darkMode = "media"
    var darkSelector = ".dark"
    var colors: [String: String] = [:]      // flattened: "red-500", "primary", "primary-dark"
    var maps: [String: [String: String]] = [:]
    var spacingBase: String?                // v4 `--spacing`
    var customUtilities: [String: String] = [:]   // v4 @utility name { body }
    var customVariants: [String: String] = [:]    // v4 @custom-variant name (selector)
    var extraNames: Set<String> = []        // plugin classes known by name only (typography ...)
    var inputs: [String] = []               // config / css files this was built from (definition targets)
    var unresolved = 0
    /// The config uses `presets` or a wrapper function (konsta, primevue, ...): its real theme needs JavaScript. Unknown classes then stay with the external server.
    var incomplete = false

    func map(_ key: String) -> [String: String] { maps[key] ?? [:] }
    func value(_ key: String, _ name: String) -> String? { maps[key]?[name] }

    /// Memory estimate of the resolved theme (for the benchmark).
    var approxBytes: Int {
        var n = colors.count * 48
        for (_, m) in maps { n += m.count * 64 }
        return n + 4096
    }

    // MARK: defaults

    static let paletteTable = """
    slate f8fafc f1f5f9 e2e8f0 cbd5e1 94a3b8 64748b 475569 334155 1e293b 0f172a 020617
    gray f9fafb f3f4f6 e5e7eb d1d5db 9ca3af 6b7280 4b5563 374151 1f2937 111827 030712
    zinc fafafa f4f4f5 e4e4e7 d4d4d8 a1a1aa 71717a 52525b 3f3f46 27272a 18181b 09090b
    neutral fafafa f5f5f5 e5e5e5 d4d4d4 a3a3a3 737373 525252 404040 262626 171717 0a0a0a
    stone fafaf9 f5f5f4 e7e5e4 d6d3d1 a8a29e 78716c 57534e 44403c 292524 1c1917 0c0a09
    red fef2f2 fee2e2 fecaca fca5a5 f87171 ef4444 dc2626 b91c1c 991b1b 7f1d1d 450a0a
    orange fff7ed ffedd5 fed7aa fdba74 fb923c f97316 ea580c c2410c 9a3412 7c2d12 431407
    amber fffbeb fef3c7 fde68a fcd34d fbbf24 f59e0b d97706 b45309 92400e 78350f 451a03
    yellow fefce8 fef9c3 fef08a fde047 facc15 eab308 ca8a04 a16207 854d0e 713f12 422006
    lime f7fee7 ecfccb d9f99d bef264 a3e635 84cc16 65a30d 4d7c0f 3f6212 365314 1a2e05
    green f0fdf4 dcfce7 bbf7d0 86efac 4ade80 22c55e 16a34a 15803d 166534 14532d 052e16
    emerald ecfdf5 d1fae5 a7f3d0 6ee7b7 34d399 10b981 059669 047857 065f46 064e3b 022c22
    teal f0fdfa ccfbf1 99f6e4 5eead4 2dd4bf 14b8a6 0d9488 0f766e 115e59 134e4a 042f2e
    cyan ecfeff cffafe a5f3fc 67e8f9 22d3ee 06b6d4 0891b2 0e7490 155e75 164e63 083344
    sky f0f9ff e0f2fe bae6fd 7dd3fc 38bdf8 0ea5e9 0284c7 0369a1 075985 0c4a6e 082f49
    blue eff6ff dbeafe bfdbfe 93c5fd 60a5fa 3b82f6 2563eb 1d4ed8 1e40af 1e3a8a 172554
    indigo eef2ff e0e7ff c7d2fe a5b4fc 818cf8 6366f1 4f46e5 4338ca 3730a3 312e81 1e1b4b
    violet f5f3ff ede9fe ddd6fe c4b5fd a78bfa 8b5cf6 7c3aed 6d28d9 5b21b6 4c1d95 2e1065
    purple faf5ff f3e8ff e9d5ff d8b4fe c084fc a855f7 9333ea 7e22ce 6b21a8 581c87 3b0764
    fuchsia fdf4ff fae8ff f5d0fe f0abfc e879f9 d946ef c026d3 a21caf 86198f 701a75 4a044e
    pink fdf2f8 fce7f3 fbcfe8 f9a8d4 f472b6 ec4899 db2777 be185d 9d174d 831843 500724
    rose fff1f2 ffe4e6 fecdd3 fda4af fb7185 f43f5e e11d48 be123c 9f1239 881337 4c0519
    """
    static let shades = ["50", "100", "200", "300", "400", "500", "600", "700", "800", "900", "950"]

    /// family -> shade -> "#hex"
    static let palette: [String: [String: String]] = {
        var out: [String: [String: String]] = [:]
        for line in paletteTable.split(separator: "\n") {
            let p = line.split(separator: " ").map(String.init)
            guard p.count == 12 else { continue }
            var m: [String: String] = [:]
            for (i, s) in shades.enumerated() { m[s] = "#" + p[i + 1] }
            out[p[0]] = m
        }
        return out
    }()

    static let spacingKeys = ["0", "px", "0.5", "1", "1.5", "2", "2.5", "3", "3.5", "4", "5", "6", "7", "8", "9", "10", "11", "12", "14", "16", "20", "24", "28", "32", "36", "40",
                              "44", "48", "52", "56", "60", "64", "72", "80", "96"]

    static func spacingValue(_ k: String) -> String {
        if k == "0" { return "0px" }
        if k == "px" { return "1px" }
        return remString((Double(k) ?? 0) * 0.25)
    }

    static func remString(_ v: Double) -> String {
        if v == 0 { return "0px" }
        var s = String(format: "%.4f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s + "rem"
    }

    private static let defaultMaps = """
    screens: sm=640px md=768px lg=1024px xl=1280px 2xl=1536px
    fontSize: xs=0.75rem|1rem sm=0.875rem|1.25rem base=1rem|1.5rem lg=1.125rem|1.75rem xl=1.25rem|1.75rem 2xl=1.5rem|2rem 3xl=1.875rem|2.25rem 4xl=2.25rem|2.5rem 5xl=3rem|1 6xl=3.75rem|1 7xl=4.5rem|1 8xl=6rem|1 9xl=8rem|1
    fontWeight: thin=100 extralight=200 light=300 normal=400 medium=500 semibold=600 bold=700 extrabold=800 black=900
    lineHeight: none=1 tight=1.25 snug=1.375 normal=1.5 relaxed=1.625 loose=2 3=.75rem 4=1rem 5=1.25rem 6=1.5rem 7=1.75rem 8=2rem 9=2.25rem 10=2.5rem
    letterSpacing: tighter=-0.05em tight=-0.025em normal=0em wide=0.025em wider=0.05em widest=0.1em
    borderRadius: none=0px sm=0.125rem DEFAULT=0.25rem md=0.375rem lg=0.5rem xl=0.75rem 2xl=1rem 3xl=1.5rem full=9999px
    borderWidth: DEFAULT=1px 0=0px 2=2px 4=4px 8=8px
    opacity: 0=0 5=0.05 10=0.1 15=0.15 20=0.2 25=0.25 30=0.3 35=0.35 40=0.4 45=0.45 50=0.5 55=0.55 60=0.6 65=0.65 70=0.7 75=0.75 80=0.8 85=0.85 90=0.9 95=0.95 100=1
    zIndex: auto=auto 0=0 10=10 20=20 30=30 40=40 50=50
    maxWidth: none=none 0=0rem xs=20rem sm=24rem md=28rem lg=32rem xl=36rem 2xl=42rem 3xl=48rem 4xl=56rem 5xl=64rem 6xl=72rem 7xl=80rem full=100% min=min-content max=max-content fit=fit-content prose=65ch
    blur: none= sm=4px DEFAULT=8px md=12px lg=16px xl=24px 2xl=40px 3xl=64px
    brightness: 0=0 50=.5 75=.75 90=.9 95=.95 100=1 105=1.05 110=1.1 125=1.25 150=1.5 200=2
    contrast: 0=0 50=.5 75=.75 100=1 125=1.25 150=1.5 200=2
    grayscale: 0=0 DEFAULT=100%
    hueRotate: 0=0deg 15=15deg 30=30deg 60=60deg 90=90deg 180=180deg
    invert: 0=0 DEFAULT=100%
    saturate: 0=0 50=.5 100=1 150=1.5 200=2
    sepia: 0=0 DEFAULT=100%
    transitionDuration: DEFAULT=150ms 0=0s 75=75ms 100=100ms 150=150ms 200=200ms 300=300ms 500=500ms 700=700ms 1000=1000ms
    transitionDelay: 0=0s 75=75ms 100=100ms 150=150ms 200=200ms 300=300ms 500=500ms 700=700ms 1000=1000ms
    transitionTimingFunction: DEFAULT=cubic-bezier(0.4,0,0.2,1) linear=linear in=cubic-bezier(0.4,0,1,1) out=cubic-bezier(0,0,0.2,1) in-out=cubic-bezier(0.4,0,0.2,1)
    scale: 0=0 50=.5 75=.75 90=.9 95=.95 100=1 105=1.05 110=1.1 125=1.25 150=1.5
    rotate: 0=0deg 1=1deg 2=2deg 3=3deg 6=6deg 12=12deg 45=45deg 90=90deg 180=180deg
    skew: 0=0deg 1=1deg 2=2deg 3=3deg 6=6deg 12=12deg
    aspectRatio: auto=auto square=1/1 video=16/9
    lineClamp: 1=1 2=2 3=3 4=4 5=5 6=6
    columns: auto=auto 1=1 2=2 3=3 4=4 5=5 6=6 7=7 8=8 9=9 10=10 11=11 12=12 3xs=16rem 2xs=18rem xs=20rem sm=24rem md=28rem lg=32rem xl=36rem 2xl=42rem 3xl=48rem 4xl=56rem 5xl=64rem 6xl=72rem 7xl=80rem
    outlineWidth: 0=0px 1=1px 2=2px 4=4px 8=8px
    outlineOffset: 0=0px 1=1px 2=2px 4=4px 8=8px
    ringWidth: DEFAULT=3px 0=0px 1=1px 2=2px 4=4px 8=8px
    ringOffsetWidth: 0=0px 1=1px 2=2px 4=4px 8=8px
    textDecorationThickness: auto=auto from-font=from-font 0=0px 1=1px 2=2px 4=4px 8=8px
    textUnderlineOffset: auto=auto 0=0px 1=1px 2=2px 4=4px 8=8px
    strokeWidth: 0=0 1=1 2=2
    borderSpacing: 0=0px
    divideWidth: DEFAULT=1px 0=0px 2=2px 4=4px 8=8px
    gridTemplateColumns: none=none subgrid=subgrid
    gridTemplateRows: none=none subgrid=subgrid
    flex: 1=1|1|0% auto=1|1|auto initial=0|1|auto none=none
    flexGrow: DEFAULT=1 0=0
    flexShrink: DEFAULT=1 0=0
    order: first=-9999 last=9999 none=0
    animation: none=none spin=spin|1s|linear|infinite ping=ping|1s|cubic-bezier(0,0,0.2,1)|infinite pulse=pulse|2s|cubic-bezier(0.4,0,0.6,1)|infinite bounce=bounce|1s|infinite
    """

    static let defaultShadows: [(String, String)] = [
        ("sm", "0 1px 2px 0 rgb(0 0 0 / 0.05)"),
        ("DEFAULT", "0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)"),
        ("md", "0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1)"),
        ("lg", "0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)"),
        ("xl", "0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1)"),
        ("2xl", "0 25px 50px -12px rgb(0 0 0 / 0.25)"),
        ("inner", "inset 0 2px 4px 0 rgb(0 0 0 / 0.05)"),
        ("none", "0 0 #0000"),
    ]

    static let fontFamilies: [(String, String)] = [
        ("sans", "ui-sans-serif, system-ui, sans-serif, \"Apple Color Emoji\", \"Segoe UI Emoji\", \"Segoe UI Symbol\", \"Noto Color Emoji\""),
        ("serif", "ui-serif, Georgia, Cambria, \"Times New Roman\", Times, serif"),
        ("mono", "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace"),
    ]

    static var parsedDefaults: [String: [String: String]] = {
        var out: [String: [String: String]] = [:]
        for line in defaultMaps.split(separator: "\n") {
            guard let c = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<c]).trimmingCharacters(in: .whitespaces)
            var m: [String: String] = [:]
            for item in line[line.index(after: c)...].split(separator: " ") {
                guard let eq = item.firstIndex(of: "=") else { continue }
                m[String(item[item.startIndex..<eq])] = String(item[item.index(after: eq)...])
            }
            out[key] = m
        }
        var sp: [String: String] = [:]
        for k in spacingKeys { sp[k] = spacingValue(k) }
        out["spacing"] = sp
        out["boxShadow"] = Dictionary(uniqueKeysWithValues: defaultShadows)
        out["fontFamily"] = Dictionary(uniqueKeysWithValues: fontFamilies)
        var gc = [String: String](), gr = [String: String](), colm = [String: String](), rowm = [String: String]()
        for i in 1...12 { gc[String(i)] = "repeat(\(i), minmax(0, 1fr))"; colm["span-\(i)"] = "span \(i) / span \(i)"; colm[String(i)] = String(i) }
        for i in 1...12 { gr[String(i)] = "repeat(\(i), minmax(0, 1fr))"; rowm["span-\(i)"] = "span \(i) / span \(i)"; rowm[String(i)] = String(i) }
        gc["none"] = "none"; gc["subgrid"] = "subgrid"; gr["none"] = "none"; gr["subgrid"] = "subgrid"
        colm["auto"] = "auto"; colm["span-full"] = "1 / -1"; rowm["auto"] = "auto"; rowm["span-full"] = "1 / -1"
        out["gridTemplateColumns"] = gc; out["gridTemplateRows"] = gr; out["gridColumn"] = colm; out["gridRow"] = rowm
        for k in ["transitionTimingFunction", "animation"] { out[k] = out[k]?.mapValues { $0.replacingOccurrences(of: ",", with: ", ").replacingOccurrences(of: "|", with: " ") } }
        return out
    }()

    static func defaultColors() -> [String: String] {
        var c: [String: String] = ["inherit": "inherit", "current": "currentColor", "transparent": "transparent", "black": "#000", "white": "#fff"]
        for (fam, shades) in palette { for (s, v) in shades { c[fam + "-" + s] = v } }
        return c
    }

    /// A tailwind with the stock v3 theme (also the base every config extends).
    static func makeDefault(version: Int) -> NWTailwind {
        let t = NWTailwind()
        t.version = version
        t.colors = defaultColors()
        t.maps = parsedDefaults
        if version >= 4 {
            t.spacingBase = "0.25rem"
            t.maps["screens"] = ["sm": "40rem", "md": "48rem", "lg": "64rem", "xl": "80rem", "2xl": "96rem"]
            t.maps["borderRadius"] = ["xs": "0.125rem", "sm": "0.25rem", "md": "0.375rem", "lg": "0.5rem", "xl": "0.75rem", "2xl": "1rem", "3xl": "1.5rem", "4xl": "2rem"]
            t.maps["boxShadow"] = ["2xs": "0 1px rgb(0 0 0 / 0.05)", "xs": "0 1px 2px 0 rgb(0 0 0 / 0.05)", "sm": "0 1px 3px 0 rgb(0 0 0 / 0.1), 0 1px 2px -1px rgb(0 0 0 / 0.1)",
                                   "md": "0 4px 6px -1px rgb(0 0 0 / 0.1), 0 2px 4px -2px rgb(0 0 0 / 0.1)", "lg": "0 10px 15px -3px rgb(0 0 0 / 0.1), 0 4px 6px -4px rgb(0 0 0 / 0.1)",
                                   "xl": "0 20px 25px -5px rgb(0 0 0 / 0.1), 0 8px 10px -6px rgb(0 0 0 / 0.1)", "2xl": "0 25px 50px -12px rgb(0 0 0 / 0.25)", "none": "0 0 #0000"]
            t.maps["blur"] = ["xs": "4px", "sm": "8px", "md": "12px", "lg": "16px", "xl": "24px", "2xl": "40px", "3xl": "64px"]
            t.maps["maxWidth"]?["3xs"] = "16rem"; t.maps["maxWidth"]?["2xs"] = "18rem"
            t.maps["borderWidth"] = ["DEFAULT": "1px", "0": "0px", "2": "2px", "4": "4px", "8": "8px"]
            t.maps["ringWidth"] = ["DEFAULT": "1px", "0": "0px", "1": "1px", "2": "2px", "3": "3px", "4": "4px", "5": "5px", "6": "6px", "8": "8px"]
        }
        return t
    }
}

/// Variants offered by name (completion) with their selector / at-rule template.
enum NWVariants {
    /// `&` is the class selector; `@` prefix = at-rule wrapper.
    static let simple: [String: String] = [
        "hover": "&:hover", "focus": "&:focus", "focus-visible": "&:focus-visible", "focus-within": "&:focus-within", "active": "&:active", "visited": "&:visited",
        "target": "&:target", "disabled": "&:disabled", "enabled": "&:enabled", "checked": "&:checked", "indeterminate": "&:indeterminate", "default": "&:default",
        "required": "&:required", "optional": "&:optional", "valid": "&:valid", "invalid": "&:invalid", "in-range": "&:in-range", "out-of-range": "&:out-of-range",
        "placeholder-shown": "&:placeholder-shown", "autofill": "&:autofill", "read-only": "&:read-only", "empty": "&:empty", "first": "&:first-child", "last": "&:last-child",
        "only": "&:only-child", "odd": "&:nth-child(odd)", "even": "&:nth-child(even)", "first-of-type": "&:first-of-type", "last-of-type": "&:last-of-type",
        "only-of-type": "&:only-of-type", "open": "&[open]", "before": "&::before", "after": "&::after", "first-letter": "&::first-letter", "first-line": "&::first-line",
        "marker": "&::marker", "selection": "&::selection", "file": "&::file-selector-button", "placeholder": "&::placeholder", "backdrop": "&::backdrop",
        "ltr": "&:where([dir=\"ltr\"], [dir=\"ltr\"] *)", "rtl": "&:where([dir=\"rtl\"], [dir=\"rtl\"] *)", "inert": "&:is([inert], [inert] *)",
        "print": "@media print", "motion-safe": "@media (prefers-reduced-motion: no-preference)", "motion-reduce": "@media (prefers-reduced-motion: reduce)",
        "contrast-more": "@media (prefers-contrast: more)", "contrast-less": "@media (prefers-contrast: less)", "portrait": "@media (orientation: portrait)",
        "landscape": "@media (orientation: landscape)", "forced-colors": "@media (forced-colors: active)", "starting": "@starting-style",
        "*": "& > *", "**": "& *", "user-valid": "&:user-valid", "user-invalid": "&:user-invalid", "details-content": "&::details-content",
    ]
    /// Variants taking a suffix: group-hover, peer-checked, has-[...], aria-*, data-*, supports-*, not-*, in-*, nth-*, min-*, max-*.
    static let prefixed = ["group", "peer", "has", "aria", "data", "supports", "not", "in", "nth", "min", "max", "@container", "@min", "@max", "group-has", "peer-has", "nth-last", "nth-of-type"]
    static let ariaStates = ["busy", "checked", "disabled", "expanded", "hidden", "pressed", "readonly", "required", "selected"]
}
