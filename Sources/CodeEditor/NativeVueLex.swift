import Foundation

/// Flat JavaScript / TypeScript token stream for the native Vue service. No tree: the Vue service only needs top level declarations,
/// object literal entries and type literal members, all of which a bracket-matched token array answers cheaply. Transient (never cached).
struct VSTok {
    enum Kind: UInt8 { case ident, str, num, punct, tmpl, regex }
    var kind: Kind
    var s: Int          // absolute UTF-16 offset
    var e: Int
    var text: String    // ident / punct text, string contents (undecoded) for .str
    var nl: Bool        // a line break precedes this token
    func isP(_ p: String) -> Bool { kind == .punct && text == p }
    func isI(_ p: String) -> Bool { kind == .ident && text == p }
}

final class VSTokens {
    var t: [VSTok] = []
    var match: [Int] = []                 // matching bracket index for ( [ { and their closers, else -1
    var docs: [Int: NSRange] = [:]        // token index -> the /** */ comment right before it
    var count: Int { t.count }
    subscript(i: Int) -> VSTok { t[i] }
    func has(_ i: Int) -> Bool { i >= 0 && i < t.count }
}

enum VSLex {
    static let regexKeywords: Set<String> = ["return", "typeof", "instanceof", "in", "of", "new", "delete", "void", "throw", "case", "do", "else", "yield", "await"]

    @inline(__always) static func isIdStart(_ c: unichar) -> Bool { (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c == 36 || c > 127 }
    @inline(__always) static func isIdPart(_ c: unichar) -> Bool { isIdStart(c) || (c >= 48 && c <= 57) }

    static func chars(_ ns: NSString, _ r: NSRange) -> [unichar] {
        var b = [unichar](repeating: 0, count: r.length)
        if r.length > 0 { ns.getCharacters(&b, range: r) }
        return b
    }

    static func run(_ u: [unichar], base: Int = 0) -> VSTokens {
        let out = VSTokens()
        out.t.reserveCapacity(u.count / 5)
        let n = u.count
        var i = 0
        var nl = false
        var pendingDoc: NSRange?
        var tmplStack: [Int] = []
        var braceDepth = 0

        func add(_ k: VSTok.Kind, _ s: Int, _ e: Int, _ text: String) {
            out.t.append(VSTok(kind: k, s: base + s, e: base + e, text: text, nl: nl))
            nl = false
            if let d = pendingDoc { out.docs[out.t.count - 1] = d; pendingDoc = nil }
        }
        func str(_ a: Int, _ b: Int) -> String {
            guard b > a else { return "" }
            return u[a..<b].withUnsafeBufferPointer { String(utf16CodeUnits: $0.baseAddress!, count: b - a) }
        }
        /// Scans a template literal chunk starting at `start` (just after the backtick or the closing brace of `${}`); returns the index after it.
        func template(_ start: Int, from tokStart: Int) -> Int {
            var j = start
            while j < n {
                let c = u[j]
                if c == 92 { j += 2; continue }
                if c == 10 { /* newlines inside templates do not count as statement breaks */ }
                if c == 96 { add(.tmpl, tokStart, j + 1, ""); return j + 1 }
                if c == 36, j + 1 < n, u[j + 1] == 123 {
                    add(.tmpl, tokStart, j + 2, "")
                    tmplStack.append(braceDepth); braceDepth += 1
                    return j + 2
                }
                j += 1
            }
            add(.tmpl, tokStart, n, "")
            return n
        }

        while i < n {
            let c = u[i]
            if c == 10 || c == 13 { nl = true; i += 1; continue }
            if c == 32 || c == 9 || c == 12 || c == 0xFEFF || c == 0xA0 { i += 1; continue }
            if c == 47, i + 1 < n {                                  // comments
                if u[i + 1] == 47 {
                    while i < n, u[i] != 10 { i += 1 }
                    continue
                }
                if u[i + 1] == 42 {
                    let s = i
                    i += 2
                    while i + 1 < n, !(u[i] == 42 && u[i + 1] == 47) { if u[i] == 10 { nl = true }; i += 1 }
                    i = min(n, i + 2)
                    if i - s > 4, u[s + 2] == 42 { pendingDoc = NSRange(location: base + s, length: i - s) }
                    continue
                }
            }
            if VSLex.isIdStart(c) {
                let s = i
                while i < n, VSLex.isIdPart(u[i]) { i += 1 }
                add(.ident, s, i, str(s, i))
                continue
            }
            if (c >= 48 && c <= 57) || (c == 46 && i + 1 < n && u[i + 1] >= 48 && u[i + 1] <= 57) {
                let s = i
                i += 1
                while i < n, VSLex.isIdPart(u[i]) || u[i] == 46 { i += 1 }
                add(.num, s, i, "")
                continue
            }
            if c == 34 || c == 39 {
                let s = i
                i += 1
                while i < n, u[i] != c, u[i] != 10 { if u[i] == 92 { i += 1 }; i += 1 }
                let e = min(i, n)
                add(.str, s, min(e + 1, n), str(s + 1, e))
                i = e + 1
                continue
            }
            if c == 96 { i = template(i + 1, from: i); continue }
            if c == 47 {                                              // regex or division
                var isRegex = true
                if let p = out.t.last {
                    switch p.kind {
                    case .ident: isRegex = regexKeywords.contains(p.text)
                    case .num, .str, .tmpl, .regex: isRegex = false
                    case .punct: isRegex = !(p.text == ")" || p.text == "]" || p.text == "}")
                    }
                }
                if isRegex {
                    var j = i + 1
                    var inClass = false
                    var ok = false
                    while j < n, u[j] != 10 {
                        if u[j] == 92 { j += 2; continue }
                        if u[j] == 91 { inClass = true } else if u[j] == 93 { inClass = false }
                        else if u[j] == 47, !inClass { ok = true; break }
                        j += 1
                    }
                    if ok {
                        j += 1
                        while j < n, VSLex.isIdPart(u[j]) { j += 1 }
                        add(.regex, i, j, "")
                        i = j
                        continue
                    }
                }
            }
            // punctuation
            let s = i
            var text: String
            let c1: unichar = i + 1 < n ? u[i + 1] : 0
            let c2: unichar = i + 2 < n ? u[i + 2] : 0
            if c == 46, c1 == 46, c2 == 46 { text = "..."; i += 3 }
            else if c == 61, c1 == 62 { text = "=>"; i += 2 }
            else if c == 63, c1 == 46, !(c2 >= 48 && c2 <= 57) { text = "?."; i += 2 }
            else if (c == 61 || c == 33), c1 == 61 { if c2 == 61 { text = c == 61 ? "===" : "!=="; i += 3 } else { text = c == 61 ? "==" : "!="; i += 2 } }
            else if c == 38, c1 == 38 { text = "&&"; i += 2 }
            else if c == 124, c1 == 124 { text = "||"; i += 2 }
            else if c == 63, c1 == 63 { text = "??"; i += 2 }
            else if (c == 60 || c == 62), c1 == 61 { text = c == 60 ? "<=" : ">="; i += 2 }
            else { text = String(utf16CodeUnits: [c], count: 1); i += 1 }
            if text == "{" { braceDepth += 1 }
            else if text == "}" {
                braceDepth -= 1
                if let top = tmplStack.last, top == braceDepth {
                    tmplStack.removeLast()
                    i = template(i, from: s)
                    continue
                }
            }
            add(.punct, s, i, text)
        }
        // bracket matching
        var match = [Int](repeating: -1, count: out.t.count)
        var stack: [Int] = []
        for (k, tk) in out.t.enumerated() where tk.kind == .punct {
            switch tk.text {
            case "(", "[", "{": stack.append(k)
            case ")", "]", "}":
                if let o = stack.popLast() { match[o] = k; match[k] = o }
            default: break
            }
        }
        out.match = match
        return out
    }
}
