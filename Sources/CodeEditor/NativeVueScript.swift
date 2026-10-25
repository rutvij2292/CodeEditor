import Foundation

// MARK: - Component summary model (compact, cacheable)

struct VSDecl {
    enum Kind: UInt8 { case imp, const, `let`, `var`, function, `class`, prop, data, computed, method, setup, inject }
    var name: String
    var kind: Kind
    var loc: Int
    var len: Int
    var detail: String = ""
    var initCall: String?
    var spec: String?            // `import('./X.vue')` found in the initializer (async components)
    var exportDefault = false
}

struct VSImport {
    var local: String
    var imported: String         // "default", "*" or the exported name
    var spec: String
    var loc: Int
    var len: Int
    var typeOnly = false
}

struct VSPropDecl {
    var name: String
    var loc: Int
    var len: Int
    var type: String = ""
    var required = false
    var doc: String = ""
    var isModel = false
}

struct VSEmitDecl {
    var name: String
    var loc: Int
    var len: Int
    var sig: String = ""
    var doc: String = ""
}

struct VSSlotDecl {
    var name: String             // "default" for the unnamed slot
    var loc: Int
    var props: [String] = []
    var doc: String = ""
}

struct VSReg {
    var key: String
    var loc: Int
    var valueIdent: String?
    var spec: String?
}

struct VSExportB {
    var name: String             // exported name ("default" included)
    var local: String?           // local binding (or the imported name for `export { a as b } from`)
    var spec: String?
    var loc: Int
}

final class VSComp {
    var path = ""
    var isSetup = false          // has <script setup>
    var hasOptions = false       // export default { ... } found
    var optionsName: String?
    var decls: [VSDecl] = []
    var imports: [VSImport] = []
    var props: [VSPropDecl] = []
    var emits: [VSEmitDecl] = []
    var slots: [VSSlotDecl] = []
    var regs: [VSReg] = []
    var exports: [VSExportB] = []
    var starExports: [String] = []
    var emitCalls: [VSEmitDecl] = []     // emit('x') / $emit('x') call sites
    var globalRegs: [VSReg] = []         // app.component('X', Y) (plain modules)
    var setupInsert: Int?                // where a new import statement goes in <script setup>
    var setupHasImport = false
    var rootOffset = 0           // where a jump to this component lands (template root element, else 0)
    var templateRange: NSRange?
    var stamp: Int64 = 0
    var isDeclaration = false    // parsed from a .d.ts (library component)
    var declName = ""            // d.ts: the component's const name
    var cost: Int {
        400 + decls.count * 120 + imports.count * 140 + props.count * 160 + emits.count * 120 + slots.count * 100 + regs.count * 100 + exports.count * 100
    }

    func decl(_ name: String) -> VSDecl? { decls.first { $0.name == name } }
    func imp(_ name: String) -> VSImport? { imports.first { $0.local == name } }
    func prop(_ name: String) -> VSPropDecl? {
        if let p = props.first(where: { $0.name == name }) { return p }
        let c = VSName.camel(name)
        return props.first { VSName.camel($0.name) == c }
    }
    func emit(_ name: String) -> VSEmitDecl? {
        if let e = emits.first(where: { $0.name == name }) { return e }
        let c = VSName.camel(name), k = VSName.kebab(name)
        return emits.first { $0.name == c || $0.name == k || VSName.camel($0.name) == c }
    }
}

enum VSName {
    /// `foo-bar` -> `fooBar` (Vue's camelize: only `-x` sequences).
    static func camel(_ s: String) -> String {
        guard s.contains("-") else { return s }
        var out = ""
        var up = false
        for ch in s {
            if ch == "-" { up = true; continue }
            if up { out += String(ch).uppercased(); up = false } else { out.append(ch) }
        }
        return out
    }
    static func pascal(_ s: String) -> String {
        let c = camel(s)
        guard let f = c.first else { return c }
        return String(f).uppercased() + c.dropFirst()
    }
    /// `FooBar` / `fooBar` -> `foo-bar` (Vue's hyphenate).
    static func kebab(_ s: String) -> String {
        var out = ""
        for (i, ch) in s.enumerated() {
            if ch.isUppercase { if i > 0 { out += "-" }; out += String(ch).lowercased() } else { out.append(ch) }
        }
        return out
    }
}

// MARK: - Script parser

struct VSScriptParser {
    let tk: VSTokens
    let ns: NSString
    var c: VSComp
    let setup: Bool
    var typeBodies: [String: Int] = [:]          // interface / type alias name -> index of its `{`

    init(tk: VSTokens, ns: NSString, comp: VSComp, setup: Bool) { self.tk = tk; self.ns = ns; self.c = comp; self.setup = setup }

    // MARK: helpers

    func isOpen(_ i: Int) -> Bool { tk.has(i) && tk[i].kind == .punct && (tk[i].text == "(" || tk[i].text == "[" || tk[i].text == "{") }
    func skipBracket(_ i: Int) -> Int { tk.match[i] >= 0 ? tk.match[i] + 1 : i + 1 }

    func slice(_ a: Int, _ b: Int, cap: Int = 100) -> String {
        guard a < b, tk.has(a), tk.has(b - 1) else { return "" }
        let r = NSRange(location: tk[a].s, length: max(0, tk[b - 1].e - tk[a].s))
        guard r.location >= 0, NSMaxRange(r) <= ns.length else { return "" }
        var s = ns.substring(with: r)
        s = s.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return s.count > cap ? String(s.prefix(cap)) + "…" : s
    }

    func firstLine(_ a: Int, _ b: Int) -> String {
        guard a < b, tk.has(a) else { return "" }
        let lo = tk[a].s
        let hi = min(ns.length, tk[min(b, tk.count) - 1].e)
        guard hi > lo else { return "" }
        var s = ns.substring(with: NSRange(location: lo, length: min(hi - lo, 400)))
        if let nl = s.firstIndex(where: { $0 == "\n" || $0 == "\r" }) { s = String(s[s.startIndex..<nl]) + " …" }
        s = s.trimmingCharacters(in: .whitespaces)
        return s.count > 140 ? String(s.prefix(140)) + "…" : s
    }

    func docText(_ idx: Int) -> String {
        guard let r = tk.docs[idx], r.location >= 0, NSMaxRange(r) <= ns.length else { return "" }
        return VSDoc.clean(ns.substring(with: r))
    }

    /// Statement boundary heuristics (ASI): a token on a new line starts a statement when the previous token ends an expression and this one cannot continue it.
    func startsStatement(prev: VSTok, cur: VSTok) -> Bool {
        guard cur.nl else { return false }
        if prev.kind == .punct, !(prev.text == ")" || prev.text == "]" || prev.text == "}") { return false }
        if cur.kind == .punct, [".", "?.", "(", "[", "+", "-", "*", "/", "?", ":", "&&", "||", "??", "=", "=>", ",", "==", "===", "!=", "!==", "<", ">", "<=", ">=", "|", "&"].contains(cur.text) { return false }
        if cur.kind == .tmpl { return false }
        if cur.kind == .ident, ["else", "catch", "finally", "as", "satisfies", "in", "of", "instanceof"].contains(cur.text) { return false }
        if prev.kind == .ident, ["return", "typeof", "new", "await", "async", "extends", "in", "of", "instanceof", "else", "do", "yield", "void", "delete", "as"].contains(prev.text) { return false }
        return true
    }

    func stmtEnd(_ from: Int, stopAtComma: Bool = false) -> Int {
        var j = from
        while j < tk.count {
            let t = tk[j]
            if j > from, startsStatement(prev: tk[j - 1], cur: t) { return j }
            if t.kind == .punct {
                if t.text == ";" { return j + 1 }
                if stopAtComma, t.text == "," { return j }
                if isOpen(j) { j = skipBracket(j); continue }
                if t.text == "}" || t.text == ")" || t.text == "]" { return j }
            }
            j += 1
        }
        return tk.count
    }

    // MARK: patterns

    /// Names bound by a destructuring pattern starting at the `{` / `[` at `open`.
    func patternNames(_ open: Int) -> [(String, Int)] {
        guard isOpen(open), tk.match[open] > open else { return [] }
        var out: [(String, Int)] = []
        let isObj = tk[open].text == "{"
        var i = open + 1
        let end = tk.match[open]
        while i < end {
            var j = i
            // one element up to the next top level comma
            var elemEnd = i
            while elemEnd < end {
                if tk[elemEnd].isP(",") { break }
                elemEnd = isOpen(elemEnd) ? skipBracket(elemEnd) : elemEnd + 1
            }
            elemEnd = min(elemEnd, end)
            if tk[j].isP("...") { j += 1 }
            if isObj {
                // key [: target] [= default]
                if j + 1 < elemEnd, tk[j + 1].isP(":") {
                    let t = j + 2
                    if t < elemEnd {
                        if isOpen(t) { out += patternNames(t) }
                        else if tk[t].kind == .ident { out.append((tk[t].text, t)) }
                    }
                } else if tk[j].kind == .ident { out.append((tk[j].text, j)) }
            } else if j < elemEnd {
                if isOpen(j) { out += patternNames(j) }
                else if tk[j].kind == .ident { out.append((tk[j].text, j)) }
            }
            i = elemEnd + 1
        }
        return out
    }

    // MARK: declarations

    mutating func parseVarDecl(_ i: Int) -> ([VSDecl], Int) {
        let kw = tk[i].text
        let kind: VSDecl.Kind = kw == "const" ? .const : kw == "let" ? .let : .var
        var j = i + 1
        var out: [VSDecl] = []
        let stmtStart = i
        while j < tk.count {
            var names: [(String, Int)] = []
            if tk[j].kind == .ident { names = [(tk[j].text, j)]; j += 1 }
            else if isOpen(j) { names = patternNames(j); j = skipBracket(j) }
            else { break }
            if j < tk.count, tk[j].isP(":") {                          // type annotation
                j += 1
                while j < tk.count, !(tk[j].isP("=") || tk[j].isP(",") || tk[j].isP(";")), !(tk[j].nl && j > 0 && startsStatement(prev: tk[j - 1], cur: tk[j])) {
                    j = isOpen(j) ? skipBracket(j) : j + 1
                }
            }
            var initCall: String?
            var spec: String?
            var declEnd = j
            if j < tk.count, tk[j].isP("=") {
                let initStart = j + 1
                declEnd = stmtEnd(initStart, stopAtComma: true)
                var k = initStart
                if k < declEnd, tk[k].isI("await") { k += 1 }
                if k < declEnd, tk[k].kind == .ident {
                    var callee = tk[k].text
                    var m = k + 1
                    while m + 1 < declEnd, tk[m].isP("."), tk[m + 1].kind == .ident { callee += "." + tk[m + 1].text; m += 2 }
                    if m < declEnd, tk[m].isP("(") || tk[m].isP("<") || tk[m].isP("?.") { initCall = callee }
                }
                var q = initStart
                while q + 2 < declEnd {                                  // import('./X.vue') anywhere in the initializer
                    if tk[q].isI("import"), tk[q + 1].isP("("), tk[q + 2].kind == .str { spec = tk[q + 2].text; break }
                    q += 1
                }
            }
            let detail = firstLine(stmtStart, max(declEnd, stmtStart + 1))
            for (name, idx) in names {
                var d = VSDecl(name: name, kind: kind, loc: tk[idx].s, len: tk[idx].e - tk[idx].s)
                d.detail = detail; d.initCall = initCall; d.spec = spec
                out.append(d)
            }
            j = declEnd
            if j < tk.count, tk[j].isP(",") { j += 1; continue }
            break
        }
        if j < tk.count, tk[j].isP(";") { j += 1 }
        return (out, max(j, i + 1))
    }

    func parseFunction(_ i: Int) -> (VSDecl?, Int) {
        var j = i
        if tk[j].isI("async") { j += 1 }
        guard tk.has(j), tk[j].isI("function") else { return (nil, i + 1) }
        j += 1
        if tk.has(j), tk[j].isP("*") { j += 1 }
        var decl: VSDecl?
        if tk.has(j), tk[j].kind == .ident {
            var d = VSDecl(name: tk[j].text, kind: .function, loc: tk[j].s, len: tk[j].e - tk[j].s)
            d.detail = firstLine(i, min(tk.count, j + 8))
            if let p = (j..<min(tk.count, j + 12)).first(where: { tk[$0].isP("(") }), tk.match[p] > p { d.detail = firstLine(i, tk.match[p] + 1) }
            decl = d
            j += 1
        }
        while j < tk.count, !tk[j].isP("("), !tk[j].isP("{") { j += 1 }
        if j < tk.count, tk[j].isP("(") { j = skipBracket(j) }
        while j < tk.count, !tk[j].isP("{"), !(tk[j].nl && j > 0 && startsStatement(prev: tk[j - 1], cur: tk[j])), !tk[j].isP(";") { j += 1 }
        if j < tk.count, tk[j].isP("{") { j = skipBracket(j) }
        return (decl, max(j, i + 1))
    }

    func parseClass(_ i: Int) -> (VSDecl?, Int) {
        var j = i + 1
        var decl: VSDecl?
        if tk.has(j), tk[j].kind == .ident, tk[j].text != "extends" {
            var d = VSDecl(name: tk[j].text, kind: .class, loc: tk[j].s, len: tk[j].e - tk[j].s)
            d.detail = firstLine(i, min(tk.count, j + 4))
            decl = d
            j += 1
        }
        while j < tk.count, !tk[j].isP("{") { j += 1 }
        if j < tk.count { j = skipBracket(j) }
        return (decl, max(j, i + 1))
    }

    mutating func parseImport(_ i: Int) -> Int {
        var j = i + 1
        guard tk.has(j) else { return j }
        if tk[j].kind == .str { return j + 1 }
        if tk[j].isP("(") || tk[j].isP(".") { return stmtEnd(i) }             // dynamic import() / import.meta used as an expression
        var typeOnly = false
        if tk[j].isI("type"), tk.has(j + 1), !tk[j + 1].isI("from"), !tk[j + 1].isP(",") { typeOnly = true; j += 1 }
        var pending: [(local: String, imported: String, idx: Int)] = []
        if tk.has(j), tk[j].kind == .ident, !tk[j].isI("from") || (tk.has(j + 1) && !tk[j + 1].kind.isString) {
            pending.append((tk[j].text, "default", j)); j += 1
            if tk.has(j), tk[j].isP(",") { j += 1 }
        }
        if tk.has(j), tk[j].isP("*") {
            j += 1
            if tk.has(j), tk[j].isI("as") { j += 1 }
            if tk.has(j), tk[j].kind == .ident { pending.append((tk[j].text, "*", j)); j += 1 }
        } else if tk.has(j), tk[j].isP("{"), tk.match[j] > j {
            let end = tk.match[j]
            var k = j + 1
            while k < end {
                var t = k
                if tk[t].isI("type"), t + 1 < end, !tk[t + 1].isP(","), !tk[t + 1].isI("as") { t += 1 }
                let imported = tk[t].kind == .str ? tk[t].text : tk[t].text
                var local = imported
                var li = t
                if t + 2 < end + 0, tk[t + 1].isI("as") { local = tk[t + 2].text; li = t + 2 }
                if tk[t].kind == .ident || tk[t].kind == .str { pending.append((local, imported, li)) }
                while k < end, !tk[k].isP(",") { k += 1 }
                k += 1
            }
            j = end + 1
        }
        if tk.has(j), tk[j].isI("from"), tk.has(j + 1), tk[j + 1].kind == .str {
            let spec = tk[j + 1].text
            for p in pending {
                c.imports.append(VSImport(local: p.local, imported: p.imported, spec: spec, loc: tk[p.idx].s, len: tk[p.idx].e - tk[p.idx].s, typeOnly: typeOnly))
                var d = VSDecl(name: p.local, kind: .imp, loc: tk[p.idx].s, len: tk[p.idx].e - tk[p.idx].s)
                d.detail = p.imported == "default" ? "import \(p.local) from '\(spec)'" : p.imported == "*" ? "import * as \(p.local) from '\(spec)'"
                    : p.imported == p.local ? "import { \(p.local) } from '\(spec)'" : "import { \(p.imported) as \(p.local) } from '\(spec)'"
                d.spec = spec
                c.decls.append(d)
            }
            j += 2
        }
        if tk.has(j), tk[j].isP(";") { j += 1 }
        if setup, j > i { c.setupInsert = tk[min(j, tk.count) - 1].e; c.setupHasImport = true }
        return j
    }

    mutating func parseExport(_ i: Int) -> Int {
        var j = i + 1
        guard tk.has(j) else { return j }
        let t = tk[j]
        if t.isI("default") {
            j += 1
            guard tk.has(j) else { return j }
            // options object: `{`, or `callee(...{`
            var obj = -1
            if tk[j].isP("{") { obj = j }
            else if tk[j].kind == .ident {
                var k = j
                while k + 2 < tk.count, tk[k + 1].isP("."), tk[k + 2].kind == .ident { k += 2 }
                if tk.has(k + 2), tk[k + 1].isP("("), tk[k + 2].isP("{") { obj = k + 2 }
                else if tk.has(k + 1), !tk[k + 1].isP("("), tk[k].kind == .ident, !["function", "class", "async"].contains(tk[k].text) {
                    c.exports.append(VSExportB(name: "default", local: tk[k].text, spec: nil, loc: tk[k].s))
                }
            }
            if obj >= 0 { parseOptions(obj) }
            return stmtEnd(j)
        }
        if t.isP("{") {
            let end = tk.match[j]
            guard end > j else { return j + 1 }
            var specs: [(String, String, Int)] = []        // exported name, local, loc
            var k = j + 1
            while k < end {
                var a = k
                if tk[a].isI("type"), a + 1 < end, !tk[a + 1].isP(","), !tk[a + 1].isI("as") { a += 1 }
                let local = tk[a].text
                var exported = local
                if a + 2 < end + 0, tk[a + 1].isI("as") { exported = tk[a + 2].text }
                specs.append((exported, local, tk[a].s))
                while k < end, !tk[k].isP(",") { k += 1 }
                k += 1
            }
            j = end + 1
            var spec: String?
            if tk.has(j), tk[j].isI("from"), tk.has(j + 1), tk[j + 1].kind == .str { spec = tk[j + 1].text; j += 2 }
            for s in specs { c.exports.append(VSExportB(name: s.0, local: s.1, spec: spec, loc: s.2)) }
            return j
        }
        if t.isP("*") {
            j += 1
            var alias: String?
            if tk.has(j), tk[j].isI("as"), tk.has(j + 1) { alias = tk[j + 1].text; j += 2 }
            if tk.has(j), tk[j].isI("from"), tk.has(j + 1), tk[j + 1].kind == .str {
                if let a = alias { c.exports.append(VSExportB(name: a, local: "*", spec: tk[j + 1].text, loc: tk[j + 1].s)) } else { c.starExports.append(tk[j + 1].text) }
                j += 2
            }
            return j
        }
        if t.kind == .ident, ["const", "let", "var"].contains(t.text) {
            let (ds, next) = parseVarDecl(j)
            for d in ds { c.decls.append(d); c.exports.append(VSExportB(name: d.name, local: d.name, spec: nil, loc: d.loc)) }
            return next
        }
        if t.kind == .ident, t.text == "function" || t.text == "async" {
            let (d, next) = parseFunction(j)
            if let d { c.decls.append(d); c.exports.append(VSExportB(name: d.name, local: d.name, spec: nil, loc: d.loc)) }
            return next
        }
        if t.isI("interface") || t.isI("type") { return parseTypeDecl(j) }
        if t.isI("class") {
            let (d, next) = parseClass(j)
            if let d { c.decls.append(d); c.exports.append(VSExportB(name: d.name, local: d.name, spec: nil, loc: d.loc)) }
            return next
        }
        return stmtEnd(i)
    }

    mutating func parseTypeDecl(_ i: Int) -> Int {
        if tk.has(i + 1), tk[i + 1].kind == .ident {
            var j = i + 2
            while j < tk.count, !tk[j].isP("{"), !tk[j].isP("="), !(tk[j].nl && startsStatement(prev: tk[j - 1], cur: tk[j])) { j = isOpen(j) ? skipBracket(j) : j + 1 }
            if j < tk.count, tk[j].isP("=") { j += 1 }
            if j < tk.count, tk[j].isP("{") { typeBodies[tk[i + 1].text] = j; return skipBracket(j) }
        }
        return max(i + 1, stmtEnd(i))
    }

    mutating func topLevel() {
        var i = 0
        while i < tk.count {
            let t = tk[i]
            guard t.kind == .ident else { i = max(i + 1, stmtEnd(i)); continue }
            switch t.text {
            case "import": i = parseImport(i)
            case "export": i = parseExport(i)
            case "const", "let", "var":
                let (ds, next) = parseVarDecl(i)
                c.decls += ds
                i = next
            case "function", "async":
                if t.text == "async", !(tk.has(i + 1) && tk[i + 1].isI("function")) { i = max(i + 1, stmtEnd(i)); break }
                let (d, next) = parseFunction(i)
                if let d { c.decls.append(d) }
                i = next
            case "class":
                let (d, next) = parseClass(i)
                if let d { c.decls.append(d) }
                i = next
            case "interface", "type": i = parseTypeDecl(i)
            default: i = max(i + 1, stmtEnd(i))
            }
        }
    }

    // MARK: object literal entries

    struct Entry {
        var key: String
        var keyIdx: Int
        var valueStart: Int          // first token of the value / method params; == keyIdx for shorthand
        var end: Int                 // index after the entry (before the comma)
        var isMethod = false
        var isSpread = false
        var shorthand = false
    }

    func entries(_ open: Int) -> [Entry] {
        guard isOpen(open), tk.match[open] > open else { return [] }
        let end = tk.match[open]
        var out: [Entry] = []
        var i = open + 1
        while i < end {
            if tk[i].isP(",") { i += 1; continue }
            var k = i
            if tk[k].isP("...") {
                var j = k + 1
                while j < end, !tk[j].isP(",") { j = isOpen(j) ? skipBracket(j) : j + 1 }
                out.append(Entry(key: "", keyIdx: k, valueStart: k + 1, end: j, isSpread: true))
                i = j
                continue
            }
            if tk[k].kind == .ident, ["async", "get", "set", "static"].contains(tk[k].text), k + 1 < end, !(tk[k + 1].isP(":") || tk[k + 1].isP("(") || tk[k + 1].isP(",") || tk[k + 1].isP("=")) { k += 1 }
            if tk[k].isP("*") { k += 1 }
            guard k < end, tk[k].kind == .ident || tk[k].kind == .str || tk[k].kind == .num else {
                var j = k
                while j < end, !tk[j].isP(",") { j = isOpen(j) ? skipBracket(j) : j + 1 }
                i = max(j, i + 1)
                continue
            }
            let key = tk[k].text
            let next = k + 1
            if next < end, tk[next].isP(":") {
                var j = next + 1
                while j < end, !tk[j].isP(",") { j = isOpen(j) ? skipBracket(j) : j + 1 }
                out.append(Entry(key: key, keyIdx: k, valueStart: next + 1, end: j))
                i = j
            } else if next < end, tk[next].isP("(") {
                var j = skipBracket(next)
                while j < end, !tk[j].isP("{"), !tk[j].isP(",") { j += 1 }          // return type annotation
                if j < end, tk[j].isP("{") { j = skipBracket(j) }
                out.append(Entry(key: key, keyIdx: k, valueStart: next, end: j, isMethod: true))
                i = j
            } else {
                var j = next
                while j < end, !tk[j].isP(",") { j = isOpen(j) ? skipBracket(j) : j + 1 }
                out.append(Entry(key: key, keyIdx: k, valueStart: k, end: j, shorthand: true))
                i = j
            }
        }
        return out
    }

    func strings(inArray open: Int) -> [(String, Int)] {
        guard isOpen(open), tk[open].isP("["), tk.match[open] > open else { return [] }
        var out: [(String, Int)] = []
        for k in (open + 1)..<tk.match[open] where tk[k].kind == .str { out.append((tk[k].text, k)) }
        return out
    }

    // MARK: props / emits (runtime and type forms)

    func typeText(_ start: Int, _ end: Int) -> String {
        guard start < end, tk.has(start) else { return "" }
        // `String as PropType<X>`: cut at `as`
        var e = start
        while e < end {
            if tk[e].isI("as") { break }
            e = isOpen(e) ? skipBracket(e) : e + 1
        }
        let r = slice(start, min(e, end))
        return r
    }

    func runtimeProps(_ open: Int) -> [VSPropDecl] {
        if tk[open].isP("[") { return strings(inArray: open).map { VSPropDecl(name: $0.0, loc: tk[$0.1].s, len: tk[$0.1].e - tk[$0.1].s, doc: docText($0.1)) } }
        var out: [VSPropDecl] = []
        for e in entries(open) where !e.isSpread {
            var p = VSPropDecl(name: e.key, loc: tk[e.keyIdx].s, len: tk[e.keyIdx].e - tk[e.keyIdx].s, doc: docText(e.keyIdx))
            let v = e.valueStart
            if v < e.end {
                if tk[v].isP("{") {
                    for sub in entries(v) where !sub.isSpread {
                        if sub.key == "type" { p.type = typeText(sub.valueStart, sub.end) }
                        if sub.key == "required", sub.valueStart < sub.end, tk[sub.valueStart].isI("true") { p.required = true }
                    }
                } else { p.type = typeText(v, e.end) }
            }
            out.append(p)
        }
        return out
    }

    /// Members of an interface / type literal body (`{` at `open`): property / method signatures, call signatures (`(e: 'x'): void`).
    func typeMembers(_ open: Int) -> [(name: String, idx: Int, optional: Bool, typeStart: Int, typeEnd: Int, isCall: Bool, isMethod: Bool)] {
        guard isOpen(open), tk[open].isP("{"), tk.match[open] > open else { return [] }
        let end = tk.match[open]
        var out: [(name: String, idx: Int, optional: Bool, typeStart: Int, typeEnd: Int, isCall: Bool, isMethod: Bool)] = []
        var i = open + 1
        func memberEnd(_ from: Int) -> Int {
            var j = from
            while j < end {
                if j > from, tk[j].nl, tk[j - 1].kind != .punct || [")", "]", "}", ">"].contains(tk[j - 1].text), tk[j].kind == .ident || tk[j].kind == .str || tk[j].isP("(") || tk[j].isP("[") { return j }
                if tk[j].isP(";") || tk[j].isP(",") { return j }
                j = isOpen(j) ? skipBracket(j) : j + 1
            }
            return end
        }
        while i < end {
            if tk[i].isP(";") || tk[i].isP(",") { i += 1; continue }
            var k = i
            if tk[k].isI("readonly"), k + 1 < end, !tk[k + 1].isP(":"), !tk[k + 1].isP("?") { k += 1 }
            let me = memberEnd(k)
            if tk[k].isP("(") {                                           // call signature: event name = first string in the first parameter
                let close = tk.match[k]
                var name = ""
                var idx = k
                if close > k { for q in (k + 1)..<close where tk[q].kind == .str { name = tk[q].text; idx = q; break } }
                if !name.isEmpty { out.append((name, idx, false, k, me, true, false)) }
            } else if tk[k].kind == .ident || tk[k].kind == .str || tk[k].kind == .num {
                var n = k + 1
                var optional = false
                if n < end, tk[n].isP("?") { optional = true; n += 1 }
                if n < end, tk[n].isP(":") { out.append((tk[k].text, k, optional, n + 1, me, false, false)) }
                else if n < end, tk[n].isP("(") || tk[n].isP("<") { out.append((tk[k].text, k, optional, n, me, false, true)) }
            }
            i = max(me, i + 1)
        }
        return out
    }

    func typeBodyOpen(at k: Int) -> Int? {
        // tk[k] is the first token of a type argument: `{` literal or a name
        guard tk.has(k) else { return nil }
        if tk[k].isP("{") { return k }
        if tk[k].kind == .ident, let o = typeBodies[tk[k].text] { return o }
        return nil
    }

    mutating func parseMacros() {
        var gotProps = false, gotEmits = false
        var i = 0
        while i < tk.count {
            let t = tk[i]
            guard t.kind == .ident, i == 0 || !tk[i - 1].isP(".") else { i += 1; continue }
            switch t.text {
            case "defineProps" where !gotProps:
                gotProps = true
                var k = i + 1
                if tk.has(k), tk[k].isP("<"), let o = typeBodyOpen(at: k + 1) {
                    for m in typeMembers(o) where !m.isCall {
                        var p = VSPropDecl(name: m.name, loc: tk[m.idx].s, len: tk[m.idx].e - tk[m.idx].s, doc: docText(m.idx))
                        p.type = slice(m.typeStart, m.typeEnd, cap: 90); p.required = !m.optional
                        c.props.append(p)
                    }
                } else {
                    while tk.has(k), !tk[k].isP("(") , k < i + 2 { k += 1 }
                    if tk.has(k), tk[k].isP("("), tk.has(k + 1), isOpen(k + 1), tk[k + 1].isP("[") || tk[k + 1].isP("{") { c.props += runtimeProps(k + 1) }
                }
            case "defineEmits" where !gotEmits:
                gotEmits = true
                let k = i + 1
                if tk.has(k), tk[k].isP("<") {
                    if let o = typeBodyOpen(at: k + 1), tk[o].isP("{") {
                        for m in typeMembers(o) {
                            var e = VSEmitDecl(name: m.name, loc: tk[m.idx].s, len: tk[m.idx].e - tk[m.idx].s, sig: slice(m.typeStart, m.typeEnd, cap: 90), doc: docText(m.idx))
                            if m.isCall { e.sig = slice(m.typeStart, m.typeEnd, cap: 90) }
                            c.emits.append(e)
                        }
                    } else if tk.has(k + 1), tk[k + 1].isP("("), tk.match[k + 1] > k + 1 {     // `<(e: 'a' | 'b', v: X) => void>`
                        let close = tk.match[k + 1]
                        var q = k + 2
                        while q < close, !tk[q].isP(":") { q += 1 }
                        q += 1
                        while q < close, !tk[q].isP(",") { if tk[q].kind == .str { c.emits.append(VSEmitDecl(name: tk[q].text, loc: tk[q].s, len: tk[q].e - tk[q].s)) }; q += 1 }
                    }
                } else if tk.has(k), tk[k].isP("("), tk.has(k + 1) {
                    c.emits += runtimeEmits(k + 1)
                }
            case "defineModel":
                var k = i + 1
                if tk.has(k), tk[k].isP("<") { while tk.has(k), !tk[k].isP("("), k < i + 40 { k += 1 } }
                var name = "modelValue"
                var loc = t.s, len = t.e - t.s
                if tk.has(k), tk[k].isP("("), tk.has(k + 1), tk[k + 1].kind == .str { name = tk[k + 1].text; loc = tk[k + 1].s; len = tk[k + 1].e - tk[k + 1].s }
                var p = VSPropDecl(name: name, loc: loc, len: len)
                p.isModel = true
                c.props.append(p)
                c.emits.append(VSEmitDecl(name: "update:" + name, loc: loc, len: len))
            default: break
            }
            i += 1
        }
    }

    func runtimeEmits(_ open: Int) -> [VSEmitDecl] {
        guard isOpen(open) else { return [] }
        if tk[open].isP("[") { return strings(inArray: open).map { VSEmitDecl(name: $0.0, loc: tk[$0.1].s, len: tk[$0.1].e - tk[$0.1].s, doc: docText($0.1)) } }
        if tk[open].isP("{") { return entries(open).filter { !$0.isSpread }.map { VSEmitDecl(name: $0.key, loc: tk[$0.keyIdx].s, len: tk[$0.keyIdx].e - tk[$0.keyIdx].s, doc: docText($0.keyIdx)) } }
        return []
    }

    // MARK: options API

    static let mapHelpers: [String: VSDecl.Kind] = ["mapState": .computed, "mapGetters": .computed, "mapWritableState": .computed, "mapActions": .method, "mapMutations": .method]

    mutating func parseOptions(_ obj: Int) {
        c.hasOptions = true
        for e in entries(obj) where !e.isSpread {
            let v = e.valueStart
            switch e.key {
            case "name":
                if v < e.end, tk[v].kind == .str { c.optionsName = tk[v].text }
            case "props":
                if v < e.end, isOpen(v) { c.props += runtimeProps(v) }
            case "emits":
                if v < e.end, isOpen(v) { c.emits += runtimeEmits(v) }
            case "components":
                guard v < e.end, tk[v].isP("{") else { break }
                for r in entries(v) where !r.isSpread {
                    var reg = VSReg(key: r.key, loc: tk[r.keyIdx].s)
                    if r.shorthand { reg.valueIdent = r.key }
                    else if r.valueStart < r.end {
                        if tk[r.valueStart].kind == .ident, r.valueStart + 1 == r.end { reg.valueIdent = tk[r.valueStart].text }
                        var q = r.valueStart
                        while q + 2 < r.end { if tk[q].isI("import"), tk[q + 1].isP("("), tk[q + 2].kind == .str { reg.spec = tk[q + 2].text; break }; q += 1 }
                        if reg.valueIdent == nil, reg.spec == nil, tk[r.valueStart].kind == .ident, tk.has(r.valueStart + 1), tk[r.valueStart + 1].isP("(") {
                            // defineAsyncComponent(() => import('x')) handled by the loop above; anything else is unknown
                        }
                    }
                    c.regs.append(reg)
                }
            case "data":
                var q = v
                var objStart = -1
                while q < e.end {
                    if tk[q].isI("return"), tk.has(q + 1), tk[q + 1].isP("{") { objStart = q + 1; break }
                    if tk[q].isP("=>"), tk.has(q + 2), tk[q + 1].isP("("), tk[q + 2].isP("{") { objStart = q + 2; break }
                    q += 1
                }
                if objStart < 0, e.isMethod { // method form: body is the `{` after params
                    var b = skipBracket(v)
                    while b < e.end, !tk[b].isP("{") { b += 1 }
                    var r = b
                    while r < e.end, tk.match[b] > b, r < tk.match[b] { if tk[r].isI("return"), tk.has(r + 1), tk[r + 1].isP("{") { objStart = r + 1; break }; r += 1 }
                }
                if objStart >= 0 {
                    for d in entries(objStart) where !d.isSpread {
                        var decl = VSDecl(name: d.key, kind: .data, loc: tk[d.keyIdx].s, len: tk[d.keyIdx].e - tk[d.keyIdx].s)
                        decl.detail = "data: " + firstLine(d.keyIdx, max(d.end, d.keyIdx + 1))
                        c.decls.append(decl)
                    }
                }
            case "computed", "methods":
                guard v < e.end, tk[v].isP("{") else { break }
                let kind: VSDecl.Kind = e.key == "computed" ? .computed : .method
                for m in entries(v) {
                    if m.isSpread {
                        // ...mapState(['a', 'b']) / ...mapGetters('ns', { x: 'y' })
                        let s = m.keyIdx + 1
                        guard tk.has(s + 1), tk[s].kind == .ident, let hk = Self.mapHelpers[tk[s].text], tk[s + 1].isP("(") else { continue }
                        var a = s + 2
                        if tk.has(a), tk[a].kind == .str, tk.has(a + 1), tk[a + 1].isP(",") { a += 2 }
                        guard tk.has(a), isOpen(a) else { continue }
                        var names: [(String, Int)] = []
                        if tk[a].isP("[") { names = strings(inArray: a) } else if tk[a].isP("{") { names = entries(a).filter { !$0.isSpread }.map { ($0.key, $0.keyIdx) } }
                        for (n, idx) in names {
                            var decl = VSDecl(name: n, kind: hk, loc: tk[idx].s, len: tk[idx].e - tk[idx].s)
                            decl.detail = "\(tk[s].text)(…)"
                            c.decls.append(decl)
                        }
                        continue
                    }
                    var decl = VSDecl(name: m.key, kind: kind, loc: tk[m.keyIdx].s, len: tk[m.keyIdx].e - tk[m.keyIdx].s)
                    decl.detail = firstLine(m.keyIdx, max(m.end, m.keyIdx + 1))
                    c.decls.append(decl)
                }
            case "setup":
                parseSetup(e)
            case "inject":
                if v < e.end, tk[v].isP("[") { for (n, idx) in strings(inArray: v) { c.decls.append(VSDecl(name: n, kind: .inject, loc: tk[idx].s, len: tk[idx].e - tk[idx].s, detail: "inject")) } }
                else if v < e.end, tk[v].isP("{") { for d in entries(v) where !d.isSpread { c.decls.append(VSDecl(name: d.key, kind: .inject, loc: tk[d.keyIdx].s, len: tk[d.keyIdx].e - tk[d.keyIdx].s, detail: "inject")) } }
            default: break
            }
        }
    }

    mutating func parseSetup(_ e: Entry) {
        var b = e.valueStart
        if e.isMethod { b = skipBracket(b) }
        while b < e.end, !tk[b].isP("{") { b = tk[b].isP("(") ? skipBracket(b) : b + 1 }
        guard b < e.end, tk[b].isP("{"), tk.match[b] > b else { return }
        let end = tk.match[b]
        var locals: [VSDecl] = []
        var ret = -1
        var j = b + 1
        while j < end {
            let t = tk[j]
            if t.kind == .ident, ["const", "let", "var"].contains(t.text) { let (ds, next) = parseVarDecl(j); locals += ds; j = next; continue }
            if t.kind == .ident, t.text == "function" || t.text == "async" {
                if t.text == "async", !(tk.has(j + 1) && tk[j + 1].isI("function")) { j = max(j + 1, stmtEnd(j)); continue }
                let (d, next) = parseFunction(j)
                if let d { locals.append(d) }
                j = next
                continue
            }
            if t.isI("return"), tk.has(j + 1), tk[j + 1].isP("{") { ret = j + 1; j = skipBracket(j + 1); continue }
            j = max(j + 1, isOpen(j) ? skipBracket(j) : stmtEnd(j))
        }
        guard ret >= 0 else { return }
        for r in entries(ret) where !r.isSpread {
            let local = r.shorthand ? r.key : (r.valueStart < r.end && tk[r.valueStart].kind == .ident && r.valueStart + 1 == r.end ? tk[r.valueStart].text : r.key)
            if let d = locals.first(where: { $0.name == local }) {
                var decl = d; decl.name = r.key; decl.kind = .setup
                c.decls.append(decl)
            } else {
                c.decls.append(VSDecl(name: r.key, kind: .setup, loc: tk[r.keyIdx].s, len: tk[r.keyIdx].e - tk[r.keyIdx].s, detail: "setup() → " + r.key))
            }
        }
    }
}

extension VSTok.Kind { var isString: Bool { self == .str } }

enum VSDoc {
    /// `/** ... */` -> plain text (tags other than @deprecated dropped, `@param {T} name - text` kept as `name: text`).
    static func clean(_ raw: String) -> String {
        var lines: [String] = []
        for l in raw.components(separatedBy: "\n") {
            var s = l.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("/**") { s.removeFirst(3) }
            if s.hasSuffix("*/") { s.removeLast(2) }
            if s.hasPrefix("*") { s.removeFirst(1) }
            s = s.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { continue }
            if s.hasPrefix("@") {
                if s.hasPrefix("@defaultValue") || s.hasPrefix("@default") { lines.append("Default: " + (s.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? "")) }
                else if s.hasPrefix("@deprecated") { lines.append("Deprecated") }
                continue
            }
            lines.append(s)
        }
        return lines.joined(separator: " ")
    }
}
