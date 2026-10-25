import Foundation

enum NWCssLang { case css, scss, less }

struct NWCssSel {
    var name: String
    var isId: Bool
    var offset: Int32        // start of the name (after `.` / `#`)
    var ruleStart: Int32     // start of the rule prelude
    var ruleEnd: Int32       // after the closing brace (-1 while open)
}

struct NWCssProp {
    var name: String         // `--x`, `$x` (scss) or `@x` (less)
    var offset: Int32
    var valueStart: Int32
    var valueEnd: Int32
    var inTheme: Bool        // declared inside an `@theme` block (Tailwind v4)
    var value: String        // trimmed value text (custom properties only, capped)
}

struct NWCssAt {
    var name: String         // import, utility, custom-variant, theme, keyframes, config, plugin, source, use, forward, tailwind, apply
    var params: String
    var offset: Int32        // start of params
}

/// Everything the navigation / completion needs from one stylesheet; compact (a few dozen bytes per selector).
final class NWCssIndex {
    var sels: [NWCssSel] = []
    var props: [NWCssProp] = []
    var ats: [NWCssAt] = []
    var length = 0
    var approxBytes: Int { sels.count * 56 + props.count * 110 + ats.count * 80 + 256 }
}

enum NWCss {
    static func lang(path: String) -> NWCssLang {
        switch (path as NSString).pathExtension.lowercased() {
        case "scss", "sass": return .scss
        case "less": return .less
        default: return .css
        }
    }

    private static let maxSels = 40_000

    /// Skips whitespace and complete comments (`/* */`, and `//` for scss / less) from `a` towards `e`.
    static func skipTrivia(_ b: NWBuf, _ a: Int, _ e: Int, lang: NWCssLang) -> Int {
        var i = a
        let end = min(e, b.count)
        while i < end {
            let c = b[i]
            if NWChar.isSpace(c) { i += 1; continue }
            if c == 47, i + 1 < b.count, b[i + 1] == 42 {
                var j = i + 2
                while j + 1 < b.count, !(b[j] == 42 && b[j + 1] == 47) { j += 1 }
                if j + 1 >= b.count || j + 2 > end { return i }
                i = j + 2; continue
            }
            if c == 47, lang != .css, i + 1 < b.count, b[i + 1] == 47 {
                var j = i
                while j < b.count, b[j] != 10 { j += 1 }
                if j >= end { return i }
                i = j; continue
            }
            break
        }
        return i
    }

    /// One pass over the stylesheet. Tolerant: unbalanced braces, comments, strings, `//` comments (scss / less) and `#{}` interpolation.
    static func index(_ b: NWBuf, lang: NWCssLang, from: Int = 0, to: Int? = nil) -> NWCssIndex {
        let idx = NWCssIndex()
        let n = min(to ?? b.count, b.count)
        idx.length = n
        struct Frame { var firstSel: Int; var name: String; var theme: Bool; var classes: [String] }
        var stack: [Frame] = []
        var stmt = from
        var paren = 0
        var i = from

        func skipString(_ q: unichar) {
            i += 1
            while i < n {
                let c = b[i]
                if c == 92 { i += 2; continue }
                if c == q || c == 10 { return }
                i += 1
            }
        }
        func skipInterp() {          // at `#{`
            var d = 0
            while i < n {
                if b[i] == 123 { d += 1 } else if b[i] == 125 { d -= 1; if d == 0 { return } }
                i += 1
            }
        }
        func firstNonSpace(_ a: Int, _ e: Int) -> Int { skipTrivia(b, a, e, lang: lang) }

        /// Handles one finished statement (up to `;` or `}`): custom properties, variables, at-rule statements.
        func statement(_ a: Int, _ e: Int) {
            let s = firstNonSpace(a, e)
            guard s < e else { return }
            let c = b[s]
            if c == 64 {                                   // @import "x"; @use ...; @plugin; @source; @config; @tailwind; @apply
                var k = s + 1
                while k < e, NWChar.isIdent(b[k]) { k += 1 }
                let name = b.str(s + 1, k).lowercased()
                // Less variables `@var: value;` are declarations, not at-rules.
                if lang == .less, k < e, b[k] == 58 { addProp(s, k, valueFrom: k + 1, e); return }
                if ["import", "use", "forward", "config", "plugin", "source", "tailwind", "apply", "layer", "reference", "custom-variant", "utility", "variant"].contains(name) {
                    let ps = firstNonSpace(k, e)
                    idx.ats.append(NWCssAt(name: name, params: b.str(ps, min(e, ps + 240)).trimmingCharacters(in: .whitespacesAndNewlines), offset: Int32(ps)))
                }
                return
            }
            if stack.isEmpty && lang == .css { return }
            let isCustom = c == 45 && s + 1 < e && b[s + 1] == 45
            let isScssVar = c == 36 && lang == .scss
            guard isCustom || isScssVar else { return }
            var k = s + 1
            while k < e, NWChar.isIdent(b[k]) { k += 1 }
            var m = k
            while m < e, NWChar.isSpace(b[m]) { m += 1 }
            guard m < e, b[m] == 58 else { return }
            addProp(s, k, valueFrom: m + 1, e)
        }
        func addProp(_ s: Int, _ nameEnd: Int, valueFrom: Int, _ e: Int) {
            guard idx.props.count < maxSels else { return }
            let vs = firstNonSpace(valueFrom, e)
            var ve = e
            while ve > vs, NWChar.isSpace(b[ve - 1]) { ve -= 1 }
            idx.props.append(NWCssProp(name: b.str(s, nameEnd), offset: Int32(s), valueStart: Int32(vs), valueEnd: Int32(ve), inTheme: stack.contains { $0.theme },
                                       value: b.str(vs, min(ve, vs + 160))))
        }

        func prelude(_ a: Int, _ e: Int) {
            let s = firstNonSpace(a, e)
            var last = e
            while last > s, NWChar.isSpace(b[last - 1]) { last -= 1 }
            var frame = Frame(firstSel: idx.sels.count, name: "", theme: false, classes: [])
            defer { stack.append(frame) }
            guard s < last else { return }
            if b[s] == 64 {
                var k = s + 1
                while k < last, NWChar.isIdent(b[k]) { k += 1 }
                let name = b.str(s + 1, k).lowercased()
                frame.name = name
                let ps = firstNonSpace(k, last)
                let params = b.str(ps, min(last, ps + 240))
                if name == "theme" { frame.theme = true }
                if ["utility", "custom-variant", "variant", "keyframes", "theme", "media", "layer", "container", "font-face"].contains(name) || name.hasSuffix("keyframes") {
                    if name != "media" && name != "layer" && name != "container" && name != "font-face" {
                        idx.ats.append(NWCssAt(name: name.hasSuffix("keyframes") ? "keyframes" : name, params: params.trimmingCharacters(in: .whitespacesAndNewlines), offset: Int32(ps)))
                    }
                }
                return
            }
            if idx.sels.count >= maxSels { return }
            // selector list: `.class` and `#id` tokens (also inside :not() / :is()), not inside [attr] or strings
            var k = s
            var bracket = 0
            let parentClasses = stack.last?.classes ?? []
            while k < last {
                let c = b[k]
                if c == 47, k + 1 < last, b[k + 1] == 42 {
                    k += 2
                    while k + 1 < last, !(b[k] == 42 && b[k + 1] == 47) { k += 1 }
                    k += 2; continue
                }
                if c == 47, lang != .css, k + 1 < last, b[k + 1] == 47 { while k < last, b[k] != 10 { k += 1 }; continue }
                if c == 34 || c == 39 {
                    let q = c; k += 1
                    while k < last, b[k] != q { if b[k] == 92 { k += 1 }; k += 1 }
                    k += 1; continue
                }
                if c == 91 { bracket += 1; k += 1; continue }
                if c == 93 { bracket = max(0, bracket - 1); k += 1; continue }
                if bracket > 0 { k += 1; continue }
                if c == 35, k + 1 < last, b[k + 1] == 123 { var d = 0; while k < last { if b[k] == 123 { d += 1 } else if b[k] == 125 { d -= 1; if d == 0 { break } }; k += 1 }; k += 1; continue }
                if c == 38, lang != .css, k + 1 < last, b[k + 1] == 45 || b[k + 1] == 95 || NWChar.isNameStart(b[k + 1]) {      // `&-suffix`
                    var e = k + 1
                    while e < last, NWChar.isIdent(b[e]) { e += 1 }
                    let suffix = b.str(k + 1, e)
                    for p in parentClasses.prefix(4) {
                        let full = p + suffix
                        idx.sels.append(NWCssSel(name: full, isId: false, offset: Int32(k + 1), ruleStart: Int32(s), ruleEnd: -1))
                        frame.classes.append(full)
                    }
                    k = e; continue
                }
                if (c == 46 || c == 35), k + 1 < last {
                    let d = b[k + 1]
                    if NWChar.isNameStart(d) || d == 45 || d == 92 {
                        var e = k + 1
                        var name = ""
                        while e < last {
                            let x = b[e]
                            if x == 92, e + 1 < last { name.append(Character(UnicodeScalar(b[e + 1]) ?? " ")); e += 2; continue }
                            if NWChar.isIdent(x) { name.append(Character(UnicodeScalar(x) ?? " ")); e += 1; continue }
                            break
                        }
                        if !name.isEmpty, name != "-" {
                            idx.sels.append(NWCssSel(name: name, isId: c == 35, offset: Int32(k + 1), ruleStart: Int32(s), ruleEnd: -1))
                            if c == 46 { frame.classes.append(name) }
                        }
                        k = max(e, k + 1); continue
                    }
                }
                k += 1
            }
        }

        while i < n {
            let c = b[i]
            if c == 47, i + 1 < n, b[i + 1] == 42 {                 // /* */
                i += 2
                while i + 1 < n, !(b[i] == 42 && b[i + 1] == 47) { i += 1 }
                i += 2; continue
            }
            if c == 47, i + 1 < n, b[i + 1] == 47, lang != .css, paren == 0, i == 0 || b[i - 1] != 58 {     // // comment
                while i < n, b[i] != 10 { i += 1 }
                continue
            }
            if c == 34 || c == 39 { skipString(c); i += 1; continue }
            if c == 35, i + 1 < n, b[i + 1] == 123, lang != .css { skipInterp(); i += 1; continue }
            if c == 40 { paren += 1 } else if c == 41 { paren = max(0, paren - 1) }
            else if paren == 0 {
                if c == 123 { prelude(stmt, i); stmt = i + 1 }
                else if c == 125 {
                    statement(stmt, i)
                    if let f = stack.popLast() {
                        var k = f.firstSel
                        while k < idx.sels.count { if idx.sels[k].ruleEnd < 0 { idx.sels[k].ruleEnd = Int32(i + 1) }; k += 1 }
                    }
                    stmt = i + 1
                } else if c == 59 { statement(stmt, i); stmt = i + 1 }
            }
            i += 1
        }
        if stmt < n { statement(stmt, n) }
        for k in 0..<idx.sels.count where idx.sels[k].ruleEnd < 0 { idx.sels[k].ruleEnd = Int32(n) }
        return idx
    }

    // MARK: Position classification (completion / hover)

    struct Pos {
        enum Kind { case none, comment, string, selector, atName, atParams, property, value, paren }
        var kind: Kind = .none
        var prefixStart = 0          // start of the token being completed
        var stmtStart = 0
        var prop = ""                // value: the property; paren: the function name
        var atName = ""              // atName / atParams
        var text = ""                // statement text before the caret (atParams: after the name; value: after the colon)
        var frames: [String] = []    // enclosing at-rule names ("" = a style rule)
        var fn = ""                  // innermost function when in parentheses within a value
        var stringStart = 0
        var parenOpen = -1
    }

    private static let declBlocks: Set<String> = ["font-face", "page", "property", "counter-style", "font-feature-values", "viewport", "theme", "position-try",
                                                  "view-transition", "color-profile", "font-palette-values", "-ms-viewport"]

    /// Where `caret` sits in a stylesheet (or `<style>` content / `style=""` attribute value starting at `from`).
    /// `declarationsOnly` treats the region as the inside of a rule (inline `style` attribute).
    static func position(_ b: NWBuf, from: Int, caret: Int, lang: NWCssLang, declarationsOnly: Bool = false) -> Pos {
        var pos = Pos()
        let n = min(caret, b.count)
        var frames: [String] = declarationsOnly ? [""] : []
        var stmt = from
        var parens: [Int] = []
        var i = from
        var inComment = false
        var quote: unichar = 0, quoteStart = 0
        while i < n {
            let c = b[i]
            if c == 47, i + 1 < n + 1, i + 1 < b.count, b[i + 1] == 42 {
                var j = i + 2
                while j + 1 < b.count, !(b[j] == 42 && b[j + 1] == 47) { j += 1 }
                if j + 1 >= b.count || j + 2 > n { inComment = true; break }
                i = j + 2; continue
            }
            if c == 47, lang != .css, i + 1 < b.count, b[i + 1] == 47, parens.isEmpty, i == 0 || b[i - 1] != 58 {
                var j = i
                while j < b.count, b[j] != 10 { j += 1 }
                if j >= n { inComment = true; break }
                i = j; continue
            }
            if c == 34 || c == 39 {
                var j = i + 1
                var closed = false
                while j < b.count {
                    if b[j] == 92 { j += 2; continue }
                    if b[j] == c { closed = true; break }
                    if b[j] == 10 { break }
                    j += 1
                }
                if !closed || j >= n { quote = c; quoteStart = i; break }
                i = j + 1; continue
            }
            if c == 35, lang != .css, i + 1 < n, b[i + 1] == 123 {
                var d = 0
                while i < n { if b[i] == 123 { d += 1 } else if b[i] == 125 { d -= 1; if d == 0 { break } }; i += 1 }
                i += 1; continue
            }
            if c == 40 { parens.append(i) }
            else if c == 41 { _ = parens.popLast() }
            else if parens.isEmpty {
                if c == 123 {
                    var s = stmt
                    while s < i, NWChar.isSpace(b[s]) { s += 1 }
                    if s < i, b[s] == 64 {
                        var k = s + 1
                        while k < i, NWChar.isIdent(b[k]) { k += 1 }
                        frames.append(b.str(s + 1, k).lowercased())
                    } else { frames.append("") }
                    stmt = i + 1
                } else if c == 125 { _ = frames.popLast(); stmt = i + 1 }
                else if c == 59 { stmt = i + 1 }
            }
            i += 1
        }
        pos.frames = frames
        pos.stmtStart = stmt
        if inComment { pos.kind = .comment; return pos }
        if quote != 0 {
            pos.kind = .string; pos.stringStart = quoteStart
            pos.text = b.str(stmt, quoteStart)
            return pos
        }
        let s = skipTrivia(b, stmt, n, lang: lang)
        let text = b.str(s, n)
        if let open = parens.last {
            var k = open
            while k > from, NWChar.isSpace(b[k - 1]) { k -= 1 }
            let e = k
            while k > from, NWChar.isIdent(b[k - 1]) { k -= 1 }
            pos.fn = b.str(k, e).lowercased()
            pos.parenOpen = open
        }
        // at-rule prelude
        if s < n, b[s] == 64 {
            var k = s + 1
            while k < n, NWChar.isIdent(b[k]) { k += 1 }
            pos.atName = b.str(s + 1, k).lowercased()
            if k >= n { pos.kind = .atName; pos.prefixStart = s + 1; return pos }
            // `@apply`, `@include x` and Less `@var: v` statements live inside rule bodies
            pos.kind = .atParams
            pos.text = b.str(k, n)
            pos.prefixStart = NWChar.identStart(b, n, floor: k)
            if pos.atName == "apply" || pos.atName == "include" || pos.atName == "extend" { return pos }
            if lang == .less, k < n, b[k] == 58 { pos.kind = .value; pos.prop = "@" + pos.atName; pos.text = b.str(k + 1, n); pos.prefixStart = NWChar.identStart(b, n, floor: k) }
            return pos
        }
        if !parens.isEmpty, pos.fn == "var" || pos.fn == "theme" || pos.fn == "--theme" || pos.fn == "url" || pos.fn == "config" {
            pos.kind = .paren; pos.prop = pos.fn
            pos.prefixStart = identStartDashes(b, n, floor: parens.last! + 1)
            pos.text = b.str(parens.last! + 1, n)
            return pos
        }
        let top = frames.last
        let inRuleCtx: Bool = {
            guard let t = top else { return false }
            if t == "" || declBlocks.contains(t) { return true }
            return frames.contains("")       // nested at-rule inside a rule: declarations are allowed (CSS nesting)
        }()
        if !inRuleCtx || top.map({ $0.hasSuffix("keyframes") }) == true {
            pos.kind = .selector; pos.text = text; pos.prefixStart = identStartDashes(b, n, floor: s)
            if top?.hasSuffix("keyframes") == true { pos.kind = .none }
            return pos
        }
        // inside a declaration block: property name or value (or a nested selector)
        var colon = -1
        var depth = 0
        var k = s
        while k < n {
            let c = b[k]
            if c == 40 || c == 91 { depth += 1 } else if c == 41 || c == 93 { depth = max(0, depth - 1) }
            else if c == 58, depth == 0 { colon = k; break }
            k += 1
        }
        let nestedStart: Set<unichar> = [46, 35, 38, 91, 62, 43, 126, 42, 58]   // . # & [ > + ~ * :
        if s < n, nestedStart.contains(b[s]) || (s < n && b[s] == 44) {
            pos.kind = .selector; pos.text = text; pos.prefixStart = identStartDashes(b, n, floor: s); return pos
        }
        if colon < 0 {
            pos.kind = .property; pos.text = text
            pos.prefixStart = identStartDashes(b, n, floor: s)
            return pos
        }
        let prop = b.str(s, colon).trimmingCharacters(in: .whitespaces)
        pos.prop = prop.lowercased() == prop || prop.hasPrefix("--") || prop.hasPrefix("$") || prop.hasPrefix("@") ? prop : prop.lowercased()
        pos.kind = .value
        pos.text = b.str(colon + 1, n)
        var vs = n
        while vs > colon + 1, NWChar.isIdent(b[vs - 1]) || b[vs - 1] == 35 || b[vs - 1] == 33 || b[vs - 1] == 36 || b[vs - 1] == 46 || b[vs - 1] == 37 { vs -= 1 }
        pos.prefixStart = vs
        return pos
    }

    static func identStartDashes(_ b: NWBuf, _ from: Int, floor: Int) -> Int {
        var s = min(from, b.count)
        while s > floor, NWChar.isIdent(b[s - 1]) { s -= 1 }
        return s
    }
}
