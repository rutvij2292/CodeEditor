import Foundation

/// One request of a `.http` / `.rest` file (JetBrains HTTP Client / VS Code REST Client syntax).
struct HttpRequest {
    var name: String?
    var title: String?              // text after `###`
    var method: String
    var url: String
    var headers: [(name: String, value: String)]
    var body: String?
    /// 1-based lines: first line of the block (after the previous `###`), the request line (gutter marker), the last line.
    var blockStart: Int
    var line: Int
    var endLine: Int

    var displayName: String { name ?? title ?? "\(method) \(url)" }
}

/// Parsed file: requests plus the `@name = value` variables declared in it.
struct HttpDocument {
    var requests: [HttpRequest] = []
    var variables: [(name: String, value: String)] = []

    static let methods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "TRACE", "CONNECT", "LOCK", "UNLOCK",
                                       "PROPFIND", "PROPPATCH", "MKCOL", "COPY", "MOVE", "PURGE", "LINK", "UNLINK", "VIEW"]

    /// The request whose block contains a 1-based line (nil when the line is in no request).
    func request(atLine line: Int) -> HttpRequest? {
        requests.first { line >= $0.blockStart && line <= $0.endLine }
    }

    func request(named name: String) -> HttpRequest? { requests.first { $0.name == name } }

    static func parse(_ text: String) -> HttpDocument {
        var doc = HttpDocument()
        let lines = text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var blockStart = 0
        var title: String?
        func flush(_ range: Range<Int>) {
            if let r = parseBlock(lines, range, title: title, doc: &doc) { doc.requests.append(r) }
        }
        for (i, l) in lines.enumerated() where l.hasPrefix("###") {
            flush(blockStart..<i)
            let t = l.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            title = t.isEmpty ? nil : t
            blockStart = i + 1
        }
        flush(blockStart..<lines.count)
        return doc
    }

    /// `range` is 0-based over `lines`.
    private static func parseBlock(_ lines: [String], _ range: Range<Int>, title: String?, doc: inout HttpDocument) -> HttpRequest? {
        var i = range.lowerBound
        var name: String?
        // Preamble: blanks, comments, `# @name`, `@var = value`, until the request line.
        while i < range.upperBound {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty { i += 1; continue }
            if t.hasPrefix("#") || t.hasPrefix("//") {
                let c = t.drop(while: { $0 == "#" || $0 == "/" }).trimmingCharacters(in: .whitespaces)
                if c.hasPrefix("@name") {
                    let n = c.dropFirst(5).trimmingCharacters(in: CharacterSet(charactersIn: " =\t"))
                    if !n.isEmpty { name = n }
                }
                i += 1; continue
            }
            if t.hasPrefix("@"), let eq = t.firstIndex(of: "=") {
                let k = t[t.index(after: t.startIndex)..<eq].trimmingCharacters(in: .whitespaces)
                let v = t[t.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                if !k.isEmpty { doc.variables.append((k, v)) }
                i += 1; continue
            }
            break
        }
        guard i < range.upperBound else { return nil }
        let first = lines[i].trimmingCharacters(in: .whitespaces)
        let parts = first.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        var method = "GET", urlPart = first
        if parts.count == 2, methods.contains(parts[0].uppercased()) { method = parts[0].uppercased(); urlPart = String(parts[1]) }
        else if parts.count == 1, methods.contains(parts[0].uppercased()) { return nil }   // a method without a URL
        urlPart = urlPart.trimmingCharacters(in: .whitespaces)
        if let r = urlPart.range(of: #"\s+HTTP/\d(\.\d)?$"#, options: .regularExpression) { urlPart.removeSubrange(r) }
        let requestLine = i
        i += 1
        // Continuation lines: indented `?a=b` / `&c=d`.
        while i < range.upperBound {
            let raw = lines[i], t = raw.trimmingCharacters(in: .whitespaces)
            guard raw.first == " " || raw.first == "\t", t.hasPrefix("?") || t.hasPrefix("&") else { break }
            urlPart += t; i += 1
        }
        // Headers until a blank line.
        var headers: [(name: String, value: String)] = []
        while i < range.upperBound {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty { break }
            if t.hasPrefix("#") || t.hasPrefix("//") { i += 1; continue }
            guard let colon = t.firstIndex(of: ":") else { break }
            headers.append((t[..<colon].trimmingCharacters(in: .whitespaces), t[t.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
            i += 1
        }
        // Body: everything after the blank line, trailing blank lines dropped.
        var body: String?
        if i + 1 < range.upperBound {
            var bodyLines = Array(lines[(i + 1)..<range.upperBound])
            while let l = bodyLines.last, l.trimmingCharacters(in: .whitespaces).isEmpty { bodyLines.removeLast() }
            if !bodyLines.isEmpty { body = bodyLines.joined(separator: "\n") }
        }
        var last = range.upperBound   // 1-based number of the block's last line
        while last > requestLine + 1, lines[last - 1].trimmingCharacters(in: .whitespaces).isEmpty { last -= 1 }
        return HttpRequest(name: name, title: title, method: method, url: urlPart, headers: headers, body: body,
                           blockStart: range.lowerBound + 1, line: requestLine + 1, endLine: max(last, requestLine + 1))
    }
}

/// Highlighting for `.http` files (SimpleLexer kind `.http`): methods, URLs, header names, `###`, comments, `@vars`, `{{templates}}`.
enum HttpLexer {
    private enum Part { case preamble, headers, body }

    static func lex(_ s: [unichar], base: Int, emit: (Int, Int, String) -> Void) {
        let n = s.count
        var i = 0
        var part = Part.preamble
        func str(_ a: Int, _ b: Int) -> String { String(utf16CodeUnits: Array(s[a..<b]), count: b - a) }
        func templates(_ a: Int, _ b: Int) {
            var k = a
            while k + 1 < b {
                if s[k] == 123, s[k + 1] == 123 {
                    var e = k + 2
                    while e + 1 < b, !(s[e] == 125 && s[e + 1] == 125) { e += 1 }
                    if e + 1 < b { emit(base + k, base + e + 2, "variable.builtin"); k = e + 2; continue }
                }
                k += 1
            }
        }
        while i < n {
            var eol = i; while eol < n, s[eol] != 10 { eol += 1 }
            var end = eol; if end > i, s[end - 1] == 13 { end -= 1 }
            var p = i; while p < end, s[p] == 32 || s[p] == 9 { p += 1 }
            let blank = p == end
            if end - i >= 3, s[i] == 35, s[i + 1] == 35, s[i + 2] == 35 {                    // ### separator
                emit(base + i, base + end, "comment")
                part = .preamble
            } else if part != .body, !blank, s[p] == 35 || (s[p] == 47 && p + 1 < end && s[p + 1] == 47) {   // # or // comment
                emit(base + p, base + end, "comment")
                if let r = str(p, end).range(of: "@name") {
                    let off = str(p, end).distance(from: str(p, end).startIndex, to: r.lowerBound)
                    emit(base + p + off, base + p + off + 5, "keyword")
                }
            } else if part == .preamble, !blank, s[p] == 64 {                                  // @var = value
                var k = p; while k < end, s[k] != 61 { k += 1 }
                if k < end {
                    var ke = k; while ke > p, s[ke - 1] == 32 { ke -= 1 }
                    emit(base + p, base + ke, "property"); emit(base + k, base + k + 1, "operator")
                    templates(k + 1, end)
                }
            } else if part == .preamble, !blank {                                               // request line
                var k = p; while k < end, s[k] != 32, s[k] != 9 { k += 1 }
                var urlStart = p
                if HttpDocument.methods.contains(str(p, k).uppercased()) {
                    emit(base + p, base + k, "keyword")
                    urlStart = k; while urlStart < end, s[urlStart] == 32 || s[urlStart] == 9 { urlStart += 1 }
                }
                var urlEnd = end
                if let r = str(urlStart, end).range(of: #"\s+HTTP/\d(\.\d)?$"#, options: .regularExpression) {
                    let off = str(urlStart, end).distance(from: str(urlStart, end).startIndex, to: r.lowerBound)
                    urlEnd = urlStart + off
                    emit(base + urlEnd, base + end, "constant.builtin")
                }
                if urlEnd > urlStart { emit(base + urlStart, base + urlEnd, "string") }
                templates(urlStart, urlEnd)
                part = .headers
            } else if part == .headers {
                if blank { part = .body } else {
                    var k = p; while k < end, s[k] != 58 { k += 1 }
                    if k < end, k > p { emit(base + p, base + k, "property"); emit(base + k, base + k + 1, "operator") }
                    else if p < end, s[p] == 63 || s[p] == 38 { emit(base + p, base + end, "string") }   // ?a=b continuation
                    templates(p, end)
                }
            } else if part == .body {
                templates(i, end)
            }
            i = eol + 1
        }
    }
}
