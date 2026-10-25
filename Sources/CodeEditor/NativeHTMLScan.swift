import Foundation

/// Tolerant HTML tokenizer shared by completion, hover, definition and usage search. Understands comments, raw-text elements
/// (script / style / textarea / title), PHP / Blade / Twig / Vue mustache regions (opaque, also inside attribute values),
/// Blade directives inside tags, quoted / unquoted / `{expr}` attribute values. Works on a UTF-16 snapshot, never builds a tree.
enum NWHtml {
    struct Attr {
        var name: NSRange
        var value: NSRange?          // inner range (without quotes / braces)
        var quote: unichar           // 34, 39, 123 ({expr}), or 0
    }

    enum Token {
        case open(start: Int, name: NSRange, attrs: [Attr], end: Int, closed: Bool, selfClosing: Bool)
        case close(start: Int, name: NSRange, end: Int)
        case comment(start: Int, end: Int)
        case server(start: Int, end: Int)
        case raw(tag: String, range: NSRange)        // script / style content
    }

    static func dropCaches() { NWHtmlData.dropCaches() }

    @inline(__always) private static func lower(_ c: unichar) -> unichar { (c >= 65 && c <= 90) ? c + 32 : c }
    private static func isTagNameChar(_ c: unichar) -> Bool { NWChar.isIdent(c) || c == 58 || c == 46 }

    private static func matches(_ b: NWBuf, _ at: Int, _ s: String) -> Bool {
        var i = at
        for u in s.utf16 {
            guard i < b.count, lower(b[i]) == u else { return false }
            i += 1
        }
        return true
    }

    private static func find(_ b: NWBuf, _ s: String, from: Int) -> Int? {
        let pat = Array(s.utf16)
        guard !pat.isEmpty else { return from }
        var i = from
        let last = b.count - pat.count
        while i <= last {
            if lower(b[i]) == pat[0] {
                var k = 1
                while k < pat.count, lower(b[i + k]) == pat[k] { k += 1 }
                if k == pat.count { return i }
            }
            i += 1
        }
        return nil
    }

    /// End (exclusive) of a server-side construct starting at `i`, or nil when `i` does not start one.
    static func serverEnd(_ b: NWBuf, _ i: Int) -> Int? {
        guard i + 1 < b.count else { return nil }
        let c = b[i], d = b[i + 1]
        if c == 60, d == 63 { return find(b, "?>", from: i + 2).map { $0 + 2 } ?? b.count }                 // <? ... ?>
        if c == 60, d == 37 { return find(b, "%>", from: i + 2).map { $0 + 2 } ?? b.count }                 // <% ... %>
        if c == 123, d == 123 {
            if i + 2 < b.count, b[i + 2] == 123 { return find(b, "}}}", from: i + 3).map { $0 + 3 } ?? b.count }
            return find(b, "}}", from: i + 2).map { $0 + 2 } ?? b.count
        }
        if c == 123, d == 33, i + 2 < b.count, b[i + 2] == 33 { return find(b, "!!}", from: i + 3).map { $0 + 3 } ?? b.count }   // {!! !!}
        if c == 123, d == 37 { return find(b, "%}", from: i + 2).map { $0 + 2 } ?? b.count }                // {% %}
        if c == 123, d == 35 { return find(b, "#}", from: i + 2).map { $0 + 2 } ?? b.count }                // {# #}
        return nil
    }

    private static func skipBalanced(_ b: NWBuf, _ i: Int, open: unichar, close: unichar) -> Int {
        var d = 0, k = i
        while k < b.count {
            let c = b[k]
            if c == 34 || c == 39 || c == 96 {
                let q = c; k += 1
                while k < b.count, b[k] != q { if b[k] == 92 { k += 1 }; k += 1 }
            } else if c == open { d += 1 } else if c == close { d -= 1; if d == 0 { return k + 1 } }
            k += 1
        }
        return b.count
    }

    /// Walks the document; `visit` returns false to stop. Tokens are emitted in order.
    static func tokenize(_ b: NWBuf, _ visit: (Token) -> Bool) {
        let n = b.count
        var i = 0
        while i < n {
            let c = b[i]
            if c == 64, i + 1 < n, NWChar.isNameStart(b[i + 1]) {                    // Blade @php ... @endphp / @verbatim
                let atLineStart = i == 0 || b[i - 1] == 10 || NWChar.isSpace(b[i - 1])
                if atLineStart {
                    for (open, close) in [("@php", "@endphp"), ("@verbatim", "@endverbatim")] where matches(b, i, open) {
                        var k = i + open.utf16.count
                        while k < n, b[k] == 32 || b[k] == 9 { k += 1 }
                        if k < n, b[k] == 40 { break }                                 // @php(...)
                        if open == "@php", k < n, NWChar.isNameStart(b[k]) { break }
                        let e = find(b, close, from: k).map { $0 + close.utf16.count } ?? n
                        if !visit(.server(start: i, end: e)) { return }
                        i = e
                        break
                    }
                }
                i += 1
                continue
            }
            guard c == 60 || c == 123 else { i += 1; continue }
            if let e = serverEnd(b, i) {
                if !visit(.server(start: i, end: e)) { return }
                i = max(e, i + 1); continue
            }
            guard c == 60, i + 1 < n else { i += 1; continue }
            let d = b[i + 1]
            if d == 33 {                                                            // <!-- --> / <!DOCTYPE> / <![CDATA[
                let e: Int
                if matches(b, i, "<!--") { e = find(b, "-->", from: i + 4).map { $0 + 3 } ?? n }
                else if matches(b, i, "<![cdata[") { e = find(b, "]]>", from: i + 3).map { $0 + 3 } ?? n }
                else { var k = i + 2; while k < n, b[k] != 62 { k += 1 }; e = min(n, k + 1) }
                if !visit(.comment(start: i, end: e)) { return }
                i = e; continue
            }
            if d == 47, i + 2 < n, NWChar.isNameStart(b[i + 2]) {                  // </name>
                var k = i + 2
                while k < n, isTagNameChar(b[k]) { k += 1 }
                let nameRange = NSRange(location: i + 2, length: k - (i + 2))
                var e = k
                while e < n, b[e] != 62, b[e] != 60 { e += 1 }
                if e < n, b[e] == 62 { e += 1 }
                if !visit(.close(start: i, name: nameRange, end: e)) { return }
                i = e; continue
            }
            guard NWChar.isNameStart(d) else { i += 1; continue }
            // open tag
            var k = i + 1
            while k < n, isTagNameChar(b[k]) { k += 1 }
            let nameRange = NSRange(location: i + 1, length: k - (i + 1))
            var attrs: [Attr] = []
            var closed = false, selfClosing = false
            tagLoop: while k < n {
                while k < n, NWChar.isSpace(b[k]) { k += 1 }
                guard k < n else { break }
                let ch = b[k]
                if ch == 62 { k += 1; closed = true; break }
                if ch == 47 { if k + 1 < n, b[k + 1] == 62 { k += 2; closed = true; selfClosing = true; break }; k += 1; continue }
                if ch == 60 {
                    if let e = serverEnd(b, k) { k = e; continue }
                    break tagLoop                                                    // a new tag starts: this one is unterminated
                }
                if ch == 123, let e = serverEnd(b, k) { k = e; continue }
                if ch == 64, k + 1 < n, NWChar.isNameStart(b[k + 1]) {              // Blade directive inside the tag: @if(...) / @class([...])
                    var m = k + 1
                    while m < n, NWChar.isIdent(b[m]) { m += 1 }
                    var p = m
                    while p < n, b[p] == 32 { p += 1 }
                    if p < n, b[p] == 40 { k = skipBalanced(b, p, open: 40, close: 41); continue }
                }
                // attribute name
                let ns = k
                while k < n {
                    let x = b[k]
                    if NWChar.isSpace(x) || x == 61 || x == 62 || x == 60 { break }
                    if x == 47, k + 1 < n, b[k + 1] == 62 { break }
                    if x == 123, k + 1 < n, b[k + 1] == 123 { break }
                    k += 1
                }
                if k == ns { k += 1; continue }
                var attr = Attr(name: NSRange(location: ns, length: k - ns), value: nil, quote: 0)
                var j = k
                while j < n, NWChar.isSpace(b[j]) { j += 1 }
                if j < n, b[j] == 61 {
                    j += 1
                    while j < n, NWChar.isSpace(b[j]) { j += 1 }
                    if j < n, b[j] == 34 || b[j] == 39 {
                        let q = b[j]
                        var m = j + 1
                        var found = false
                        let limit = min(n, j + 6000)
                        while m < limit {
                            let x = b[m]
                            if x == q { found = true; break }
                            if x == 123 || x == 60, let e = serverEnd(b, m) { m = e; continue }
                            m += 1
                        }
                        if found { attr.value = NSRange(location: j + 1, length: m - (j + 1)); attr.quote = q; k = m + 1 }
                        else {                                                       // unterminated: stop at the end of the line
                            var e = j + 1
                            while e < n, b[e] != 10, b[e] != 62 { e += 1 }
                            attr.value = NSRange(location: j + 1, length: e - (j + 1)); attr.quote = q; k = e
                        }
                    } else if j < n, b[j] == 123 {
                        let e = skipBalanced(b, j, open: 123, close: 125)
                        attr.value = NSRange(location: j + 1, length: max(0, e - 1 - (j + 1))); attr.quote = 123; k = e
                    } else {
                        var m = j
                        while m < n, !NWChar.isSpace(b[m]), b[m] != 62 {
                            if b[m] == 47, m + 1 < n, b[m + 1] == 62 { break }
                            if b[m] == 123 || b[m] == 60, let e = serverEnd(b, m) { m = e; continue }
                            m += 1
                        }
                        attr.value = NSRange(location: j, length: m - j); attr.quote = 0; k = m
                    }
                }
                attrs.append(attr)
            }
            if !visit(.open(start: i, name: nameRange, attrs: attrs, end: min(k, n), closed: closed, selfClosing: selfClosing)) { return }
            i = max(k, i + 1)
            if closed, !selfClosing {                                                // raw text elements
                let name = b.str(nameRange.location, NSMaxRange(nameRange)).lowercased()
                if NWHtmlData.rawTextTags.contains(name) {
                    let end = find(b, "</" + name, from: i) ?? n
                    if name == "script" || name == "style" {
                        if !visit(.raw(tag: name, range: NSRange(location: i, length: end - i))) { return }
                    }
                    i = end
                }
            }
        }
    }

    // MARK: Locating the caret

    struct Loc {
        enum Kind { case text, tagName, attrName, attrValue, style, script, comment, server }
        var kind = Kind.text
        var tag = ""
        var tagStart = 0
        var tagEnd = 0
        var nameRange = NSRange(location: 0, length: 0)       // tag name (tagName)
        var isClose = false
        var attrName = ""
        var attrRange = NSRange(location: 0, length: 0)
        var valueRange: NSRange?
        var quote: unichar = 0
        var existing: Set<String> = []
        var contentRange = NSRange(location: 0, length: 0)    // style / script content
        var stack: [String] = []                              // open elements before the caret
        var tagClosed = true
    }

    static func locate(_ b: NWBuf, at offset: Int, wantStack: Bool = false) -> Loc {
        var loc = Loc()
        var stack: [String] = []
        let off = min(offset, b.count)
        tokenize(b) { t in
            switch t {
            case .open(let start, let name, let attrs, let end, let closed, let selfClosing):
                let limit = closed ? end : end + 1
                if off <= start { return false }
                if off >= limit {
                    if wantStack, closed, !selfClosing {
                        let nm = b.str(name.location, NSMaxRange(name)).lowercased()
                        if !NWHtmlData.voidTags.contains(nm) { stack.append(nm) }
                        if stack.count > 400 { stack.removeFirst(100) }
                    }
                    return true
                }
                loc.tag = b.str(name.location, NSMaxRange(name))
                loc.tagStart = start; loc.tagEnd = end; loc.tagClosed = closed; loc.nameRange = name
                loc.existing = Set(attrs.map { b.str($0.name.location, NSMaxRange($0.name)).lowercased() })
                if off <= NSMaxRange(name) { loc.kind = .tagName; return false }
                for a in attrs {
                    if off >= a.name.location, off <= NSMaxRange(a.name) {
                        loc.kind = .attrName
                        loc.attrName = b.str(a.name.location, NSMaxRange(a.name)); loc.attrRange = a.name
                        loc.existing.remove(loc.attrName.lowercased())
                        return false
                    }
                    if let v = a.value {
                        if off >= v.location, off <= NSMaxRange(v) {
                            loc.kind = .attrValue
                            loc.attrName = b.str(a.name.location, NSMaxRange(a.name)); loc.attrRange = a.name
                            loc.valueRange = v; loc.quote = a.quote
                            loc.existing.remove(loc.attrName.lowercased())
                            return false
                        }
                    }
                }
                loc.kind = .attrName          // whitespace between attributes: a new attribute name
                return false
            case .close(let start, let name, let end):
                if off <= start { return false }
                if off > end || (off == end && b.str(end - 1, end) == ">") {
                    if wantStack {
                        let nm = b.str(name.location, NSMaxRange(name)).lowercased()
                        if let k = stack.lastIndex(of: nm) { stack.removeSubrange(k...) }
                    }
                    return true
                }
                loc.tag = b.str(name.location, NSMaxRange(name)); loc.tagStart = start; loc.tagEnd = end; loc.nameRange = name; loc.isClose = true
                loc.kind = .tagName
                return false
            case .comment(let start, let end):
                if off <= start { return off < start ? false : true }
                if off < end || end == b.count { loc.kind = .comment; loc.tagStart = start; loc.tagEnd = end; return false }
                return true
            case .server(let start, let end):
                if off <= start { return off < start ? false : true }
                if off < end || end == b.count { loc.kind = .server; loc.tagStart = start; loc.tagEnd = end; return false }
                return true
            case .raw(let tag, let range):
                if off >= range.location, off <= NSMaxRange(range) {
                    loc.kind = tag == "style" ? .style : .script
                    loc.contentRange = range; loc.tag = tag
                    return false
                }
                return off > NSMaxRange(range)
            }
        }
        loc.stack = stack
        return loc
    }

    // MARK: Attribute enumeration (usage search, indexes)

    /// Calls `body(tagName, attrName, nameRange, valueRange)` for every attribute with a value, skipping nothing.
    static func eachAttribute(_ b: NWBuf, _ body: (_ tag: String, _ name: String, _ nameRange: NSRange, _ value: NSRange, _ quote: unichar) -> Void) {
        tokenize(b) { t in
            if case .open(_, let name, let attrs, _, _, _) = t {
                let tag = b.str(name.location, NSMaxRange(name))
                for a in attrs {
                    guard let v = a.value else { continue }
                    body(tag, b.str(a.name.location, NSMaxRange(a.name)), a.name, v, a.quote)
                }
            }
            return true
        }
    }

    /// `<style>` blocks of a document: content ranges.
    static func styleBlocks(_ b: NWBuf) -> [NSRange] {
        var out: [NSRange] = []
        tokenize(b) { t in
            if case .raw(let tag, let r) = t, tag == "style" { out.append(r) }
            return true
        }
        return out
    }

    // MARK: Class lists

    /// Names in a class attribute value (whitespace separated), skipping server-side constructs; with their offsets.
    static func classTokens(_ b: NWBuf, in range: NSRange) -> [(name: String, range: NSRange)] {
        var out: [(String, NSRange)] = []
        var i = range.location
        let end = NSMaxRange(range)
        while i < end {
            if NWChar.isSpace(b[i]) { i += 1; continue }
            if b[i] == 123 || b[i] == 60, let e = serverEnd(b, i) { i = e; continue }
            let s = i
            while i < end, !NWChar.isSpace(b[i]) {
                if (b[i] == 123 || b[i] == 60), serverEnd(b, i) != nil { break }
                i += 1
            }
            if i > s { out.append((b.str(s, i), NSRange(location: s, length: i - s))) }
        }
        return out
    }
}
