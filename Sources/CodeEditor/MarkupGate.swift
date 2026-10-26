import AppKit

/// Markup editing rules for HTML-like files (.html, .vue, ...): when the auto-popup stays quiet (plain text between tags) and
/// when typing `>` closes the tag that was just opened.
enum MarkupGate {
    static let extensions: Set<String> = ["html", "htm", "vue", "phtml", "svelte", "astro", "twig"]

    private static func isNameChar(_ c: unichar) -> Bool { CompletionLex.isIdent(c) || c == 45 || c == 58 || c == 46 }

    /// True when `caret` is in the text content of an element (not a tag, attribute, `{{ }}` expression, script, style or comment).
    /// Auto-popups are suppressed there; Ctrl-Space still works.
    static func isPlainText(_ ns: NSString, caret: Int, ext: String) -> Bool {
        guard extensions.contains(ext.lowercased()), caret <= ns.length else { return false }
        var i = caret
        while i > 0, isNameChar(ns.character(at: i - 1)) { i -= 1 }
        if i > 0, ns.character(at: i - 1) == 60 { return false }                                   // `<name`
        if i > 1, ns.character(at: i - 1) == 47, ns.character(at: i - 2) == 60 { return false }    // `</name`
        let head = NSRange(location: max(0, caret - 600), length: min(caret, 600))
        let open = ns.range(of: "{", options: .backwards, range: head)
        if open.location != NSNotFound, open.location > 0, ns.character(at: open.location - 1) == 123 {   // `{{` (Vue, Twig)
            let closed = ns.range(of: "}}", options: .backwards, range: head)
            if closed.location == NSNotFound || closed.location < open.location { return false }
        }
        if ns.range(of: "<?", options: .backwards, range: head).location != NSNotFound,
           ns.range(of: "?>", options: .backwards, range: head).location == NSNotFound { return false }   // inside PHP
        let loc = NWHtml.locate(NWBuf(ns), at: caret)
        return loc.kind == .text
    }

    private static let voids: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]

    /// The element name to close when `>` is typed at `caret`: the caret sits inside an open tag (`<h1`, `<div class="x"`) that is
    /// not void, not self-closing and not already followed by its own end tag. nil = just insert `>`.
    static func tagToClose(_ ns: NSString, caret: Int, ext: String) -> String? {
        guard extensions.contains(ext.lowercased()) || ext.lowercased() == "php" else { return nil }
        let floor = max(0, caret - 2000)
        var i = caret
        var quote: unichar = 0
        // walk back to the `<` that opens this tag; a `<` / `>` outside quotes before it means we are not in a tag
        var lt = -1
        var j = floor
        var lastLT = -1
        while j < caret {                                   // forward pass keeps quote state right
            let c = ns.character(at: j)
            if quote != 0 { if c == quote { quote = 0 } }
            else if c == 34 || c == 39 { if lastLT >= 0 { quote = c } }
            else if c == 60 { lastLT = j }
            else if c == 62 { lastLT = -1 }
            j += 1
        }
        guard quote == 0 || lastLT >= 0 else { return nil }
        lt = lastLT
        guard lt >= 0, lt + 1 < caret else { return nil }
        if lt > 0, CompletionLex.isIdent(ns.character(at: lt - 1)) || ns.character(at: lt - 1) == 41 { return nil }    // `a<b`, `ref<T>`
        var k = lt + 1
        while k < caret, isNameChar(ns.character(at: k)) { k += 1 }
        guard k > lt + 1, CompletionLex.isIdent(ns.character(at: lt + 1)), ns.character(at: lt + 1) >= 65 else { return nil }
        let name = ns.substring(with: NSRange(location: lt + 1, length: k - lt - 1))
        if caret > 0, ns.character(at: caret - 1) == 47 { return nil }                       // `/>`
        if voids.contains(name.lowercased()) { return nil }
        // not inside script / style content
        i = lt
        let head = NSRange(location: 0, length: lt)
        for tag in ["script", "style"] {
            let o = ns.range(of: "<" + tag, options: [.backwards, .caseInsensitive], range: head)
            if o.location != NSNotFound {
                let c = ns.range(of: "</" + tag, options: [.backwards, .caseInsensitive], range: head)
                if c.location == NSNotFound || c.location < o.location {
                    let gt = ns.range(of: ">", options: [], range: NSRange(location: o.location, length: lt - o.location))
                    if gt.location != NSNotFound { return nil }
                }
            }
        }
        _ = i
        // already closed right here
        let close = "</" + name
        if caret + close.utf16.count <= ns.length, ns.substring(with: NSRange(location: caret, length: close.utf16.count)) == close { return nil }
        return name
    }

    /// True when the `>` at `gt` ends an opening tag of a non-void element (`<div class="x">`, not `</div>`, `<br>` or `<x />`).
    static func opensElement(_ ns: NSString, gt: Int) -> Bool {
        guard gt >= 0, gt < ns.length, ns.character(at: gt) == 62, gt > 0, ns.character(at: gt - 1) != 47 else { return false }
        let floor = max(0, gt - 1500)
        var j = gt - 1
        var quote: unichar = 0
        // walk back to the `<`; quotes may hide a `>` or `<` inside attribute values
        while j >= floor {
            let c = ns.character(at: j)
            if quote != 0 { if c == quote { quote = 0 } }
            else if c == 34 || c == 39 { quote = c }
            else if c == 62 { return false }
            else if c == 60 { break }
            j -= 1
        }
        guard j >= floor, ns.character(at: j) == 60, j + 1 < gt else { return false }
        let first = ns.character(at: j + 1)
        guard (first >= 65 && first <= 90) || (first >= 97 && first <= 122) else { return false }
        var k = j + 1
        while k < gt, isNameChar(ns.character(at: k)) { k += 1 }
        return !voids.contains(ns.substring(with: NSRange(location: j + 1, length: k - j - 1)).lowercased())
    }
}
