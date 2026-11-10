import Foundation

/// Finds the code block (PHP / SQL / JS / ...) around a terminal row so it can be copied in one click.
/// Pure text logic; runs only when the context menu opens, so it costs nothing while idle.
enum TerminalCodeBlocks {
    /// Block containing `row` (0-based index into `lines`): a fenced ``` / ~~~ block (fences excluded),
    /// else the contiguous run of code-looking lines. Common indent and trailing spaces are stripped.
    static func block(in lines: [String], at row: Int) -> String? {
        guard lines.indices.contains(row) else { return nil }
        if let r = fenced(lines, row) { return clean(Array(lines[r])) }
        return heuristic(lines, row)
    }

    private static func isFence(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("```") || t.hasPrefix("~~~")
    }

    private static func fenced(_ lines: [String], _ row: Int) -> Range<Int>? {
        var open: Int?
        for (i, l) in lines.enumerated() where isFence(l) {
            if let o = open {
                if row >= o && row <= i { return row == o || row == i ? nil : (o + 1)..<i }
                open = nil
            } else { open = i }
            if i > row, open == nil { break }
        }
        return nil
    }

    /// `$name` (PHP / shell variable), not a "$ " shell prompt.
    private static func isPHPVariableStart(_ t: String) -> Bool {
        guard t.hasPrefix("$"), let c = t.dropFirst().first else { return false }
        return c.isLetter || c == "_"
    }

    static func looksLikeCode(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return false }
        if t.hasPrefix("<?php") || t.hasPrefix("?>") || t.hasPrefix("//") || t.hasPrefix("/*") || t.hasPrefix("*") || t.hasPrefix("#[") { return true }
        if isPHPVariableStart(t) || t == "{" || t == "}" || t.hasPrefix("}") || t.hasPrefix("{") { return true }
        if t.hasSuffix(";") || t.hasSuffix("{") || t.hasSuffix("},") || t.hasSuffix(",") && t.contains("=>") { return true }
        let first = t.split(whereSeparator: { " (\t".contains($0) }).first.map { $0.uppercased() } ?? ""
        let starters: Set<String> = ["SELECT", "INSERT", "UPDATE", "DELETE", "FROM", "WHERE", "JOIN", "LEFT", "INNER", "GROUP", "ORDER", "HAVING", "LIMIT",
                                     "SET", "VALUES", "CREATE", "ALTER", "DROP", "AND", "OR", "ON", "UNION", "WITH",
                                     "FUNCTION", "CONST", "LET", "VAR", "RETURN", "IF", "ELSE", "FOREACH", "FOR", "WHILE", "CLASS", "USE", "NAMESPACE",
                                     "PUBLIC", "PRIVATE", "PROTECTED", "STATIC", "IMPORT", "EXPORT", "ASYNC", "AWAIT", "SWITCH", "CASE", "TRY", "CATCH", "THROW", "NEW"]
        if starters.contains(first.trimmingCharacters(in: CharacterSet(charactersIn: ":"))) { return true }
        return t.contains("=>") || t.contains("->") || t.contains("::") || t.contains("===") || t.contains("();")
    }

    private static func heuristic(_ lines: [String], _ row: Int) -> String? {
        guard looksLikeCode(lines[row]) else { return nil }
        var a = row, b = row
        // Blank lines inside a block are kept when code continues after them.
        func codeOrBlankBridge(_ i: Int, _ step: Int) -> Bool {
            if looksLikeCode(lines[i]) { return true }
            guard lines[i].trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            let j = i + step
            return lines.indices.contains(j) && looksLikeCode(lines[j])
        }
        while a > 0, codeOrBlankBridge(a - 1, -1) { a -= 1 }
        while b < lines.count - 1, codeOrBlankBridge(b + 1, 1) { b += 1 }
        return clean(Array(lines[a...b]))
    }

    /// Drops leading/trailing blank lines and trailing spaces, removes the common left indent.
    static func clean(_ raw: [String]) -> String? {
        var ls = raw.map { l -> String in var s = l; while s.last == " " || s.last == "\t" { s.removeLast() }; return s }
        while ls.first?.isEmpty == true { ls.removeFirst() }
        while ls.last?.isEmpty == true { ls.removeLast() }
        guard !ls.isEmpty else { return nil }
        let indent = ls.filter { !$0.isEmpty }.map { $0.prefix(while: { $0 == " " }).count }.min() ?? 0
        return ls.map { String($0.dropFirst(min(indent, $0.count))) }.joined(separator: "\n")
    }
}
