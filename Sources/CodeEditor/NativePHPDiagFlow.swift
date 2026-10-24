import Foundation

// Function scopes and variable classification shared by the undefined-variable and member rules.

struct NPFn {
    var keyword: Int
    var isArrow: Bool
    var open: Int            // "(" of the parameter list
    var close: Int
    var useOpen: Int         // "(" of a closure `use (...)`, -1 if none
    var bodyOpen: Int        // "{" (-1 for arrow functions and bodiless declarations)
    var bodyClose: Int
}

struct NPScope {
    var fn: NPFn
    var parent = -1
    var defs = Set<String>()
    var dynamic = false
    var reads: [Int] = []
    var varTypes: [String: String] = [:]        // variable -> class written, while it has exactly one typed definition
    var defCount: [String: Int] = [:]
    var uncertain = Set<String>()               // used with instanceof / method_exists ...
}

final class NPFlow {
    unowned let c: NPDiagContext     // the context owns the flow (lazy var): a strong reference here leaked both per analysed file
    private(set) var fns: [Int: NPFn] = [:]
    private(set) var scopes: [NPScope] = []
    private(set) var scopeOf: [Int]
    private(set) var defMark: [Bool]
    private(set) var softMark: [Bool]
    private var bodyAt: [Int: Int] = [:]

    private static let dynamicIdents: Set<String> = ["extract", "eval", "include", "include_once", "require", "require_once", "get_defined_vars",
                                                      "parse_str", "mb_parse_str", "import_request_variables", "func_get_args"]
    private static let superGlobals: Set<String> = ["$this", "$GLOBALS", "$_GET", "$_POST", "$_COOKIE", "$_FILES", "$_ENV", "$_REQUEST", "$_SERVER",
                                                    "$_SESSION", "$argv", "$argc", "$http_response_header", "$php_errormsg", "$"]
    private static let noCallKeywords: Set<String> = ["if", "elseif", "while", "for", "foreach", "switch", "match", "catch", "return", "echo", "print",
                                                      "isset", "empty", "unset", "list", "array", "and", "or", "xor", "not", "as", "in", "yield",
                                                      "throw", "clone", "exit", "die", "declare", "fn", "function", "use", "else", "case", "new"]

    init(_ c: NPDiagContext) {
        self.c = c
        scopeOf = [Int](repeating: -1, count: c.n)
        defMark = [Bool](repeating: false, count: c.n)
        softMark = [Bool](repeating: false, count: c.n)
        findFunctions()
        for d in c.typeDecls { bodyAt[d.open] = d.close }
        assign(0, c.n, -1)
        classify()
        collect()
    }

    // MARK: Functions

    private func findFunctions() {
        let n = c.n
        for i in 0..<n where c.toks[i].kind == .ident && !c.isMember(i) && !c.inImport[i] {
            let l = c.lower(i)
            guard l == "function" || l == "fn" else { continue }
            var j = i + 1
            if c.punct(j, "&") { j += 1 }
            if l == "function", c.isIdent(j) { j += 1 }
            guard j < n, c.punct(j, "("), c.match(j) > j else { continue }
            let open = j, close = c.match(j)
            var k = close + 1
            var useOpen = -1
            if c.kw(k, "use"), c.punct(k + 1, "("), c.match(k + 1) > k + 1 { useOpen = k + 1; k = c.match(k + 1) + 1 }
            if c.punct(k, ":") {
                var steps = 0
                k += 1
                while k < n, steps < 40, !(c.toks[k].kind == .punct && (c.toks[k].ch == 123 || c.toks[k].ch == 59 || c.toks[k].ch == PHPTok.fat)) { k += 1; steps += 1 }
            }
            if l == "fn" {
                fns[i] = NPFn(keyword: i, isArrow: true, open: open, close: close, useOpen: -1, bodyOpen: -1, bodyClose: -1)
            } else if k < n, c.punct(k, "{"), c.match(k) > k {
                fns[i] = NPFn(keyword: i, isArrow: false, open: open, close: close, useOpen: useOpen, bodyOpen: k, bodyClose: c.match(k))
            } else {
                fns[i] = NPFn(keyword: i, isArrow: false, open: open, close: close, useOpen: useOpen, bodyOpen: -1, bodyClose: -1)
            }
        }
    }

    private func assign(_ lo: Int, _ hi: Int, _ scope: Int) {
        var i = lo
        while i < hi {
            if let f = fns[i], !f.isArrow {
                let sid = scopes.count
                scopes.append(NPScope(fn: f, parent: scope))
                let headerEnd = f.bodyOpen >= 0 ? f.bodyOpen : f.close
                for k in i...headerEnd { scopeOf[k] = sid }
                if f.bodyOpen >= 0 {
                    assign(f.bodyOpen + 1, f.bodyClose, sid)
                    scopeOf[f.bodyClose] = sid
                    i = f.bodyClose + 1
                } else { i = f.close + 1 }
                continue
            }
            if let close = bodyAt[i] {
                scopeOf[i] = -1
                assign(i + 1, min(close, hi), -1)
                scopeOf[close] = scope
                i = close + 1
                continue
            }
            scopeOf[i] = scope
            i += 1
        }
    }

    // MARK: Classification

    private func isAssignOp(_ j: Int) -> Bool {
        let n = c.n
        guard j < n, c.toks[j].kind == .punct else { return false }
        let t0 = c.toks[j]
        if t0.ch == 61 {
            if j + 1 < n, c.toks[j + 1].kind == .punct, c.toks[j + 1].ch == 61, c.toks[j + 1].loc == t0.loc + 1 { return false }
            return true
        }
        let ops: Set<UInt16> = [46, 43, 45, 42, 47, 37, 38, 124, 94, 63, 60, 62]
        var k = j
        var chars: [UInt16] = []
        while k < n, c.toks[k].kind == .punct, c.toks[k].loc == t0.loc + (k - j), ops.contains(c.toks[k].ch) { chars.append(c.toks[k].ch); k += 1 }
        if k < n, c.toks[k].kind == .punct, c.toks[k].ch == 61, c.toks[k].loc == t0.loc + (k - j), !chars.isEmpty {
            if chars.count == 1, chars[0] == 60 || chars[0] == 62 { return false }
            return true
        }
        if chars.count == 2, chars[0] == chars[1], chars[0] == 43 || chars[0] == 45 { return true }
        return false
    }

    private func writeTarget(_ i: Int) -> Bool {
        var j = i + 1
        while j < c.n, c.punct(j, "["), c.match(j) > j { j = c.match(j) + 1 }
        return isAssignOp(j)
    }

    private func prefixIncDec(_ i: Int) -> Bool {
        guard i >= 2 else { return false }
        let a = c.toks[i - 2], b = c.toks[i - 1]
        return a.kind == .punct && b.kind == .punct && a.ch == b.ch && (a.ch == 43 || a.ch == 45) && a.loc + 1 == b.loc && b.loc + 1 == c.toks[i].loc
    }

    private func markVars(_ lo: Int, _ hi: Int, def: Bool) {
        guard lo < hi else { return }
        for k in lo..<hi where c.toks[k].kind == .variable {
            if def { defMark[k] = true } else { softMark[k] = true }
        }
    }

    private func classify() {
        let n = c.n
        // Function parameter lists and closure `use` lists define variables.
        for (_, f) in fns {
            markVars(f.open + 1, f.close, def: true)
            if f.useOpen >= 0 { markVars(f.useOpen + 1, c.match(f.useOpen), def: true) }
        }
        var parenStack: [Bool] = []          // isCall for "(" ; false for other brackets
        for i in 0..<n {
            let t = c.toks[i]
            if t.kind == .punct {
                if t.ch == 40 || t.ch == 91 || t.ch == 123 {
                    var isCall = false
                    if t.ch == 40, i > 0 {
                        let p = c.toks[i - 1]
                        if p.kind == .ident { isCall = !Self.noCallKeywords.contains(c.lower(i - 1)) }
                        else if p.kind == .variable { isCall = true }
                        else if p.kind == .punct, p.ch == 41 || p.ch == 93 { isCall = true }
                    }
                    parenStack.append(isCall)
                    if t.ch == 91, c.match(i) > i, isDestructuring(i) { markVars(i + 1, c.match(i), def: true) }
                } else if t.ch == 41 || t.ch == 93 || t.ch == 125 {
                    if !parenStack.isEmpty { parenStack.removeLast() }
                }
                continue
            }
            if t.kind == .ident, !c.isMember(i), i + 1 < n {
                let l = c.lower(i)
                switch l {
                case "foreach":
                    if c.punct(i + 1, "("), c.match(i + 1) > i + 1 {
                        let close = c.match(i + 1)
                        var k = i + 2
                        while k < close, !c.kw(k, "as") { if c.toks[k].kind == .punct, [40, 91, 123].contains(c.toks[k].ch), c.match(k) > k { k = c.match(k) }; k += 1 }
                        if k < close { markVars(k + 1, close, def: true) }
                    }
                case "catch":
                    if c.punct(i + 1, "("), c.match(i + 1) > i + 1 { markVars(i + 2, c.match(i + 1), def: true) }
                case "list":
                    if c.punct(i + 1, "("), c.match(i + 1) > i + 1 { markVars(i + 2, c.match(i + 1), def: true) }
                case "isset", "empty", "unset":
                    if c.punct(i + 1, "("), c.match(i + 1) > i + 1 { markVars(i + 2, c.match(i + 1), def: false) }
                case "global", "static":
                    if c.isVariable(i + 1) {
                        var k = i + 1
                        while k < n, !c.punct(k, ";") { if c.toks[k].kind == .variable { defMark[k] = true }; k += 1 }
                    }
                default: break
                }
                continue
            }
            if t.kind == .variable {
                if writeTarget(i) || prefixIncDec(i) { defMark[i] = true }
                if i > 0, c.punct(i - 1, "&") { defMark[i] = true }
                if i > 0, i + 1 < n, parenStack.last == true, (c.punct(i - 1, "(") || c.punct(i - 1, ",")), (c.punct(i + 1, ",") || c.punct(i + 1, ")")) { defMark[i] = true }
                if !defMark[i] { if coalesced(i) { softMark[i] = true } }
            }
        }
    }

    private func coalesced(_ i: Int) -> Bool {
        var j = i + 1
        while j < c.n {
            if c.punct(j, "["), c.match(j) > j { j = c.match(j) + 1; continue }
            if c.isArrow(j), j + 1 < c.n, c.toks[j + 1].kind != .punct { j += 2; if c.punct(j, "("), c.match(j) > j { j = c.match(j) + 1 }; continue }
            break
        }
        guard j + 1 < c.n else { return false }
        let a = c.toks[j], b = c.toks[j + 1]
        return a.kind == .punct && b.kind == .punct && a.ch == 63 && b.ch == 63 && a.loc + 1 == b.loc
    }

    private func isDestructuring(_ open: Int) -> Bool {
        let close = c.match(open)
        guard close + 1 < c.n else { return false }
        // `[` after a value is a subscript, not a list literal
        if open > 0 {
            let p = c.toks[open - 1]
            switch p.kind {
            case .variable, .number: return false
            case .string: if c.ns.character(at: p.loc) != 60 { return false }          // a heredoc token swallows its closing `;`
            case .ident: if !Self.noCallKeywords.contains(c.lower(open - 1)) { return false }
            case .punct: if p.ch == 93 || p.ch == 41 { return false }
            }
        }
        let j = close + 1
        guard c.punct(j, "=") else { return false }
        return !(j + 1 < c.n && c.punct(j + 1, "=") && c.toks[j + 1].loc == c.toks[j].loc + 1)
    }

    // MARK: Collection

    private func collect() {
        let n = c.n
        // closure captures count as definitions in the enclosing scope
        for s in scopes where s.fn.useOpen >= 0 && s.parent >= 0 {
            for k in (s.fn.useOpen + 1)..<c.match(s.fn.useOpen) where c.toks[k].kind == .variable { scopes[s.parent].defs.insert(c.text(k)) }
        }
        for i in 0..<n {
            let sid = scopeOf[i]
            guard sid >= 0 else { continue }
            let t = c.toks[i]
            if t.kind == .ident, !c.isMember(i), i < n {
                if Self.dynamicIdents.contains(c.lower(i)) { scopes[sid].dynamic = true }
                continue
            }
            guard t.kind == .variable else { continue }
            let name = c.text(i)
            if name == "$" { scopes[sid].dynamic = true; continue }
            if i > 0, c.isDColon(i - 1) { continue }
            if defMark[i] {
                scopes[sid].defs.insert(name)
                scopes[sid].defCount[name, default: 0] += 1
                recordType(sid, i, name)
            } else if !softMark[i] { scopes[sid].reads.append(i) }
            if i + 1 < n, c.kw(i + 1, "instanceof") { scopes[sid].uncertain.insert(name) }
        }
    }

    private func recordType(_ sid: Int, _ i: Int, _ name: String) {
        let f = scopes[sid].fn
        // parameter with one class type
        if i > f.open, i < f.close {
            var j = i - 1
            var types: [Int] = []
            var bad = false
            while j > f.open, !c.punct(j, ",") {
                let t = c.toks[j]
                if t.kind == .ident { if !["public", "protected", "private", "readonly"].contains(c.lower(j)) { types.append(j) } }
                else if t.kind == .punct, t.ch == 63 {}
                else if t.kind == .punct, t.ch == 38 || t.ch == 124 || t.ch == 46 { bad = true }
                else if t.kind == .punct, t.ch == 35 || t.ch == 93 || t.ch == 91 || t.ch == 40 || t.ch == 41 { break }
                j -= 1
            }
            if !bad, types.count == 1 { scopes[sid].varTypes[name] = c.text(types[0]) }
            return
        }
        // `$v = new Foo(...)`
        if i + 3 < c.n, c.punct(i + 1, "="), c.kw(i + 2, "new"), c.isIdent(i + 3), !c.punct(i + 2, "("), !c.punct(i + 3, "(") {
            let w = c.lower(i + 3)
            if w != "class", w != "static", w != "self", w != "parent" { scopes[sid].varTypes[name] = c.text(i + 3); return }
        }
    }

    // MARK: Undefined variables

    func undefinedVariables() -> [NPDiag] {
        var out: [NPDiag] = []
        let doc = c.docVarNames
        for s in scopes where !s.dynamic && s.fn.bodyOpen >= 0 {
            for i in s.reads {
                let name = c.text(i)
                if Self.superGlobals.contains(name) { continue }
                if s.defs.contains(name) || doc.contains(name) { continue }
                out.append(NPDiag(range: c.range(i), severity: 2, message: "Undefined variable '\(name)'", code: "undefined-variable", group: .variables))
                if out.count > 80 { return out }
            }
        }
        return out
    }
}

extension NPDiagContext {
    func variablesPass() -> [NPDiag] { flow.undefinedVariables() }
}
