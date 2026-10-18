import Foundation

/// Block structure of a Markdown document (CommonMark/GFM subset: ATX/setext headings, fenced code, block quotes, nested
/// lists with task items, pipe tables, rules, HTML blocks, paragraphs). Inline syntax is left as text for the renderer.
/// Every block carries its 0-based source line so the preview can follow the editor's scroll position.
indirect enum MDBlock: Equatable {
    case heading(level: Int, text: String, line: Int)
    case paragraph(text: String, line: Int)
    case code(lang: String, text: String, line: Int)
    case quote(blocks: [MDBlock], line: Int)
    case list(ordered: Bool, start: Int, items: [MDItem], line: Int)
    case table(header: [String], align: [Int], rows: [[String]], line: Int)   // align: 0 left, 1 center, 2 right
    case rule(line: Int)
    case html(text: String, line: Int)

    var line: Int {
        switch self {
        case .heading(_, _, let l), .paragraph(_, let l), .code(_, _, let l), .quote(_, let l), .list(_, _, _, let l),
             .table(_, _, _, let l), .rule(let l), .html(_, let l): return l
        }
    }
}

struct MDItem: Equatable {
    var blocks: [MDBlock]
    var task: Bool?          // nil: not a task item; false: unchecked; true: checked
    var line: Int
}

enum MarkdownParser {
    private struct L { var s: Substring; var no: Int }

    static func parse(_ text: String) -> [MDBlock] {
        var lines: [L] = []
        var n = 0
        for part in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var s = part
            if s.last == "\r" { s = s.dropLast() }
            lines.append(L(s: s, no: n)); n += 1
        }
        // YAML front matter is not Markdown: skip it (the editor still shows it).
        if lines.first?.s == "---", let close = lines.dropFirst().firstIndex(where: { $0.s == "---" || $0.s == "..." }), close > 0 {
            lines = Array(lines[(close + 1)...])
        }
        return blocks(lines, depth: 0)
    }

    // MARK: Line classification

    private static func indentOf(_ s: Substring) -> Int {
        var n = 0
        for c in s { if c == " " { n += 1 } else if c == "\t" { n += 4 - n % 4 } else { break } }
        return n
    }

    private static func isBlank(_ s: Substring) -> Bool { s.allSatisfy { $0 == " " || $0 == "\t" } }

    private static func stripIndent(_ s: Substring, _ n: Int) -> Substring {
        var cols = 0
        var idx = s.startIndex
        while idx < s.endIndex, cols < n {
            if s[idx] == " " { cols += 1 } else if s[idx] == "\t" { cols += 4 - cols % 4 } else { break }
            idx = s.index(after: idx)
        }
        return s[idx...]
    }

    private static func trimmed(_ s: Substring) -> Substring {
        var a = s.startIndex, b = s.endIndex
        while a < b, s[a] == " " || s[a] == "\t" { a = s.index(after: a) }
        while b > a, s[s.index(before: b)] == " " || s[s.index(before: b)] == "\t" { b = s.index(before: b) }
        return s[a..<b]
    }

    private static func fence(_ s: Substring) -> (char: Character, len: Int, info: String)? {
        guard indentOf(s) < 4 else { return nil }
        let t = trimmed(s)
        guard let c = t.first, c == "`" || c == "~" else { return nil }
        let run = t.prefix { $0 == c }.count
        guard run >= 3 else { return nil }
        let info = String(t.dropFirst(run)).trimmingCharacters(in: .whitespaces)
        if c == "`", info.contains("`") { return nil }
        return (c, run, info)
    }

    private static func atx(_ s: Substring) -> (Int, String)? {
        guard indentOf(s) < 4 else { return nil }
        let t = trimmed(s)
        let hashes = t.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = t.dropFirst(hashes)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var text = String(trimmed(rest))
        // closing sequence of #s
        if let r = text.range(of: #"\s+#+\s*$"#, options: .regularExpression) { text.removeSubrange(r) }
        else if text.allSatisfy({ $0 == "#" }) { text = "" }
        return (hashes, text)
    }

    private static func isRule(_ s: Substring) -> Bool {
        guard indentOf(s) < 4 else { return false }
        let t = s.filter { $0 != " " && $0 != "\t" }
        guard t.count >= 3, let c = t.first, c == "-" || c == "*" || c == "_" else { return false }
        return t.allSatisfy { $0 == c }
    }

    private static func setext(_ s: Substring) -> Int? {
        guard indentOf(s) < 4 else { return nil }
        let t = trimmed(s)
        guard let c = t.first, c == "=" || c == "-", t.allSatisfy({ $0 == c }) else { return nil }
        return c == "=" ? 1 : 2
    }

    private struct Marker { var ordered: Bool; var number: Int; var char: Character; var indent: Int; var content: Int; var offset: Int }

    private static func marker(_ s: Substring) -> Marker? {
        let ind = indentOf(s)
        guard ind < 4 else { return nil }
        let t = stripIndent(s, ind)
        guard let f = t.first else { return nil }
        var width = 0, ordered = false, number = 0
        var ch: Character = f
        if f == "-" || f == "+" || f == "*" {
            width = 1
        } else if f.isASCII, f.isNumber {
            let digits = t.prefix { $0.isASCII && $0.isNumber }
            guard digits.count <= 9 else { return nil }
            let after = t.dropFirst(digits.count)
            guard let d = after.first, d == "." || d == ")" else { return nil }
            width = digits.count + 1; ordered = true; number = Int(digits) ?? 1; ch = d
        } else { return nil }
        let rest = t.dropFirst(width)
        if !rest.isEmpty, rest.first != " ", rest.first != "\t" { return nil }
        let spaces = rest.prefix { $0 == " " }.count
        if isRule(s), !ordered { return nil }
        // 5+ spaces after the marker: content is an indented code block, marker content starts 1 space after
        let pad = spaces == 0 || spaces > 4 ? 1 : spaces
        let lead = s.prefix { $0 == " " || $0 == "\t" }.count
        return Marker(ordered: ordered, number: number, char: ch, indent: ind, content: ind + width + (rest.isEmpty ? 1 : pad), offset: lead + width + (rest.isEmpty ? 0 : pad))
    }

    private static func isDelimiterRow(_ s: Substring) -> [Int]? {
        let t = trimmed(s)
        guard t.contains("-"), t.allSatisfy({ "|-: \t".contains($0) }) else { return nil }
        var cells = splitRow(t)
        if cells.isEmpty { return nil }
        var aligns: [Int] = []
        for i in cells.indices {
            let c = cells[i].trimmingCharacters(in: .whitespaces)
            guard c.count >= 1, c.contains("-"), c.allSatisfy({ $0 == "-" || $0 == ":" }) else { return nil }
            aligns.append(c.hasPrefix(":") && c.hasSuffix(":") ? 1 : (c.hasSuffix(":") ? 2 : 0))
        }
        cells.removeAll()
        return aligns
    }

    /// Splits a pipe row into cells honouring `\|` escapes and code spans.
    static func splitRow<S: StringProtocol>(_ row: S) -> [String] {
        var cells: [String] = []
        var cur = ""
        var inCode = false
        var prevBackslash = false
        for ch in row {
            if ch == "`" && !prevBackslash { inCode.toggle() }
            if ch == "|" && !inCode && !prevBackslash { cells.append(cur); cur = ""; prevBackslash = false; continue }
            if prevBackslash && ch == "|" { cur.removeLast() }   // drop the escaping backslash
            cur.append(ch)
            prevBackslash = ch == "\\" && !prevBackslash
        }
        cells.append(cur)
        var t = cells.map { $0.trimmingCharacters(in: .whitespaces) }
        if row.trimmingCharacters(in: .whitespaces).hasPrefix("|"), !t.isEmpty { t.removeFirst() }
        if row.trimmingCharacters(in: .whitespaces).hasSuffix("|"), !t.isEmpty, !row.hasSuffix("\\|") { t.removeLast() }
        return t
    }

    private static func startsHTML(_ s: Substring) -> Bool {
        guard indentOf(s) < 4 else { return false }
        let t = trimmed(s)
        guard t.first == "<", t.count > 1 else { return false }
        let n = t[t.index(after: t.startIndex)]
        return n.isLetter || n == "/" || n == "!"
    }

    /// Lines that end a paragraph without a blank line.
    private static func interrupts(_ s: Substring) -> Bool {
        if isBlank(s) || atx(s) != nil || fence(s) != nil || isRule(s) { return true }
        if indentOf(s) < 4, trimmed(s).hasPrefix(">") { return true }
        if let m = marker(s), !isBlank(stripIndent(s, m.content)), !m.ordered || m.number == 1 { return true }
        return false
    }

    // MARK: Blocks

    private static func blocks(_ lines: [L], depth: Int) -> [MDBlock] {
        var out: [MDBlock] = []
        var i = 0
        let n = lines.count
        while i < n {
            let l = lines[i]
            if isBlank(l.s) { i += 1; continue }
            if depth > 12 { out.append(.paragraph(text: String(trimmed(l.s)), line: l.no)); i += 1; continue }

            if let f = fence(l.s) {
                let ind = indentOf(l.s)
                var body: [String] = []
                var j = i + 1
                while j < n {
                    let t = lines[j].s
                    if let c = fence(t), c.char == f.char, c.len >= f.len, c.info.isEmpty { break }
                    body.append(String(stripIndent(t, ind)))
                    j += 1
                }
                out.append(.code(lang: String(f.info.split(separator: " ").first ?? ""), text: body.joined(separator: "\n"), line: l.no))
                i = min(n, j + 1)
                continue
            }
            if let (level, text) = atx(l.s) { out.append(.heading(level: level, text: text, line: l.no)); i += 1; continue }
            if isRule(l.s) { out.append(.rule(line: l.no)); i += 1; continue }
            if indentOf(l.s) >= 4 {      // indented code block
                var body: [String] = []
                var j = i
                while j < n, isBlank(lines[j].s) || indentOf(lines[j].s) >= 4 { body.append(String(stripIndent(lines[j].s, 4))); j += 1 }
                while body.last.map({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) == true { body.removeLast() }
                out.append(.code(lang: "", text: body.joined(separator: "\n"), line: l.no))
                i = j
                continue
            }
            if trimmed(l.s).hasPrefix(">") {
                var inner: [L] = []
                var j = i
                while j < n {
                    let t = lines[j].s
                    if indentOf(t) < 4, trimmed(t).hasPrefix(">") {
                        var u = trimmed(t).dropFirst()
                        if u.first == " " { u = u.dropFirst() }
                        inner.append(L(s: u, no: lines[j].no))
                    } else if !isBlank(t), !inner.isEmpty, !isBlank(inner.last!.s), !interrupts(t) {
                        inner.append(L(s: trimmed(t), no: lines[j].no))     // lazy continuation
                    } else { break }
                    j += 1
                }
                out.append(.quote(blocks: blocks(inner, depth: depth + 1), line: l.no))
                i = j
                continue
            }
            if let m = marker(l.s) {
                var items: [MDItem] = []
                var j = i
                var cur = m
                while j < n, let mk = marker(lines[j].s), mk.ordered == m.ordered, mk.char == m.char, mk.indent < cur.content {
                    cur = mk
                    let first = lines[j]
                    var inner: [L] = [L(s: first.s.dropFirst(mk.offset), no: first.no)]
                    var k = j + 1
                    var sawBlank = false
                    while k < n {
                        let t = lines[k].s
                        if isBlank(t) { inner.append(L(s: "", no: lines[k].no)); sawBlank = true; k += 1; continue }
                        if indentOf(t) >= mk.content { inner.append(L(s: stripIndent(t, mk.content), no: lines[k].no)); sawBlank = false; k += 1; continue }
                        if !sawBlank, !interrupts(t), marker(t) == nil { inner.append(L(s: trimmed(t), no: lines[k].no)); k += 1; continue }  // lazy
                        break
                    }
                    while inner.last.map({ isBlank($0.s) }) == true { inner.removeLast() }
                    // a blank run followed by another sibling marker belongs to the list, otherwise the list ends here
                    var task: Bool?
                    if let f = inner.first {
                        let t = f.s
                        if t.hasPrefix("[ ] ") || t == "[ ]" { task = false; inner[0].s = t.dropFirst(min(4, t.count)) }
                        else if t.hasPrefix("[x] ") || t.hasPrefix("[X] ") || t == "[x]" || t == "[X]" { task = true; inner[0].s = t.dropFirst(min(4, t.count)) }
                    }
                    items.append(MDItem(blocks: blocks(inner, depth: depth + 1), task: task, line: first.no))
                    j = k
                    // skip blank lines between siblings
                    var peek = j
                    while peek < n, isBlank(lines[peek].s) { peek += 1 }
                    if peek < n, let nm = marker(lines[peek].s), nm.ordered == m.ordered, nm.char == m.char, nm.indent < cur.content { j = peek } else { break }
                }
                out.append(.list(ordered: m.ordered, start: m.number, items: items, line: l.no))
                i = max(j, i + 1)
                continue
            }
            if startsHTML(l.s) {
                var body: [String] = []
                var j = i
                while j < n, !isBlank(lines[j].s) { body.append(String(trimmed(lines[j].s))); j += 1 }
                out.append(.html(text: body.joined(separator: "\n"), line: l.no))
                i = j
                continue
            }
            // table: header row with a pipe, followed by a delimiter row
            if l.s.contains("|"), i + 1 < n, let aligns = isDelimiterRow(lines[i + 1].s) {
                let header = splitRow(l.s)
                if header.count == aligns.count {
                    var rows: [[String]] = []
                    var j = i + 2
                    while j < n, !isBlank(lines[j].s), lines[j].s.contains("|") || !rows.isEmpty && !interrupts(lines[j].s) {
                        var cells = splitRow(lines[j].s)
                        while cells.count < header.count { cells.append("") }
                        rows.append(Array(cells.prefix(header.count)))
                        j += 1
                    }
                    out.append(.table(header: header, align: aligns, rows: rows, line: l.no))
                    i = j
                    continue
                }
            }
            // paragraph (+ setext heading)
            var para: [Substring] = [trimmed(l.s)]
            var j = i + 1
            var heading: Int?
            while j < n {
                let t = lines[j].s
                if let lv = setext(t) { heading = lv; j += 1; break }
                if interrupts(t) { break }
                para.append(trimmed(t))
                j += 1
            }
            if let lv = heading {
                out.append(.heading(level: lv, text: para.joined(separator: " "), line: l.no))
            } else {
                // hard line breaks: two trailing spaces or a backslash
                var text = ""
                for (k, p) in para.enumerated() {
                    let raw = lines[i + k].s
                    var piece = String(p)
                    let hard = k < para.count - 1 && (raw.hasSuffix("  ") || piece.hasSuffix("\\"))
                    if hard, piece.hasSuffix("\\") { piece.removeLast() }
                    text += piece
                    if k < para.count - 1 { text += hard ? "\u{2028}" : " " }
                }
                out.append(.paragraph(text: text, line: l.no))
            }
            i = j
        }
        return out
    }
}
