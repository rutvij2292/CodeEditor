import Foundation

/// Hover text: the declaration as written (never an inferred type), plus the JSDoc above it.
extension NJSEnv {
    private func collapse(_ s: String, max: Int = 360) -> String {
        var t = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        for p in ["export default ", "export ", "declare ", "default "] where t.hasPrefix(p) { t = String(t.dropFirst(p.count)) }
        for p in ["declare ", "export "] where t.hasPrefix(p) { t = String(t.dropFirst(p.count)) }
        while t.hasSuffix(";") || t.hasSuffix(",") { t.removeLast() }
        return t.count > max ? String(t.prefix(max)) + " ..." : t
    }

    func markdown(_ r: NJSRes, others: Int) -> String {
        let rel = r.path.hasPrefix(proj.root + "/") ? String(r.path.dropFirst(proj.root.count + 1)) : r.path
        if r.fileTop { return "```typescript\nmodule \"\(rel)\"\n```" }
        guard let t = text(r.path), r.declStart >= 0, r.sigEnd <= t.length, r.declStart <= r.sigEnd else { return "" }
        func slice(_ a: Int, _ b: Int) -> String { b > a ? t.substring(with: NSRange(location: a, length: b - a)) : "" }
        var label: String
        switch r.kind {
        case .variable, .constant:
            let body = collapse(slice(r.loc, r.sigEnd), max: 2000)
            var head = body, value = ""
            if let eq = body.range(of: " = ") { head = String(body[..<eq.lowerBound]); value = String(body[eq.upperBound...]) }
            let annotated = head.contains(":")
            label = (r.keyword ?? "var") + " " + head
            if !annotated, !value.isEmpty { label += value.count <= 60 ? " = " + value : " = ..." }
        case .parameter: label = "(parameter) " + collapse(slice(r.declStart, r.sigEnd))
        case .method, .getter, .setter, .property, .enumMember:
            var body = collapse(slice(r.loc, r.sigEnd))
            if r.kind == .property, let eq = body.range(of: " = ") { body = String(body[..<eq.lowerBound]) }
            let owner = r.owner.map { $0 + "." } ?? ""
            label = "(\(r.kind.label)) " + owner + body
        case .namespace where r.declStart == r.sigEnd: label = "namespace " + r.name
        case .typeAlias: label = collapse(slice(r.declStart, r.sigEnd), max: 500)
        default: label = collapse(slice(r.declStart, r.sigEnd))
        }
        if label.isEmpty { return "" }
        var md = "```typescript\n\(label)\n```"
        if r.docStart >= 0, r.docEnd <= t.length, r.docEnd > r.docStart {
            let d = NJSEnv.jsdoc(slice(r.docStart, r.docEnd))
            if !d.isEmpty { md += "\n\n" + d }
        }
        if r.path != path { md += "\n\n*\(rel)*" }
        if others > 0 { md += "\n\n*+\(others) more declaration\(others == 1 ? "" : "s")*" }
        return md
    }

    /// True when the declaration leaves its type to inference, so a TypeScript server (if running) has a better hover.
    func isInferred(_ r: NJSRes) -> Bool {
        guard !r.fileTop, let t = text(r.path), r.sigEnd <= t.length, r.loc >= 0, r.loc <= r.sigEnd else { return false }
        let tail = t.substring(with: NSRange(location: r.loc, length: r.sigEnd - r.loc))
        switch r.kind {
        case .variable, .constant, .property:
            let head = tail.range(of: " = ").map { String(tail[..<$0.lowerBound]) } ?? tail
            return !head.contains(":")
        case .parameter:
            return !t.substring(with: NSRange(location: r.declStart, length: max(0, r.sigEnd - r.declStart))).contains(":")
        case .function, .method, .getter:
            let sig = t.substring(with: NSRange(location: r.declStart, length: max(0, r.sigEnd - r.declStart)))
            return sig.range(of: #"\)\s*:"#, options: .regularExpression) == nil
        default: return false
        }
    }

    static func jsdoc(_ raw: String) -> String {
        var lines: [String] = []
        for l in raw.components(separatedBy: "\n") {
            var s = l.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("/**") { s.removeFirst(3) }
            if s.hasSuffix("*/") { s.removeLast(2) }
            if s.hasPrefix("*") { s.removeFirst() }
            s = s.trimmingCharacters(in: .whitespaces)
            lines.append(s)
        }
        var out: [String] = []
        for l in lines {
            if l.hasPrefix("@") {
                let parts = l.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
                let tag = parts[0]
                var rest = parts.count > 1 ? parts[1] : ""
                if tag == "@param" || tag == "@property" || tag == "@arg" {
                    if rest.hasPrefix("{"), let close = rest.firstIndex(of: "}") { rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces) }
                    let p = rest.split(separator: " ", maxSplits: 1).map(String.init)
                    out.append("*\(tag)* `\(p.first ?? "")`" + (p.count > 1 ? " - " + p[1].trimmingCharacters(in: CharacterSet(charactersIn: "- ")) : ""))
                } else if tag == "@returns" || tag == "@return" {
                    if rest.hasPrefix("{"), let close = rest.firstIndex(of: "}") { rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces) }
                    out.append("*@returns* " + rest)
                } else {
                    out.append("*\(tag)* " + rest)
                }
            } else { out.append(l) }
        }
        while out.first?.isEmpty == true { out.removeFirst() }
        while out.last?.isEmpty == true { out.removeLast() }
        return out.joined(separator: "\n\n").replacingOccurrences(of: "\n\n\n\n", with: "\n\n")
    }
}
