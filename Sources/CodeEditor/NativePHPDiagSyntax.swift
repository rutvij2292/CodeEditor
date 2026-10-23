import Foundation
import SwiftTreeSitter

/// Syntax errors from the vendored tree-sitter PHP grammar (ERROR / MISSING nodes). Top-most error nodes only (no cascades),
/// at most one finding per line and `maxErrors` per file.
enum NPDiagSyntax {
    static let maxErrors = 5
    private static let lock = NSLock()
    private static var cachedLanguage: Language?

    /// Must be called once on the main thread before `check` runs elsewhere (grammar loading is main-thread only).
    @discardableResult
    static func prime() -> Language? {
        lock.lock(); defer { lock.unlock() }
        if cachedLanguage == nil, Thread.isMainThread { cachedLanguage = Languages.grammar(forKey: "php")?.language }
        return cachedLanguage
    }

    private static func language() -> Language? {
        lock.lock(); let l = cachedLanguage; lock.unlock()
        return l ?? prime()
    }

    static func hasSyntaxError(_ text: NSString) -> Bool {
        guard let language = language() else { return false }
        let parser = Parser()
        guard (try? parser.setLanguage(language)) != nil, let tree = parser.parse(text as String), let root = tree.rootNode else { return false }
        return root.hasError && NPDiagPHPLint.accepts(text) != true
    }

    static func check(_ ns: NSString) -> [NPDiag] {
        guard let language = language() else { return [] }
        let parser = Parser()
        guard (try? parser.setLanguage(language)) != nil, let tree = parser.parse(ns as String), let root = tree.rootNode, root.hasError else { return [] }
        // A grammar limitation is not a syntax error: when PHP itself accepts the file, stay silent.
        if NPDiagPHPLint.accepts(ns) == true { return [] }
        var found: [NPDiag] = []
        collect(root, ns, &found, depth: 0)
        found.sort { $0.range.location < $1.range.location }
        // One per line, none inside the previous error's range, capped.
        var out: [NPDiag] = []
        var lastLineStart = -1, lastEnd = -1
        for d in found {
            let ls = ns.lineRange(for: NSRange(location: min(d.range.location, max(0, ns.length - 1)), length: 0)).location
            if ls == lastLineStart || d.range.location < lastEnd { continue }
            out.append(d)
            lastLineStart = ls; lastEnd = NSMaxRange(d.range)
            if out.count >= maxErrors { break }
        }
        return out
    }

    private static func collect(_ node: Node, _ ns: NSString, _ out: inout [NPDiag], depth: Int) {
        guard (node.hasError || node.isMissing), depth < 400, out.count < 64 else { return }
        if node.isMissing {
            let type = node.nodeType ?? "token"
            var loc = node.range.location
            // Report at the end of the previous token, like editors do for a missing ';' or ')'.
            var k = min(loc, ns.length)
            while k > 0, loc - k < 400, [32, 9, 10, 13].contains(ns.character(at: k - 1)) { k -= 1 }
            if k > 0 { loc = k - 1 }
            let len = loc < ns.length ? 1 : 0
            guard len > 0 else {
                out.append(NPDiag(range: NSRange(location: max(0, ns.length - 1), length: ns.length > 0 ? 1 : 0), severity: 1,
                                  message: "Syntax error: expected \(describe(type))", code: "syntax", group: .syntax))
                return
            }
            out.append(NPDiag(range: NSRange(location: loc, length: len), severity: 1, message: "Syntax error: expected \(describe(type))",
                              code: "syntax", group: .syntax))
            return
        }
        if node.nodeType == "ERROR" {
            let r = node.range
            let tokenLen = firstTokenLength(ns, r)
            let text = tokenLen > 0 ? ns.substring(with: NSRange(location: r.location, length: min(tokenLen, 24))) : ""
            let msg = text.isEmpty ? "Syntax error" : "Syntax error: unexpected '\(text)'"
            out.append(NPDiag(range: NSRange(location: r.location, length: max(1, min(tokenLen, max(1, ns.length - r.location)))), severity: 1,
                              message: msg, code: "syntax", group: .syntax))
            return
        }
        for i in 0..<node.childCount { if let c = node.child(at: i) { collect(c, ns, &out, depth: depth + 1) } }
    }

    private static func describe(_ type: String) -> String {
        switch type {
        case ";", ")", "}", "]", "(", "{", "[", ",", ":", "=>", "->", "::": return "'\(type)'"
        case "name": return "a name"
        case "variable_name": return "a variable"
        case "$": return "'$'"
        default: return type.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// Length of the first word / symbol inside `r` (what the squiggle covers).
    private static func firstTokenLength(_ ns: NSString, _ r: NSRange) -> Int {
        var i = r.location
        let end = min(NSMaxRange(r), ns.length)
        while i < end, [32, 9, 10, 13].contains(ns.character(at: i)) { i += 1 }
        guard i < end else { return 0 }
        let start = i
        func isWord(_ c: unichar) -> Bool { (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c >= 0x80 }
        if isWord(ns.character(at: i)) { while i < end, isWord(ns.character(at: i)) { i += 1 } } else { i += 1 }
        // Squiggle starts at the node start; account for leading whitespace skipped.
        return (start - r.location) + (i - start)
    }
}
