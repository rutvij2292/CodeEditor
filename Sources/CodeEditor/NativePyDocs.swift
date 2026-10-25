import Foundation

/// Docstrings and hover text.
enum PyDocs {
    /// Source text of a file for docstring extraction: the live buffer, or the file on disk when it still matches the outline.
    static func text(of file: PyFile) -> NSString? {
        if let l = file.live { return l }
        guard let st = PyFS.stat(file.path), st.mtime == file.mtime, st.size == file.rawSize, let s = PyFS.read(file.path) else { return nil }
        return s as NSString
    }

    static func docstring(_ range: NSRange?, in file: PyFile) -> String? {
        guard let range, let t = text(of: file), NSMaxRange(range) <= t.length else { return nil }
        let doc = clean(t.substring(with: range))
        return doc.isEmpty ? nil : doc
    }

    /// `inspect.cleandoc` on the source of a string literal.
    static func clean(_ literal: String) -> String {
        var s = Substring(literal)
        while let f = s.first, f.isLetter { s.removeFirst() }                        // r / u / b prefixes
        for q in ["\"\"\"", "'''"] where s.hasPrefix(q) {
            s = s.dropFirst(3)
            if s.hasSuffix(q) { s = s.dropLast(3) }
            return cleanBody(String(s))
        }
        if let f = s.first, f == "\"" || f == "'" {
            s = s.dropFirst()
            if s.last == f { s = s.dropLast() }
        }
        return cleanBody(String(s))
    }

    private static func cleanBody(_ body: String) -> String {
        var lines = body.replacingOccurrences(of: "\t", with: "        ").components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        guard !lines.isEmpty else { return "" }
        var indent = Int.max
        for l in lines.dropFirst() {
            let t = l.drop(while: { $0 == " " })
            if t.isEmpty { continue }
            indent = min(indent, l.count - t.count)
        }
        lines[0] = String(lines[0].drop(while: { $0 == " " }))
        if indent != Int.max { for i in 1..<lines.count { lines[i] = String(lines[i].dropFirst(min(indent, lines[i].prefix(while: { $0 == " " }).count))) } }
        while let l = lines.last, l.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        while let l = lines.first, l.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        var out = lines.joined(separator: "\n")
        if out.count > 3000 { out = String(out.prefix(3000)) + "…" }
        return out
    }

    // MARK: Hover

    static func isConstantName(_ n: String) -> Bool {
        n.contains(where: { $0.isLetter }) && n == n.uppercased() && !n.hasPrefix("__")
    }

    static func markdown(for sym: PySym, _ r: PyResolver) -> String {
        var sig: String
        switch sym.kind {
        case .cls:
            sig = "class " + (sym.header.map { $0.hasPrefix("class ") ? String($0.dropFirst(6)) : $0 } ?? sym.name)
        case .fn:
            let isMethod = sym.scope?.kind == .cls
            if sym.isProperty {
                let t = r.returnType(sym, awaited: false, selfClass: nil)
                sig = "(property) \(sym.name)" + (r.typeString(t).map { ": " + $0 } ?? "")
            } else {
                let head = "(\(isMethod ? "method" : "function")) " + (sym.header ?? "def \(sym.name)(…)")
                let decs = sym.decorators.filter { !$0.isEmpty }.prefix(3).map { "@" + $0 }
                sig = (decs + [head]).joined(separator: "\n")
            }
        case .variable, .attr:
            let t = r.typeString(r.typeOf(sym))
            let tag = sym.kind == .attr ? "attribute" : (isConstantName(sym.name) ? "constant" : "variable")
            sig = "(\(tag)) \(sym.name)" + (t.map { ": " + $0 } ?? "")
        case .param:
            let t = r.typeString(r.typeOf(sym))
            var line = "(parameter) \(sym.name)" + (t.map { ": " + $0 } ?? "")
            if let fn = sym.scope?.owner, sym.paramIndex >= 0, sym.paramIndex < fn.params.count, let d = fn.params[sym.paramIndex].defaultText { line += " = " + d }
            sig = line
        case .imp:
            sig = "(import) \(sym.name)"
        }
        var md = "```python\n\(sig)\n```"
        if sym.kind == .cls || sym.kind == .fn, let file = r.ctx.file(sym.path), let doc = docstring(sym.docRange, in: file) {
            md += "\n\n---\n\n" + doc
        } else if sym.kind == .cls, let doc = initDoc(sym, r) {
            md += "\n\n---\n\n" + doc
        }
        return md
    }

    private static func initDoc(_ cls: PySym, _ r: PyResolver) -> String? {
        guard let m = r.memberSyms(cls, "__init__").first, m.kind == .fn, let f = r.ctx.file(m.path) else { return nil }
        return docstring(m.docRange, in: f)
    }

    static func moduleMarkdown(_ loc: PyCtx.Loc, name: String, _ r: PyResolver) -> String {
        var md = "```python\n(module) \(name)\n```"
        if case .file(let p) = loc, let f = r.ctx.file(p), let doc = docstring(f.docRange, in: f) { md += "\n\n---\n\n" + doc }
        return md
    }
}
