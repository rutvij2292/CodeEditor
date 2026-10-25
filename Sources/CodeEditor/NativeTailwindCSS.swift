import Foundation

/// class token -> generated CSS (variants, important, negatives, arbitrary values, opacity modifiers) and class-name enumeration.
extension NWTailwind {
    // MARK: tokens

    /// Splits `sm:hover:!p-4` into variants and the utility, honouring `[...]` and `(...)` groups.
    func split(_ token: String) -> (variants: [String], utility: String)? {
        var parts: [String] = []
        var depth = 0
        var cur = ""
        for ch in token {
            if ch == "[" || ch == "(" { depth += 1 } else if ch == "]" || ch == ")" { depth = max(0, depth - 1) }
            if ch == ":", depth == 0 { parts.append(cur); cur = ""; continue }
            cur.append(ch)
        }
        guard !cur.isEmpty else { return nil }
        return (parts, cur)
    }

    static func escapeClass(_ s: String) -> String {
        var out = ""
        for (i, ch) in s.unicodeScalars.enumerated() {
            let v = ch.value
            let plain = (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122) || v == 45 || v == 95 || v > 127
            if i == 0, v >= 48, v <= 57 { out += "\\3\(Character(ch)) "; continue }
            if i == 0, v == 45, s.unicodeScalars.count > 1, let n = s.unicodeScalars.dropFirst().first, n.value >= 48, n.value <= 57 { out += "\\-"; continue }
            out += plain ? String(Character(ch)) : "\\" + String(Character(ch))
        }
        return out
    }

    // MARK: utilities

    func resolveUtility(_ raw: String) -> (util: NWUtil, important: Bool)? {
        var u = raw
        var important = false
        if u.hasPrefix("!") { important = true; u.removeFirst() }
        if u.hasSuffix("!"), version >= 4 { important = true; u.removeLast() }
        var neg = false
        if u.hasPrefix("-"), u.count > 1 { neg = true; u.removeFirst() }
        if !prefix.isEmpty {
            guard u.hasPrefix(prefix) else { return nil }
            u.removeFirst(prefix.count)
        }
        guard !u.isEmpty else { return nil }
        // arbitrary property: [mask-type:luminance]
        if u.hasPrefix("["), u.hasSuffix("]"), let colon = u.firstIndex(of: ":") {
            let prop = String(u[u.index(after: u.startIndex)..<colon])
            var val = String(u[u.index(after: colon)...].dropLast())
            val = val.replacingOccurrences(of: "_", with: " ")
            guard !prop.isEmpty, prop.allSatisfy({ $0.isLetter || $0 == "-" }) else { return nil }
            return (NWUtil(decls: [(prop, val)]), important)
        }
        if !neg, let d = NWTailwindStatic.map[u] { return (NWUtil(decls: d), important) }
        if !neg, let body = customUtilities[u] {
            let decls: NWDecls = body.split(separator: ";").compactMap { p in
                guard let c = p.firstIndex(of: ":") else { return nil }
                return (p[p.startIndex..<c].trimmingCharacters(in: .whitespacesAndNewlines), p[p.index(after: c)...].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return (NWUtil(decls: decls), important)
        }
        for fam in NWFamilies.all {
            if neg, !fam.negatable { continue }
            var rest: String
            if u == fam.prefix { guard fam.bare else { continue }; rest = "" }
            else if u.hasPrefix(fam.prefix + "-") { rest = String(u.dropFirst(fam.prefix.count + 1)) }
            else { continue }
            if rest.isEmpty && u != fam.prefix { continue }
            if let r = fam.resolve(self, rest, neg) { return (r, important) }
        }
        return nil
    }

    // MARK: variants

    private func pseudo(of template: String) -> String? { template.hasPrefix("&") && !template.hasPrefix("& ") && !template.hasPrefix("&[") ? String(template.dropFirst()) : (template.hasPrefix("&[") ? String(template.dropFirst()) : nil) }

    func screenQuery(_ name: String) -> String? {
        guard let v = maps["screens"]?[name] else { return nil }
        if v.hasPrefix("@max:") { return "@media (max-width: \(v.dropFirst(5)))" }
        if v.hasPrefix("@raw:") { return "@media \(v.dropFirst(5))" }
        return version >= 4 ? "@media (width >= \(v))" : "@media (min-width: \(v))"
    }

    func variant(_ v: String) -> (selector: String?, at: String?)? {
        if let s = customVariants[v] { return (s.contains("&") ? s : "&:" + s, nil) }
        if v == "dark" {
            switch darkMode {
            case "class": return (":is(\(darkSelector) &)", nil)
            case "selector": return (":where(\(darkSelector), \(darkSelector) *) &".replacingOccurrences(of: ") &", with: ") &"), nil)
            case "variant": return ("&:where(\(darkSelector), \(darkSelector) *)", nil)
            default: return (nil, "@media (prefers-color-scheme: dark)")
            }
        }
        if let t = NWVariants.simple[v] { return t.hasPrefix("@") ? (nil, t) : (t, nil) }
        if let q = screenQuery(v) { return (nil, q) }
        if v.hasPrefix("[") && v.hasSuffix("]") {
            let inner = String(v.dropFirst().dropLast()).replacingOccurrences(of: "_", with: " ")
            if inner.hasPrefix("@") { return (nil, inner.replacingOccurrences(of: "@media(", with: "@media (")) }
            return (inner.contains("&") ? inner : "&" + inner, nil)
        }
        func arg(_ prefix: String) -> String? { v.hasPrefix(prefix + "-") ? String(v.dropFirst(prefix.count + 1)) : nil }
        func bracket(_ s: String) -> String? { s.hasPrefix("[") && s.hasSuffix("]") ? String(s.dropFirst().dropLast()).replacingOccurrences(of: "_", with: " ") : nil }
        if let a = arg("max") {
            if let w = maps["screens"]?[a], !w.hasPrefix("@") { return (nil, version >= 4 ? "@media (width < \(w))" : "@media not all and (min-width: \(w))") }
            if let b = bracket(a) { return (nil, "@media (max-width: \(b))") }
        }
        if let a = arg("min") {
            if let w = maps["screens"]?[a], !w.hasPrefix("@") { return (nil, "@media (min-width: \(w))") }
            if let b = bracket(a) { return (nil, "@media (min-width: \(b))") }
        }
        for (p, joiner) in [("group", " "), ("peer", " ~ ")] {
            var rest = v
            guard v == p || v.hasPrefix(p + "-") || v.hasPrefix(p + "/") else { continue }
            rest = v == p ? "" : String(v.dropFirst(p.count))
            var name = ""
            if let slash = rest.firstIndex(of: "/") { name = String(rest[rest.index(after: slash)...]); rest = String(rest[rest.startIndex..<slash]) }
            if rest.hasPrefix("-") { rest.removeFirst() }
            let anchor = "." + p + (name.isEmpty ? "" : "\\/" + name)
            var inner: String?
            if let b = bracket(rest) { inner = b.contains("&") ? b.replacingOccurrences(of: "&", with: "") : b }
            else if let t = NWVariants.simple[rest], let ps = pseudo(of: t) { inner = ps }
            else if rest.hasPrefix("has-"), let t = NWVariants.simple[String(rest.dropFirst(4))], let ps = pseudo(of: t) { inner = ":has(\(ps))" }
            guard let pseu = inner else { continue }
            return (anchor + pseu + joiner + "&", nil)
        }
        if let a = arg("has") {
            if let b = bracket(a) { return ("&:has(\(b))", nil) }
            if let t = NWVariants.simple[a], let ps = pseudo(of: t) { return ("&:has(\(ps))", nil) }
        }
        if let a = arg("not") {
            if let b = bracket(a) { return ("&:not(\(b))", nil) }
            if let t = NWVariants.simple[a], let ps = pseudo(of: t) { return ("&:not(\(ps))", nil) }
            if let q = screenQuery(a) { return (nil, q.replacingOccurrences(of: "@media ", with: "@media not all and ")) }
        }
        if let a = arg("in") { if let b = bracket(a) { return (b + " &", nil) }; if let t = NWVariants.simple[a], let ps = pseudo(of: t) { return (ps + " &", nil) } }
        if let a = arg("aria") {
            if let b = bracket(a) { let kv = b.split(separator: "=", maxSplits: 1).map(String.init); return (kv.count == 2 ? "&[aria-\(kv[0])=\"\(kv[1])\"]" : "&[aria-\(b)]", nil) }
            return ("&[aria-\(a)=\"true\"]", nil)
        }
        if let a = arg("data") {
            if let b = bracket(a) { let kv = b.split(separator: "=", maxSplits: 1).map(String.init); return (kv.count == 2 ? "&[data-\(kv[0])=\"\(kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))\"]" : "&[data-\(b)]", nil) }
            return ("&[data-\(a)]", nil)
        }
        if let a = arg("supports") {
            if let b = bracket(a) { return (nil, "@supports (\(b))") }
            return (nil, "@supports (\(a): var(--tw))")
        }
        if let a = arg("nth") { if let b = bracket(a) { return ("&:nth-child(\(b))", nil) }; return ("&:nth-child(\(a))", nil) }
        if v.hasPrefix("@") {
            let sizes = ["3xs": "16rem", "2xs": "18rem", "xs": "20rem", "sm": "24rem", "md": "28rem", "lg": "32rem", "xl": "36rem", "2xl": "42rem", "3xl": "48rem", "4xl": "56rem", "5xl": "64rem", "6xl": "72rem", "7xl": "80rem"]
            var s = String(v.dropFirst())
            var kind = "min-width"
            if s.hasPrefix("max-") { kind = "max-width"; s = String(s.dropFirst(4)) }
            if s.hasPrefix("min-") { s = String(s.dropFirst(4)) }
            if let slash = s.firstIndex(of: "/") { s = String(s[s.startIndex..<slash]) }
            if let w = sizes[s] { return (nil, "@container (\(kind): \(w))") }
            if let b = bracket(s) { return (nil, "@container (\(kind): \(b))") }
        }
        return nil
    }

    // MARK: CSS text

    private func format(selector: String, decls: NWDecls, important: Bool, indent: Int) -> String {
        let pad = String(repeating: " ", count: indent)
        var s = pad + selector + " {\n"
        for (p, v) in decls { s += pad + "  \(p): \(v)\(important && !p.hasPrefix("--") ? " !important" : "");\n" }
        return s + pad + "}"
    }

    /// Full generated CSS for a class token, or nil when it is not a (known) Tailwind class.
    func css(for token: String) -> String? {
        guard let (variants, utility) = split(token), let (util, important0) = resolveUtility(utility) else { return nil }
        var selector = "." + NWTailwind.escapeClass(token)
        var ats: [String] = []
        var extraDecls: NWDecls = []
        for v in variants.reversed() {
            guard let info = variant(v) else { return nil }
            if let s = info.selector { selector = s.replacingOccurrences(of: "&", with: selector) }
            if let a = info.at { ats.insert(a, at: 0) }
            if v == "before" || v == "after" { if !util.decls.contains(where: { $0.0 == "content" }) { extraDecls.append(("content", "var(--tw-content)")) } }
        }
        if let imp = important, imp != "true" { selector = imp + " " + selector }
        selector += util.selSuffix
        let important = important0 || important == "true"
        var out = ""
        var decls = extraDecls + util.decls
        var rules: [String] = []
        if utility == "container" {
            decls = [("width", "100%")]
            rules.append(format(selector: selector, decls: decls, important: important, indent: 0))
            for (name, v) in maps["screens"]?.sorted(by: { (Double($0.value.filter { $0.isNumber || $0 == "." }) ?? 0) < (Double($1.value.filter { $0.isNumber || $0 == "." }) ?? 0) }) ?? [] where !v.hasPrefix("@") {
                rules.append("@media (min-width: \(v)) {\n" + format(selector: selector, decls: [("max-width", v)], important: important, indent: 2) + "\n}")
                _ = name
            }
            return rules.joined(separator: "\n\n")
        }
        var body = format(selector: selector, decls: decls, important: important, indent: ats.count * 2)
        for (i, at) in ats.enumerated().reversed() {
            body = String(repeating: " ", count: i * 2) + at + " {\n" + body + "\n" + String(repeating: " ", count: i * 2) + "}"
        }
        out = util.extra + body
        return out
    }

    /// The class names a rule's declarations; used by tests.
    func decls(for token: String) -> NWDecls? {
        guard let (_, utility) = split(token), let r = resolveUtility(utility) else { return nil }
        return r.util.decls
    }

    // MARK: enumeration (completion)

    /// Utility class names (without variants) matching `q` as a subsequence (empty `q` matches everything), capped at `limit`.
    func utilityNames(matching q: [UInt8], limit: Int, includePrefix: Bool = true) -> [String] {
        var starts: [String] = [], subs: [String] = []
        let pre = includePrefix ? prefix : ""
        let query = String(decoding: q, as: UTF8.self)
        func add(_ s: String) {
            let full = pre + s
            if q.isEmpty { if starts.count < limit { starts.append(full) }; return }
            let l = full.lowercased()
            if l.hasPrefix(query) || l.hasPrefix("-" + query) { if starts.count < limit { starts.append(full) } }
            else if subs.count < limit, CompletionLex.subsequence(q, in: full) { subs.append(full) }
        }
        for n in NWTailwindStatic.names { add(n) }
        for n in customUtilities.keys { add(n) }
        for n in extraNames { add(n) }
        for fam in NWFamilies.all {
            if fam.bare { add(fam.prefix) }
            guard let keys = fam.keys else { continue }
            for k in keys(self) where k != "DEFAULT" {
                add(fam.prefix + "-" + k)
                if fam.negatable { add("-" + fam.prefix + "-" + k) }
            }
        }
        return starts + subs
    }

    func variantNames() -> [String] {
        var v = Set(NWVariants.simple.keys)
        v.formUnion(maps["screens"]?.keys ?? [:].keys)
        for s in (maps["screens"] ?? [:]).keys { v.insert("max-" + s); v.insert("min-" + s) }
        v.insert("dark"); v.formUnion(customVariants.keys)
        for a in ["group-hover", "group-focus", "group-active", "group-focus-within", "group-disabled", "group-checked", "group-first", "group-last", "group-odd", "group-even", "group-open",
                  "peer-hover", "peer-focus", "peer-checked", "peer-disabled", "peer-invalid", "peer-placeholder-shown", "peer-focus-visible", "peer-required", "peer-open",
                  "has-checked", "has-hover", "has-focus", "has-disabled", "has-[", "aria-[", "aria-checked", "aria-disabled", "aria-expanded", "aria-selected", "aria-pressed", "aria-busy", "aria-hidden",
                  "data-[", "supports-[", "min-[", "max-[", "not-hover", "not-focus", "not-first", "not-last", "not-disabled", "not-checked", "in-hover", "nth-[", "@sm", "@md", "@lg", "@xl", "@2xl"] { v.insert(a) }
        if prefix.isEmpty == false { /* variants are not prefixed */ }
        return v.sorted()
    }
}
