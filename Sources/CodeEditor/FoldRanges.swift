import Foundation
import SwiftTreeSitter

enum FoldKind: String { case block, comment, imports, markup, region }

/// One foldable region. Lines are 1-based. Folding hides `hiddenStart..<hiddenEnd` (UTF-16 offsets): everything after the
/// first line's text up to the closer on the last line (PhpStorm style: `function foo() {⋯}`), so lines
/// `startLine + 1 ... endLine` disappear and the closer's remainder joins the header row.
struct FoldRange: Equatable {
    var startLine: Int
    var endLine: Int
    var kind: FoldKind
    var placeholder: String
    /// Nesting depth among regions (1 = outermost).
    var level: Int
    var hiddenStart: Int
    var hiddenEnd: Int
    /// Half-open 1-based line range covered by the region.
    var lines: Range<Int> { startLine..<(endLine + 1) }
}

/// Pure fold-region detection (tree-sitter for the languages we highlight, scanners for Blade / Markdown / YAML /
/// `// region` markers, indentation otherwise). Safe to call from any thread.
enum FoldRanges {
    static let placeholder = "\u{22EF}"
    static let maxRegions = 20_000

    static func compute(text: String, fileName: String) -> [FoldRange] {
        let b = Builder(text: text)
        let key = Languages.key(forFileName: fileName)
        switch key {
        case "php": b.tree(text: text, lang: "php", offsetBase: 0, rules: Rules.php)
        case "js": b.tree(text: text, lang: "js", offsetBase: 0, rules: Rules.js)
        case "ts": b.tree(text: text, lang: "ts", offsetBase: 0, rules: Rules.js)
        case "tsx": b.tree(text: text, lang: "tsx", offsetBase: 0, rules: Rules.js)
        case "html", "vue": b.tree(text: text, lang: "html", offsetBase: 0, rules: Rules.html, vue: key == "vue")
        case "css": b.tree(text: text, lang: "css", offsetBase: 0, rules: Rules.css)
        case "scss": b.tree(text: text, lang: "scss", offsetBase: 0, rules: Rules.css)
        case "json": b.tree(text: text, lang: "json", offsetBase: 0, rules: Rules.json)
        case "blade":
            b.blade()
            b.tree(text: text, lang: "html", offsetBase: 0, rules: Rules.html)
        case "md": b.markdown()
        case "yaml": b.indentation(closers: false)
        default: b.indentation(closers: true)
        }
        b.regionMarkers()
        return b.finish()
    }

    // MARK: Rules

    struct Rule {
        var kind: FoldKind
        var prio: Int
        enum Closer { case none, bracket, comment, lastChild(String) }
        var closer: Closer
        /// Anchor = end of the first child of this type (HTML start tag) instead of the node start.
        var anchorAfterChild: String? = nil
    }

    enum Rules {
        static let php: [String: Rule] = [
            "compound_statement": Rule(kind: .block, prio: 3, closer: .bracket),
            "declaration_list": Rule(kind: .block, prio: 3, closer: .bracket),
            "enum_declaration_list": Rule(kind: .block, prio: 3, closer: .bracket),
            "switch_block": Rule(kind: .block, prio: 3, closer: .bracket),
            "match_block": Rule(kind: .block, prio: 3, closer: .bracket),
            "case_statement": Rule(kind: .block, prio: 2, closer: .none),
            "default_statement": Rule(kind: .block, prio: 2, closer: .none),
            "colon_block": Rule(kind: .block, prio: 2, closer: .none),
            "array_creation_expression": Rule(kind: .block, prio: 2, closer: .bracket),
            "arguments": Rule(kind: .block, prio: 1, closer: .bracket),
            "formal_parameters": Rule(kind: .block, prio: 1, closer: .bracket),
            "attribute_list": Rule(kind: .block, prio: 1, closer: .bracket),
            "comment": Rule(kind: .comment, prio: 4, closer: .comment),
        ]
        static let js: [String: Rule] = [
            "statement_block": Rule(kind: .block, prio: 3, closer: .bracket),
            "class_body": Rule(kind: .block, prio: 3, closer: .bracket),
            "interface_body": Rule(kind: .block, prio: 3, closer: .bracket),
            "enum_body": Rule(kind: .block, prio: 3, closer: .bracket),
            "object_type": Rule(kind: .block, prio: 3, closer: .bracket),
            "switch_body": Rule(kind: .block, prio: 3, closer: .bracket),
            "object": Rule(kind: .block, prio: 2, closer: .bracket),
            "object_pattern": Rule(kind: .block, prio: 2, closer: .bracket),
            "array": Rule(kind: .block, prio: 2, closer: .bracket),
            "array_pattern": Rule(kind: .block, prio: 2, closer: .bracket),
            "named_imports": Rule(kind: .block, prio: 2, closer: .bracket),
            "switch_case": Rule(kind: .block, prio: 2, closer: .none),
            "switch_default": Rule(kind: .block, prio: 2, closer: .none),
            "arguments": Rule(kind: .block, prio: 1, closer: .bracket),
            "formal_parameters": Rule(kind: .block, prio: 1, closer: .bracket),
            "template_string": Rule(kind: .block, prio: 1, closer: .bracket),
            "parenthesized_expression": Rule(kind: .block, prio: 1, closer: .bracket),
            "jsx_expression": Rule(kind: .block, prio: 1, closer: .bracket),
            "jsx_element": Rule(kind: .markup, prio: 3, closer: .lastChild("jsx_closing_element"), anchorAfterChild: "jsx_opening_element"),
            "comment": Rule(kind: .comment, prio: 4, closer: .comment),
        ]
        static let html: [String: Rule] = [
            "element": Rule(kind: .markup, prio: 3, closer: .lastChild("end_tag"), anchorAfterChild: "start_tag"),
            "script_element": Rule(kind: .markup, prio: 3, closer: .lastChild("end_tag"), anchorAfterChild: "start_tag"),
            "style_element": Rule(kind: .markup, prio: 3, closer: .lastChild("end_tag"), anchorAfterChild: "start_tag"),
            "comment": Rule(kind: .comment, prio: 4, closer: .lastChild("-->")),
        ]
        static let css: [String: Rule] = [
            "block": Rule(kind: .block, prio: 3, closer: .bracket),
            "map": Rule(kind: .block, prio: 2, closer: .bracket),
            "comment": Rule(kind: .comment, prio: 4, closer: .comment),
            "multiline_comment": Rule(kind: .comment, prio: 4, closer: .comment),
        ]
        static let json: [String: Rule] = [
            "object": Rule(kind: .block, prio: 3, closer: .bracket),
            "array": Rule(kind: .block, prio: 3, closer: .bracket),
        ]
        /// Node types whose consecutive siblings form one imports region.
        static let importTypes: Set<String> = ["namespace_use_declaration", "import_statement", "use_statement", "import_declaration"]
        /// Languages whose `//` / `#` single-line comments group into one comment region.
        static let lineCommentPrefixes: [String] = ["//", "#", "--"]
    }

    // MARK: Builder

    final class Builder {
        struct Raw { var hStart: Int; var hEnd: Int; var kind: FoldKind; var prio: Int }
        let text: String
        let ns: NSString
        let length: Int
        var lineStarts: [Int] = [0]
        var raws: [Raw] = []

        init(text: String) {
            self.text = text
            ns = text as NSString
            length = ns.length
            var buf = [unichar](repeating: 0, count: 16384)
            var pos = 0
            while pos < length {
                let n = min(buf.count, length - pos)
                ns.getCharacters(&buf, range: NSRange(location: pos, length: n))
                for i in 0..<n where buf[i] == 10 { lineStarts.append(pos + i + 1) }
                pos += n
            }
        }

        /// 0-based line containing an offset.
        func line(of offset: Int) -> Int {
            var lo = 0, hi = lineStarts.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }

        /// End of a line's text, before its line terminator.
        func contentEnd(ofLine l: Int) -> Int {
            var e = l + 1 < lineStarts.count ? lineStarts[l + 1] - 1 : length
            if l + 1 < lineStarts.count, e > lineStarts[l], ns.character(at: e - 1) == 13 { e -= 1 }
            return e
        }

        func firstNonBlank(ofLine l: Int) -> Int {
            var i = lineStarts[l]
            let e = contentEnd(ofLine: l)
            while i < e, ns.character(at: i) == 32 || ns.character(at: i) == 9 { i += 1 }
            return i
        }

        func hasContent(_ a: Int, _ b: Int) -> Bool {
            var i = a
            while i < b {
                let c = ns.character(at: i)
                if c != 32 && c != 9 && c != 10 && c != 13 { return true }
                i += 1
            }
            return false
        }

        /// Adds a region whose header row is the line containing `anchor` and whose hidden text ends at `hEnd`.
        func add(anchor: Int, hEnd: Int, kind: FoldKind, prio: Int) {
            guard raws.count < FoldRanges.maxRegions, anchor >= 0, hEnd <= length else { return }
            let sl = line(of: min(anchor, length))
            let hStart = contentEnd(ofLine: sl)
            guard hEnd > hStart, line(of: hEnd) > sl, hasContent(hStart, hEnd) else { return }
            raws.append(Raw(hStart: hStart, hEnd: hEnd, kind: kind, prio: prio))
        }

        // MARK: tree-sitter

        static var cacheLock = NSLock()
        static var languages: [String: Language] = [:]

        static func language(for key: String) -> Language? {
            cacheLock.lock()
            if let l = languages[key] { cacheLock.unlock(); return l }
            cacheLock.unlock()
            var found: Language?
            let resolve = { found = Languages.grammar(forKey: key)?.language }
            if Thread.isMainThread { resolve() } else { DispatchQueue.main.sync(execute: resolve) }
            if let found { cacheLock.lock(); languages[key] = found; cacheLock.unlock() }
            return found
        }

        static func parser(for key: String) -> Parser? {
            let dict = Thread.current.threadDictionary
            if let p = dict["ce.fold.parser.\(key)"] as? Parser { return p }
            guard let lang = language(for: key) else { return nil }
            let p = Parser()
            do { try p.setLanguage(lang) } catch { return nil }
            dict["ce.fold.parser.\(key)"] = p
            return p
        }

        func tree(text sub: String, lang: String, offsetBase: Int, rules: [String: Rule], vue: Bool = false) {
            guard let parser = Self.parser(for: lang), let tree = parser.parse(sub), let root = tree.rootNode else {
                if offsetBase == 0 { indentation(closers: true) }
                return
            }
            var walker = Walker(b: self, rules: rules, base: offsetBase, lang: lang)
            walker.walk(root, depth: 0)
        }

        struct Walker {
            let b: Builder
            let rules: [String: Rule]
            let base: Int
            let lang: String

            func type(_ n: Node) -> String { n.nodeType ?? "" }

            func walk(_ node: Node, depth: Int) {
                guard depth < 300, b.raws.count < FoldRanges.maxRegions else { return }
                let t = type(node)
                if let rule = rules[t] { apply(rule, node, type: t) }
                if t == "script_element" || t == "style_element" { embedded(node, isScript: t == "script_element") }
                let count = node.childCount
                guard count > 0 else { return }
                var children: [Node] = []
                children.reserveCapacity(count)
                for i in 0..<count { if let c = node.child(at: i) { children.append(c) } }
                groupSiblings(children)
                for c in children { walk(c, depth: depth + 1) }
            }

            func apply(_ rule: Rule, _ node: Node, type t: String) {
                let r = node.range
                guard r.location != NSNotFound else { return }
                let start = r.location + base, end = NSMaxRange(r) + base
                var anchor = start
                if let after = rule.anchorAfterChild {
                    var found = false
                    for i in 0..<node.childCount {
                        if let c = node.child(at: i), type(c) == after { anchor = NSMaxRange(c.range) + base; found = true; break }
                    }
                    if !found { return }
                }
                var hEnd = end
                if t == "comment", lang == "html" {
                    // `<!-- ... -->`: hide up to the closing token.
                    guard end - start >= 7, end <= b.length, b.ns.substring(with: NSRange(location: end - 3, length: 3)) == "-->" else { return }
                    b.add(anchor: anchor, hEnd: end - 3, kind: .comment, prio: 4)
                    return
                }
                switch rule.closer {
                case .none:
                    if rule.kind == .comment { return }
                case .bracket:
                    guard let last = node.lastChild, let lt = last.nodeType, lt == "}" || lt == ")" || lt == "]" || lt == "`" else { return }
                    hEnd = last.range.location + base
                case .comment:
                    // Only block comments; line comments are grouped by their parent.
                    guard end - start >= 4, b.ns.character(at: start) == 47, b.ns.character(at: start + 1) == 42 else { return }
                    hEnd = end - 2
                    if hEnd > b.length || b.ns.character(at: hEnd) != 42 { return }
                case .lastChild(let lt):
                    guard let last = node.lastChild, last.nodeType == lt else { return }
                    hEnd = last.range.location + base
                }
                b.add(anchor: anchor, hEnd: hEnd, kind: rule.kind, prio: rule.prio)
            }

            /// Consecutive `use` / `import` siblings and runs of `//` comment lines become one region each.
            func groupSiblings(_ children: [Node]) {
                var i = 0
                while i < children.count {
                    let t = type(children[i])
                    if Rules.importTypes.contains(t) {
                        var j = i
                        while j + 1 < children.count, type(children[j + 1]) == t { j += 1 }
                        let a = children[i].range, z = children[j].range
                        let hEnd = NSMaxRange(z) + base
                        // Trailing `;` is part of the node; keep the region to the end of the last statement.
                        b.add(anchor: a.location + base, hEnd: hEnd, kind: .imports, prio: 5)
                        i = j + 1
                        continue
                    }
                    if t == "comment" || t == "line_comment" || t == "single_line_comment" {
                        let r = children[i].range
                        if r.length >= 2, isLineComment(r) {
                            var j = i
                            var lastEnd = NSMaxRange(r) + base
                            while j + 1 < children.count, type(children[j + 1]) == t,
                                  isLineComment(children[j + 1].range),
                                  b.line(of: children[j + 1].range.location + base) == b.line(of: lastEnd) + 1 {
                                j += 1
                                lastEnd = NSMaxRange(children[j].range) + base
                            }
                            if j > i { b.add(anchor: r.location + base, hEnd: trimmedEnd(lastEnd), kind: .comment, prio: 4) }
                            i = j + 1
                            continue
                        }
                    }
                    i += 1
                }
            }

            func trimmedEnd(_ e: Int) -> Int {
                var x = e
                while x > 0, [10, 13, 32, 9].contains(b.ns.character(at: x - 1)) { x -= 1 }
                return x
            }

            func isLineComment(_ r: NSRange) -> Bool {
                let s = r.location + base
                guard s + 1 < b.length else { return false }
                let c0 = b.ns.character(at: s), c1 = b.ns.character(at: s + 1)
                if c0 == 47 && c1 == 47 { return true }
                if c0 == 35 && c1 != 91 { return true }        // `#` but not a PHP attribute `#[`
                if c0 == 45 && c1 == 45 { return true }
                return false
            }

            /// `<script>` / `<style>` bodies: fold what is inside with the embedded language's grammar.
            func embedded(_ node: Node, isScript: Bool) {
                var startTag: Node?, raw: Node?
                for i in 0..<node.childCount {
                    guard let c = node.child(at: i) else { continue }
                    if c.nodeType == "start_tag" { startTag = c } else if c.nodeType == "raw_text" { raw = c }
                }
                guard let raw, raw.range.length > 0 else { return }
                let tag = startTag.map { b.ns.substring(with: NSRange(location: $0.range.location + base, length: $0.range.length)) } ?? ""
                var key: String
                var table: [String: Rule]
                if isScript {
                    if tag.contains("json") { return }
                    key = tag.contains("tsx") ? "tsx" : (tag.contains("ts") && !tag.contains("text/")) || tag.contains("typescript") ? "ts" : "js"
                    table = Rules.js
                } else {
                    key = tag.contains("scss") || tag.contains("sass") ? "scss" : "css"
                    table = Rules.css
                }
                let r = raw.range
                let sub = b.ns.substring(with: NSRange(location: r.location + base, length: r.length))
                b.tree(text: sub, lang: key, offsetBase: r.location + base, rules: table)
            }
        }

        // MARK: Blade

        static let bladeBlocks: [String: Set<String>] = [
            "if": ["endif"], "unless": ["endunless"], "isset": ["endisset"], "empty": ["endempty"], "auth": ["endauth"],
            "guest": ["endguest"], "env": ["endenv"], "production": ["endproduction"], "foreach": ["endforeach"],
            "forelse": ["endforelse"], "for": ["endfor"], "while": ["endwhile"], "section": ["endsection", "show", "stop", "append", "overwrite"],
            "push": ["endpush"], "pushonce": ["endpushonce"], "pushif": ["endpushif"], "prepend": ["endprepend"], "prependonce": ["endprependonce"],
            "php": ["endphp"], "once": ["endonce"], "component": ["endcomponent"], "slot": ["endslot"], "switch": ["endswitch"],
            "can": ["endcan"], "cannot": ["endcannot"], "canany": ["endcanany"], "error": ["enderror"], "verbatim": ["endverbatim"],
            "session": ["endsession"], "fragment": ["endfragment"], "hassection": ["endhassection"], "sectionmissing": ["endsectionmissing"],
            "context": ["endcontext"], "teleport": ["endteleport"], "livewire": [],
        ]
        static let bladeMiddle: Set<String> = ["else", "elseif", "elseauth", "elseguest", "elsecan", "elsecannot", "elseenv", "empty", "case", "default"]

        func blade() {
            // Block comments `{{-- ... --}}`.
            var search = NSRange(location: 0, length: length)
            while search.length > 0 {
                let open = ns.range(of: "{{--", options: [], range: search)
                if open.location == NSNotFound { break }
                let rest = NSRange(location: NSMaxRange(open), length: length - NSMaxRange(open))
                let close = ns.range(of: "--}}", options: [], range: rest)
                if close.location == NSNotFound { break }
                add(anchor: open.location, hEnd: close.location, kind: .comment, prio: 4)
                search = NSRange(location: NSMaxRange(close), length: length - NSMaxRange(close))
            }
            // Directive blocks.
            struct Open { var name: String; var anchorLine: Int }
            var stack: [Open] = []
            var verbatim = false
            let lineCount = lineStarts.count
            for l in 0..<lineCount {
                let st = firstNonBlank(ofLine: l)
                let ce = contentEnd(ofLine: l)
                guard st + 1 < ce, ns.character(at: st) == 64 else { continue }     // '@'
                var e = st + 1
                while e < ce {
                    let c = ns.character(at: e)
                    if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 { e += 1 } else { break }
                }
                guard e > st + 1 else { continue }
                let name = ns.substring(with: NSRange(location: st + 1, length: e - st - 1)).lowercased()
                if verbatim { if name == "endverbatim" { verbatim = false } else { continue } }
                let isOpener = Self.bladeBlocks[name] != nil
                let isMiddle = Self.bladeMiddle.contains(name)
                var isEnd = false
                if let top = stack.last, let ends = Self.bladeBlocks[top.name], ends.contains(name) { isEnd = true }
                else if stack.contains(where: { Self.bladeBlocks[$0.name]?.contains(name) == true }) { isEnd = true }
                if isEnd {
                    while let top = stack.popLast() {
                        // Close the branch that is still open, ending right before this directive.
                        add(anchor: lineStarts[top.anchorLine], hEnd: st, kind: .block, prio: 3)
                        if Self.bladeBlocks[top.name]?.contains(name) == true { break }
                    }
                    continue
                }
                if isMiddle, let top = stack.last, !(name == "empty" && top.name != "forelse"), !(name == "default" && top.name != "switch"), !(name == "case" && top.name != "switch") {
                    add(anchor: lineStarts[top.anchorLine], hEnd: st, kind: .block, prio: 3)
                    stack[stack.count - 1].anchorLine = l
                    continue
                }
                if isOpener {
                    // Inline forms have no end directive: `@php($x)`, `@section('a', 'b')`, `@push(...)` with a value, `@livewire(...)`.
                    var rest = ""
                    if e < ce { rest = ns.substring(with: NSRange(location: e, length: ce - e)) }
                    let trimmed = rest.drop(while: { $0 == " " })
                    if name == "php", trimmed.hasPrefix("(") { continue }
                    if (name == "section" || name == "push" || name == "pushonce" || name == "slot") && Builder.topLevelCommaCount(String(trimmed)) >= 1 && name != "slot" { continue }
                    if name == "livewire" || Self.bladeBlocks[name]?.isEmpty == true { continue }
                    // A one-line `@if(...) ... @endif` is closed on the same line: nothing to fold.
                    if rest.lowercased().contains("@end") { continue }
                    if name == "verbatim" { verbatim = true }
                    stack.append(Open(name: name, anchorLine: l))
                }
            }
        }

        static func topLevelCommaCount(_ s: String) -> Int {
            var depth = 0, commas = 0
            var inStr: Character?
            for ch in s {
                if let q = inStr { if ch == q { inStr = nil }; continue }
                switch ch {
                case "'", "\"": inStr = ch
                case "(", "[": depth += 1
                case ")", "]": depth -= 1; if depth == 0 { return commas }
                case ",": if depth == 1 { commas += 1 }
                default: break
                }
            }
            return commas
        }

        // MARK: Markdown

        func markdown() {
            var fence: (marker: unichar, len: Int, line: Int)?
            struct Head { var level: Int; var line: Int }
            var heads: [Head] = []
            let lineCount = lineStarts.count
            // Front matter.
            if lineCount > 2, matches(line: 0, "---") {
                var l = 1
                while l < lineCount, !matches(line: l, "---") { l += 1 }
                if l < lineCount { add(anchor: lineStarts[0], hEnd: firstNonBlank(ofLine: l), kind: .block, prio: 3) }
            }
            for l in 0..<lineCount {
                let st = firstNonBlank(ofLine: l), ce = contentEnd(ofLine: l)
                guard st < ce else { continue }
                let c = ns.character(at: st)
                if c == 96 || c == 126 {
                    var n = 0
                    while st + n < ce, ns.character(at: st + n) == c { n += 1 }
                    if n >= 3 {
                        if let f = fence {
                            if f.marker == c, n >= f.len, st + n == ce {
                                add(anchor: lineStarts[f.line], hEnd: st, kind: .block, prio: 3)
                                fence = nil
                            }
                        } else { fence = (c, n, l) }
                        continue
                    }
                }
                if fence != nil { continue }
                if c == 35 {
                    var n = 0
                    while st + n < ce, ns.character(at: st + n) == 35 { n += 1 }
                    if n <= 6, st + n < ce, ns.character(at: st + n) == 32 || ns.character(at: st + n) == 9 { heads.append(Head(level: n, line: l)) }
                }
            }
            // Heading sections end before the next heading of the same or a higher level.
            func lastNonBlank(before l: Int) -> Int {
                var x = l - 1
                while x > 0, firstNonBlank(ofLine: x) >= contentEnd(ofLine: x) { x -= 1 }
                return x
            }
            var stack: [Head] = []
            func close(_ h: Head, before l: Int) {
                let last = lastNonBlank(before: l)
                guard last > h.line else { return }
                add(anchor: lineStarts[h.line], hEnd: contentEnd(ofLine: last), kind: .markup, prio: 3)
            }
            for h in heads {
                while let top = stack.last, top.level >= h.level { stack.removeLast(); close(top, before: h.line) }
                stack.append(h)
            }
            while let top = stack.popLast() { close(top, before: lineCount) }
        }

        func matches(line l: Int, _ s: String) -> Bool {
            let st = lineStarts[l], ce = contentEnd(ofLine: l)
            return ce - st == s.utf16.count && ns.substring(with: NSRange(location: st, length: ce - st)) == s
        }

        // MARK: Indentation (YAML and unknown languages)

        func indentation(closers: Bool) {
            guard length > 0 else { return }
            struct Cand { var line: Int; var indent: Int }
            var stack: [Cand] = []
            var lastNonBlank = -1
            let lineCount = lineStarts.count
            func indentOf(_ l: Int) -> Int? {
                var i = lineStarts[l]
                let e = contentEnd(ofLine: l)
                var col = 0
                while i < e {
                    let c = ns.character(at: i)
                    if c == 32 { col += 1 } else if c == 9 { col += 4 - col % 4 } else { return col }
                    i += 1
                }
                return nil
            }
            func isCloser(_ l: Int) -> Bool {
                let st = firstNonBlank(ofLine: l), ce = contentEnd(ofLine: l)
                guard st < ce else { return false }
                let c = ns.character(at: st)
                if c == 125 || c == 41 || c == 93 { return true }
                if c == 60, st + 1 < ce, ns.character(at: st + 1) == 47 { return true }   // `</tag`
                let word = ns.substring(with: NSRange(location: st, length: min(ce - st, 8)))
                for w in ["end", "fi", "done", "esac"] where word == w || (word.hasPrefix(w) && word.count > w.count && !(word.dropFirst(w.count).first!.isLetter || word.dropFirst(w.count).first! == "_")) { return true }
                return false
            }
            for l in 0..<lineCount {
                guard let d = indentOf(l) else { continue }
                while let top = stack.last, top.indent >= d {
                    stack.removeLast()
                    if lastNonBlank > top.line {
                        if closers, top.indent == d, isCloser(l) {
                            add(anchor: lineStarts[top.line], hEnd: firstNonBlank(ofLine: l), kind: .block, prio: 3)
                        } else {
                            add(anchor: lineStarts[top.line], hEnd: contentEnd(ofLine: lastNonBlank), kind: .block, prio: 3)
                        }
                    }
                }
                stack.append(Cand(line: l, indent: d))
                lastNonBlank = l
            }
            while let top = stack.popLast() {
                if lastNonBlank > top.line { add(anchor: lineStarts[top.line], hEnd: contentEnd(ofLine: lastNonBlank), kind: .block, prio: 3) }
            }
        }

        // MARK: `// region` markers

        func regionMarkers() {
            guard ns.range(of: "region").location != NSNotFound else { return }
            guard let re = try? NSRegularExpression(pattern: #"^[ \t]*(?://|#|/\*|<!--|--|;|%)[ \t]*#?(end)?region\b[^\n]*$"#, options: [.anchorsMatchLines]) else { return }
            var stack: [Int] = []
            re.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: length)) { m, _, _ in
                guard let m else { return }
                let l = self.line(of: m.range.location)
                if m.range(at: 1).location == NSNotFound { stack.append(l) }
                else if let s = stack.popLast() {
                    self.add(anchor: self.lineStarts[s], hEnd: self.firstNonBlank(ofLine: l), kind: .region, prio: 6)
                }
            }
        }

        // MARK: Finish

        func finish() -> [FoldRange] {
            // Sort outermost first; drop partial overlaps; same-line duplicates keep the highest priority.
            let sorted = raws.sorted { a, b in a.hStart != b.hStart ? a.hStart < b.hStart : a.hEnd > b.hEnd }
            var bestByLines: [Int: Int] = [:]    // key = startLine<<32 | endLine -> index in `sorted`
            for (i, r) in sorted.enumerated() {
                let key = line(of: r.hStart) << 32 | line(of: r.hEnd)
                if let j = bestByLines[key] {
                    if r.prio > sorted[j].prio || (r.prio == sorted[j].prio && r.hEnd < sorted[j].hEnd) { bestByLines[key] = i }
                } else { bestByLines[key] = i }
            }
            let keep = Set(bestByLines.values)
            var out: [FoldRange] = []
            var stack: [Int] = []       // hEnd of open regions
            for (i, r) in sorted.enumerated() where keep.contains(i) {
                while let top = stack.last, top <= r.hStart { stack.removeLast() }
                if let top = stack.last, r.hEnd > top { continue }       // crosses its parent
                if let prev = out.last, prev.hiddenStart == r.hStart, prev.hiddenEnd == r.hEnd { continue }
                stack.append(r.hEnd)
                out.append(FoldRange(startLine: line(of: r.hStart) + 1, endLine: line(of: r.hEnd) + 1, kind: r.kind,
                                     placeholder: FoldRanges.placeholder, level: stack.count, hiddenStart: r.hStart, hiddenEnd: r.hEnd))
            }
            return out
        }
    }
}
