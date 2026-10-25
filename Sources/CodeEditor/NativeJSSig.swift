import AppKit
import SwiftTreeSitter

/// Signature help (Parameter Info) for the native JS / TS service: the call under the caret is found in the syntax tree, its callee
/// resolved with the same rules as go to definition (functions, arrow consts, methods, constructors through `new`, overloads declared
/// as `function f(...)` signatures), and the label is the declaration's own parameter list. JSDoc `@param` text fills the parameter
/// docs. No answer (`unknown`) whenever the callee is not certain: the caller falls back to a server if one runs.
enum NJSSigOutcome {
    case help([String: Any])           // LSP SignatureHelp payload for `LSPUIParse.signature`
    case notInCall
    case unknown
}

extension NJSEnv {
    /// Parameter texts of `(a: number, { b }: T = {}, ...rest: any[]): void` as ranges inside `sig`, and the offset after the list.
    static func parameterRanges(_ sig: String) -> [NSRange] {
        let u = Array(sig.utf16)
        guard let open = u.firstIndex(of: 40) ?? nil else { return [] }       // first "("
        var out: [NSRange] = []
        var depth = 0, start = open + 1, i = open
        var angle = 0
        while i < u.count {
            let c = u[i]
            switch c {
            case 40, 91, 123: depth += 1                                       // ( [ {
            case 41, 93, 125:
                depth -= 1
                if depth == 0 { if start < i { out.append(trimmed(u, start, i)) }; return out }
            case 60: if depth == 1 { angle += 1 }                              // <
            case 62: if depth == 1, angle > 0, !(i > 0 && u[i - 1] == 61) { angle -= 1 }      // > (but not =>)
            case 44: if depth == 1, angle == 0 { out.append(trimmed(u, start, i)); start = i + 1 }
            case 34, 39, 96:                                                   // string: skip to the closing quote
                var j = i + 1
                while j < u.count, u[j] != c { if u[j] == 92 { j += 1 }; j += 1 }
                i = j
            default: break
            }
            i += 1
        }
        return out
    }

    private static func trimmed(_ u: [UInt16], _ a: Int, _ b: Int) -> NSRange {
        var s = a, e = b
        while s < e, u[s] == 32 { s += 1 }
        while e > s, u[e - 1] == 32 { e -= 1 }
        return NSRange(location: s, length: e - s)
    }

    private static func jsdocParts(_ raw: String) -> (summary: String, params: [String: String]) {
        var summary: [String] = []
        var params: [String: String] = [:]
        for l in raw.components(separatedBy: "\n") {
            var s = l.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("/**") { s.removeFirst(3) }
            if s.hasSuffix("*/") { s.removeLast(2) }
            if s.hasPrefix("*") { s.removeFirst() }
            s = s.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("@param") || s.hasPrefix("@arg") {
                var rest = s.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
                if rest.hasPrefix("{"), let close = rest.firstIndex(of: "}") { rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces) }
                let p = rest.split(separator: " ", maxSplits: 1).map(String.init)
                if let n = p.first { params[n.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).components(separatedBy: "=").first ?? n] = p.count > 1 ? p[1].trimmingCharacters(in: CharacterSet(charactersIn: "- ")) : "" }
            } else if !s.hasPrefix("@"), params.isEmpty { summary.append(s) }
        }
        return (summary.joined(separator: " ").trimmingCharacters(in: .whitespaces), params)
    }

    private func signature(for r: NJSRes, label name: String, argCount: Int, activeIndex: Int) -> (payload: [String: Any], fits: Bool)? {
        guard var sig = r.sigText else { return nil }
        // a `this:` parameter is a type annotation, not an argument: tsc leaves it out of the list
        if let m = sig.range(of: #"\(this: [^,)]*(, )?"#, options: .regularExpression) { sig.replaceSubrange(m, with: "(") }
        let label = name + sig
        let prefix = (name as NSString).length
        let ranges = NJSEnv.parameterRanges(sig).map { NSRange(location: $0.location + prefix, length: $0.length) }
        var docs: [String: String] = [:], summary = ""
        if r.docStart >= 0, let t = source(r.path), r.docEnd <= t.length, r.docEnd > r.docStart {
            (summary, docs) = NJSEnv.jsdocParts(t.sub(r.docStart, r.docEnd))
        }
        var params: [[String: Any]] = []
        let ns = label as NSString
        for rg in ranges {
            var p: [String: Any] = ["label": [NSNumber(value: rg.location), NSNumber(value: rg.location + rg.length)]]
            let ptxt = ns.substring(with: rg)
            let pname = ptxt.drop(while: { $0 == "." }).prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" })
            if let d = docs[String(pname)], !d.isEmpty { p["documentation"] = d }
            params.append(p)
        }
        var out: [String: Any] = ["label": label, "parameters": params]
        if !summary.isEmpty { out["documentation"] = summary }
        let hasRest = ranges.contains { ns.substring(with: $0).hasPrefix("...") }
        return (out, hasRest || argCount <= ranges.count)
    }

    func signatureHelp(at caret: Int) -> NJSSigOutcome {
        guard doc.inScript(caret) else { return .notInCall }
        // the innermost `arguments` node that contains the caret
        var node = doc.leaf(at: max(0, caret - 1))
        if caret == 0 { return .notInCall }
        var args: Node?
        while let n = node {
            if n.kind == "arguments", n.start < caret {
                let close = n.allKids.last
                let closed = close?.kind == ")" && close?.isMissing == false
                if caret < n.end || !closed { args = n; break }
            }
            if n.kind == "statement_block" || n.kind == "class_body" { break }          // inside a function body: not an argument position
            node = n.parent
        }
        guard let a = args, let call = a.parent, call.kind == "call_expression" || call.kind == "new_expression" else { return .notInCall }
        let isNew = call.kind == "new_expression"
        guard let callee = call.field(isNew ? "constructor" : "function") else { return .unknown }
        // which argument is the caret in
        var active = 0
        for c in a.allKids where c.kind == "," && c.end <= caret { active += 1 }
        let argCount = max(active + 1, a.kids.count)
        var target: Node? = callee
        if callee.kind == "member_expression" { target = callee.field("property") }
        guard let t = target, t.kind == "identifier" || t.kind == "property_identifier" || t.kind == "private_property_identifier" else { return .unknown }
        var res = resolveToken(t)
        guard !res.isEmpty else { return .unknown }
        var name = t.text(doc.text)
        if isNew || res.contains(where: { $0.kind == .class }) {
            guard isNew else { return .unknown }                                // calling a class without `new`: not a signature
            var out: [NJSRes] = []
            for r in res where r.kind == .variable || r.kind == .constant {      // `declare var Map: MapConstructor`
                guard let t = r.typeName else { continue }
                for iface in resolveTypeRef(t, in: r.path) { out += members(of: iface, name: "new", isStatic: false) }
            }
            for r in res where r.kind == .class {
                let ctors = members(of: r, name: "constructor", isStatic: false)
                out += ctors
                if ctors.isEmpty { var e = r; e.sigText = "()"; e.docStart = r.docStart; out.append(e) }
            }
            guard !out.isEmpty else { return .unknown }
            res = out; name = "new " + name
        } else if res.allSatisfy({ ($0.kind == .variable || $0.kind == .constant) && $0.sigText == nil && $0.typeName != nil }) {
            var out: [NJSRes] = []                                              // a callable interface: `Number(x)`
            for r in res { for iface in resolveTypeRef(r.typeName ?? "", in: r.path) { out += members(of: iface, name: "()", isStatic: false) } }
            if !out.isEmpty { res = out }
        }
        // an overload list hides its implementation
        if res.contains(where: { $0.overload }) { res = res.filter { $0.overload } }
        res = res.filter { $0.sigText != nil || $0.kind == .class }
        var sigs: [([String: Any], Bool)] = []
        for r in res.prefix(12) { if let s = signature(for: r, label: name, argCount: argCount, activeIndex: active) { sigs.append((s.payload, s.fits)) } }
        guard !sigs.isEmpty else { return .unknown }
        let chosen = sigs.firstIndex { $0.1 } ?? 0
        var activeParam = active
        let plist = sigs[chosen].0["parameters"] as? [[String: Any]] ?? []
        if let last = plist.last?["label"] as? [NSNumber], let lab = sigs[chosen].0["label"] as? NSString, active >= plist.count,
           lab.substring(with: NSRange(location: last[0].intValue, length: last[1].intValue - last[0].intValue)).hasPrefix("...") { activeParam = plist.count - 1 }     // the rest parameter takes every further argument
        return .help(["signatures": sigs.map { $0.0 }, "activeSignature": chosen, "activeParameter": activeParam])
    }
}

extension NativeJS {
    /// Asynchronous variant for the editor popup; `completion` runs on the main queue.
    /// The closing brackets that would balance `prefix` (strings and comments skipped), or nil when no `(` is open at its end.
    static func closers(for prefix: NSString) -> String? {
        var stack: [unichar] = []
        var i = 0
        let n = prefix.length
        while i < n {
            let c = prefix.character(at: i)
            if c == 47, i + 1 < n, prefix.character(at: i + 1) == 47 { while i < n, prefix.character(at: i) != 10 { i += 1 }; continue }
            if c == 47, i + 1 < n, prefix.character(at: i + 1) == 42 {
                i += 2
                while i + 1 < n, !(prefix.character(at: i) == 42 && prefix.character(at: i + 1) == 47) { i += 1 }
                i += 2; continue
            }
            if c == 34 || c == 39 || c == 96 {
                i += 1
                while i < n, prefix.character(at: i) != c { if prefix.character(at: i) == 92 { i += 1 }; i += 1 }
                i += 1; continue
            }
            if c == 40 || c == 91 || c == 123 { stack.append(c) }
            else if c == 41 || c == 93 || c == 125, !stack.isEmpty { stack.removeLast() }
            i += 1
        }
        guard stack.contains(40) else { return nil }
        return String(stack.reversed().map { $0 == 40 ? ")" : $0 == 91 ? "]" : "}" })
    }

    /// Runs the lookup on the live buffer; when the call is not closed yet and the tree is too damaged to show it, on the text up to the
    /// caret with the brackets balanced.
    fileprivate static func signature(url: URL, text: NSString, caret: Int, proj: NJSProject) -> NJSSigOutcome {
        if let e = env(url: url, text: text, root: proj.root) {
            let r = e.signatureHelp(at: caret)
            if case .notInCall = r {} else { return r }
        }
        guard caret > 0, let close = closers(for: text.substring(to: min(caret, text.length)) as NSString) else { return .notInCall }
        let patched = (text.substring(to: min(caret, text.length)) + "0" + close) as NSString
        guard let d = NJSDoc(path: (url.standardizedFileURL.path as NSString).standardizingPath, text: patched) else { return .notInCall }
        return NJSEnv(proj: proj, doc: d).signatureHelp(at: caret)
    }

    static func signatureHelpAsync(url: URL, text: NSString, caret: Int, completion: @escaping (NJSSigOutcome) -> Void) {
        guard handles(url) else { completion(.unknown); return }
        let proj = NJSProject.shared(root: root(for: url))
        let snapshot = NSString(string: text as String)
        proj.queue.async {
            let out = signature(url: url, text: snapshot, caret: caret, proj: proj)
            DispatchQueue.main.async { completion(out) }
        }
    }

    static func signatureHelp(url: URL, text: NSString, caret: Int) -> NJSSigOutcome {
        guard handles(url) else { return .unknown }
        let proj = NJSProject.shared(root: root(for: url))
        return proj.queue.sync { signature(url: url, text: text, caret: caret, proj: proj) }
    }
}
