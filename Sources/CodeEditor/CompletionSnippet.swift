import Foundation

/// LSP snippet syntax: `$1`, `${2:placeholder}`, `${3|a,b|}`, `$0`, variables (expanded to their default / empty), escapes `\$ \} \\`.
struct ParsedSnippet {
    var text: String
    /// Tab stops in visiting order ($1, $2, ... then $0 last); ranges are UTF-16 offsets into `text`.
    var stops: [(index: Int, range: NSRange)]
}

enum SnippetParser {
    static func parse(_ source: String) -> ParsedSnippet {
        var p = Parser(c: Array(source))
        p.run(untilBrace: false)
        var firstByIndex: [Int: NSRange] = [:]
        for s in p.stops where firstByIndex[s.0] == nil { firstByIndex[s.0] = s.1 }
        var ordered = firstByIndex.filter { $0.key != 0 }.sorted { $0.key < $1.key }.map { (index: $0.key, range: $0.value) }
        let end = p.out.utf16.count
        ordered.append((0, firstByIndex[0] ?? NSRange(location: end, length: 0)))
        return ParsedSnippet(text: p.out, stops: ordered)
    }

    private struct Parser {
        var c: [Character]
        var i = 0
        var out = ""
        var stops: [(Int, NSRange)] = []

        mutating func number() -> Int? {
            var s = ""
            while i < c.count, let d = c[i].wholeNumberValue, c[i].isASCII { s.append(c[i]); i += 1; _ = d }
            return s.isEmpty ? nil : Int(s)
        }

        mutating func run(untilBrace: Bool) {
            while i < c.count {
                let ch = c[i]
                if ch == "\\", i + 1 < c.count, "$}\\,|".contains(c[i + 1]) { out.append(c[i + 1]); i += 2; continue }
                if untilBrace, ch == "}" { i += 1; return }
                guard ch == "$" else { out.append(ch); i += 1; continue }
                i += 1
                guard i < c.count else { out.append("$"); return }
                if c[i] == "{" {
                    i += 1
                    if let n = number() {
                        let start = out.utf16.count
                        if i < c.count, c[i] == ":" { i += 1; run(untilBrace: true) }
                        else if i < c.count, c[i] == "|" {
                            i += 1
                            var first = true
                            while i < c.count, c[i] != "|" {
                                if c[i] == "," { first = false } else if first { out.append(c[i]) }
                                i += 1
                            }
                            while i < c.count, c[i] != "}" { i += 1 }
                            i += 1
                        } else { while i < c.count, c[i] != "}" { i += 1 }; i += 1 }
                        stops.append((n, NSRange(location: start, length: out.utf16.count - start)))
                    } else {
                        // variable with optional default
                        while i < c.count, c[i].isLetter || c[i] == "_" { i += 1 }
                        if i < c.count, c[i] == ":" { i += 1; run(untilBrace: true) }
                        else { while i < c.count, c[i] != "}" { i += 1 }; i += 1 }
                    }
                } else if let n = number() {
                    stops.append((n, NSRange(location: out.utf16.count, length: 0)))
                } else if c[i].isLetter || c[i] == "_" {
                    while i < c.count, c[i].isLetter || c[i] == "_" || c[i].isNumber { i += 1 }
                } else { out.append("$") }
            }
        }
    }
}
