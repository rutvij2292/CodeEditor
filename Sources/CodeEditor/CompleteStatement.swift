import AppKit

/// "Complete Current Statement" (Ctrl-Shift-Return; Cmd-Shift-Return is Write Claude Prompt) for C-like languages: closes the brackets that are still open on the
/// caret line, adds the `;`, or opens a `{ }` block for `if (...)` / `foreach (...)` / `function ...()` / `class X` headers, and moves the
/// caret to where the next thing is typed. Pure text transformation (`compute`) so it is testable without a window; one undo step.
enum CompleteStatement {
    struct Edit: Equatable {
        var range: NSRange          // replaced range of the original text
        var text: String            // replacement
        var caret: Int              // caret offset in the ORIGINAL coordinate system after the edit (range.location + offset into `text`)
    }

    static let extensions: Set<String> = ["php", "phtml", "js", "jsx", "ts", "tsx", "mjs", "cjs", "java", "c", "cpp", "h", "swift", "rs", "go", "kt", "cs"]

    private static let blockHeads: [String] = ["if", "elseif", "else if", "while", "for", "foreach", "switch", "catch", "match", "do", "try", "finally", "else"]
    private static let noSemicolonTails: Set<Character> = [";", "{", "}", ",", ":", "(", "[", ".", "+", "-", "*", "/", "=", ">", "<", "&", "|", "?", "\\", "!", "%", "^", "~"]

    /// Scans `s` and returns the stack of unclosed brackets and whether a string / block comment is still open at the end.
    private static func openBrackets(_ s: [Character]) -> (stack: [Character], inString: Bool, lineComment: Int?) {
        var stack: [Character] = []
        var quote: Character?
        var i = 0
        while i < s.count {
            let c = s[i]
            if let q = quote {
                if c == "\\" { i += 2; continue }
                if c == q { quote = nil }
                i += 1; continue
            }
            if c == "/" , i + 1 < s.count, s[i + 1] == "/" { return (stack, false, i) }
            if c == "#", i == 0 || s[i - 1] == " " || s[i - 1] == "\t" { if s.count > i + 1, s[i + 1] != "[" { return (stack, false, i) } }
            switch c {
            case "'", "\"", "`": quote = c
            case "(", "[", "{": stack.append(c)
            case ")", "]", "}": if let l = stack.last, (l == "(" && c == ")") || (l == "[" && c == "]") || (l == "{" && c == "}") { stack.removeLast() }
            default: break
            }
            i += 1
        }
        return (stack, quote != nil, nil)
    }

    private static func closer(_ c: Character) -> Character { c == "(" ? ")" : (c == "[" ? "]" : "}") }

    /// Brackets left open by everything BEFORE the caret line (multi-line call arguments / arrays): a statement inside them takes no `;`.
    private static func outerOpen(_ ns: NSString, lineStart: Int) -> Bool {
        let from = max(0, lineStart - 6000)
        let chars = Array(ns.substring(with: NSRange(location: from, length: lineStart - from)))
        var stack: [Character] = []
        var quote: Character?
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if let q = quote { if c == "\\" { i += 2; continue }; if c == q { quote = nil }; i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" { while i < chars.count, chars[i] != "\n" { i += 1 }; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" { i += 2; while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }; i += 2; continue }
            switch c {
            case "'", "\"", "`": quote = c
            case "(", "[": stack.append(c)
            case "{": stack.append(c)
            case ")", "]", "}": if !stack.isEmpty { stack.removeLast() }
            default: break
            }
            i += 1
        }
        return stack.last == "(" || stack.last == "["
    }

    /// Edit that completes the statement on the line of `caret`, nil when there is nothing to do (blank line, comment, already complete).
    static func compute(text ns: NSString, caret: Int, indentUnit: String = "    ") -> Edit? {
        guard ns.length > 0, caret >= 0, caret <= ns.length else { return nil }
        let lr = ns.lineRange(for: NSRange(location: min(caret, max(0, ns.length - 1)), length: 0))
        var content = ns.substring(with: lr)
        while content.hasSuffix("\n") || content.hasSuffix("\r") { content.removeLast() }
        let lineEndAbs = lr.location + (content as NSString).length
        let indent = String(content.prefix(while: { $0 == " " || $0 == "\t" }))
        var code = Array(content.dropFirst(indent.count))
        guard !code.isEmpty else { return nil }
        let (_, _, lineComment) = openBrackets(code)
        var comment = ""
        if let lc = lineComment { comment = String(code[lc...]); code = Array(String(code[..<lc]).trimmingCharacters(in: .whitespaces)) }
        else { code = Array(String(code).trimmingCharacters(in: .whitespaces)) }
        guard !code.isEmpty else { return nil }
        if code.first == "*" || code.first == "@" || String(code).hasPrefix("/*") || String(code).hasPrefix("<?") || String(code).hasPrefix("?>") { return nil }
        let (stack, inString, _) = openBrackets(code)
        if inString { return nil }
        var head = String(code)
        // close what is still open (innermost first); a `{` is a block the user is still typing: leave it alone
        if stack.contains("{") { return nil }
        for b in stack.reversed() { head.append(closer(b)) }
        let trailer = comment.isEmpty ? "" : " " + comment
        let lowered = head.lowercased()
        func isHead(_ h: String) -> Bool {
            guard lowered.hasPrefix(h) else { return false }
            let rest = lowered.dropFirst(h.count)
            return rest.isEmpty || rest.first == " " || rest.first == "(" || rest.first == "{"
        }
        let bodyIndent = indent + indentUnit
        func block(_ h: String, close: String = "}") -> Edit {
            let opening = indent + h + " {" + "\n" + bodyIndent
            return Edit(range: NSRange(location: lr.location, length: lineEndAbs - lr.location), text: opening + "\n" + indent + close + trailer,
                        caret: lr.location + (opening as NSString).length)
        }
        // a block header that is still open (`if (...)`, `foreach (...)`, `function f()`, `class X`) gets its braces
        if head.hasSuffix("{") || head.hasSuffix("}") { return nil }
        let modifiers: Set<String> = ["public", "protected", "private", "static", "abstract", "final", "readonly"]
        let words = lowered.split(whereSeparator: { !($0.isLetter || $0 == "_") }).map(String.init)
        let firstNonModifier = words.first(where: { !modifiers.contains($0) }) ?? ""
        let isAbstractMember = words.contains("abstract")
        if blockHeads.contains(where: { isHead($0) }) {
            if ["do", "try", "else", "finally"].contains(firstNonModifier) && !head.contains("(") { return block(head) }
            if head.hasSuffix(")") { return block(head) }
        } else if firstNonModifier == "function", head.contains("("), !isAbstractMember {
            let afterParen = head.lastIndex(of: ")").map { String(head[head.index(after: $0)...]) } ?? ""
            if head.hasSuffix(")") || afterParen.trimmingCharacters(in: .whitespaces).hasPrefix(":") { return block(head) }
        } else if ["class", "trait", "enum"].contains(firstNonModifier) && !lowered.contains("::class") {
            return block(head)
        } else if firstNonModifier == "interface" {
            return block(head)
        } else if lowered.contains("= function") || lowered.contains("=function") || lowered.contains("= fn") && false {
            if head.hasSuffix(")") || head.contains(") use (") { return block(head, close: "};") }
        }
        // plain statement
        var out = head
        if let last = out.last, !noSemicolonTails.contains(last), !outerOpen(ns, lineStart: lr.location) { out.append(";") }
        else if let last = out.last, last == ")" || last == "]", !outerOpen(ns, lineStart: lr.location) { out.append(";") }
        let newText = indent + out + trailer
        let original = indent + String(code) + trailer
        guard newText != original || caret != lineEndAbs else { return nil }
        return Edit(range: NSRange(location: lr.location, length: lineEndAbs - lr.location), text: newText, caret: lr.location + (indent + out as NSString).length)
    }

    static func perform(on tv: NSTextView) {
        guard tv.selectedRanges.count == 1, tv.selectedRange().length == 0 else { return }
        let ns = tv.string as NSString
        let caret = tv.selectedRange().location
        let unit = (tv as? CodeTextView).map { _ in "    " } ?? "    "
        guard let e = compute(text: ns, caret: caret, indentUnit: unit) else {
            // nothing to complete: behave like "start new line below"
            let lr = ns.lineRange(for: NSRange(location: min(caret, max(0, ns.length - 1)), length: 0))
            var end = lr.location + lr.length
            if end > lr.location, ns.character(at: end - 1) == 10 { end -= 1 }
            tv.setSelectedRange(NSRange(location: end, length: 0))
            return
        }
        if tv.shouldChangeText(in: e.range, replacementString: e.text) {
            tv.replaceCharacters(in: e.range, with: e.text)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: min(e.caret, (tv.string as NSString).length), length: 0))
        }
    }
}
