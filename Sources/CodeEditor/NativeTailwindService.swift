import AppKit

/// Tailwind class completion and hover (generated CSS) over a class list token.
enum NWTailwindService {
    static let opacitySteps = ["0", "5", "10", "15", "20", "25", "30", "35", "40", "45", "50", "55", "60", "65", "70", "75", "80", "85", "90", "95", "100"]

    static func cssDoc(_ css: String) -> String { "```css\n" + css + "\n```" }

    static func complete(_ tw: NWTailwind, _ p: NWProject, _ b: NWBuf, site: NWClassSite, caret: Int, url: URL, extraClasses: [(name: String, detail: String)] = []) -> [CompletionItem] {
        let ts = site.tokenRange.location
        guard ts <= caret else { return [] }
        let token = b.str(ts, caret)
        // variants already typed
        var variantEnd = token.startIndex
        var depth = 0
        for i in token.indices {
            let c = token[i]
            if c == "[" || c == "(" { depth += 1 } else if c == "]" || c == ")" { depth = max(0, depth - 1) }
            else if c == ":", depth == 0 { variantEnd = token.index(after: i) }
        }
        let variantPrefix = String(token[token.startIndex..<variantEnd])
        var tail = String(token[variantEnd...])
        var bang = ""
        if tail.hasPrefix("!") { bang = "!"; tail.removeFirst() }
        let range = NSRange(location: ts, length: caret - ts)
        var out: [CompletionItem] = []
        // opacity modifier: bg-red-500/<n>
        if let slash = tw.topLevelSlash(tail) {
            let base = String(tail[tail.startIndex..<slash])
            guard tw.resolveUtility(bang + base) != nil || tw.arbitrary(base) != nil else { return [] }
            for s in opacitySteps {
                let name = variantPrefix + bang + base + "/" + s
                var item = CI.make(name, .value, detail: "opacity \(s)%", sort: String(format: "%03d", Int(s) ?? 0), range: range)
                item.filterText = name
                out.append(item)
            }
            return out
        }
        let ascii = tail.utf8.allSatisfy { $0 < 128 }
        let q: [UInt8] = ascii ? Array(tail.lowercased().utf8) : []
        let wantsNeg = tail.hasPrefix("-")
        var names = tw.utilityNames(matching: q, limit: 450)
        if !wantsNeg && !tail.isEmpty { names.removeAll { $0.hasPrefix("-") } }
        names.sort { a, c in
            let ap = a.hasPrefix(tail), cp = c.hasPrefix(tail)
            if ap != cp { return ap }
            if a.count != c.count { return a.count < c.count }
            return a < c
        }
        if names.count > 450 { names.removeLast(names.count - 450) }
        for n in names {
            let label = variantPrefix + bang + n
            let colorName = colorKey(of: n, tw)
            var item = CI.make(label, colorName != nil ? .color : .value, detail: colorName.flatMap { tw.colors[$0] }.map { colorDetail($0) } ?? "tailwind", sort: n, range: range)
            let full = variantPrefix + bang + n
            let base = item
            item.resolve = { done in
                var updated = base
                updated.resolve = nil
                if let css = tw.css(for: full) { updated.documentation = cssDoc(css) }
                done(updated)
            }
            out.append(item)
        }
        // variants (only before the utility)
        for v in tw.variantNames() where q.isEmpty || CompletionLex.subsequence(q, in: v) {
            let text = variantPrefix + v + (v.hasSuffix("[") ? "" : ":")
            out.append(CI.make(text, .keyword, detail: "variant", sort: "~" + v, range: range))
        }
        // project classes defined in CSS (also usable next to utilities)
        let ql = tail.lowercased()
        for c in extraClasses where ql.isEmpty || c.name.lowercased().hasPrefix(ql) || (!q.isEmpty && CompletionLex.subsequence(q, in: c.name)) {
            out.append(CI.make(variantPrefix + bang + c.name, .class, detail: c.detail, sort: "~~" + c.name, range: range))
        }
        return out
    }

    private static func colorDetail(_ v: String) -> String { v.hasPrefix("#") || v.hasPrefix("rgb") || v.hasPrefix("hsl") || v.hasPrefix("oklch") ? v : "color" }

    /// `bg-red-500` -> "red-500" when the tail is a theme color.
    static func colorKey(of name: String, _ tw: NWTailwind) -> String? {
        let n = name.hasPrefix("-") ? String(name.dropFirst()) : name
        for pre in ["bg-", "text-", "border-", "border-t-", "border-b-", "border-l-", "border-r-", "border-x-", "border-y-", "ring-", "ring-offset-", "outline-", "decoration-", "accent-", "caret-",
                    "fill-", "stroke-", "divide-", "placeholder-", "from-", "via-", "to-", "shadow-"] where n.hasPrefix(pre) {
            let rest = String(n.dropFirst(pre.count))
            if tw.colors[rest] != nil { return rest }
        }
        return nil
    }

    static func lookup(_ tw: NWTailwind, _ p: NWProject, _ b: NWBuf, site: NWClassSite, offset: Int, url: URL) -> NPHit? {
        let r = site.tokenRange
        guard r.length > 0 else { return nil }
        let token = b.str(r.location, NSMaxRange(r))
        guard let css = tw.css(for: token) else { return nil }
        var md = cssDoc(css)
        if let key = colorKey(of: String(token.split(separator: ":", omittingEmptySubsequences: false).last ?? ""), tw), let v = tw.colors[key] { md += "\n\n" + colorLine(v) }
        return NPHit(range: r, targets: [], markdown: md, kind: "tailwind")
    }

    static func colorLine(_ v: String) -> String {
        if let c = NWCssData.parseHex(v) { return "`\(v)` (rgb \(c.r), \(c.g), \(c.b))" }
        return "`\(v)`"
    }
}
