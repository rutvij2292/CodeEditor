import Foundation

// Native PHP service support: bounded file-text cache, docblock extraction/parsing and markdown rendering for hover.
// Nothing here is resident beyond a handful of recently used file texts (NPFiles) -- everything else is computed on demand.

/// Last few PHP file texts (path + mtime keyed, hard capped by count and bytes). Thread-safe: several project queues may ask.
enum NPFiles {
    private static let lock = NSLock()
    private static var entries: [(path: String, stamp: Int64, text: NSString)] = []
    private static let maxEntries = 6
    private static let maxBytes = 3_000_000       // characters (<= 6 MB of UTF-16 in the worst case)

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
    private static let tableLock = NSLock()
    private static var tables: [(text: NSString, table: NPLineStarts)] = []

    /// Line table of a big text, kept for the last 2 texts (a lookup asks for several positions in the same large vendor file).
    private static func table(_ ns: NSString) -> NPLineStarts {
        tableLock.lock()
        if let i = tables.firstIndex(where: { $0.text === ns }) { let t = tables[i].table; tableLock.unlock(); return t }
        tableLock.unlock()
        let t = NPLineStarts(ns)
        tableLock.lock()
        tables.append((ns, t))
        if tables.count > 2 { tables.removeFirst() }
        tableLock.unlock()
        return t
    }

    static func dropTables() { tableLock.lock(); tables.removeAll(); tableLock.unlock() }

    static func lineCol(_ ns: NSString, _ offset: Int) -> (line: Int, col: Int) {
        if offset > 30_000 { return table(ns).position(of: offset) }
        let end = min(max(0, offset), ns.length)
        var buf = [unichar](repeating: 0, count: min(end, 4096))
        var line = 1, ls = 0, pos = 0
        while pos < end {                                  // chunked: no allocation proportional to the file
            let len = min(4096, end - pos)
            ns.getCharacters(&buf, range: NSRange(location: pos, length: len))
            for i in 0..<len where buf[i] == 10 { line += 1; ls = pos + i + 1 }
            pos += len
        }
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
        d.fill(tags)
        return d
    }


    /// Interprets collected tags (shared by the full and the query parser).
    private mutating func fill(_ tags: [(name: String, text: String, loc: Int)]) {
        var d = self
        for t in tags {
            switch t.name {
            case "param":
                let (ty, rest) = NPDoc.splitType(t.text)
                var nm = "", text = rest
                if rest.hasPrefix("$") || rest.hasPrefix("...$") || rest.hasPrefix("&$") {
                    let w = String(rest.prefix { !$0.isWhitespace })
                    nm = w.replacingOccurrences(of: "...", with: "").replacingOccurrences(of: "&", with: "")
                    text = String(rest.dropFirst(w.count)).trimmingCharacters(in: .whitespaces)
                }
                d.params.append((nm, ty, text))
            case "return", "returns":
                let (ty, rest) = NPDoc.splitType(t.text)
                d.ret = (ty, rest)
            case "var":
                d.varType = NPDoc.splitType(t.text).0
            case "throws":
                d.throwsList.append(NPDoc.splitType(t.text).0)
            case "deprecated":
                d.deprecated = t.text.isEmpty ? "deprecated" : t.text
            case "see", "mixin":
                if let f = t.text.split(separator: " ").first { d.sees.append(String(f)) }
            case "property", "property-read", "property-write":
                let (ty, rest) = NPDoc.splitType(t.text)
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
        self = d
    }

    // MARK: Query parsing (huge class docblocks)

    /// What a caller needs from a docblock. Class docblocks of IDE-helper / Carbon style hold thousands of `@method` lines;
    /// parsing them whole costs milliseconds on every lookup, so big docblocks are scanned once for just the requested tags.
    struct Query {
        var core = false          // summary, @param, @return, @var, @throws, @deprecated
        var sees = false          // @see / @mixin
        var templates = false     // @template lines (kept in `raw`)
        var method: String?       // the @method line of this name
        var prop: String?         // the @property line of this name
        static let classInfo = Query(core: true, sees: true, templates: true)
        static let core = Query(core: true)
        static let sees = Query(sees: true)
        static func method(_ n: String) -> Query { Query(method: n) }
        static func prop(_ n: String) -> Query { Query(prop: n) }
    }

    static let bigDocBytes = 4096

    /// Same result as `parse` for the requested parts; docblocks under `bigDocBytes` are simply parsed whole.
    static func parse(_ rawText: String, start: Int = 0, query q: Query) -> NPDoc {
        let t0 = NPStats.now()
        defer { NPStats.docNs &+= NPStats.now() &- t0 }
        var text = rawText
        let big = text.utf8.count >= bigDocBytes
        if !big { return parse(rawText, start: start) }
        var d = NPDoc()
        var summary: [String] = []
        var tags: [(name: String, text: String, loc: Int)] = []
        var tmplLines: [String] = []
        text.withUTF8 { b in
            let n = b.count
            @inline(__always) func isWS(_ c: UInt8) -> Bool { c == 32 || c == 9 }
            func has(_ lo: Int, _ hi: Int, _ needle: [UInt8]) -> Bool {
                let m = needle.count
                guard m > 0, hi - lo >= m else { return false }
                var i = lo
                let f = needle[0]
                while i + m <= hi {
                    if b[i] == f {
                        var k = 1
                        while k < m, b[i + k] == needle[k] { k += 1 }
                        if k == m { return true }
                    }
                    i += 1
                }
                return false
            }
            let mNeedle: [UInt8] = q.method.map { Array(($0 + "(").utf8) } ?? []
            let pNeedle: [UInt8] = q.prop.map { Array(("$" + $0).utf8) } ?? []
            var tag: (name: String, text: String, loc: Int)?
            var inSummary = true
            var u16 = 0                       // UTF-16 offset of the current line start
            var ls = 0
            func flush() { if let t = tag { tags.append(t); tag = nil } }
            while ls <= n {
                var le = ls
                while le < n, b[le] != 10 { le += 1 }
                // original line handling
                var cs = ls, ce = le, lead = 0
                while cs < ce, b[cs] == 32 || b[cs] == 9 || b[cs] == 13 { cs += 1; lead += 1 }
                if ce - cs >= 3, b[cs] == 47, b[cs + 1] == 42, b[cs + 2] == 42 { cs += 3; lead += 3 }
                else if ce - cs >= 2, b[cs] == 47, b[cs + 1] == 42 { cs += 2; lead += 2 }
                if ce - cs >= 2, b[ce - 1] == 47, b[ce - 2] == 42 { ce -= 2 }
                if cs < ce, b[cs] == 42 { cs += 1; lead += 1 }
                if cs < ce, b[cs] == 32 { cs += 1; lead += 1 }
                var ts = cs, te = ce
                while ts < te, isWS(b[ts]) { ts += 1 }
                while te > ts, isWS(b[te - 1]) { te -= 1 }
                if ts == te {
                    if inSummary, !summary.isEmpty { inSummary = false }
                    flush()
                } else if b[ts] == 64 {
                    flush()
                    inSummary = false
                    var ne = ts + 1
                    while ne < te, !(b[ne] == 32 || b[ne] == 9 || b[ne] == 13) { ne += 1 }
                    let name = String(decoding: UnsafeBufferPointer(rebasing: b[(ts + 1)..<ne]), as: UTF8.self)
                    var wanted = false
                    switch name {
                    case "param", "return", "returns", "var", "throws", "deprecated": wanted = q.core
                    case "see", "mixin": wanted = q.sees
                    case "method": wanted = !mNeedle.isEmpty && (has(ts, te, mNeedle) || !has(ts, te, [40]))
                    case "property", "property-read", "property-write": wanted = !pNeedle.isEmpty && has(ts, te, pNeedle)
                    default:
                        if q.templates, name.hasPrefix("template") { tmplLines.append(String(decoding: UnsafeBufferPointer(rebasing: b[ts..<te]), as: UTF8.self)) }
                    }
                    if wanted {
                        let line = String(decoding: UnsafeBufferPointer(rebasing: b[ts..<te]), as: UTF8.self)
                        tag = (name, String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces), start + u16 + lead)
                    }
                } else if inSummary {
                    if q.core { summary.append(String(decoding: UnsafeBufferPointer(rebasing: b[ts..<te]), as: UTF8.self)) }
                } else if tag != nil {
                    tag!.text += " " + String(decoding: UnsafeBufferPointer(rebasing: b[ts..<te]), as: UTF8.self)
                }
                // advance (UTF-16 length of this line + newline)
                var i = ls
                while i < le {
                    let c = b[i]
                    if c & 0xC0 != 0x80 { u16 += c >= 0xF0 ? 2 : 1 }
                    i += 1
                }
                u16 += 1
                ls = le + 1
            }
            flush()
        }
        d.raw = tmplLines.isEmpty ? "*" : tmplLines.joined(separator: "\n")
        d.summary = summary.joined(separator: " ")
        d.fill(tags)
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
