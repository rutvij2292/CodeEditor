import Foundation

/// Minimal PHP tokenizer used by the Laravel route/config/lang parsers. Not a real parser: it only needs
/// strings, identifiers, punctuation and bracket matching, with comments skipped.
struct PHPTok {
    enum Kind: UInt8 { case ident, string, variable, number, punct }
    static let dcolon: UInt16 = 1   // ::
    static let arrow: UInt16 = 2    // -> or ?->
    static let fat: UInt16 = 3      // =>

    var kind: Kind
    var loc: Int        // UTF-16 offset
    var len: Int
    var line: Int       // 1-based
    var col: Int        // 1-based
    var ch: UInt16 = 0  // punct code
}

final class PHPLex {
    let ns: NSString
    private(set) var toks: [PHPTok] = []
    /// Index of the matching bracket for every ( [ { ) ] } token, else -1.
    private(set) var match: [Int] = []

    init(_ text: NSString) {
        ns = text
        lex()
        pair()
    }

    var count: Int { toks.count }

    func text(_ i: Int) -> String { ns.substring(with: NSRange(location: toks[i].loc, length: toks[i].len)) }

    func isPunct(_ i: Int, _ c: Character) -> Bool {
        i >= 0 && i < toks.count && toks[i].kind == .punct && toks[i].ch == c.utf16.first!
    }
    func isPunct(_ i: Int, code: UInt16) -> Bool { i >= 0 && i < toks.count && toks[i].kind == .punct && toks[i].ch == code }
    func isIdent(_ i: Int, _ s: String) -> Bool { i >= 0 && i < toks.count && toks[i].kind == .ident && text(i) == s }

    /// Value of a string token (quotes removed, `\\` and `\'` unescaped).
    func strValue(_ i: Int) -> String {
        let t = toks[i]
        guard t.len >= 2 else { return "" }
        let raw = ns.substring(with: NSRange(location: t.loc + 1, length: t.len - 2))
        guard raw.contains("\\") else { return raw }
        return raw.replacingOccurrences(of: "\\\\", with: "\\").replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "\\\"", with: "\"")
    }

    private func lex() {
        let n = ns.length
        var u = [UInt16](repeating: 0, count: n)
        if n > 0 { ns.getCharacters(&u, range: NSRange(location: 0, length: n)) }
        var i = 0, line = 1, lineStart = 0
        toks.reserveCapacity(n / 5)
        @inline(__always) func isWord(_ c: UInt16) -> Bool {
            (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c >= 0x80
        }
        @inline(__always) func isStart(_ c: UInt16) -> Bool {
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 92 || c >= 0x80
        }
        func at(_ k: Int) -> UInt16 { k < n ? u[k] : 0 }
        while i < n {
            let c = u[i]
            if c == 10 { line += 1; i += 1; lineStart = i; continue }
            if c == 32 || c == 9 || c == 13 { i += 1; continue }
            if (c == 47 && at(i + 1) == 47) || (c == 35 && at(i + 1) != 91) {   // // and # (not #[)
                while i < n, u[i] != 10 { i += 1 }
                continue
            }
            if c == 47 && at(i + 1) == 42 {   // /* */
                i += 2
                while i < n, !(u[i] == 42 && at(i + 1) == 47) {
                    if u[i] == 10 { line += 1; lineStart = i + 1 }
                    i += 1
                }
                i = min(n, i + 2)
                continue
            }
            let start = i, startLine = line, startCol = i - lineStart + 1
            if c == 39 || c == 34 {   // string
                i += 1
                while i < n, u[i] != c {
                    if u[i] == 92 { i += 1 }
                    if i < n, u[i] == 10 { line += 1; lineStart = i + 1 }
                    i += 1
                }
                i = min(n, i + 1)
                toks.append(PHPTok(kind: .string, loc: start, len: i - start, line: startLine, col: startCol))
                continue
            }
            if c == 60 && at(i + 1) == 60 && at(i + 2) == 60 {   // heredoc / nowdoc
                var j = i + 3
                while j < n, u[j] == 32 || u[j] == 39 || u[j] == 34 { j += 1 }
                let idStart = j
                while j < n, isWord(u[j]) { j += 1 }
                let ident = ns.substring(with: NSRange(location: idStart, length: j - idStart))
                if !ident.isEmpty {
                    var k = j
                    while k < n, u[k] != 10 { k += 1 }
                    k += 1
                    var endAt = n
                    while k < n {
                        var e = k
                        while e < n, u[e] != 10 { e += 1 }
                        let rawLine = ns.substring(with: NSRange(location: k, length: e - k))
                        let lineText = rawLine.trimmingCharacters(in: .whitespaces)
                        if lineText.hasPrefix(ident) {
                            // The token ends right after the closing identifier, so the `;` / `)` that follows stays a token of its own.
                            let lead = rawLine.utf16.count - rawLine.drop(while: { $0 == " " || $0 == "\t" }).utf16.count
                            endAt = min(e, k + lead + ident.utf16.count)
                            break
                        }
                        k = e + 1
                    }
                    for q in start..<endAt where u[q] == 10 { line += 1; lineStart = q + 1 }
                    i = endAt
                    toks.append(PHPTok(kind: .string, loc: start, len: max(2, i - start), line: startLine, col: startCol))
                    continue
                }
            }
            if c == 36 {   // $var
                i += 1
                while i < n, isWord(u[i]) { i += 1 }
                toks.append(PHPTok(kind: .variable, loc: start, len: i - start, line: startLine, col: startCol))
                continue
            }
            if c >= 48 && c <= 57 {
                while i < n, isWord(u[i]) || u[i] == 46 { i += 1 }
                toks.append(PHPTok(kind: .number, loc: start, len: i - start, line: startLine, col: startCol))
                continue
            }
            if isStart(c) {
                while i < n, isWord(u[i]) || u[i] == 92 { i += 1 }
                toks.append(PHPTok(kind: .ident, loc: start, len: i - start, line: startLine, col: startCol))
                continue
            }
            var code = c, len = 1
            if c == 58 && at(i + 1) == 58 { code = PHPTok.dcolon; len = 2 }
            else if c == 45 && at(i + 1) == 62 { code = PHPTok.arrow; len = 2 }
            else if c == 63 && at(i + 1) == 45 && at(i + 2) == 62 { code = PHPTok.arrow; len = 3 }
            else if c == 61 && at(i + 1) == 62 { code = PHPTok.fat; len = 2 }
            i += len
            toks.append(PHPTok(kind: .punct, loc: start, len: len, line: startLine, col: startCol, ch: code))
        }
    }

    private func pair() {
        match = [Int](repeating: -1, count: toks.count)
        var stack: [Int] = []
        for (i, t) in toks.enumerated() where t.kind == .punct {
            switch t.ch {
            case 40, 91, 123: stack.append(i)
            case 41, 93, 125:
                if let o = stack.popLast() { match[o] = i; match[i] = o }
            default: break
            }
        }
    }
}

enum PHPArrayKeys {
    struct Loc { let line: Int; let col: Int }

    /// Dotted key path -> location of the key string, for the first `return [ ... ]` / `return array(...)` of a config/lang file.
    static func parse(_ lex: PHPLex) -> [String: Loc] {
        var out: [String: Loc] = [:]
        var open = -1
        for i in 0..<lex.count where lex.isIdent(i, "return") {
            if lex.isPunct(i + 1, "[") { open = i + 1; break }
            if lex.isIdent(i + 1, "array"), lex.isPunct(i + 2, "(") { open = i + 2; break }
        }
        guard open >= 0 else { return out }

        func walk(_ open: Int, _ prefix: String) {
            let end = lex.match[open]
            guard end > open else { return }
            var i = open + 1
            var idx = 0
            while i < end {
                var key: String?
                var keyLoc: Loc?
                if (lex.toks[i].kind == .string || lex.toks[i].kind == .number), lex.isPunct(i + 1, code: PHPTok.fat) {
                    key = lex.toks[i].kind == .string ? lex.strValue(i) : lex.text(i)
                    keyLoc = Loc(line: lex.toks[i].line, col: lex.toks[i].col + (lex.toks[i].kind == .string ? 1 : 0))
                    if lex.toks[i].kind == .number, let n = Int(lex.text(i)) { idx = n + 1 }
                    i += 2
                } else {
                    key = String(idx); idx += 1
                }
                let full = prefix.isEmpty ? key! : prefix + "." + key!
                if let keyLoc, out[full] == nil { out[full] = keyLoc }
                if i < end {
                    if lex.isPunct(i, "["), lex.match[i] > i {
                        walk(i, full)
                        i = lex.match[i] + 1
                    } else if lex.isIdent(i, "array"), lex.isPunct(i + 1, "("), lex.match[i + 1] > i {
                        walk(i + 1, full)
                        i = lex.match[i + 1] + 1
                    }
                }
                while i < end, !lex.isPunct(i, ",") {
                    if lex.toks[i].kind == .punct, [40, 91, 123].contains(lex.toks[i].ch), lex.match[i] > i { i = lex.match[i] + 1 } else { i += 1 }
                }
                i += 1
            }
        }
        walk(open, "")
        return out
    }
}
