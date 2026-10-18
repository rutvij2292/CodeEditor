import Foundation

/// Compact, index-based document tree ("tape") shared by the JSON and YAML viewers. Struct-of-arrays instead of node objects:
/// ~33 bytes per value, so a 10 MB JSON file costs a few tens of MB while it is shown and nothing once the pane is hidden.
/// Source positions are UTF-8 byte offsets for JSON and UTF-16 offsets for YAML (`toUTF16` converts for the editor).
enum StructKind: UInt8 { case object, array, string, number, bool, null }

struct StructIssue {
    var severity: Int            // 1 error, 2 warning
    var message: String
    var offset: Int              // UTF-16 offset in the source text
    var length: Int
}

final class StructTape {
    private(set) var kind: [UInt8] = []
    private(set) var start: [Int32] = []
    private(set) var end: [Int32] = []
    private(set) var keyStart: [Int32] = []        // -1: array element / root
    private(set) var keyEnd: [Int32] = []
    private(set) var firstChild: [Int32] = []
    private(set) var nextSibling: [Int32] = []
    private(set) var count: [Int32] = []           // number of children
    private(set) var parent: [Int32] = []
    var issues: [StructIssue] = []
    /// The node cap was hit: the tree shows a prefix of the document (syntax is still validated to the end).
    var truncated = false
    var isJSON = true
    /// Source slice [a, b) as text, and source offset -> UTF-16 offset in the editor text.
    var slice: (Int, Int) -> String = { _, _ in "" }
    var toUTF16: (Int) -> Int = { $0 }

    var nodeCount: Int { kind.count }
    var isEmpty: Bool { kind.isEmpty }
    var root: Int32 { kind.isEmpty ? -1 : 0 }

    func reserve(_ n: Int) {
        kind.reserveCapacity(n); start.reserveCapacity(n); end.reserveCapacity(n); keyStart.reserveCapacity(n); keyEnd.reserveCapacity(n)
        firstChild.reserveCapacity(n); nextSibling.reserveCapacity(n); count.reserveCapacity(n); parent.reserveCapacity(n)
    }

    /// Appends a node; links it as the next child of `parent` (`lastSibling` = the parent's current last child, or -1).
    @discardableResult
    func add(_ k: StructKind, start s: Int, keyStart ks: Int = -1, keyEnd ke: Int = -1, parent p: Int32, after lastSibling: Int32) -> Int32 {
        let i = Int32(kind.count)
        kind.append(k.rawValue); start.append(Int32(truncatingIfNeeded: s)); end.append(Int32(truncatingIfNeeded: s))
        keyStart.append(Int32(truncatingIfNeeded: ks)); keyEnd.append(Int32(truncatingIfNeeded: ke))
        firstChild.append(-1); nextSibling.append(-1); count.append(0); parent.append(p)
        if p >= 0 {
            if lastSibling >= 0 { nextSibling[Int(lastSibling)] = i } else { firstChild[Int(p)] = i }
            count[Int(p)] += 1
        }
        return i
    }

    func close(_ i: Int32, end e: Int) { if i >= 0 { end[Int(i)] = Int32(truncatingIfNeeded: e) } }
    func setKind(_ i: Int32, _ k: StructKind) { kind[Int(i)] = k.rawValue }

    // MARK: Queries

    func kindOf(_ i: Int32) -> StructKind { StructKind(rawValue: kind[Int(i)]) ?? .null }
    func isContainer(_ i: Int32) -> Bool { let k = kindOf(i); return k == .object || k == .array }
    func childCount(_ i: Int32) -> Int { Int(count[Int(i)]) }
    func parentOf(_ i: Int32) -> Int32 { parent[Int(i)] }
    func hasKey(_ i: Int32) -> Bool { keyStart[Int(i)] >= 0 }

    /// Children indices of a container, in source order.
    func children(of i: Int32) -> [Int32] {
        var out: [Int32] = []
        out.reserveCapacity(Int(count[Int(i)]))
        var c = firstChild[Int(i)]
        while c >= 0 { out.append(c); c = nextSibling[Int(c)] }
        return out
    }

    func keyText(_ i: Int32) -> String? {
        let ks = keyStart[Int(i)], ke = keyEnd[Int(i)]
        guard ks >= 0, ke >= ks else { return nil }
        let raw = slice(Int(ks), Int(ke))
        return Self.unquote(raw, json: isJSON)
    }

    /// Display text of a scalar (strings unescaped, unquoted); containers return "".
    func scalarText(_ i: Int32, limit: Int = 300) -> String {
        guard !isContainer(i) else { return "" }
        let s = Int(start[Int(i)]), e = Int(end[Int(i)])
        guard e > s else { return "" }
        if e - s > limit * 4 {      // never materialise a huge string just to truncate it
            let head = slice(s, min(e, s + limit * 4))
            return Self.unquote(head, json: isJSON, partial: true).prefix(limit) + "…"
        }
        let raw = slice(s, e)
        let text = kindOf(i) == .string ? Self.unquote(raw, json: isJSON) : raw
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }

    func fullScalarText(_ i: Int32) -> String {
        guard !isContainer(i) else { return "" }
        let raw = slice(Int(start[Int(i)]), Int(end[Int(i)]))
        return kindOf(i) == .string ? Self.unquote(raw, json: isJSON) : raw
    }

    /// Source range of the node's value, in UTF-16 units of the editor text.
    func editorRange(_ i: Int32) -> NSRange {
        let s = toUTF16(Int(keyStart[Int(i)] >= 0 ? keyStart[Int(i)] : start[Int(i)]))
        let e = toUTF16(Int(end[Int(i)]))
        return NSRange(location: s, length: max(0, e - s))
    }

    /// `$.a.b[3]["odd key"]`
    func path(_ i: Int32) -> String {
        var parts: [String] = []
        var n = i
        while n >= 0 {
            let p = parent[Int(n)]
            if p < 0 { break }
            if kindOf(p) == .array {
                var idx = 0, c = firstChild[Int(p)]
                while c >= 0, c != n { idx += 1; c = nextSibling[Int(c)] }
                parts.append("[\(idx)]")
            } else {
                let k = keyText(n) ?? "?"
                let simple = !k.isEmpty && k.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" || $0 == "$" }
                parts.append(simple ? "." + k : "[\"" + k.replacingOccurrences(of: "\"", with: "\\\"") + "\"]")
            }
            n = p
        }
        return "$" + parts.reversed().joined()
    }

    /// Deepest node whose range contains `offset` (editor UTF-16 offset), as the chain root...node. Children are in source order.
    func chain(at offset: Int) -> [Int32] {
        guard !isEmpty else { return [] }
        var out: [Int32] = [0]
        var cur: Int32 = 0
        while isContainer(cur) {
            var found: Int32 = -1
            var c = firstChild[Int(cur)]
            while c >= 0 {
                let s = toUTF16(Int(keyStart[Int(c)] >= 0 ? keyStart[Int(c)] : start[Int(c)])), e = toUTF16(Int(end[Int(c)]))
                if offset >= s && offset <= e { found = c; break }
                if s > offset { break }
                c = nextSibling[Int(c)]
            }
            if found < 0 { break }
            out.append(found); cur = found
        }
        return out
    }

    /// Nodes whose key or scalar text contains `query` (case-insensitive), plus their ancestors. Capped; call off the main thread.
    func search(_ query: String, maxMatches: Int = 2000) -> (matches: [Int32], visible: Set<Int32>) {
        let q = query.lowercased()
        guard !q.isEmpty else { return ([], []) }
        var matches: [Int32] = []
        var visible = Set<Int32>()
        for i in 0..<kind.count {
            let n = Int32(i)
            var hit = false
            if let k = keyText(n), k.lowercased().contains(q) { hit = true }
            if !hit, !isContainer(n), scalarText(n, limit: 200).lowercased().contains(q) { hit = true }
            guard hit else { continue }
            matches.append(n)
            var p = n
            while p >= 0, visible.insert(p).inserted { p = parent[Int(p)] }
            if matches.count >= maxMatches { break }
        }
        return (matches, visible)
    }

    // MARK: Text helpers

    static func unquote(_ raw: String, json: Bool, partial: Bool = false) -> String {
        guard let f = raw.first else { return raw }
        guard f == "\"" || f == "'" else { return raw }
        var body = Substring(raw.dropFirst())
        if !partial, body.last == f { body = body.dropLast() }
        if f == "'" && !json { return body.replacingOccurrences(of: "''", with: "'") }
        guard body.contains("\\") else { return String(body) }
        var out = ""
        var it = body.makeIterator()
        while let c = it.next() {
            guard c == "\\", let n = it.next() else { out.append(c); continue }
            switch n {
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            case "b": out.append("\u{8}")
            case "f": out.append("\u{c}")
            case "/": out.append("/")
            case "u":
                var hex = ""
                for _ in 0..<4 { if let h = it.next() { hex.append(h) } }
                if let v = UInt32(hex, radix: 16), let u = Unicode.Scalar(v) { out.unicodeScalars.append(u) }
            default: out.append(n)
            }
        }
        return out
    }
}

// MARK: - JSON parser

/// Tolerant single-pass JSON parser: comments, trailing commas, single quotes, unquoted keys and hex/Infinity/NaN numbers
/// are accepted (and reported as warnings unless `lenient`), so .jsonc / .json5 / tsconfig load. A hard syntax error stops
/// the build and keeps the partial tree. Runs on any queue.
enum JSONTapeParser {
    static let defaultMaxNodes = 1_000_000

    static func parse(_ bytes: [UInt8], lenient: Bool, maxNodes: Int = defaultMaxNodes) -> StructTape {
        let tape = StructTape()
        var p = P(tape: tape, lenient: lenient, maxNodes: maxNodes)
        bytes.withUnsafeBufferPointer { buf in
            p.buf = buf
            p.run()
        }
        let ascii = p.ascii
        tape.isJSON = true
        let copy = bytes
        tape.slice = { a, b in
            let lo = max(0, min(a, copy.count)), hi = max(lo, min(b, copy.count))
            return String(decoding: copy[lo..<hi], as: UTF8.self)
        }
        if ascii {
            tape.toUTF16 = { $0 }
        } else {
            tape.toUTF16 = { off in String(decoding: copy[0..<max(0, min(off, copy.count))], as: UTF8.self).utf16.count }
        }
        // Issue offsets were recorded as byte offsets: convert once.
        if !ascii { tape.issues = tape.issues.map { var i = $0; i.offset = tape.toUTF16(i.offset); return i } }
        return tape
    }

    private struct P {
        let tape: StructTape
        let lenient: Bool
        let maxNodes: Int
        var buf = UnsafeBufferPointer<UInt8>(start: nil, count: 0)
        var i = 0
        var failed = false
        var ascii = true
        var warned = Set<String>()
        var emit = true
        var depth = 0

        init(tape: StructTape, lenient: Bool, maxNodes: Int) { self.tape = tape; self.lenient = lenient; self.maxNodes = maxNodes }

        mutating func run() {
            var n = buf.count
            for b in buf where b >= 0x80 { ascii = false; break }
            if n > 0 { tape.reserve(min(maxNodes, max(16, n / 6))) }
            if n >= 3, buf[0] == 0xEF, buf[1] == 0xBB, buf[2] == 0xBF { i = 3 }
            skipWS()
            n = buf.count
            guard i < n else { return }
            _ = value(parent: -1, last: -1, ks: -1, ke: -1)
            if failed { return }
            skipWS()
            if i < n, !failed { fail("Unexpected content after the JSON value") }
        }

        mutating func fail(_ message: String, at pos: Int? = nil, length: Int = 1) {
            guard !failed else { return }
            failed = true
            tape.issues.append(StructIssue(severity: 1, message: message, offset: pos ?? i, length: length))
        }

        mutating func warn(_ message: String, at pos: Int, length: Int = 1) {
            guard !lenient, warned.insert(message).inserted, tape.issues.count < 50 else { return }
            tape.issues.append(StructIssue(severity: 2, message: message, offset: pos, length: length))
        }

        mutating func skipWS() {
            let n = buf.count
            while i < n {
                let c = buf[i]
                if c == 32 || c == 10 || c == 13 || c == 9 { i += 1; continue }
                if c == 47, i + 1 < n {            // comments
                    if buf[i + 1] == 47 {
                        warn("Comments are not permitted in JSON", at: i, length: 2)
                        while i < n, buf[i] != 10 { i += 1 }
                        continue
                    }
                    if buf[i + 1] == 42 {
                        warn("Comments are not permitted in JSON", at: i, length: 2)
                        let s = i
                        i += 2
                        while i + 1 < n, !(buf[i] == 42 && buf[i + 1] == 47) { i += 1 }
                        if i + 1 >= n { i = n; fail("Unterminated comment", at: s, length: 2) } else { i += 2 }
                        continue
                    }
                }
                break
            }
        }

        mutating func node(_ k: StructKind, start: Int, ks: Int, ke: Int, parent: Int32, last: Int32) -> Int32 {
            guard emit else { return -1 }
            if tape.nodeCount >= maxNodes { emit = false; tape.truncated = true; return -1 }
            return tape.add(k, start: start, keyStart: ks, keyEnd: ke, parent: parent, after: last)
        }

        /// Parses one value at `i`; returns its node index (-1 when not emitted).
        mutating func value(parent: Int32, last: Int32, ks: Int, ke: Int) -> Int32 {
            let n = buf.count
            guard i < n else { fail("Unexpected end of input"); return -1 }
            let c = buf[i]
            let s = i
            switch c {
            case 123: return object(parent: parent, last: last, ks: ks, ke: ke)
            case 91: return array(parent: parent, last: last, ks: ks, ke: ke)
            case 34, 39:
                if c == 39 { warn("Single-quoted strings are not permitted in JSON", at: i) }
                scanString(c)
                let idx = node(.string, start: s, ks: ks, ke: ke, parent: parent, last: last)
                tape.close(idx, end: i)
                return idx
            default:
                if c == 45 || c == 43 || c == 46 || (c >= 48 && c <= 57) || c == 73 || c == 78 {
                    while i < n, isTokenByte(buf[i]) { i += 1 }
                    if !validNumber(s, i) { fail("Invalid number", at: s, length: max(1, i - s)); return -1 }
                    let idx = node(.number, start: s, ks: ks, ke: ke, parent: parent, last: last)
                    tape.close(idx, end: i)
                    return idx
                }
                if isIdentByte(c) {
                    while i < n, isIdentByte(buf[i]) { i += 1 }
                    let word = String(decoding: UnsafeBufferPointer(rebasing: buf[s..<i]), as: UTF8.self)
                    let k: StructKind
                    switch word {
                    case "true", "false": k = .bool
                    case "null": k = .null
                    default: fail("Unexpected token '\(word.prefix(20))'", at: s, length: i - s); return -1
                    }
                    let idx = node(k, start: s, ks: ks, ke: ke, parent: parent, last: last)
                    tape.close(idx, end: i)
                    return idx
                }
                fail(c == 125 || c == 93 ? "Unexpected '\(Character(UnicodeScalar(c)))'" : "Unexpected character", at: i)
                return -1
            }
        }

        func isTokenByte(_ c: UInt8) -> Bool {
            (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 43 || c == 45 || c == 46 || c == 95
        }
        func isIdentByte(_ c: UInt8) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 }

        mutating func validNumber(_ a: Int, _ b: Int) -> Bool {
            var j = a
            if j < b, buf[j] == 45 { j += 1 } else if j < b, buf[j] == 43 { warn("Leading '+' is not permitted in JSON", at: a); j += 1 }
            guard j < b else { return false }
            if buf[j] == 73 || buf[j] == 78 {      // Infinity / NaN
                let word = String(decoding: UnsafeBufferPointer(rebasing: buf[j..<b]), as: UTF8.self)
                if word == "Infinity" || word == "NaN" { warn("Infinity/NaN are not permitted in JSON", at: a, length: b - a); return true }
                return false
            }
            if buf[j] == 48, j + 1 < b, buf[j + 1] == 120 || buf[j + 1] == 88 { warn("Hex numbers are not permitted in JSON", at: a, length: b - a); return true }
            var digits = 0
            if j < b, buf[j] == 48 { j += 1; digits = 1; if j < b, buf[j] >= 48, buf[j] <= 57 { warn("Leading zeros are not permitted in JSON", at: a, length: b - a) } }
            while j < b, buf[j] >= 48, buf[j] <= 57 { j += 1; digits += 1 }
            if j < b, buf[j] == 46 {
                j += 1
                var frac = 0
                while j < b, buf[j] >= 48, buf[j] <= 57 { j += 1; frac += 1 }
                if frac == 0 { if digits == 0 { return false }; warn("Number has no digits after '.'", at: a, length: b - a) }
                if digits == 0 { warn("Number has no digits before '.'", at: a, length: b - a) }
            } else if digits == 0 { return false }
            if j < b, buf[j] == 101 || buf[j] == 69 {
                j += 1
                if j < b, buf[j] == 43 || buf[j] == 45 { j += 1 }
                var e = 0
                while j < b, buf[j] >= 48, buf[j] <= 57 { j += 1; e += 1 }
                if e == 0 { return false }
            }
            return j == b
        }

        mutating func scanString(_ q: UInt8) {
            let n = buf.count
            let s = i
            i += 1
            while i < n {
                let c = buf[i]
                if c == q { i += 1; return }
                if c == 92 { i += 2; continue }
                if c == 10 { fail("Unterminated string", at: s, length: i - s); return }
                i += 1
            }
            i = n
            fail("Unterminated string", at: s, length: n - s)
        }

        mutating func object(parent: Int32, last: Int32, ks: Int, ke: Int) -> Int32 {
            let me = node(.object, start: i, ks: ks, ke: ke, parent: parent, last: last)
            depth += 1
            defer { depth -= 1 }
            if depth > 400 { fail("Nesting is too deep"); return me }
            let n = buf.count
            let open = i
            i += 1
            var lastChild: Int32 = -1
            skipWS()
            if i < n, buf[i] == 125 { i += 1; tape.close(me, end: i); return me }
            while !failed {
                skipWS()
                guard i < n else { fail("Unterminated object", at: open); break }
                let kc = buf[i]
                let kS = i
                if kc == 34 || kc == 39 {
                    if kc == 39 { warn("Single-quoted strings are not permitted in JSON", at: i) }
                    scanString(kc)
                } else if isIdentByte(kc) || (kc >= 48 && kc <= 57) {
                    warn("Property names must be quoted in JSON", at: i)
                    while i < n, isIdentByte(buf[i]) || (buf[i] >= 48 && buf[i] <= 57) { i += 1 }
                } else {
                    fail(kc == 125 ? "Trailing comma or missing property" : "Expected a property name", at: i)
                    break
                }
                if failed { break }
                let kE = i
                skipWS()
                guard i < n, buf[i] == 58 else { fail("Expected ':' after the property name"); break }
                i += 1
                skipWS()
                let child = value(parent: me, last: lastChild, ks: kS, ke: kE)
                if child >= 0 { lastChild = child }
                if failed { break }
                skipWS()
                guard i < n else { fail("Unterminated object", at: open); break }
                if buf[i] == 44 {
                    i += 1
                    skipWS()
                    if i < n, buf[i] == 125 { warn("Trailing commas are not permitted in JSON", at: i - 1); i += 1; break }
                    continue
                }
                if buf[i] == 125 { i += 1; break }
                fail("Expected ',' or '}'")
            }
            tape.close(me, end: i)
            return me
        }

        mutating func array(parent: Int32, last: Int32, ks: Int, ke: Int) -> Int32 {
            let me = node(.array, start: i, ks: ks, ke: ke, parent: parent, last: last)
            depth += 1
            defer { depth -= 1 }
            if depth > 400 { fail("Nesting is too deep"); return me }
            let n = buf.count
            let open = i
            i += 1
            var lastChild: Int32 = -1
            skipWS()
            if i < n, buf[i] == 93 { i += 1; tape.close(me, end: i); return me }
            while !failed {
                skipWS()
                guard i < n else { fail("Unterminated array", at: open); break }
                let child = value(parent: me, last: lastChild, ks: -1, ke: -1)
                if child >= 0 { lastChild = child }
                if failed { break }
                skipWS()
                guard i < n else { fail("Unterminated array", at: open); break }
                if buf[i] == 44 {
                    i += 1
                    skipWS()
                    if i < n, buf[i] == 93 { warn("Trailing commas are not permitted in JSON", at: i - 1); i += 1; break }
                    continue
                }
                if buf[i] == 93 { i += 1; break }
                fail("Expected ',' or ']'")
            }
            tape.close(me, end: i)
            return me
        }
    }
}
