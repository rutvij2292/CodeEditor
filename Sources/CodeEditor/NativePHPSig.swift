import Foundation

// Native signature help (phase 2a). Finds the innermost call around the caret by scanning tokens backwards (strings and comments
// are single tokens / skipped by PHPLex, nested calls and arrays are skipped by bracket depth), resolves the callee with the same
// machinery as go to definition (`findMember`, `ev.eval`, global functions, built-ins) and returns an LSP-shaped answer that the
// existing signature popup renders (LSPUIParse.signature). Nothing is cached beyond the shared one-entry lex memo.

struct NPSigHelp {
    var label: String
    var ranges: [NSRange]            // UTF-16 range of each parameter inside `label`
    var active: Int                  // index of the active parameter (>= ranges.count: none)
    var summary: String
    var paramDocs: [String]

    /// LSP SignatureHelp payload understood by `LSPUIParse.signature`.
    var lspPayload: [String: Any] {
        var params: [[String: Any]] = []
        for (i, r) in ranges.enumerated() {
            var p: [String: Any] = ["label": [NSNumber(value: r.location), NSNumber(value: r.location + r.length)]]
            if i < paramDocs.count, !paramDocs[i].isEmpty { p["documentation"] = paramDocs[i] }
            params.append(p)
        }
        var sig: [String: Any] = ["label": label, "parameters": params]
        if !summary.isEmpty { sig["documentation"] = summary }
        return ["signatures": [sig], "activeSignature": 0, "activeParameter": active]
    }
}

enum NPSigOutcome {
    case help(NPSigHelp)
    case notInCall                   // the caret is not inside call parentheses: no answer exists anywhere
    case unknown                     // inside a call native cannot resolve (Intelephense may know)
}

struct NPCallSite {
    var open: Int                    // token index of "("
    var index: Int                   // number of top-level commas before the caret
    var argStart: Int                // first token of the argument under the caret
    var spread: Bool
}

struct NPSigTarget {
    var name: String
    var params: String
    var ret: String
    var doc: NPDoc?
    var dropFirst = false            // Eloquent scope: the first parameter ($query) is injected
}

extension NPResolver {
    private static let nonCallWords: Set<String> = [
        "if", "elseif", "while", "for", "foreach", "switch", "match", "catch", "array", "isset", "empty", "unset", "list", "echo", "print", "return", "and",
        "or", "xor", "fn", "function", "use", "declare", "exit", "die", "include", "include_once", "require", "require_once", "as", "new", "clone", "yield",
        "throw", "else", "do", "static", "self", "parent", "instanceof", "case",
    ]

    // MARK: Entry

    func signatureHelp(at caret: Int) -> NPSigOutcome {
        fp.beginRequest()
        guard inPHP(min(caret, max(0, ns.length - 1))) else { return .notInCall }
        guard let site = callSite(at: caret) else { return .notInCall }
        guard let target = calleeTarget(open: site.open) else { return .unknown }
        return .help(build(target, site))
    }

    // MARK: Finding the call

    /// Innermost enclosing call parentheses of the caret (skipping grouping parens, arrays, and keyword constructs).
    func callSite(at caret: Int) -> NPCallSite? {
        var i = ev.tokenIndex(atOrAfter: caret) - 1
        var depth = 0, commas = 0, steps = 0
        var argStart = -1
        var commaSeen = false
        while i >= 0, steps < 4000 {
            steps += 1
            let t = lex.toks[i]
            if t.kind == .punct {
                switch t.ch {
                case 41, 93, 125: depth += 1
                case 40, 91, 123:
                    if depth > 0 { depth -= 1; break }
                    if t.ch == 123 { return nil }                          // inside a block / match / closure body
                    if t.ch == 91 { commas = 0; commaSeen = false; break }  // array literal / index: keep looking outward
                    if isCallParen(i) {
                        let start = commaSeen ? argStart : i + 1
                        let spread = start + 2 < lex.count && lex.isPunct(start, ".") && lex.isPunct(start + 1, ".") && lex.isPunct(start + 2, ".")
                        return NPCallSite(open: i, index: commas, argStart: start, spread: spread)
                    }
                    if isDeclarationParen(i) { return nil }
                    commas = 0; commaSeen = false                           // grouping / keyword parens: continue outward
                case 44:
                    if depth == 0 { commas += 1; if !commaSeen { commaSeen = true; argStart = i + 1 } }
                case 59:
                    if depth == 0 { return nil }
                default: break
                }
            }
            i -= 1
        }
        return nil
    }

    private func isCallParen(_ open: Int) -> Bool {
        guard open > 0 else { return false }
        let p = lex.toks[open - 1]
        if p.kind == .variable { return true }
        guard p.kind == .ident else { return false }
        let w = lex.text(open - 1).lowercased()
        if Self.nonCallWords.contains(w) { return open >= 2 && lex.isIdent(open - 2, "new") && (w == "static" || w == "self" || w == "parent") }
        if open >= 2, lex.isIdent(open - 2, "function") || (lex.isPunct(open - 2, "&") && lex.isIdent(open - 3, "function")) { return false }
        return true
    }

    private func isDeclarationParen(_ open: Int) -> Bool {
        guard open > 0, lex.toks[open - 1].kind == .ident else { return false }
        if lex.isIdent(open - 1, "function") || lex.isIdent(open - 1, "fn") { return true }
        return open >= 2 && (lex.isIdent(open - 2, "function") || (lex.isPunct(open - 2, "&") && lex.isIdent(open - 3, "function")))
    }

    // MARK: Resolving the callee

    func owners(for recv: FTType) -> (owners: [String], model: String?) {
        switch recv {
        case .instance(let f), .staticRef(let f): return ([f], ev.isModel(f) ? f : nil)
        case .builder(let m): return ([Self.eloquentBuilder, Self.queryBuilder], m)
        case .table: return ([Self.queryBuilder], nil)
        case .collection: return ([Self.collectionClass], nil)
        }
    }

    func calleeTarget(open: Int) -> NPSigTarget? {
        let o = open - 1
        guard o >= 0 else { return nil }
        let tok = lex.toks[o]
        if tok.kind == .variable { return closureTarget(varTok: o) }
        guard tok.kind == .ident else { return nil }
        let name = lex.text(o)
        if o >= 1, isOpTok(o - 1) {
            let isStaticOp = lex.isPunct(o - 1, code: PHPTok.dcolon)
            let lo = ev.chainStart(before: o - 1)
            guard lo < o - 1, let recv = ev.eval(lo, o - 1) else { return nil }
            let (owners, model) = owners(for: recv)
            guard let mem = findMember(owners: owners, model: model, name: name, isCall: true, isStatic: isStaticOp, kindVariable: false) else { return nil }
            guard var t = memberTarget(mem) else { return nil }
            if t.dropFirst { t.name = name }                      // scope: show `active(...)`, not `scopeActive(...)`
            return t
        }
        if o >= 1, lex.isIdent(o - 1, "new") { return constructorTarget(name) }
        return functionTarget(name)
    }

    private func docOf(_ mem: NPMember) -> NPDoc? {
        guard let m = mem.method, let t = text(of: mem.owner), let d = NPDoc.leading(t, before: m.declStart) else { return nil }
        return NPDoc.parse(d.text, start: d.start)
    }

    private func memberTarget(_ mem: NPMember) -> NPSigTarget? {
        switch mem.kind {
        case .method:
            guard let m = mem.method else { return nil }
            return NPSigTarget(name: m.name, params: m.params, ret: m.ret, doc: docOf(mem), dropFirst: mem.extra.hasPrefix("Eloquent scope"))
        case .docMethod:
            guard let p = Self.parseSignatureText(mem.extra) else { return nil }
            return NPSigTarget(name: p.name, params: p.params, ret: p.ret, doc: nil)
        default: return nil
        }
    }

    private func constructorTarget(_ written: String) -> NPSigTarget? {
        guard let (fqn, builtin) = resolveClassName(written), !builtin else { return nil }
        let classes = ev.hierarchy(fqn)
        guard let first = classes.first else { return nil }
        if let mem = findMember(owners: [fqn], model: nil, name: "__construct", isCall: true, isStatic: false, kindVariable: false), let t = memberTarget(mem) {
            return NPSigTarget(name: first.name, params: t.params, ret: "", doc: t.doc)
        }
        if classes.count > 1 || first.extends == nil { return NPSigTarget(name: first.name, params: "", ret: "", doc: nil) }
        return nil
    }

    private func functionTarget(_ written: String) -> NPSigTarget? {
        var name = written
        if name.hasPrefix("\\") { name.removeFirst() }
        if let b = name.lastIndex(of: "\\") { name = String(name[name.index(after: b)...]) }
        guard !name.isEmpty else { return nil }
        // declared in this file
        for j in 0..<max(0, lex.count - 2) where lex.isIdent(j, "function") {
            var k = j + 1
            if lex.isPunct(k, "&") { k += 1 }
            guard k < lex.count, lex.toks[k].kind == .ident, lex.text(k).caseInsensitiveCompare(name) == .orderedSame, lex.isPunct(k + 1, "(") else { continue }
            if let c = cur, c.methods.contains(where: { $0.loc == lex.toks[k].loc }) { continue }
            if j > 0, lex.toks[j - 1].kind == .ident, ["public", "protected", "private", "static", "abstract", "final"].contains(lex.text(j - 1)) { continue }
            guard let sig = NPFuncIndex.signature(ns, nameLoc: lex.toks[k].loc) else { continue }
            let doc = NPDoc.leading(ns, before: lex.toks[j].loc).map { NPDoc.parse($0.text, start: $0.start) }
            return NPSigTarget(name: sig.name, params: sig.params, ret: sig.ret, doc: doc)
        }
        if let f = NPFuncIndex.shared(root: fp.path).function(name), let t = NPFiles.text(f.path), let sig = NPFuncIndex.signature(t, nameLoc: f.loc) {
            let doc = NPDoc.leading(t, before: f.declStart).map { NPDoc.parse($0.text, start: $0.start) }
            return NPSigTarget(name: sig.name, params: sig.params, ret: sig.ret, doc: doc)
        }
        if let b = NPBuiltins.functions[name.lowercased()], let p = Self.parseSignatureText(b.signature) {
            var d = NPDoc(); d.summary = b.doc
            return NPSigTarget(name: p.name, params: p.params, ret: p.ret, doc: d)
        }
        return nil
    }

    /// `$fn(` where `$fn = function (...) {...}` / `fn (...) =>` earlier in the file.
    private func closureTarget(varTok: Int) -> NPSigTarget? {
        let name = lex.text(varTok)
        guard name != "$this" else { return nil }
        var q = varTok - 1
        var steps = 0
        while q >= 0, steps < 6000 {
            steps += 1
            if lex.toks[q].kind == .variable, lex.text(q) == name, lex.isPunct(q + 1, "="), !lex.isPunct(q + 2, "=") {
                var k = q + 2
                if lex.isIdent(k, "static") { k += 1 }
                guard lex.isIdent(k, "function") || lex.isIdent(k, "fn") else { return nil }
                k += 1
                if lex.isPunct(k, "&") { k += 1 }
                guard lex.isPunct(k, "("), lex.match[k] > k else { return nil }
                let a = lex.toks[k].loc + 1, b = lex.toks[lex.match[k]].loc
                let params = ns.substring(with: NSRange(location: a, length: max(0, b - a)))
                return NPSigTarget(name: name, params: Self.collapse(params), ret: "", doc: nil)
            }
            q -= 1
        }
        return nil
    }

    // MARK: Building the answer

    static func collapse(_ s: String) -> String { s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }

    /// Splits a parameter list on top-level commas (quotes, (), [] and {} are respected).
    static func splitParams(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var depth = 0
        var quote: Character?
        var prev: Character = " "
        for c in s {
            if let q = quote { cur.append(c); if c == q, prev != "\\" { quote = nil }; prev = c; continue }
            if c == "'" || c == "\"" { quote = c; cur.append(c); prev = c; continue }
            if "([{".contains(c) { depth += 1 } else if ")]}".contains(c) { depth -= 1 }
            if c == ",", depth == 0 { out.append(cur); cur = "" } else { cur.append(c) }
            prev = c
        }
        out.append(cur)
        return out.map { collapse($0) }.filter { !$0.isEmpty }
    }

    static func paramName(_ p: String) -> String? {
        guard let r = p.range(of: #"\$\w+"#, options: .regularExpression) else { return nil }
        return String(p[r])
    }

    /// `[static] [Type] name(params) [description]` (PHPDoc @method line or a built-in table signature).
    static func parseSignatureText(_ text: String) -> (name: String, params: String, ret: String)? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("static ") { s = String(s.dropFirst(7)) }
        guard let open = s.firstIndex(of: "(") else { return nil }
        let head = s[..<open].split(separator: " ").map(String.init)
        guard let name = head.last else { return nil }
        var depth = 0
        var close: String.Index?
        var idx = open
        var quote: Character?
        while idx < s.endIndex {
            let c = s[idx]
            if let q = quote { if c == q { quote = nil } }
            else if c == "'" || c == "\"" { quote = c }
            else if c == "(" { depth += 1 } else if c == ")" { depth -= 1; if depth == 0 { close = idx; break } }
            idx = s.index(after: idx)
        }
        guard let close else { return nil }
        let params = String(s[s.index(after: open)..<close])
        var ret = head.dropLast().joined(separator: " ")
        let rest = s[s.index(after: close)...].trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix(":") { ret = rest.dropFirst().split(separator: " ").first.map(String.init) ?? ret }
        return (name, collapse(params), ret)
    }

    func build(_ t: NPSigTarget, _ site: NPCallSite) -> NPSigHelp {
        var ps = Self.splitParams(t.params)
        if t.dropFirst, !ps.isEmpty { ps.removeFirst() }
        var label = t.name + "("
        var ranges: [NSRange] = []
        for (i, p) in ps.enumerated() {
            if i > 0 { label += ", " }
            ranges.append(NSRange(location: (label as NSString).length, length: (p as NSString).length))
            label += p
        }
        label += ")"
        if !t.ret.isEmpty { label += ": " + t.ret }
        // active parameter: named argument, else the comma count (variadic parameter absorbs the rest)
        var active = site.index
        let a = site.argStart
        if a >= 0, a + 1 < lex.count, lex.toks[a].kind == .ident, lex.isPunct(a + 1, ":") {
            let n = "$" + lex.text(a)
            active = ps.firstIndex(where: { Self.paramName($0) == n }) ?? ps.count
        } else if active >= ps.count, let last = ps.last, last.contains("...") {
            active = ps.count - 1
        } else if site.spread, let idx = ps.firstIndex(where: { $0.contains("...") }) {
            active = idx
        }
        var docs: [String] = []
        for p in ps {
            if let n = Self.paramName(p), let d = t.doc?.params.first(where: { $0.name == n }), !d.text.isEmpty {
                docs.append(NPDoc.clip(NPDoc.cleanInline(d.text), 220))
            } else { docs.append("") }
        }
        var summary = ""
        if let d = t.doc, !d.summary.isEmpty { summary = NPDoc.clip(NPDoc.cleanInline(d.summary), 300) }
        return NPSigHelp(label: label, ranges: ranges, active: active, summary: summary, paramDocs: docs)
    }
}

extension NativePHP {
    /// Synchronous signature help (tests, manual invocation). Waits on the project's fast-tier queue.
    static func signatureHelp(url: URL, text: NSString, caret: Int, root: String? = nil) -> NPSigOutcome {
        guard handles(url), let r = root ?? FastTier.root(for: url) else { return .unknown }
        let fp = FastProject.shared(root: URL(fileURLWithPath: r))
        return fp.queue.sync { resolver(fp: fp, url: url, text: text).signatureHelp(at: caret) }
    }

    /// Asynchronous variant for the editor popup; `completion` runs on the main queue.
    static func signatureHelpAsync(url: URL, text: NSString, caret: Int, completion: @escaping (NPSigOutcome) -> Void) {
        guard handles(url), let r = FastTier.root(for: url) else { completion(.unknown); return }
        let fp = FastProject.shared(root: URL(fileURLWithPath: r))
        let snapshot = NSString(string: text as String)
        fp.queue.async {
            let out = resolver(fp: fp, url: url, text: snapshot).signatureHelp(at: caret)
            DispatchQueue.main.async { completion(out) }
        }
    }
}
