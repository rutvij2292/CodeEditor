import AppKit

/// CSS completion, hover and navigation (stylesheets, `<style>` blocks, inline `style=""` values).
enum NWCssService {
    // MARK: project data

    /// Class (or id) names defined in the project's stylesheets: (name, "file").
    static func projectNames(_ p: NWProject, ids: Bool, limit: Int, skipPath: String? = nil) -> [(name: String, detail: String)] {
        var seen = Set<String>()
        var out: [(String, String)] = []
        for (path, idx) in p.allCSSIndexes() where path != skipPath {
            let file = (path as NSString).lastPathComponent
            for s in idx.sels where s.isId == ids {
                if seen.insert(s.name).inserted { out.append((s.name, file)); if out.count >= limit { return out } }
            }
        }
        return out
    }

    static func customProps(_ p: NWProject, current: NWCssIndex?, currentBuf: NWBuf?, currentPath: String?, limit: Int = 400, query: [UInt8] = []) -> [(name: String, value: String, file: String)] {
        var seen = Set<String>()
        var out: [(String, String, String)] = []
        if let idx = current {
            for pr in idx.props where pr.name.hasPrefix("--") && CompletionLex.subsequence(query, in: pr.name) {
                if seen.insert(pr.name).inserted { out.append((pr.name, pr.value, "this file")) }
            }
        }
        for (path, idx) in p.allCSSIndexes() where path != currentPath {
            var file: String?
            for pr in idx.props where pr.name.hasPrefix("--") && CompletionLex.subsequence(query, in: pr.name) && seen.insert(pr.name).inserted {
                if file == nil { file = (path as NSString).lastPathComponent }
                out.append((pr.name, pr.value, file!))
                if out.count >= limit { return out }
            }
        }
        return out
    }

    // MARK: completion

    private static let tailwindAtRulesV3: [(String, String, String)] = [("tailwind", "Inserts Tailwind's base, components, utilities or variants layer.", "tailwind ${1|base,components,utilities,variants|};"),
                                                                         ("apply", "Inlines existing utility classes into custom CSS.", "apply $0;"),
                                                                         ("screen", "Media query for a configured breakpoint.", "screen ${1:md} {\n\t$0\n}"),
                                                                         ("config", "Uses a different Tailwind config file.", "config \"$0\";")]
    private static let tailwindAtRulesV4: [(String, String, String)] = [("theme", "Defines design tokens (theme variables).", "theme {\n\t$0\n}"),
                                                                         ("utility", "Registers a custom utility class.", "utility ${1:name} {\n\t$0\n}"),
                                                                         ("variant", "Applies a Tailwind variant inside CSS.", "variant ${1:hover} {\n\t$0\n}"),
                                                                         ("custom-variant", "Registers a custom variant.", "custom-variant ${1:name} (${2:&:hover});"),
                                                                         ("apply", "Inlines existing utility classes into custom CSS.", "apply $0;"),
                                                                         ("source", "Registers an additional source for class detection.", "source \"$0\";"),
                                                                         ("plugin", "Loads a JavaScript plugin.", "plugin \"$0\";"),
                                                                         ("config", "Loads a legacy JavaScript config.", "config \"$0\";"),
                                                                         ("reference", "Imports a file for reference only (no output).", "reference \"$0\";")]

    static func complete(_ p: NWProject, _ b: NWBuf, _ pos: NWCss.Pos, caret: Int, lang: NWCssLang, url: URL, tw: NWTailwind?, manual: Bool, from: Int) -> [CompletionItem] {
        let range = NSRange(location: pos.prefixStart, length: max(0, caret - pos.prefixStart))
        let prefixLen = caret - pos.prefixStart
        switch pos.kind {
        case .none, .comment, .string: return []
        case .atName:
            var items: [CompletionItem] = []
            var seen = Set<String>()
            func add(_ name: String, _ doc: String, _ snippet: String) {
                guard seen.insert(name).inserted else { return }
                var it = CI.make(name, .keyword, detail: "at-rule", insert: snippet, snippet: snippet.contains("$"), doc: doc, range: range)
                it.filterText = name
                items.append(it)
            }
            for a in NWCssData.atRules { add(a.name, a.doc, a.snippet) }
            if lang != .css { for (n, d) in NWCssData.sassAtRules { add(n, d, n) } }
            if let tw { for a in (tw.version >= 4 ? tailwindAtRulesV4 : tailwindAtRulesV3) { add(a.0, a.1, a.2) } }
            return items
        case .atParams:
            switch pos.atName {
            case "apply":
                guard let tw else { return [] }
                var s = caret
                while s > from, !NWChar.isSpace(b[s - 1]), b[s - 1] != 59, b[s - 1] != 123 { s -= 1 }
                s = max(s, pos.stmtStart)
                let site = NWClassSite(tokenRange: NSRange(location: s, length: caret - s), listRange: NSRange(location: s, length: caret - s))
                return NWTailwindService.complete(tw, p, b, site: site, caret: caret, url: url, extraClasses: NWCssService.projectNames(p, ids: false, limit: 400).map { ($0.name, $0.detail) })
            case "tailwind", "layer":
                var items = ["base", "components", "utilities"].map { CI.make($0, .keyword, detail: "layer", range: range) }
                if tw?.version == 3, pos.atName == "tailwind" { items.append(CI.make("variants", .keyword, detail: "layer", range: range)) }
                return items
            case "media", "container", "supports":
                guard pos.fn.isEmpty || pos.parenOpen >= 0 else { return [] }
                if pos.atName == "supports" {
                    return NWCssData.sortedPropNames.prefix(200).map { CI.make($0, .property, detail: "property", range: range) }
                }
                let inParen = b.str(max(from, pos.parenOpen), caret).contains("(") && pos.parenOpen >= 0
                guard inParen else { return ["screen", "print", "all", "and", "not", "only"].map { CI.make($0, .keyword, detail: "media type", range: range) } }
                return NWCssData.mediaFeatures.map { CI.make($0, .property, detail: "media feature", range: range) }
            default: return []
            }
        case .selector:
            let prev: unichar = pos.prefixStart > from ? b[pos.prefixStart - 1] : 0
            if prev == 46 {                                      // .class
                let own = ownNames(b, lang: lang, from: from, ids: false)
                var items = own.map { CI.make($0, .class, detail: "this file", sort: "0" + $0, range: range) }
                var seen = Set(own)
                for n in projectNames(p, ids: false, limit: 800, skipPath: url.path) where seen.insert(n.name).inserted { items.append(CI.make(n.name, .class, detail: n.detail, sort: "1" + n.name, range: range)) }
                return items
            }
            if prev == 35 {                                      // #id
                let own = ownNames(b, lang: lang, from: from, ids: true)
                var items = own.map { CI.make($0, .value, detail: "this file", range: range) }
                var seen = Set(own)
                for n in projectNames(p, ids: true, limit: 400, skipPath: url.path) where seen.insert(n.name).inserted { items.append(CI.make(n.name, .value, detail: n.detail, range: range)) }
                return items
            }
            if prev == 58 {                                      // :pseudo / ::element
                let double = pos.prefixStart > from + 1 && b[pos.prefixStart - 2] == 58
                var items: [CompletionItem] = []
                for e in (double ? NWCssData.pseudoElements : NWCssData.pseudoClasses + NWCssData.pseudoElements) { items.append(pseudoItem(e.name, e.doc, kind: double || NWCssData.pseudoElements.contains { $0.name == e.name } ? "pseudo-element" : "pseudo-class", range: range)) }
                return items
            }
            if prev == 64 || prev == 91 || prev == 38 { return [] }
            guard prefixLen > 0 || manual else { return [] }
            return NWHtmlData.tags.map { CI.make($0.name, .keyword, detail: "element", doc: $0.doc, range: range) }
        case .property:
            if pos.text.hasPrefix("--") {
                return customProps(p, current: nil, currentBuf: nil, currentPath: nil).map { CI.make($0.name, .variable, detail: $0.value, range: range) }
            }
            guard prefixLen > 0 || manual else { return [] }
            let nextIsColon = caret < b.count && b[caret] == 58
            var items: [CompletionItem] = []
            let typed = b.str(pos.prefixStart, caret).lowercased()
            let q: [UInt8] = typed.utf8.allSatisfy { $0 < 128 } ? Array(typed.utf8) : []
            for name in NWCssData.sortedPropNames where CompletionLex.subsequence(q, in: name) {
                let sort = name.hasPrefix("-") ? "~" + name : name
                var item = CI.make(name, .property, detail: "property", insert: nextIsColon ? name : name + ": $0;", snippet: !nextIsColon, sort: sort, range: range)
                if let pr = NWCssData.props[name] {
                    let base = item
                    item.resolve = { done in var u = base; u.resolve = nil; u.documentation = pr.doc; done(u) }
                }
                items.append(item)
            }
            return items
        case .value:
            return valueItems(p, b, pos, range: range, lang: lang, url: url, from: from, tw: tw)
        case .paren:
            let r = NSRange(location: pos.prefixStart, length: max(0, caret - pos.prefixStart))
            if pos.prop == "var" {
                let idx = lang == .css ? NWCss.index(b, lang: lang, from: from) : NWCss.index(b, lang: lang)
                let typed = b.str(pos.prefixStart, caret).lowercased()
                let q: [UInt8] = typed.utf8.allSatisfy { $0 < 128 } ? Array(typed.utf8) : []
                var items = customProps(p, current: idx, currentBuf: b, currentPath: url.path, query: q).map { n -> CompletionItem in
                    var it = CI.make(n.name, .variable, detail: n.value, sort: n.file == "this file" ? "0" + n.name : "1" + n.name, doc: "`\(n.name): \(n.value)`  \n\(n.file)", range: r)
                    it.filterText = n.name
                    return it
                }
                if let tw, tw.version >= 4 { items.append(contentsOf: v4ThemeVars(tw, range: r, have: Set(items.map(\.label)))) }
                return items
            }
            if pos.prop == "theme", let tw, tw.version < 4 { return themePaths(tw, text: pos.text, range: r) }
            return []
        }
    }

    private static func pseudoItem(_ name: String, _ doc: String, kind: String, range: NSRange) -> CompletionItem {
        let hasParen = name.hasSuffix("()")
        return CI.make(name, .keyword, detail: kind, insert: hasParen ? String(name.dropLast()) + "$1)" : name, snippet: hasParen, doc: doc, filter: name, range: range)
    }

    private static func ownNames(_ b: NWBuf, lang: NWCssLang, from: Int, ids: Bool) -> [String] {
        let idx = NWCss.index(b, lang: lang, from: from)
        var seen = Set<String>()
        return idx.sels.filter { $0.isId == ids }.compactMap { seen.insert($0.name).inserted ? $0.name : nil }
    }

    private static func valueItems(_ p: NWProject, _ b: NWBuf, _ pos: NWCss.Pos, range: NSRange, lang: NWCssLang, url: URL, from: Int, tw: NWTailwind?) -> [CompletionItem] {
        let prop = pos.prop
        // unknown "property" followed by a colon: a nested selector like `a:hover`
        if !NWCssData.isProperty(prop) && !prop.hasPrefix("$") && !prop.hasPrefix("@") {
            let prev: unichar = range.location > 0 && range.location <= b.count ? b[range.location - 1] : 0
            guard prev == 58 else { return [] }
            return (NWCssData.pseudoClasses + NWCssData.pseudoElements).map { pseudoItem($0.name, $0.doc, kind: "pseudo", range: range) }
        }
        var items: [CompletionItem] = []
        var seen = Set<String>()
        func add(_ label: String, _ kind: CompletionKind, detail: String = "", insert: String? = nil, snippet: Bool = false, doc: String = "", sort: String? = nil) {
            guard seen.insert(label).inserted else { return }
            items.append(CI.make(label, kind, detail: detail, insert: insert, snippet: snippet, sort: sort, doc: doc, range: range))
        }
        let prefix = b.str(range.location, range.location + range.length)
        if prefix.hasPrefix("!") { add("!important", .keyword, detail: "priority"); return items }
        // number + unit
        if let first = prefix.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) || first == "." {
            let digits = prefix.prefix { $0.isNumber || $0 == "." || $0 == "-" }
            if digits.count == prefix.count {
                for u in NWCssData.units { add(prefix + u, .value, detail: "unit", sort: "0" + u) }
                return items
            }
        }
        let pr = NWCssData.props[prop]
        for v in pr?.values ?? [] {
            if v.hasSuffix("()") { add(v, .function, detail: prop, insert: String(v.dropLast()) + "$1)", snippet: true) }
            else { add(v, .value, detail: prop) }
        }
        for g in NWCssData.globalValues { add(g, .keyword, detail: "global", sort: "~" + g) }
        let colorProp = (pr?.hasColor ?? false) || NWCssData.colorProps.contains(prop) || prop.hasPrefix("--") && !prop.contains("spacing") || prop.hasPrefix("$") || prop.hasPrefix("@")
        if pr?.hasImage == true {
            for f in ["linear-gradient()", "radial-gradient()", "conic-gradient()", "repeating-linear-gradient()", "url()", "image-set()"] { add(f, .function, detail: "image", insert: String(f.dropLast()) + "$1)", snippet: true, sort: "4" + f) }
        }
        if colorProp {
            for hex in documentColors(b) { add(hex, .color, detail: "used in this file", sort: "3" + hex) }
            for (name, hex) in NWCssData.namedColors.sorted(by: { $0.key < $1.key }) { add(name, .color, detail: hex, sort: "5" + name) }
            add("transparent", .color, detail: "rgba(0, 0, 0, 0)", sort: "5transparent"); add("currentColor", .color, detail: "the current text color", sort: "5currentColor")
            for f in ["rgb()", "rgba()", "hsl()", "hsla()", "hwb()", "lab()", "lch()", "color()", "oklch()", "oklab()", "color-mix()", "light-dark()"] { add(f, .function, detail: "color function", insert: String(f.dropLast()) + "$1)", snippet: true, sort: "4" + f) }
            if let tw, tw.version < 4, !prop.hasPrefix("--") { add("theme()", .function, detail: "tailwind", insert: "theme($1)", snippet: true) }
        }
        if ["transition", "transition-property", "will-change"].contains(prop) {
            for n in NWCssData.sortedPropNames.prefix(260) { add(n, .property, detail: "property", sort: "6" + n) }
        }
        for f in ["var()", "calc()", "min()", "max()", "clamp()", "env()"] where !(pr?.values.contains(f) ?? false) { add(f, .function, detail: "function", insert: String(f.dropLast()) + "$1)", snippet: true, sort: "7" + f) }
        if prop != "content" {
            let idx = NWCss.index(b, lang: lang, from: from)
            for n in customProps(p, current: idx, currentBuf: b, currentPath: url.path, limit: 250) {
                add("var(\(n.name))", .variable, detail: n.value, doc: "`\(n.name): \(n.value)`  \n\(n.file)", sort: n.file == "this file" ? "2" + n.name : "3" + n.name)
            }
        }
        return items
    }

    /// `#rgb` / `#rrggbb` / `#rrggbbaa` literals in the buffer (first 150 distinct), offered again for color properties.
    static func documentColors(_ b: NWBuf) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        var i = 0
        let n = b.count
        while i < n, out.count < 150 {
            if b[i] == 35 {
                var j = i + 1
                while j < n, (b[j] >= 48 && b[j] <= 57) || (b[j] >= 97 && b[j] <= 102) || (b[j] >= 65 && b[j] <= 70) { j += 1 }
                let len = j - i - 1
                if [3, 4, 6, 8].contains(len), j >= n || !NWChar.isIdent(b[j]) {
                    let s = b.str(i, j)
                    if seen.insert(s.lowercased()).inserted { out.append(s) }
                }
                i = max(j, i + 1)
            } else { i += 1 }
        }
        return out
    }

    private static func v4ThemeVars(_ tw: NWTailwind, range: NSRange, have: Set<String>) -> [CompletionItem] {
        var items: [CompletionItem] = []
        func add(_ name: String, _ value: String) { if !have.contains(name) { items.append(CI.make(name, .variable, detail: value, sort: "9" + name, doc: "`\(name): \(value)`  \nTailwind theme", range: range)) } }
        for (k, v) in tw.colors.sorted(by: { $0.key < $1.key }) { add("--color-" + k, v) }
        let ns: [(String, String)] = [("borderRadius", "--radius-"), ("boxShadow", "--shadow-"), ("fontSize", "--text-"), ("fontFamily", "--font-"), ("screens", "--breakpoint-"),
                                      ("transitionTimingFunction", "--ease-"), ("animation", "--animate-"), ("fontWeight", "--font-weight-"), ("lineHeight", "--leading-"), ("letterSpacing", "--tracking-")]
        for (key, pre) in ns { for (k, v) in tw.map(key).sorted(by: { $0.key < $1.key }) where k != "DEFAULT" { add(pre + k, v.replacingOccurrences(of: "|", with: " / ")) } }
        add("--spacing", tw.spacingBase ?? "0.25rem")
        return items
    }

    private static func themePaths(_ tw: NWTailwind, text: String, range: NSRange) -> [CompletionItem] {
        let typed = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        var out: [CompletionItem] = []
        if !typed.contains(".") {
            for k in (["colors"] + tw.maps.keys).sorted() { out.append(CI.make(k, .module, detail: "theme", range: range)) }
            return out
        }
        let key = String(typed.split(separator: ".", maxSplits: 1)[0])
        let tailRange = NSRange(location: range.location, length: range.length)
        if key == "colors" { for (k, v) in tw.colors.sorted(by: { $0.key < $1.key }) { out.append(CI.make("colors." + k.replacingOccurrences(of: "-", with: "."), .color, detail: v, filter: "colors." + k, range: tailRange)) } }
        else { for (k, v) in tw.map(key).sorted(by: { $0.key < $1.key }) { out.append(CI.make(key + "." + k, .value, detail: v, range: tailRange)) } }
        return out
    }

    // MARK: hover / definition

    /// Hover text and definition targets for the token at `offset`. Usage search (CSS class -> markup) only when `usages` is set.
    static func lookup(_ p: NWProject, _ b: NWBuf, offset: Int, from: Int, lang: NWCssLang, url: URL, tw: NWTailwind?, limit: Int? = nil, usages: Bool = false) -> NPHit? {
        var s = offset, e = offset
        let hi = min(limit ?? b.count, b.count)
        while s > from, NWChar.isIdent(b[s - 1]) { s -= 1 }
        while e < hi, NWChar.isIdent(b[e]) { e += 1 }
        // string tokens (@import "x", url("x")) are handled before the identifier logic
        let pos0 = NWCss.position(b, from: from, caret: min(offset, hi), lang: lang)
        if pos0.kind == .string, let hit = stringTarget(p, b, pos0, offset: offset, hi: hi, url: url) { return hit }
        guard e > s else { return nil }
        let word = b.str(s, e)
        let range = NSRange(location: s, length: e - s)
        let pos = NWCss.position(b, from: from, caret: e, lang: lang)
        let prev: unichar = s > from ? b[s - 1] : 0
        switch pos.kind {
        case .atName:
            guard let a = NWCssData.atRules.first(where: { $0.name == word.lowercased() }) else {
                if let m = (NWCssData.sassAtRules.first { $0.0 == word.lowercased() }) { return NPHit(range: range, targets: [], markdown: "**@\(m.0)**\n\n\(m.1)", kind: "css-atrule") }
                return atRuleDoc(word, tw).map { NPHit(range: range, targets: [], markdown: $0, kind: "css-atrule") }
            }
            return NPHit(range: range, targets: [], markdown: "**@\(a.name)**\n\n\(a.doc)", kind: "css-atrule")
        case .atParams:
            if pos.atName == "apply", let tw {
                var ts = offset, te = offset
                while ts > pos.stmtStart, !NWChar.isSpace(b[ts - 1]), b[ts - 1] != 59 { ts -= 1 }
                while te < hi, !NWChar.isSpace(b[te]), b[te] != 59 { te += 1 }
                let site = NWClassSite(tokenRange: NSRange(location: ts, length: te - ts), listRange: NSRange(location: ts, length: te - ts))
                if let hit = NWTailwindService.lookup(tw, p, b, site: site, offset: offset, url: url) { return hit }
                // custom class used by @apply: jump to its rule
                let name = b.str(ts, te)
                let defs = classDefinitions(p, name: name, b: b, lang: lang, url: url, from: from)
                if !defs.isEmpty { return NPHit(range: site.tokenRange, targets: defs, markdown: "", kind: "css-class") }
            }
            if pos.atName == "import" || pos.atName == "use" || pos.atName == "forward" { return nil }
            return nil
        case .property:
            if word.hasPrefix("--") { return customPropHit(p, b, name: word, range: range, lang: lang, url: url, from: from) }
            guard let pr = NWCssData.props[word.lowercased()] else { return nil }
            var md = "**\(pr.name)**"
            if !pr.doc.isEmpty { md += "\n\n" + pr.doc }
            if !pr.values.isEmpty { md += "\n\nValues: " + pr.values.prefix(14).map { "`\($0)`" }.joined(separator: " ") }
            return NPHit(range: range, targets: [], markdown: md, kind: "css-property")
        case .paren:
            if pos.prop == "var", word.hasPrefix("--") {
                if let h = customPropHit(p, b, name: word, range: range, lang: lang, url: url, from: from) { return h }
                return enclosingProperty(b, pos: pos, from: from).flatMap { valueDoc($0, word) }.map { NPHit(range: range, targets: [], markdown: $0, kind: "css-property") }
            }
            if pos.prop == "theme", let tw, tw.version < 4 {
                let full = b.str(pos.prefixStart, hi)
                let path = full.prefix { $0 != ")" && $0 != "," }.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                if let v = NWTailwindLoader.themeLookup(tw, path) { return NPHit(range: NSRange(location: pos.prefixStart, length: path.utf16.count), targets: [], markdown: "`theme('\(path)')` = `\(v)`", kind: "tailwind-theme") }
            }
            return nil
        case .value:
            if pos.prop.hasPrefix("--") || pos.prop.hasPrefix("$"), word.hasPrefix("--") {
                return customPropHit(p, b, name: word, range: range, lang: lang, url: url, from: from)
            }
            if prev == 35, let c = NWCssData.parseHex("#" + word) {
                let hr = NSRange(location: s - 1, length: e - s + 1)
                return NPHit(range: hr, targets: [], markdown: "Color `#\(word)` (rgb \(c.r), \(c.g), \(c.b)\(c.a < 1 ? ", alpha \(String(format: "%.2f", c.a))" : ""))", kind: "css-color")
            }
            if let hex = NWCssData.namedColors[word.lowercased()] {
                if let c = NWCssData.parseHex(hex) { return NPHit(range: range, targets: [], markdown: "Color `\(word)` = `\(hex)` (rgb \(c.r), \(c.g), \(c.b))", kind: "css-color") }
            }
            if let md = valueDoc(pos.prop, word) { return NPHit(range: range, targets: [], markdown: md, kind: "css-value") }
            return nil
        case .selector:
            if prev == 58 {
                let double = s > from + 1 && b[s - 2] == 58
                let all = double ? NWCssData.pseudoElements : NWCssData.pseudoClasses + NWCssData.pseudoElements
                guard let d = all.first(where: { $0.name == word || $0.name == word + "()" }) else { return nil }
                return NPHit(range: range, targets: [], markdown: "**\(double ? "::" : ":")\(d.name)**\n\n\(d.doc)", kind: "css-pseudo")
            }
            if prev == 46 || prev == 35 {
                let isId = prev == 35
                var targets: [NPTarget] = []
                if usages { targets = NWNav.usages(of: word, isId: isId, in: p, current: nil) }
                // other rules for the same selector (hover): show the first few
                var md = ""
                if !usages {
                    let defs = selectorRules(p, name: word, isId: isId, b: b, lang: lang, url: url, from: from, limit: 3)
                    if defs.count > 1 { md = defs.map { "```css\n\($0.text)\n```\n*\($0.file)*" }.joined(separator: "\n\n") }
                }
                guard !targets.isEmpty || !md.isEmpty else { return nil }
                return NPHit(range: NSRange(location: s - 1, length: e - s + 1), targets: targets, markdown: md, kind: isId ? "css-id" : "css-class")
            }
            if NWCssData.tagNames.contains(word.lowercased()), let t = NWHtmlData.tagMap[word.lowercased()] {
                return NPHit(range: range, targets: [], markdown: "**<\(t.name)>**\n\n\(t.doc)", kind: "css-tag")
            }
            return nil
        case .none, .comment, .string: return nil
        }
    }

    /// The property of the declaration that contains a `var(` / `calc(` call (text before the statement's first colon).
    private static func enclosingProperty(_ b: NWBuf, pos: NWCss.Pos, from: Int) -> String? {
        var s = pos.stmtStart
        while s < b.count, NWChar.isSpace(b[s]) { s += 1 }
        var k = s
        while k < b.count, b[k] != 58, b[k] != 59, b[k] != 123, b[k] != 125 { k += 1 }
        guard k < b.count, b[k] == 58 else { return nil }
        return b.str(s, k).trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func atRuleDoc(_ name: String, _ tw: NWTailwind?) -> String? {
        let docs: [String: String] = ["tailwind": "Inserts Tailwind's `base`, `components`, `utilities` or `variants` layer.", "apply": "Inlines existing utility classes into your own CSS.",
                                      "theme": "Defines Tailwind design tokens (theme variables).", "utility": "Registers a custom utility class.", "variant": "Applies a Tailwind variant inside CSS.",
                                      "custom-variant": "Registers a custom Tailwind variant.", "source": "Registers an additional source for class detection.", "screen": "Media query for a configured Tailwind breakpoint.",
                                      "plugin": "Loads a Tailwind plugin.", "config": "Loads a Tailwind config file.", "reference": "Imports a stylesheet for reference only.", "layer": "Declares a cascade layer."]
        guard tw != nil, let d = docs[name.lowercased()] else { return nil }
        return "**@\(name)**\n\n\(d)"
    }

    /// Hovering a value (or an undeclared var()) shows the declaration's property, like the CSS language server does.
    private static func valueDoc(_ prop: String, _ word: String) -> String? {
        guard let pr = NWCssData.props[prop.lowercased()] else { return nil }
        var md = "**\(pr.name)**"
        if !pr.doc.isEmpty { md += "\n\n" + pr.doc }
        return md
    }

    // MARK: definitions

    private static func stringTarget(_ p: NWProject, _ b: NWBuf, _ pos: NWCss.Pos, offset: Int, hi: Int, url: URL) -> NPHit? {
        let at = pos.atName.isEmpty ? atNameOfStatement(b, pos.stmtStart) : pos.atName
        guard ["import", "use", "forward", "plugin", "config", "source", "reference"].contains(at) || b.str(pos.stringStart - 4, pos.stringStart).hasSuffix("url(") else { return nil }
        let q = b[pos.stringStart]
        var e = pos.stringStart + 1
        while e < hi, b[e] != q, b[e] != 10 { e += 1 }
        let ref = b.str(pos.stringStart + 1, e)
        guard let path = NWNav.resolveFile(ref, from: (url.path as NSString).deletingLastPathComponent, root: p.root) else { return nil }
        return NPHit(range: NSRange(location: pos.stringStart + 1, length: e - pos.stringStart - 1), targets: [NWNav.target(path: path, offset: 0)], markdown: "", kind: "css-import")
    }

    private static func atNameOfStatement(_ b: NWBuf, _ stmt: Int) -> String {
        var s = stmt
        while s < b.count, NWChar.isSpace(b[s]) { s += 1 }
        guard s < b.count, b[s] == 64 else { return "" }
        var k = s + 1
        while k < b.count, NWChar.isIdent(b[k]) { k += 1 }
        return b.str(s + 1, k).lowercased()
    }

    /// `--name` declarations: this buffer first, then the project.
    static func customPropHit(_ p: NWProject, _ b: NWBuf, name: String, range: NSRange, lang: NWCssLang, url: URL, from: Int) -> NPHit? {
        var targets: [NPTarget] = []
        var md: [String] = []
        let own = NWCss.index(b, lang: lang, from: from)
        for pr in own.props where pr.name == name {
            targets.append(NWNav.target(path: url.path, offset: Int(pr.offset), text: b.ns))
            md.append("```css\n\(name): \(pr.value);\n```")
        }
        for (path, idx) in p.allCSSIndexes() where path != url.path {
            for pr in idx.props where pr.name == name && targets.count < 12 {
                guard let text = FastProject.readRaw(path) else { continue }
                targets.append(NWNav.target(path: path, offset: Int(pr.offset), text: text))
                md.append("```css\n\(name): \(pr.value);\n```\n*\((path as NSString).lastPathComponent)*")
            }
        }
        if targets.isEmpty, let tw = p.tailwind(near: (url.path as NSString).deletingLastPathComponent), tw.version >= 4 {
            let n = String(name.dropFirst(2))
            if n.hasPrefix("color-"), let v = tw.colors[String(n.dropFirst(6))] { return NPHit(range: range, targets: [], markdown: "```css\n\(name): \(v);\n```\n*Tailwind theme*", kind: "css-var") }
        }
        guard !targets.isEmpty else { return nil }
        var seenMD = Set<String>()
        return NPHit(range: range, targets: targets, markdown: md.filter { seenMD.insert($0).inserted }.prefix(3).joined(separator: "\n\n"), kind: "css-var")
    }

    static func classDefinitions(_ p: NWProject, name: String, b: NWBuf?, lang: NWCssLang, url: URL?, from: Int, ids: Bool = false) -> [NPTarget] {
        var out: [NPTarget] = []
        if let b, let url {
            for s in NWCss.index(b, lang: lang, from: from).sels where s.name == name && s.isId == ids { out.append(NWNav.target(path: url.path, offset: Int(s.offset), text: b.ns)) }
        }
        for (path, idx) in p.allCSSIndexes() where path != url?.path && out.count < 60 {
            let hits = idx.sels.filter { $0.name == name && $0.isId == ids }
            guard !hits.isEmpty, let text = FastProject.readRaw(path) else { continue }
            for s in hits.prefix(6) { out.append(NWNav.target(path: path, offset: Int(s.offset), text: text)) }
        }
        return out
    }

    static func selectorRules(_ p: NWProject, name: String, isId: Bool, b: NWBuf?, lang: NWCssLang, url: URL?, from: Int, limit: Int) -> [(text: String, file: String)] {
        var out: [(String, String)] = []
        func take(_ idx: NWCssIndex, _ buf: NWBuf, _ file: String) {
            for s in idx.sels where s.name == name && s.isId == isId && out.count < limit {
                let a = Int(s.ruleStart), e = min(Int(s.ruleEnd), a + 700)
                out.append((buf.str(a, e).trimmingCharacters(in: .whitespacesAndNewlines), file))
            }
        }
        if let b, let url { take(NWCss.index(b, lang: lang, from: from), b, (url.path as NSString).lastPathComponent) }
        for (path, idx) in p.allCSSIndexes() where path != url?.path && out.count < limit {
            guard idx.sels.contains(where: { $0.name == name && $0.isId == isId }), let t = FastProject.readRaw(path) else { continue }
            take(idx, NWBuf(t), (path as NSString).lastPathComponent)
        }
        return out
    }
}
