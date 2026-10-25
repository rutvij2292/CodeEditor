import Foundation

// MARK: - SFC blocks

struct VSBlock {
    var tag: String                  // template / script / style / custom block name (lowercased)
    var open: NSRange                // the opening tag `<script setup lang="ts">`
    var content: NSRange
    var isSetup = false
    var lang = ""
    var src: String?
    var srcRange: NSRange?
}

enum VSSFC {
    /// Top level blocks of a single file component. The template block ends at its matching `</template>` (nested `<template v-if>` counted).
    static func blocks(_ ns: NSString) -> [VSBlock] {
        let n = ns.length
        guard n > 0 else { return [] }
        let u = VSLex.chars(ns, NSRange(location: 0, length: n))
        var out: [VSBlock] = []
        var i = 0
        func lower(_ a: Int, _ b: Int) -> String { String(utf16CodeUnits: Array(u[a..<b]), count: b - a).lowercased() }
        func starts(_ at: Int, _ s: String) -> Bool {
            let w = Array(s.utf16)
            guard at + w.count <= n else { return false }
            for k in 0..<w.count where (u[at + k] | 0x20) != w[k] && u[at + k] != w[k] { return false }
            return true
        }
        func find(_ s: String, from: Int) -> Int {
            var k = from
            while k < n { if u[k] == 60, starts(k, s) { return k }; k += 1 }
            return n
        }
        while i < n {
            if u[i] != 60 { i += 1; continue }
            if starts(i, "<!--") {
                var k = i + 4
                while k + 2 < n, !(u[k] == 45 && u[k + 1] == 45 && u[k + 2] == 62) { k += 1 }
                i = min(n, k + 3)
                continue
            }
            var nameEnd = i + 1
            while nameEnd < n, VSLex.isIdPart(u[nameEnd]) || u[nameEnd] == 45 { nameEnd += 1 }
            guard nameEnd > i + 1 else { i += 1; continue }
            let tag = lower(i + 1, nameEnd)
            // end of the open tag, honouring quotes
            var k = nameEnd
            var quote: unichar = 0
            while k < n {
                let c = u[k]
                if quote != 0 { if c == quote { quote = 0 } } else if c == 34 || c == 39 { quote = c } else if c == 62 { break }
                k += 1
            }
            guard k < n else { break }
            let openRange = NSRange(location: i, length: k + 1 - i)
            let selfClosing = u[k - 1] == 47
            var b = VSBlock(tag: tag, open: openRange, content: NSRange(location: k + 1, length: 0))
            let attrText = lower(nameEnd, k)
            b.isSetup = attrText.range(of: #"(^|\s)setup(\s|=|/|$)"#, options: .regularExpression) != nil
            if let r = attrText.range(of: #"lang\s*=\s*["']?([a-z0-9]+)"#, options: .regularExpression) {
                b.lang = String(attrText[r]).components(separatedBy: CharacterSet(charactersIn: "=\"' ")).last(where: { !$0.isEmpty && $0 != "lang" }) ?? ""
            }
            // src attribute value with its range
            if let r = attrText.range(of: #"(^|\s)src\s*=\s*["']"#, options: .regularExpression) {
                let afterQuote = nameEnd + attrText.distance(from: attrText.startIndex, to: r.upperBound)
                let q = u[afterQuote - 1]
                var e = afterQuote
                while e < k, u[e] != q { e += 1 }
                b.srcRange = NSRange(location: afterQuote, length: e - afterQuote)
                b.src = ns.substring(with: b.srcRange!)
            }
            if selfClosing { out.append(b); i = k + 1; continue }
            var end: Int
            if tag == "template" {
                var depth = 1
                var p = k + 1
                end = n
                while p < n {
                    if u[p] == 60 {
                        if starts(p, "<!--") {
                            var q = p + 4
                            while q + 2 < n, !(u[q] == 45 && u[q + 1] == 45 && u[q + 2] == 62) { q += 1 }
                            p = min(n, q + 3)
                            continue
                        }
                        if starts(p, "<template"), p + 9 < n, !(VSLex.isIdPart(u[p + 9]) || u[p + 9] == 45) {
                            // self closing `<template ... />` does not nest
                            var q = p + 9
                            var qu: unichar = 0
                            while q < n { let c = u[q]; if qu != 0 { if c == qu { qu = 0 } } else if c == 34 || c == 39 { qu = c } else if c == 62 { break }; q += 1 }
                            if q < n, u[q - 1] != 47 { depth += 1 }
                            p = q + 1
                            continue
                        }
                        if starts(p, "</template") {
                            depth -= 1
                            if depth == 0 { end = p; break }
                        }
                    }
                    p += 1
                }
            } else {
                end = find("</" + tag, from: k + 1)
            }
            b.content = NSRange(location: k + 1, length: max(0, end - (k + 1)))
            out.append(b)
            var after = end
            while after < n, u[after] != 62 { after += 1 }
            i = min(n, after + 1)
        }
        return out
    }
}

// MARK: - Template scanner

struct VSAttr {
    var name: String
    var nameRange: NSRange
    var value: NSRange?              // inner range (quotes excluded)
    var quote: unichar = 0
    var valueOpen = false            // value quote not closed before the end of the scanned text (completion)
}

struct VSElem {
    var name: String
    var nameRange: NSRange
    var tagStart: Int
    var openEnd: Int                 // index after `>`; -1 when the tag is not finished
    var selfClosing = false
    var attrs: [VSAttr] = []
    var parent: Int
    var closeNameRange: NSRange?
    var afterNameWhitespace = false  // incomplete tag: whitespace follows the name (completion: attribute position)
}

final class VSTemplate {
    var elems: [VSElem] = []
    var interps: [(range: NSRange, parent: Int)] = []
    var openInterp: Int?             // start of an unterminated `{{` (completion)
    var openStack: [Int] = []        // elements still open at the end of the scanned text

    static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]

    /// Scans `range` of `ns`. `toEnd`: the text may end inside a tag or interpolation (completion).
    static func scan(_ ns: NSString, range: NSRange) -> VSTemplate {
        let t = VSTemplate()
        let base = range.location
        let u = VSLex.chars(ns, range)
        let n = u.count
        var stack: [Int] = []
        var i = 0
        func name(_ a: Int, _ b: Int) -> String { String(utf16CodeUnits: Array(u[a..<b]), count: b - a) }
        func isNameChar(_ c: unichar) -> Bool { VSLex.isIdPart(c) || c == 45 || c == 58 || c == 46 }
        while i < n {
            let c = u[i]
            if c == 123, i + 1 < n, u[i + 1] == 123 {                        // {{ ... }}
                var k = i + 2
                while k + 1 < n, !(u[k] == 125 && u[k + 1] == 125) { k += 1 }
                if k + 1 < n {
                    t.interps.append((NSRange(location: base + i + 2, length: k - i - 2), stack.last ?? -1))
                    i = k + 2
                } else { t.openInterp = base + i + 2; i = n }
                continue
            }
            guard c == 60 else { i += 1; continue }
            if i + 3 < n, u[i + 1] == 33, u[i + 2] == 45, u[i + 3] == 45 {            // comment
                var k = i + 4
                while k + 2 < n, !(u[k] == 45 && u[k + 1] == 45 && u[k + 2] == 62) { k += 1 }
                i = k + 3
                continue
            }
            if i + 1 < n, u[i + 1] == 47 {                                              // closing tag
                var k = i + 2
                while k < n, isNameChar(u[k]) { k += 1 }
                let nm = name(i + 2, k)
                var e = k
                while e < n, u[e] != 62 { e += 1 }
                if !nm.isEmpty {
                    if let pos = stack.lastIndex(where: { t.elems[$0].name.caseInsensitiveCompare(nm) == .orderedSame }) {
                        t.elems[stack[pos]].closeNameRange = NSRange(location: base + i + 2, length: k - i - 2)
                        stack.removeSubrange(pos...)
                    }
                }
                i = e + 1
                continue
            }
            guard i + 1 < n, VSLex.isIdStart(u[i + 1]) else { i += 1; continue }
            var k = i + 1
            while k < n, isNameChar(u[k]) { k += 1 }
            var el = VSElem(name: name(i + 1, k), nameRange: NSRange(location: base + i + 1, length: k - i - 1), tagStart: base + i, openEnd: -1, parent: stack.last ?? -1)
            var finished = false
            while k < n {
                var sawSpace = false
                while k < n, u[k] == 32 || u[k] == 10 || u[k] == 9 || u[k] == 13 { k += 1; sawSpace = true }
                if k >= n { el.afterNameWhitespace = sawSpace; break }
                if u[k] == 62 { k += 1; finished = true; el.openEnd = base + k; break }
                if u[k] == 47, k + 1 < n, u[k + 1] == 62 { k += 2; finished = true; el.selfClosing = true; el.openEnd = base + k; break }
                if u[k] == 47 { k += 1; continue }
                let a = k
                while k < n, !(u[k] == 32 || u[k] == 10 || u[k] == 9 || u[k] == 13 || u[k] == 61 || u[k] == 62 || (u[k] == 47 && k + 1 < n && u[k + 1] == 62)) { k += 1 }
                if k == a { k += 1; continue }
                var attr = VSAttr(name: name(a, k), nameRange: NSRange(location: base + a, length: k - a))
                var p = k
                while p < n, u[p] == 32 || u[p] == 10 || u[p] == 9 || u[p] == 13 { p += 1 }
                if p < n, u[p] == 61 {
                    p += 1
                    while p < n, u[p] == 32 || u[p] == 10 || u[p] == 9 || u[p] == 13 { p += 1 }
                    if p < n, u[p] == 34 || u[p] == 39 {
                        let q = u[p]
                        var e = p + 1
                        while e < n, u[e] != q { e += 1 }
                        attr.quote = q
                        attr.value = NSRange(location: base + p + 1, length: e - p - 1)
                        if e >= n { attr.valueOpen = true }
                        k = min(n, e + 1)
                    } else {
                        var e = p
                        while e < n, !(u[e] == 32 || u[e] == 10 || u[e] == 9 || u[e] == 13 || u[e] == 62) { e += 1 }
                        attr.value = NSRange(location: base + p, length: e - p)
                        k = e
                    }
                }
                el.attrs.append(attr)
                if attr.valueOpen { k = n; break }
            }
            t.elems.append(el)
            let idx = t.elems.count - 1
            if finished {
                let lname = el.name.lowercased()
                if !el.selfClosing, !voidTags.contains(lname) {
                    if lname == "script" || lname == "style" || lname == "textarea" {
                        // raw text: skip to the closing tag
                        var e = k
                        let close = Array(("</" + lname).utf16)
                        while e + close.count <= n {
                            var ok = true
                            for q in 0..<close.count where (u[e + q] | 0x20) != close[q] { ok = false; break }
                            if ok { break }
                            e += 1
                        }
                        i = min(n, e)
                        continue
                    }
                    stack.append(idx)
                }
                i = k
            } else { i = n; stack.append(idx) }
        }
        t.openStack = stack
        return t
    }

    /// The element whose open tag contains `offset` (tag name, attributes, whitespace between them).
    func tag(containing offset: Int) -> Int? {
        var lo = 0, hi = elems.count - 1
        while lo <= hi {                                  // elements are in source order
            let mid = (lo + hi) / 2
            let e = elems[mid]
            if offset < e.tagStart { hi = mid - 1 }
            else if e.openEnd >= 0, offset >= e.openEnd { lo = mid + 1 }
            else { return mid }
        }
        return nil
    }

    // MARK: scope (v-for aliases, slot props)

    struct ScopeVar { var name: String; var loc: Int; var len: Int; var kind: String }

    static func isSlotAttr(_ n: String) -> Bool { n == "v-slot" || n.hasPrefix("v-slot:") || n.hasPrefix("#") || n == "slot-scope" }

    /// Names visible to expressions of element `e` (its own v-for aliases and every ancestor's v-for aliases / slot props; the element's own slot props
    /// only when `includeOwnSlots`, i.e. for its children).
    func scope(of e: Int, ns: NSString, includeOwnSlots: Bool) -> [ScopeVar] {
        var chain: [Int] = []
        var cur = e
        while cur >= 0 { chain.append(cur); cur = elems[cur].parent }
        var out: [ScopeVar] = []
        for x in chain.reversed() {
            for a in elems[x].attrs {
                guard let v = a.value, v.length > 0 else { continue }
                if a.name == "v-for" { out += VSTemplate.aliases(ns, v, forLoop: true, kind: "v-for") }
                else if VSTemplate.isSlotAttr(a.name), x != e || includeOwnSlots { out += VSTemplate.aliases(ns, v, forLoop: false, kind: "slot prop") }
            }
        }
        return out
    }

    static func aliases(_ ns: NSString, _ value: NSRange, forLoop: Bool, kind: String) -> [ScopeVar] {
        guard value.length > 0, value.length < 4000, NSMaxRange(value) <= ns.length else { return [] }
        let tk = VSLex.run(VSLex.chars(ns, value), base: value.location)
        var end = tk.count
        if forLoop {
            var i = 0
            while i < tk.count {
                if tk[i].kind == .ident, tk[i].text == "in" || tk[i].text == "of" { end = i; break }
                i = tk.match[i] >= 0 && tk[i].kind == .punct && tk.match[i] > i ? tk.match[i] + 1 : i + 1
            }
            if end == tk.count { return [] }
        }
        var lo = 0
        var hi = end
        if forLoop, hi > 0, tk[0].isP("("), tk.match[0] == hi - 1 { lo = 1; hi -= 1 }
        let parser = VSScriptParser(tk: tk, ns: ns, comp: VSComp(), setup: false)
        var out: [ScopeVar] = []
        var i = lo
        while i < hi {
            if tk[i].isP(",") { i += 1; continue }
            if tk[i].isP("{") || tk[i].isP("[") {
                for (n, idx) in parser.patternNames(i) { out.append(ScopeVar(name: n, loc: tk[idx].s, len: tk[idx].e - tk[idx].s, kind: kind)) }
                i = parser.skipBracket(i)
            } else if tk[i].kind == .ident {
                out.append(ScopeVar(name: tk[i].text, loc: tk[i].s, len: tk[i].e - tk[i].s, kind: kind))
                i += 1
                if i < hi, tk[i].isP("=") { while i < hi, !tk[i].isP(",") { i = parser.isOpen(i) ? parser.skipBracket(i) : i + 1 } }
            } else { i += 1 }
        }
        return out
    }
}

// MARK: - Expressions inside attribute values / interpolations

struct VSExpr {
    let tk: VSTokens
    let ns: NSString
    var arrowParams: [String: Int] = [:]          // name -> token index of the (first) declaration

    init(_ ns: NSString, _ range: NSRange) {
        self.ns = ns
        tk = VSLex.run(range.length > 0 && NSMaxRange(range) <= ns.length ? VSLex.chars(ns, range) : [], base: range.location)
        let parser = VSScriptParser(tk: tk, ns: ns, comp: VSComp(), setup: false)
        for i in 0..<tk.count where tk[i].isP("=>") && i > 0 {
            let p = tk[i - 1]
            if p.kind == .ident { if arrowParams[p.text] == nil { arrowParams[p.text] = i - 1 } }
            else if p.isP(")"), tk.match[i - 1] >= 0 {
                let open = tk.match[i - 1]
                var k = open + 1
                while k < i - 1 {
                    if tk[k].isP(",") { k += 1; continue }
                    if tk[k].isP("{") || tk[k].isP("[") { for (n, idx) in parser.patternNames(k) where arrowParams[n] == nil { arrowParams[n] = idx }; k = parser.skipBracket(k) }
                    else if tk[k].kind == .ident { if arrowParams[tk[k].text] == nil { arrowParams[tk[k].text] = k }; k += 1; while k < i - 1, !tk[k].isP(",") { k = parser.isOpen(k) ? parser.skipBracket(k) : k + 1 } }
                    else { k += 1 }
                }
            }
        }
    }

    /// Index of the token containing `offset` (end inclusive for identifiers).
    func token(at offset: Int) -> Int? {
        for i in 0..<tk.count where offset >= tk[i].s && offset <= tk[i].e { if offset == tk[i].e, i + 1 < tk.count, tk[i + 1].s == offset { continue }; return i }
        return nil
    }

    func isMember(_ i: Int) -> Bool { i > 0 && (tk[i - 1].isP(".") || tk[i - 1].isP("?.")) }

    /// Object literal key (`{ a: 1 }`), not a reference.
    func isObjectKey(_ i: Int) -> Bool {
        guard i + 1 < tk.count, tk[i + 1].isP(":") else { return false }
        guard i > 0 else { return false }
        if tk[i - 1].isP("{") || tk[i - 1].isP(",") {
            // inside braces (not a call argument list or ternary)
            var depth = 0
            var k = i - 1
            while k >= 0 {
                if tk[k].isP("}") || tk[k].isP(")") || tk[k].isP("]") { depth += 1 }
                else if tk[k].isP("{") || tk[k].isP("(") || tk[k].isP("[") { if depth == 0 { return tk[k].isP("{") }; depth -= 1 }
                k -= 1
            }
        }
        return false
    }
}
