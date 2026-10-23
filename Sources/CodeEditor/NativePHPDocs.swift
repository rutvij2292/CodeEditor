import Foundation

// Native PHP service support: bounded file-text cache, docblock extraction/parsing and markdown rendering for hover.
// Nothing here is resident beyond a handful of recently used file texts (NPFiles) -- everything else is computed on demand.

/// Last few PHP file texts (path + mtime keyed, hard capped by count and bytes). Thread-safe: several project queues may ask.
enum NPFiles {
    private static let lock = NSLock()
    private static var entries: [(path: String, stamp: Int64, text: NSString)] = []
    private static let maxEntries = 6
    private static let maxBytes = 6_000_000

    static func text(_ path: String) -> NSString? {
        let st = LaravelFS.mtime(path)
        lock.lock()
        if let i = entries.firstIndex(where: { $0.path == path }), entries[i].stamp == st {
            let e = entries.remove(at: i); entries.append(e); lock.unlock(); return e.text
        }
        lock.unlock()
        guard let t = FastProject.read(path) else { return nil }
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.path == path }
        entries.append((path, st, t))
        var total = entries.reduce(0) { $0 + $1.text.length }
        while entries.count > maxEntries || (total > maxBytes && entries.count > 1) { total -= entries.removeFirst().text.length }
        return t
    }

    static func clear() { lock.lock(); entries.removeAll(); lock.unlock() }
    static var cachedCount: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
}

enum NPText {
    /// 1-based line and column (UTF-16) of `offset`.
    static func lineCol(_ ns: NSString, _ offset: Int) -> (line: Int, col: Int) {
        let end = min(max(0, offset), ns.length)
        var buf = [unichar](repeating: 0, count: end)
        if end > 0 { ns.getCharacters(&buf, range: NSRange(location: 0, length: end)) }
        var line = 1, ls = 0
        for (i, c) in buf.enumerated() where c == 10 { line += 1; ls = i + 1 }
        return (line, end - ls + 1)
    }

    static func lineText(_ ns: NSString, _ offset: Int, maxLen: Int = 220) -> String {
        let r = ns.lineRange(for: NSRange(location: min(max(0, offset), max(0, ns.length - 1)), length: 0))
        var s = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count > maxLen { s = String(s.prefix(maxLen)) + "..." }
        return s
    }
}

struct NPDoc {
    var summary = ""
    var params: [(name: String, type: String, text: String)] = []
    var ret: (type: String, text: String)?
    var varType: String?
    var throwsList: [String] = []
    var deprecated: String?
    var sees: [String] = []
    var props: [(name: String, type: String, readOnly: Bool, loc: Int)] = []     // @property / @property-read (loc = offset in raw)
    var methods: [(name: String, line: String, loc: Int)] = []                     // @method
    var raw = ""

    var isEmpty: Bool { summary.isEmpty && params.isEmpty && ret == nil && deprecated == nil }

    // MARK: Locating

    /// Raw text of the docblock directly above `declStart` (skipping `#[Attributes]`), with its start offset.
    static func leading(_ ns: NSString, before declStart: Int) -> (text: String, start: Int)? {
        var p = min(max(0, declStart), ns.length)
        func isWS(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
        for _ in 0..<6 {
            while p > 0, isWS(ns.character(at: p - 1)) { p -= 1 }
            if p >= 2, ns.character(at: p - 1) == 47, ns.character(at: p - 2) == 42 {          // */
                let r = ns.range(of: "/*", options: [.backwards, .literal], range: NSRange(location: 0, length: p - 2))
                guard r.location != NSNotFound, r.location + 2 < ns.length, ns.character(at: r.location + 2) == 42 else { return nil }
                return (ns.substring(with: NSRange(location: r.location, length: p - r.location)), r.location)
            }
            if p > 0, ns.character(at: p - 1) == 93 {                                           // ] of an attribute
                var depth = 0, q = p - 1
                while q >= 0 {
                    let c = ns.character(at: q)
                    if c == 93 { depth += 1 } else if c == 91 { depth -= 1; if depth == 0 { break } }
                    q -= 1
                }
                guard q > 0, ns.character(at: q - 1) == 35 else { return nil }
                p = q - 1
                continue
            }
            return nil
        }
        return nil
    }

    static func parse(_ rawText: String, start: Int = 0) -> NPDoc {
        var d = NPDoc()
        d.raw = rawText
        var lines: [(String, Int)] = []
        var off = 0
        for l in rawText.components(separatedBy: "\n") {
            var s = Substring(l)
            var lead = 0
            while let f = s.first, f == " " || f == "\t" || f == "\r" { s = s.dropFirst(); lead += 1 }
            if s.hasPrefix("/**") { s = s.dropFirst(3); lead += 3 } else if s.hasPrefix("/*") { s = s.dropFirst(2); lead += 2 }
            if s.hasSuffix("*/") { s = s.dropLast(2) }
            if s.hasPrefix("*") { s = s.dropFirst(); lead += 1 }
            if s.hasPrefix(" ") { s = s.dropFirst(); lead += 1 }
            lines.append((s.trimmingCharacters(in: .whitespaces), start + off + lead))
            off += l.utf16.count + 1
        }
        var summary: [String] = []
        var tag: (name: String, text: String, loc: Int)?
        var tags: [(name: String, text: String, loc: Int)] = []
        var inSummary = true
        for (line, loc) in lines {
            if line.hasPrefix("@") {
                if let t = tag { tags.append(t) }
                inSummary = false
                let name = String(line.dropFirst().prefix { !$0.isWhitespace })
                tag = (name, String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces), loc)
            } else if line.isEmpty {
                if inSummary, !summary.isEmpty { inSummary = false }
                if tag != nil { tags.append(tag!); tag = nil }
            } else if inSummary {
                summary.append(line)
            } else if tag != nil {
                tag!.text += " " + line
            }
        }
        if let t = tag { tags.append(t) }
        d.summary = summary.joined(separator: " ")
        for t in tags {
            switch t.name {
            case "param":
                let (ty, rest) = splitType(t.text)
                var nm = "", text = rest
                if rest.hasPrefix("$") || rest.hasPrefix("...$") || rest.hasPrefix("&$") {
                    let w = String(rest.prefix { !$0.isWhitespace })
                    nm = w.replacingOccurrences(of: "...", with: "").replacingOccurrences(of: "&", with: "")
                    text = String(rest.dropFirst(w.count)).trimmingCharacters(in: .whitespaces)
                }
                d.params.append((nm, ty, text))
            case "return", "returns":
                let (ty, rest) = splitType(t.text)
                d.ret = (ty, rest)
            case "var":
                d.varType = splitType(t.text).0
            case "throws":
                d.throwsList.append(splitType(t.text).0)
            case "deprecated":
                d.deprecated = t.text.isEmpty ? "deprecated" : t.text
            case "see", "mixin":
                if let f = t.text.split(separator: " ").first { d.sees.append(String(f)) }
            case "property", "property-read", "property-write":
                let (ty, rest) = splitType(t.text)
                if rest.hasPrefix("$") {
                    let nm = String(rest.dropFirst().prefix { $0.isLetter || $0.isNumber || $0 == "_" })
                    d.props.append((nm, ty, t.name == "property-read", t.loc))
                }
            case "method":
                var s = t.text
                if s.hasPrefix("static ") { s = String(s.dropFirst(7)) }
                // [Type] name(
                if let paren = s.firstIndex(of: "(") {
                    let head = s[..<paren].split(separator: " ")
                    if let n = head.last { d.methods.append((String(n), t.text, t.loc)) }
                }
            default: break
            }
        }
        return d
    }

    /// Splits a tag payload into its type (which may contain `<..>`, `(..)`, `{..}`, `|`) and the rest.
    private static func splitType(_ s: String) -> (String, String) {
        var depth = 0
        var end = s.startIndex
        for i in s.indices {
            let c = s[i]
            if "<({[".contains(c) { depth += 1 } else if ">)}]".contains(c) { depth -= 1 }
            if c == " " && depth <= 0 { break }
            end = s.index(after: i)
        }
        return (String(s[s.startIndex..<end]), String(s[end...]).trimmingCharacters(in: .whitespaces))
    }

    // MARK: Rendering

    /// Markdown for the hover body (summary, @param/@return trimmed, deprecation, throws).
    func markdown(maxChars: Int = 600) -> String {
        var out: [String] = []
        if let dep = deprecated { out.append("**Deprecated** " + NPDoc.clip(dep, 160)) }
        if !summary.isEmpty { out.append(NPDoc.clip(NPDoc.cleanInline(summary), maxChars)) }
        var tagLines: [String] = []
        for p in params.prefix(8) {
            let nm = p.name.isEmpty ? "" : "`\(p.name)` "
            let ty = p.type.isEmpty ? "" : "`\(p.type)` "
            let line = (nm + ty + NPDoc.clip(NPDoc.cleanInline(p.text), 110)).trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { tagLines.append("- **@param** " + line) }
        }
        if params.count > 8 { tagLines.append("- ... \(params.count - 8) more parameters") }
        if let r = ret, !r.type.isEmpty, r.type != "void" {
            tagLines.append("- **@return** `\(r.type)` " + NPDoc.clip(NPDoc.cleanInline(r.text), 140))
        }
        for t in throwsList.prefix(3) { tagLines.append("- **@throws** `\(t)`") }
        if !tagLines.isEmpty { out.append(tagLines.joined(separator: "\n")) }
        return out.joined(separator: "\n\n")
    }

    static func clip(_ s: String, _ n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > n ? String(t.prefix(n)).trimmingCharacters(in: .whitespaces) + "..." : t
    }

    /// Removes `{@link ...}` / `<code>` noise and characters the small markdown renderer would treat as emphasis.
    static func cleanInline(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "{@see ", with: "`").replacingOccurrences(of: "{@link ", with: "`")
            .replacingOccurrences(of: "{@code ", with: "`").replacingOccurrences(of: "<code>", with: "`").replacingOccurrences(of: "</code>", with: "`")
            .replacingOccurrences(of: "</p>", with: " ").replacingOccurrences(of: "<p>", with: " ").replacingOccurrences(of: "<br>", with: " ")
            .replacingOccurrences(of: "<br />", with: " ")
        if t.contains("`") && t.filter({ $0 == "`" }).count % 2 == 1 { t = t.replacingOccurrences(of: "}", with: "`", options: [], range: t.range(of: "}")) }
        return t.replacingOccurrences(of: "*", with: "\\*").replacingOccurrences(of: "_", with: "\\_")
    }
}
