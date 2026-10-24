import Foundation

// Undefined methods / properties and wrong argument counts. Only for receivers whose class is certain and whose complete
// hierarchy (parents, interfaces, traits) is known, has no magic (__call/__get/@method/@property/@mixin) and is not an enum.

/// A fully known class hierarchy.
struct NPHier {
    var classes: [FTClass] = []
    var texts: [NSString] = []
    var complete = true
    var magicCall = false, magicCallStatic = false, magicGet = false, docMagic = false, unsupported = false
    var usable: Bool { complete && !unsupported && !docMagic }

    /// The method as PHP would pick it: class, traits, parents; interface declarations only when nothing concrete exists.
    func method(_ name: String) -> FTMethod? { methodInfo(name)?.method }

    /// `ambiguous`: several concrete declarations with different parameter lists (overrides we cannot order with certainty).
    func methodInfo(_ name: String) -> (method: FTMethod, ambiguous: Bool)? {
        let l = name.lowercased()
        var concrete: [FTMethod] = [], abstract: [FTMethod] = []
        for k in classes {
            for m in k.methods where m.name.lowercased() == l { if k.kind == "interface" { abstract.append(m) } else { concrete.append(m) } }
        }
        if let first = concrete.first { return (first, concrete.contains { $0.params != first.params }) }
        if let first = abstract.first { return (first, abstract.contains { $0.params != first.params }) }
        return nil
    }
    /// Any hierarchy file declares `function name(` (the parser may have missed it: conditional declarations, odd layouts).
    func declaresInText(_ name: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: #"function\s*&?\s*"# + NSRegularExpression.escapedPattern(for: name) + #"\s*\("#, options: .caseInsensitive) else { return true }
        return texts.contains { re.firstMatch(in: $0 as String, range: NSRange(location: 0, length: $0.length)) != nil }
    }
    func hasProp(_ name: String) -> Bool { classes.contains { k in k.props.contains { $0.name == name } } }
    func mentions(_ s: String) -> Bool { texts.contains { $0.range(of: s, options: .literal).location != NSNotFound } }
}

extension NPDiagContext {
    private static let safeBuiltinParents: Set<String> = ["arrayaccess", "countable", "iterator", "iteratoraggregate", "jsonserializable", "stringable",
                                                          "traversable", "serializable"]

    private func hierarchyOf(_ fqn: String, cur: FTClass?, cache: inout [String: NPHier]) -> NPHier? {
        if let h = cache[fqn.lowercased()] { return h }
        var h = NPHier()
        var seen = Set<String>()
        var queue: [(String, Int)] = [(fqn, 0)]
        while !queue.isEmpty, h.classes.count < 40 {
            let (name, depth) = queue.removeFirst()
            guard seen.insert(name.lowercased()).inserted else { continue }
            var info: FTClass?
            var text: NSString?
            if let cur, cur.fqn.lowercased() == name.lowercased() { info = cur; text = ns }
            else if let p = fp.classPath(name), !PHPStubs.isStubFile(p) { info = fp.classInfo(path: p); text = FastProject.read(p) }   // built-ins stay "unknown": member / argument checks remain silent on them
            guard let k = info else {
                if depth == 0 { return nil }
                if !Self.safeBuiltinParents.contains(name.lowercased()) { h.complete = false }
                continue
            }
            h.classes.append(k)
            if let t = text {
                h.texts.append(t)
                if t.range(of: "@method", options: .literal).location != NSNotFound || t.range(of: "@property", options: .literal).location != NSNotFound
                    || t.range(of: "@mixin", options: .literal).location != NSNotFound { h.docMagic = true }
            } else { h.complete = false }
            if k.kind == "enum" { h.unsupported = true }
            for m in k.methods {
                switch m.name.lowercased() {
                case "__call": h.magicCall = true
                case "__callstatic": h.magicCallStatic = true
                case "__get", "__set": h.magicGet = true
                default: break
                }
            }
            if depth < 14 {
                for t in k.traits { queue.append((t, depth + 1)) }
                if let e = k.extends { queue.append((e, depth + 1)) }
                for i in k.implements { queue.append((i, depth + 1)) }
            }
        }
        if !queue.isEmpty { h.complete = false }
        cache[fqn.lowercased()] = h
        return h
    }

    // MARK: Parameter counts

    /// (required, max) from a "Foo $x, int $y = 1, ...$rest" parameter text; nil when unparsable.
    static func arity(_ params: String) -> (min: Int, max: Int?)? {
        let p = params.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return (0, 0) }
        var parts: [String] = []
        var depth = 0, cur = ""
        var quote: Character?
        for ch in p {
            if let q = quote { cur.append(ch); if ch == q { quote = nil }; continue }
            if ch == "'" || ch == "\"" { quote = ch; cur.append(ch); continue }
            if ch == "(" || ch == "[" || ch == "{" { depth += 1 } else if ch == ")" || ch == "]" || ch == "}" { depth -= 1 }
            if ch == ",", depth == 0 { parts.append(cur); cur = "" } else { cur.append(ch) }
        }
        if !cur.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(cur) }
        var lastRequired = 0
        var variadic = false
        for (idx, raw) in parts.enumerated() {
            let part = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if part.hasPrefix("...") || part.contains(" ...") || part.contains("&...") { variadic = true; continue }
            if topLevelEquals(part) != nil { continue }
            lastRequired = idx + 1
        }
        return (lastRequired, variadic ? nil : parts.count)
    }

    private static func topLevelEquals(_ s: String) -> String.Index? {
        var depth = 0
        for i in s.indices {
            let ch = s[i]
            if ch == "(" || ch == "[" { depth += 1 } else if ch == ")" || ch == "]" { depth -= 1 }
            else if ch == "=", depth == 0 { return i }
        }
        return nil
    }

    /// Number of arguments of the call whose "(" is at `open`; nil for named arguments, spreads or first-class callable syntax.
    private func argumentCount(open: Int) -> Int? {
        let close = lex.match[open]
        guard close > open else { return nil }
        if close == open + 1 { return 0 }
        var count = 1
        var k = open + 1
        var segStart = true
        var lastWasComma = false
        while k < close {
            let t = toks[k]
            if t.kind == .punct {
                if t.ch == 44 { count += 1; segStart = true; lastWasComma = true; k += 1; continue }
                if t.ch == 46, k + 1 < close, toks[k + 1].kind == .punct, toks[k + 1].ch == 46 { return nil }          // ...
                if [40, 91, 123].contains(t.ch), lex.match[k] > k { k = lex.match[k] + 1; segStart = false; lastWasComma = false; continue }
            }
            if segStart, t.kind == .ident, k + 1 < close, punct(k + 1, ":"), !isDColon(k + 1) { return nil }          // named argument
            segStart = false; lastWasComma = false
            k += 1
        }
        if lastWasComma { count -= 1 }
        return count
    }

    private func fileMentionsAssignment(_ name: String, in ns: NSString) -> Bool {
        let pat = "->" + NSRegularExpression.escapedPattern(for: name) + #"\s*(\[[^\]]*\]\s*)*(=(?!=)|[.+\-*/?]=|\+\+|--)"#
        guard let re = try? NSRegularExpression(pattern: pat) else { return true }
        return re.firstMatch(in: ns as String, range: NSRange(location: 0, length: ns.length)) != nil
    }

    private func aliasedInTraits(_ name: String, _ h: NPHier) -> Bool {
        guard let re = try? NSRegularExpression(pattern: #"\bas\s+(?:(?:public|protected|private)\s+)?"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#, options: .caseInsensitive) else { return true }
        return h.texts.contains { re.firstMatch(in: $0 as String, range: NSRange(location: 0, length: $0.length)) != nil }
    }

    // MARK: Pass

    func membersPass(members wantMembers: Bool, args wantArgs: Bool) -> [NPDiag] {
        guard namespaceCount <= 1 else { return [] }
        var out: [NPDiag] = []
        let singleClass = typeDecls.count == 1 && !typeDecls[0].anonymous && typeDecls[0].kind == "class"
        let hasAnon = typeDecls.contains { $0.anonymous }
        let guarded = ns.range(of: "method_exists(", options: .literal).location != NSNotFound
            || ns.range(of: "is_callable(", options: .literal).location != NSNotFound
            || ns.range(of: "property_exists(", options: .literal).location != NSNotFound
            || ns.range(of: "__call", options: .literal).location != NSNotFound
            || ns.range(of: "$this instanceof", options: .literal).location != NSNotFound
        let cur = NativePHPDiagCurCache.parse(ns, lex: lex)
        var cache: [String: NPHier] = [:]
        let flow = self.flow
        let classBody = typeDecls.first
        let curFqn = cur?.fqn ?? ""
        // The parser must have seen every method of the class body (a class inside `if (!class_exists())` is not parsed completely).
        let curTrusted: Bool = {
            guard singleClass, let cur, let body = classBody, kind[body.keyword] == 0 else { return false }
            let known = Set(cur.methods.map { $0.name.lowercased() })
            for i in (body.open + 1)..<body.close where kind[i] == 1 && toks[i].kind == .ident && lower(i) == "function" {
                var j = i + 1
                if punct(j, "&") { j += 1 }
                if isIdent(j), j + 1 < n, punct(j + 1, "("), !known.contains(lower(j)) { return false }
            }
            return true
        }()
        let canMembers = wantMembers && !guarded && !hasAnon

        func checkCall(_ h: NPHier, nameTok i: Int, isStatic: Bool, isThisLike: Bool) {
            let name = text(i)
            let isCall = i + 1 < n && punct(i + 1, "(")
            if isCall {
                if let (m, ambiguous) = h.methodInfo(name) {
                    if wantArgs, !ambiguous, let ar = Self.arity(m.params), let cnt = argumentCount(open: i + 1), cnt < ar.min {
                        out.append(NPDiag(range: range(i), severity: 1, message: "Too few arguments to '\(m.name)': expected \(ar.min), found \(cnt)",
                                          code: "arg-count", group: .args))
                    }
                    return
                }
                guard canMembers, h.usable, h.complete else { return }
                if h.magicCall || h.magicCallStatic { return }
                if aliasedInTraits(name, h) || h.declaresInText(name) { return }
                out.append(NPDiag(range: range(i), severity: 2, message: "Undefined method '\(name)'", code: "undefined-method", group: .members))
            } else if canMembers, !isStatic, isThisLike, h.usable, h.complete, !h.magicGet, !h.magicCall {
                // property read: `$this->name`
                if h.hasProp(name) || h.method(name) != nil { return }
                if i + 1 < n, isAssignOp(i + 1) { return }
                if i > 1, isAssignOp(i - 1) { return }
                if fileMentionsAssignment(name, in: ns) { return }
                if ns.range(of: "$" + name, options: .literal).location != NSNotFound { return }
                for t in h.texts where t !== ns {
                    if t.range(of: "$" + name, options: .literal).location != NSNotFound || t.range(of: "->" + name, options: .literal).location != NSNotFound { return }
                }
                out.append(NPDiag(range: range(i), severity: 2, message: "Undefined property '\(name)'", code: "undefined-property", group: .members))
            }
        }

        for i in 0..<n where toks[i].kind == .ident || toks[i].kind == .variable {
            if inImport[i] { continue }
            let t = toks[i]
            // `$recv->name`
            if t.kind == .variable, i + 2 < n, isArrow(i + 1), c_isNameTok(i + 2) {
                if i > 0, kw(i - 1, "new") { continue }                      // `new $this->className(...)` is a dynamic class name
                let name = text(i)
                guard singleClass, curTrusted, let cur, let body = classBody else { continue }
                let nameTok = i + 2
                if name == "$this" {
                    guard i > body.open, i < body.close else { continue }
                    // inside a closure `$this` may be rebound (macros, Closure::bind): only direct method bodies are certain
                    let sid = flow.scopeOf[i]
                    guard sid >= 0, kind[flow.scopes[sid].fn.keyword] == 1 else { continue }
                    guard let h = hierarchyOf(cur.fqn, cur: cur, cache: &cache) else { continue }
                    checkCall(h, nameTok: nameTok, isStatic: false, isThisLike: true)
                } else {
                    let sid = flow.scopeOf[i]
                    guard sid >= 0, canMembers || wantArgs else { continue }
                    let s = flow.scopes[sid]
                    guard s.defCount[name] == 1, !s.uncertain.contains(name), !docVarNames.contains(name), let written = s.varTypes[name] else { continue }
                    if i > 0, isArrow(i - 1) || isDColon(i - 1) { continue }
                    let fqn: String
                    if written.lowercased() == "self" { fqn = curFqn } else if Self.reservedTypeNames.contains(written.lowercased()) { continue } else { fqn = resolve(written).fqn }
                    guard !fqn.isEmpty, fp.classPath(fqn) != nil || fqn.lowercased() == curFqn.lowercased() else { continue }
                    guard let h = hierarchyOf(fqn, cur: cur, cache: &cache), h.complete, !h.unsupported else { continue }
                    if h.classes.first?.kind == "interface" { continue }          // implementations usually add methods (docblocks narrow the type)
                    if toks[nameTok].kind == .ident, !(nameTok + 1 < n && punct(nameTok + 1, "(")) { continue }       // methods only
                    checkCall(h, nameTok: nameTok, isStatic: false, isThisLike: false)
                }
                continue
            }
            // `Name::method(`
            if t.kind == .ident, !isMember(i), i + 3 < n, isDColon(i + 1), isIdent(i + 2), punct(i + 3, "("), !(i > 0 && kw(i - 1, "new")) {
                let written = text(i)
                let lw = written.lowercased()
                var fqn: String
                var thisLike = false
                switch lw {
                case "self", "static":
                    guard singleClass, curTrusted, let cur, let body = classBody, i > body.open, i < body.close else { continue }
                    fqn = cur.fqn; thisLike = true
                case "parent":
                    guard singleClass, curTrusted, let cur, let body = classBody, i > body.open, i < body.close, let e = cur.extends else { continue }
                    fqn = e; thisLike = true
                default:
                    if Self.reservedTypeNames.contains(lw) { continue }
                    fqn = resolve(written).fqn
                }
                guard !fqn.isEmpty else { continue }
                if lw != "self", lw != "static", lw != "parent" { guard fp.classPath(fqn) != nil else { continue } }
                guard let h = hierarchyOf(fqn, cur: cur, cache: &cache), h.complete, !h.unsupported else { continue }
                if let k = h.classes.first, k.kind == "trait" || k.kind == "interface" { continue }
                checkCall(h, nameTok: i + 2, isStatic: true, isThisLike: thisLike)
                continue
            }
            // `new Name(args)`
            if wantArgs, t.kind == .ident, kw(i, "new"), i + 2 < n, isIdent(i + 1), punct(i + 2, "("), !isMember(i) {
                let written = text(i + 1)
                let lw = written.lowercased()
                if ["static", "self", "parent", "class"].contains(lw) { continue }
                let fqn = resolve(written).fqn
                guard fp.classPath(fqn) != nil, let h = hierarchyOf(fqn, cur: cur, cache: &cache), h.complete, !h.unsupported else { continue }
                guard let k = h.classes.first, k.kind == "class" else { continue }
                if let (m, ambiguous) = h.methodInfo("__construct"), !ambiguous, let ar = Self.arity(m.params), let cnt = argumentCount(open: i + 2), cnt < ar.min {
                    out.append(NPDiag(range: range(i + 1), severity: 1, message: "Too few arguments to constructor of '\(written)': expected \(ar.min), found \(cnt)",
                                      code: "arg-count", group: .args))
                }
                continue
            }
            // `function_name(args)` declared in this file or a project helper file
            if wantArgs, t.kind == .ident, !isMember(i), i + 1 < n, punct(i + 1, "("), isPlainFunctionCall(i) {
                if let params = functionParams(text(i)), let ar = Self.arity(params), let cnt = argumentCount(open: i + 1), cnt < ar.min {
                    out.append(NPDiag(range: range(i), severity: 1, message: "Too few arguments to function '\(text(i))': expected \(ar.min), found \(cnt)",
                                      code: "arg-count", group: .args))
                }
            }
        }
        return out
    }

    static let reservedTypeNames: Set<String> = ["int", "float", "string", "bool", "array", "callable", "iterable", "object", "mixed", "void", "null",
                                                 "false", "true", "never", "closure", "stdclass"]

    private func c_isNameTok(_ i: Int) -> Bool { i < n && toks[i].kind == .ident }

    private func isAssignOp(_ j: Int) -> Bool {
        guard j < n, toks[j].kind == .punct else { return false }
        if toks[j].ch == 61 { return !(j + 1 < n && toks[j + 1].kind == .punct && toks[j + 1].ch == 61 && toks[j + 1].loc == toks[j].loc + 1) }
        if toks[j].ch == 91 || toks[j].ch == 43 || toks[j].ch == 45 || toks[j].ch == 46 || toks[j].ch == 63 { return true }       // `[]=`, `++`, `.=` ... (conservative)
        return false
    }

    /// `foo(` where foo is not a declaration, keyword or member.
    private func isPlainFunctionCall(_ i: Int) -> Bool {
        let l = lower(i)
        if ["if", "elseif", "while", "for", "foreach", "switch", "match", "catch", "function", "fn", "array", "list", "isset", "empty", "unset", "echo",
            "print", "return", "exit", "die", "new", "use", "declare", "and", "or", "xor", "include", "require", "include_once", "require_once", "eval"].contains(l) { return false }
        if i > 0 {
            let p = toks[i - 1]
            if p.kind == .ident, ["function", "new", "class", "interface", "trait", "enum", "extends", "implements", "instanceof", "const", "namespace", "use", "goto"].contains(lower(i - 1)) { return false }
            if p.kind == .punct, p.ch == 38, i > 1, kw(i - 2, "function") { return false }
        }
        return !text(i).contains("\\") || true
    }

    private func functionParams(_ name: String) -> String? {
        let key = name.hasPrefix("\\") ? String(name.dropFirst()) : name
        if key.contains("\\") { return nil }
        // declared in this file (named, outside class bodies); more than one declaration -> unknown
        var found: [Int] = []
        for (kwIdx, f) in localFunctions where lower(f) == key.lowercased() { found.append(kwIdx) }
        if found.count > 1 { return nil }
        if let kwIdx = found.first {
            let open = kwIdx + 1 + (punct(kwIdx + 1, "&") ? 1 : 0) + 1
            guard open < n, punct(open, "("), lex.match[open] > open else { return nil }
            return ns.substring(with: NSRange(location: toks[open].loc + 1, length: toks[lex.match[open]].loc - toks[open].loc - 1))
        }
        // namespaced file: an unqualified call may resolve to a namespaced function we do not see
        if !namespace.isEmpty, localFunctions.isEmpty, false { return nil }
        let idx = NPFuncIndex.shared(root: fp.path)
        guard let f = idx.function(key, stubs: false), let t = FastProject.read(f.path), t.range(of: "\nnamespace ", options: .literal).location == NSNotFound,
              let sig = NPFuncIndex.signature(t, nameLoc: f.loc) else { return nil }
        return sig.params
    }
}

/// Parsing the current buffer with FTParser once per pass.
enum NativePHPDiagCurCache {
    static func parse(_ ns: NSString, lex: PHPLex) -> FTClass? { FTParser.parse(ns, lex: lex) }
}
