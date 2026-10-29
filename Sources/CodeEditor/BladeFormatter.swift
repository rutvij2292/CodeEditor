import Foundation

/// Built-in Blade formatter (no Node, no project plugin). It re-indents HTML and Blade nesting, trims trailing whitespace
/// and collapses blank-line runs. It never reflows text and never touches the inside of <pre>, <textarea> or @verbatim;
/// multi-line constructs (attribute lists, {{ }}, <script>, @php, comments) keep their shape and move as one block.
enum BladeFormatter {
    static func format(_ text: String, useTabs: Bool = false, size: Int = 4, lines: Range<Int>? = nil) -> String {
        var engine = Engine(text)
        engine.scan()
        return engine.render(useTabs: useTabs, size: max(1, size), lines: lines)
    }

    /// Line indices (0-based, on LF text) covered by a UTF-16 selection.
    static func lineRange(for range: NSRange, in text: String) -> Range<Int> {
        let ns = text as NSString
        func line(_ offset: Int) -> Int {
            var n = 0
            var i = 0
            let end = min(offset, ns.length)
            while i < end { if ns.character(at: i) == 10 { n += 1 }; i += 1 }
            return n
        }
        let a = line(range.location)
        let b = line(max(range.location, NSMaxRange(range) - (range.length > 0 && NSMaxRange(range) <= ns.length && ns.character(at: NSMaxRange(range) - 1) == 10 ? 1 : 0)))
        return a..<(max(a, b) + 1)
    }

    // MARK: Tables

    private static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
                                                "source", "track", "wbr", "!doctype"]
    private static let rawTags: Set<String> = ["script", "style", "pre", "textarea"]
    /// Elements whose end tag is commonly omitted: a new one closes the previous sibling.
    private static let impliedEnd: Set<String> = ["li", "dt", "dd", "option", "tr", "td", "th", "thead", "tbody", "tfoot", "p"]
    private static let blockDirectives: Set<String> = [
        "if", "unless", "foreach", "forelse", "for", "while", "switch", "isset", "auth", "guest", "can", "cannot", "canany", "env",
        "production", "error", "component", "slot", "push", "prepend", "pushonce", "prependonce", "once", "section", "hassection",
        "sectionmissing", "session", "fragment", "teleport", "persist", "pushif", "prependif", "script", "assets", "volt", "empty",
    ]
    private static let ifLike: Set<String> = ["if", "unless", "isset", "empty", "auth", "guest", "can", "cannot", "canany", "env",
                                              "production", "hassection", "sectionmissing", "session"]
    private static let elseDirectives: Set<String> = ["else", "elseif", "elsecan", "elsecannot", "elsecanany", "elseauth", "elseguest",
                                                      "elseenv", "case", "default"]
    private static let sectionEnders: Set<String> = ["show", "stop", "append", "overwrite"]

    // MARK: Engine

    private struct Engine {
        enum Kind { case normal, tagAttr, shift, verbatim }
        struct Entry { var name: String; var blade: Bool }

        let b: [UInt8]
        let n: Int
        var starts: [Int] = [0]
        var kind: [Kind]
        var anchor: [Int]
        var depth: [Int?]
        var leading: [Bool]
        var stack: [Entry] = []

        init(_ text: String) {
            b = Array(text.utf8)
            n = b.count
            for (i, c) in b.enumerated() where c == 10 { starts.append(i + 1) }
            kind = Array(repeating: .normal, count: starts.count)
            anchor = Array(repeating: 0, count: starts.count)
            depth = Array(repeating: nil, count: starts.count)
            leading = Array(repeating: true, count: starts.count)
        }

        // MARK: helpers

        func lineAt(_ pos: Int) -> Int {
            var lo = 0, hi = starts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if starts[mid] <= pos { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }

        func has(_ i: Int, _ s: [UInt8]) -> Bool {
            guard i >= 0, i + s.count <= n else { return false }
            for k in 0..<s.count where b[i + k] != s[k] { return false }
            return true
        }

        /// Index just past the next occurrence of `s` at or after `from` (n when missing).
        func skip(past s: [UInt8], from: Int) -> Int {
            var i = from
            while i + s.count <= n { if has(i, s) { return i + s.count }; i += 1 }
            return n
        }

        static func isWord(_ c: UInt8) -> Bool { (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 }
        static func isLetter(_ c: UInt8) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }
        static func isNameChar(_ c: UInt8) -> Bool { isWord(c) || c == 45 || c == 58 || c == 46 }

        /// Index past the matching `)` for the `(` at `i` (string literals respected); nil when unbalanced.
        func skipParens(at i: Int) -> Int? {
            var depth = 0
            var j = i
            while j < n {
                let c = b[j]
                if c == 39 || c == 34 {
                    j += 1
                    while j < n, b[j] != c { if b[j] == 92 { j += 1 }; j += 1 }
                } else if c == 40 { depth += 1 } else if c == 41 { depth -= 1; if depth == 0 { return j + 1 } }
                j += 1
            }
            return nil
        }

        func hasTopLevelComma(_ from: Int, _ to: Int) -> Bool {
            var depth = 0
            var j = from + 1
            while j < to - 1 {
                let c = b[j]
                if c == 39 || c == 34 {
                    j += 1
                    while j < to - 1, b[j] != c { if b[j] == 92 { j += 1 }; j += 1 }
                } else if c == 40 || c == 91 || c == 123 { depth += 1 } else if c == 41 || c == 93 || c == 125 { depth -= 1 } else if c == 44, depth == 0 { return true }
                j += 1
            }
            return false
        }

        mutating func touch(_ pos: Int) {
            let l = lineAt(pos)
            if leading[l] { depth[l] = stack.count; leading[l] = false }
        }

        mutating func mark(_ from: Int, _ to: Int, _ k: Kind, anchor a: Int) {
            guard from <= to, from < kind.count else { return }
            for l in from...min(to, kind.count - 1) where kind[l] == .normal {
                kind[l] = k; anchor[l] = a; leading[l] = false
            }
        }

        /// Marks the lines after `start` up to the one holding `end` as one block hanging off line `a`.
        mutating func span(_ start: Int, _ end: Int, kind k: Kind = .shift) {
            let a = lineAt(start)
            let e = lineAt(max(start, end - 1))
            if e > a { mark(a + 1, e, k, anchor: a) }
        }

        func onlyBlank(from: Int, to: Int) -> Bool {
            var i = from
            while i < to { if b[i] != 32 && b[i] != 9 && b[i] != 13 { return false }; i += 1 }
            return true
        }

        /// Raw content that ends at `end` (where the terminator begins), hanging off line `a`.
        mutating func raw(anchorLine a: Int, end: Int, kind k: Kind, closerLineIsNormal: Bool) {
            let e = lineAt(min(end, max(0, n - 1)))
            var last = e
            if end < n, closerLineIsNormal, onlyBlank(from: starts[e], to: end) { last = e - 1 }
            if last > a { mark(a + 1, last, k, anchor: a) }
        }

        // MARK: stack

        mutating func closeHTML(_ name: String, at pos: Int) {
            var idx = stack.count - 1
            while idx >= 0, !stack[idx].blade, stack[idx].name != name { idx -= 1 }
            guard idx >= 0, !stack[idx].blade else { touch(pos); return }
            stack.removeSubrange(idx...)
            let l = lineAt(pos)
            if leading[l] { depth[l] = stack.count }
        }

        mutating func closeBlade(_ name: String, at pos: Int) {
            guard let idx = stack.lastIndex(where: { $0.blade && $0.name == name }) else { touch(pos); return }
            stack.removeSubrange(idx...)
            let l = lineAt(pos)
            if leading[l] { depth[l] = stack.count }
        }

        mutating func elseBlade(_ targets: Set<String>, at pos: Int) {
            guard let idx = stack.lastIndex(where: { $0.blade && targets.contains($0.name) }) else { touch(pos); return }
            stack.removeSubrange((idx + 1)...)
            let l = lineAt(pos)
            if leading[l] { depth[l] = idx; leading[l] = false }
        }

        // MARK: tag scanning

        /// Scans an opening tag starting at `<`. Returns the index past `>` and whether it ended in `/>`.
        /// Newlines inside quoted values, {{ }} and directive arguments are reported so those lines move as a block.
        func scanTag(_ start: Int, nameEnd: Int, blockNewlines: inout [Int]) -> (end: Int, selfClosing: Bool) {
            var i = nameEnd
            var lastSignificant: UInt8 = 0
            func skipInside(_ from: Int, _ to: Int) {
                var k = from
                while k < to { if b[k] == 10 { blockNewlines.append(k) }; k += 1 }
            }
            while i < n {
                let c = b[i]
                if c == 62 { return (i + 1, lastSignificant == 47) }
                if c == 34 || c == 39 {
                    var j = i + 1
                    while j < n, b[j] != c {
                        if has(j, BladeFormatter.mustacheOpen) || has(j, BladeFormatter.rawOpen) {
                            let close = has(j, BladeFormatter.rawOpen) ? BladeFormatter.rawClose : BladeFormatter.mustacheClose
                            j = skip(past: close, from: j + 2)
                            continue
                        }
                        j += 1
                    }
                    skipInside(i, min(j, n))
                    i = min(j + 1, n); lastSignificant = c; continue
                }
                if has(i, BladeFormatter.bladeComment) { let e = skip(past: BladeFormatter.bladeCommentClose, from: i + 4); skipInside(i, e); i = e; lastSignificant = 0; continue }
                if has(i, BladeFormatter.rawOpen) { let e = skip(past: BladeFormatter.rawClose, from: i + 3); skipInside(i, e); i = e; lastSignificant = 0; continue }
                if has(i, BladeFormatter.mustacheOpen) { let e = skip(past: BladeFormatter.mustacheClose, from: i + 2); skipInside(i, e); i = e; lastSignificant = 0; continue }
                if has(i, BladeFormatter.phpOpen) { let e = skip(past: BladeFormatter.phpClose, from: i + 2); skipInside(i, e); i = e; lastSignificant = 0; continue }
                if c == 64 {
                    var j = i + 1
                    if j < n, b[j] == 64 { i = j + 1; lastSignificant = 0; continue }
                    while j < n, Engine.isWord(b[j]) { j += 1 }
                    var k = j
                    while k < n, b[k] == 32 || b[k] == 9 { k += 1 }
                    if j > i + 1, k < n, b[k] == 40, let e = skipParens(at: k) { skipInside(i, e); i = e } else { i = max(j, i + 1) }
                    lastSignificant = 0; continue
                }
                if c != 32 && c != 9 && c != 10 && c != 13 { lastSignificant = c }
                i += 1
            }
            return (n, false)
        }

        // MARK: scan

        mutating func scan() {
            var i = 0
            while i < n {
                let c = b[i]
                switch c {
                case 10, 13, 32, 9:
                    i += 1
                case 123: // {
                    if has(i, BladeFormatter.bladeComment) {
                        touch(i); let e = skip(past: BladeFormatter.bladeCommentClose, from: i + 4); span(i, e); i = e
                    } else if has(i, BladeFormatter.rawOpen) {
                        touch(i); let e = skip(past: BladeFormatter.rawClose, from: i + 3); span(i, e); i = e
                    } else if has(i, BladeFormatter.mustacheOpen) {
                        touch(i); let e = skip(past: BladeFormatter.mustacheClose, from: i + 2); span(i, e); i = e
                    } else { touch(i); i += 1 }
                case 60: // <
                    i = scanAngle(i)
                case 64: // @
                    i = scanDirective(i)
                default:
                    touch(i); i += 1
                }
            }
        }

        mutating func scanAngle(_ i: Int) -> Int {
            if has(i, BladeFormatter.htmlComment) {
                touch(i); let e = skip(past: BladeFormatter.htmlCommentClose, from: i + 4); span(i, e); return e
            }
            if has(i, BladeFormatter.phpOpen) {
                touch(i); let e = skip(past: BladeFormatter.phpClose, from: i + 2); span(i, e); return e
            }
            guard i + 1 < n else { touch(i); return i + 1 }
            let next = b[i + 1]
            let closing = next == 47
            let nameStart = closing ? i + 2 : i + 1
            guard nameStart < n, Engine.isLetter(b[nameStart]) || (!closing && b[nameStart] == 33 && has(i, BladeFormatter.doctype)) else { touch(i); return i + 1 }
            var j = nameStart + (b[nameStart] == 33 ? 1 : 0)
            while j < n, Engine.isNameChar(b[j]) { j += 1 }
            var name = String(decoding: b[nameStart..<j], as: UTF8.self).lowercased()
            if name.hasPrefix("x-slot:") { name = "x-slot" }
            if closing {
                var e = j
                while e < n, b[e] != 62 { e += 1 }
                let end = min(e + 1, n)
                closeHTML(name, at: i)
                span(i, end)
                return end
            }
            var blockNL: [Int] = []
            let (end, selfClosing) = scanTag(i, nameEnd: j, blockNewlines: &blockNL)
            if !selfClosing, BladeFormatter.impliedEnd.contains(name), let top = stack.last, !top.blade, top.name == name { stack.removeLast() }
            touch(i)
            let a = lineAt(i), e = lineAt(max(i, end - 1))
            if e > a {
                for nl in blockNL { let l = lineAt(nl) + 1; if l > a, l <= e { mark(l, l, .shift, anchor: a) } }
                mark(a + 1, e, .tagAttr, anchor: a)
            }
            if selfClosing || BladeFormatter.voidTags.contains(name) { return end }
            stack.append(Entry(name: name, blade: false))
            if BladeFormatter.rawTags.contains(name) {
                let closer = Array("</\(name)".utf8)
                var k = end
                var found = n
                while k + closer.count <= n {
                    if b[k] == 60, matchesInsensitive(k, closer) { found = k; break }
                    k += 1
                }
                raw(anchorLine: e, end: found, kind: name == "pre" || name == "textarea" ? .verbatim : .shift,
                    closerLineIsNormal: name != "pre" && name != "textarea")
                return found
            }
            return end
        }

        func matchesInsensitive(_ i: Int, _ s: [UInt8]) -> Bool {
            guard i + s.count < n else { return false }
            for k in 0..<s.count {
                var c = b[i + k]
                if c >= 65 && c <= 90 { c += 32 }
                if c != s[k] { return false }
            }
            let t = b[i + s.count]
            return t == 62 || t == 32 || t == 9 || t == 10 || t == 13 || t == 47
        }

        mutating func scanDirective(_ i: Int) -> Int {
            guard i + 1 < n else { touch(i); return i + 1 }
            if b[i + 1] == 64 { touch(i); return i + 2 }
            guard Engine.isLetter(b[i + 1]), i == 0 || !Engine.isWord(b[i - 1]) else { touch(i); return i + 1 }
            var j = i + 1
            while j < n, Engine.isWord(b[j]) { j += 1 }
            let name = String(decoding: b[(i + 1)..<j], as: UTF8.self).lowercased()
            var k = j
            while k < n, b[k] == 32 || b[k] == 9 { k += 1 }
            var argsEnd: Int?
            if k < n, b[k] == 40 { argsEnd = skipParens(at: k) }
            let end = argsEnd ?? j
            let L = BladeFormatter.self

            if name == "verbatim" && argsEnd == nil {
                touch(i)
                let close = Array("@endverbatim".utf8)
                var p = end
                while p < n, !has(p, close) { p += 1 }
                raw(anchorLine: lineAt(i), end: p, kind: .verbatim, closerLineIsNormal: true)
                return p
            }
            if name == "php" && argsEnd == nil {
                touch(i)
                let close = Array("@endphp".utf8)
                var p = end
                while p < n, !has(p, close) { p += 1 }
                raw(anchorLine: lineAt(i), end: p, kind: .shift, closerLineIsNormal: true)
                return p
            }
            if L.elseDirectives.contains(name) {
                elseBlade(name == "case" || name == "default" ? ["switch"] : L.ifLike, at: i)
                if let e = argsEnd { span(i, e) }
                return end
            }
            if name == "empty" && argsEnd == nil {
                elseBlade(["forelse"], at: i)
                return end
            }
            if L.sectionEnders.contains(name) { closeBlade("section", at: i); return end }
            if name.hasPrefix("end"), L.blockDirectives.contains(String(name.dropFirst(3))) {
                closeBlade(String(name.dropFirst(3)), at: i)
                return end
            }
            if L.blockDirectives.contains(name) {
                if name == "section", let e = argsEnd, hasTopLevelComma(k, e) { touch(i); span(i, e); return end }
                if name == "empty" && argsEnd == nil { touch(i); return end }
                touch(i)
                if let e = argsEnd { span(i, e) }
                stack.append(Entry(name: name, blade: true))
                return end
            }
            touch(i)
            if let e = argsEnd { span(i, e) }
            return end
        }

        // MARK: render

        func width(of line: Substring, tab: Int) -> Int {
            var w = 0
            for c in line.utf8 { if c == 32 { w += 1 } else if c == 9 { w += tab } else { break } }
            return w
        }

        func render(useTabs: Bool, size: Int, lines range: Range<Int>?) -> String {
            let src = String(decoding: b, as: UTF8.self)
            let rows = src.split(separator: "\n", omittingEmptySubsequences: false)
            guard rows.count == starts.count else { return src }
            let unit = size
            func indent(_ w: Int) -> String {
                useTabs ? String(repeating: "\t", count: w / unit) + String(repeating: " ", count: w % unit) : String(repeating: " ", count: w)
            }
            var newW = Array(repeating: 0, count: rows.count)
            var out: [String] = []
            var prevBlank = false
            for l in 0..<rows.count {
                let line = rows[l]
                let origW = width(of: line, tab: unit)
                let inRange = range?.contains(l) ?? true
                if !inRange { newW[l] = origW; out.append(String(line)); prevBlank = false; continue }
                if kind[l] == .verbatim { newW[l] = origW; out.append(String(line)); prevBlank = false; continue }
                var body = line.drop { $0 == " " || $0 == "\t" }
                while let last = body.last, last == " " || last == "\t" || last == "\r" { body = body.dropLast() }
                if body.isEmpty {
                    newW[l] = 0
                    if range == nil, kind[l] == .normal {
                        if prevBlank { continue }
                        prevBlank = true
                    } else { prevBlank = false }
                    out.append("")
                    continue
                }
                prevBlank = false
                var w: Int
                switch kind[l] {
                case .tagAttr:
                    let base = newW[anchor[l]]
                    w = body.hasPrefix(">") || body.hasPrefix("/>") ? base : base + unit
                case .shift:
                    w = max(0, origW + newW[anchor[l]] - width(of: rows[anchor[l]], tab: unit))
                default:
                    w = (depth[l] ?? 0) * unit
                }
                newW[l] = w
                out.append(indent(w) + body)
            }
            if range == nil {
                while out.last == "" { out.removeLast() }
                return out.isEmpty ? "" : out.joined(separator: "\n") + "\n"
            }
            return out.joined(separator: "\n")
        }
    }

    private static let mustacheOpen = Array("{{".utf8), mustacheClose = Array("}}".utf8)
    private static let rawOpen = Array("{!!".utf8), rawClose = Array("!!}".utf8)
    private static let bladeComment = Array("{{--".utf8), bladeCommentClose = Array("--}}".utf8)
    private static let htmlComment = Array("<!--".utf8), htmlCommentClose = Array("-->".utf8)
    private static let phpOpen = Array("<?".utf8), phpClose = Array("?>".utf8)
    private static let doctype = Array("<!".utf8)
}
