import AppKit

/// CompletionProvider for CSS / HTML / Tailwind. Work runs on the project's serial utility queue; superseded requests are dropped.
final class NativeWebProvider: CompletionProvider {
    let triggerCharacters = ["<", "/", " ", "=", ":", "-", "@", ".", "#", "\"", "'", "(", "!"]
    private var token = 0

    func complete(_ context: CompletionContext, deliver: @escaping ([CompletionItem], Bool) -> Void) {
        token += 1
        let mine = token
        guard NativeWeb.handles(context.fileURL), context.text.utf8.count < 2_000_000 else { deliver([], false); return }
        let p = NWProject.shared(root: NativeWeb.root(for: context.fileURL))
        p.queue.async { [weak self] in
            guard let self, self.token == mine else { return }
            let items = NWService.complete(p, context)
            deliver(items, false)
        }
    }

    func cancel() { token += 1 }
}

/// A class-list position: the token being edited and where it sits.
struct NWClassSite {
    var tokenRange: NSRange        // the class token containing the offset (may be empty at whitespace)
    var listRange: NSRange         // the whole class list string
}

enum NWService {
    // MARK: dispatch

    static func complete(_ p: NWProject, _ ctx: CompletionContext) -> [CompletionItem] {
        p.beginRequest()
        let url = ctx.fileURL
        guard let kind = NativeWeb.kind(of: url) else { return [] }
        let dir = url.deletingLastPathComponent().path
        let ns = NSString(string: ctx.text)
        if kind == .script { return scriptComplete(p, ns, caret: min(ctx.caret, ns.length), url: url) }
        let b = NWBuf(ns)
        let caret = min(ctx.caret, b.count)
        // the project (Tailwind theme, stylesheets) is only consulted where an answer needs it
        func theme() -> NWTailwind? { p.tailwind(near: dir) }
        switch kind {
        case .css:
            let tw = theme()
            let lang = NWCss.lang(path: url.path)
            let pos = NWCss.position(b, from: 0, caret: caret, lang: lang)
            return NWCssService.complete(p, b, pos, caret: caret, lang: lang, url: url, tw: tw, manual: ctx.isManual, from: 0)
        case .html:
            var loc = NWHtml.locate(b, at: caret, wantStack: true)
            if loc.kind == .text, let tagLoc = bareTagStart(b, caret) { loc = tagLoc(loc.stack) }
            switch loc.kind {
            case .style:
                let pos = NWCss.position(b, from: loc.contentRange.location, caret: caret, lang: .css)
                return NWCssService.complete(p, b, pos, caret: caret, lang: .css, url: url, tw: theme(), manual: ctx.isManual, from: loc.contentRange.location)
            case .tagName, .attrName:
                return NWHtmlService.complete(p, b, loc, caret: caret, url: url, tw: nil, manual: ctx.isManual || (loc.kind == .tagName && ctx.triggerCharacter == "<"))   // `<` itself lists the tags
            case .attrValue:
                return NWHtmlService.complete(p, b, loc, caret: caret, url: url, tw: theme(), manual: ctx.isManual)
            case .script:                         // class strings inside <script> (template literals with markup, className=, cn(...))
                guard let site = scriptClassSite(b, caret), let tw = theme() else { return [] }
                return NWTailwindService.complete(tw, p, b, site: site, caret: caret, url: url, extraClasses: NWHtmlService.projectClasses(p, limit: 600))
            default: return []
            }
        case .script: return []
        }
    }

    /// JS / TS / JSX: only class strings (className=, cn(...), clsx(...), tw``) matter, so only a window around the caret is looked at
    /// (a large source file is never copied per keystroke) and the project is not touched unless such a string is found.
    private static func scriptComplete(_ p: NWProject, _ ns: NSString, caret: Int, url: URL) -> [CompletionItem] {
        let base = max(0, caret - 4000)
        let end = min(ns.length, caret + 1500)
        let window = ns.substring(with: NSRange(location: base, length: end - base))
        let b = NWBuf(NSString(string: window))
        let c = caret - base
        guard let site = scriptClassSite(b, c), let tw = p.tailwind(near: url.deletingLastPathComponent().path) else { return [] }
        var items = NWTailwindService.complete(tw, p, b, site: site, caret: c, url: url, extraClasses: NWHtmlService.projectClasses(p, limit: 600))
        for i in items.indices { if let r = items[i].replaceRange { items[i].replaceRange = NSRange(location: r.location + base, length: r.length) } }
        return items
    }

    /// `<` / `</` followed only by name characters before the caret, in text position: a tag name being typed.
    private static func bareTagStart(_ b: NWBuf, _ caret: Int) -> (([String]) -> NWHtml.Loc)? {
        var i = caret
        while i > 0, NWChar.isIdent(b[i - 1]) || b[i - 1] == 58 || b[i - 1] == 46 { i -= 1 }
        var isClose = false
        if i > 0, b[i - 1] == 47, i > 1, b[i - 2] == 60 { isClose = true; i -= 1 }
        guard i > 0, b[i - 1] == 60 else { return nil }
        let nameStart = i
        return { stack in
            var loc = NWHtml.Loc()
            loc.kind = .tagName
            loc.nameRange = NSRange(location: nameStart, length: caret - nameStart)
            loc.tag = b.str(nameStart, caret)
            loc.isClose = isClose
            loc.tagStart = nameStart - (isClose ? 2 : 1)
            loc.stack = stack
            return loc
        }
    }

    static func lookup(_ p: NWProject, url: URL, text: NSString, offset: Int, usages: Bool) -> NPHit? {
        p.beginRequest()
        guard let kind = NativeWeb.kind(of: url) else { return nil }
        let dir = url.deletingLastPathComponent().path
        if kind == .script { return scriptLookup(p, text, offset: min(offset, text.length), url: url) }
        let b = NWBuf(text)
        let off = min(offset, b.count)
        func theme() -> NWTailwind? { p.tailwind(near: dir) }
        switch kind {
        case .css:
            let tw = theme()
            let lang = NWCss.lang(path: url.path)
            return NWCssService.lookup(p, b, offset: off, from: 0, lang: lang, url: url, tw: tw, usages: usages)
        case .html:
            let loc = NWHtml.locate(b, at: off)
            switch loc.kind {
            case .style:
                return NWCssService.lookup(p, b, offset: off, from: loc.contentRange.location, lang: .css, url: url, tw: theme(), limit: NSMaxRange(loc.contentRange), usages: usages)
            case .tagName, .attrName:
                return NWHtmlService.lookup(p, b, loc, offset: off, url: url, tw: nil, usages: usages)
            case .attrValue:
                return NWHtmlService.lookup(p, b, loc, offset: off, url: url, tw: theme(), usages: usages)
            case .script:
                guard let site = scriptClassSite(b, off), let tw = theme() else { return nil }
                return NWTailwindService.lookup(tw, p, b, site: site, offset: off, url: url)
            default: return nil
            }
        case .script: return nil
        }
    }

    private static func scriptLookup(_ p: NWProject, _ ns: NSString, offset: Int, url: URL) -> NPHit? {
        let base = max(0, offset - 4000)
        let end = min(ns.length, offset + 1500)
        let b = NWBuf(NSString(string: ns.substring(with: NSRange(location: base, length: end - base))))
        let o = offset - base
        guard let site = scriptClassSite(b, o), let tw = p.tailwind(near: url.deletingLastPathComponent().path),
              var hit = NWTailwindService.lookup(tw, p, b, site: site, offset: o, url: url) else { return nil }
        hit.range = NSRange(location: hit.range.location + base, length: hit.range.length)
        return hit
    }

    // MARK: class lists

    static func isClassAttribute(_ name: String) -> Bool {
        let n = name.lowercased()
        return n == "class" || n == "classname" || n == "classlist" || n == "class:list" || n == ":class" || n == "[class]" || n == "ngclass" || n == "[ngclass]"
            || n.hasSuffix(":class") || n == "x-bind:class" || n == "hx-class" || n == "wire:class"
    }

    /// Innermost string literal (', ", `) containing `offset` inside [range], by a forward scan from the range start.
    static func innerString(_ b: NWBuf, in range: NSRange, offset: Int) -> NSRange? {
        var i = range.location
        let end = NSMaxRange(range)
        while i < end {
            let c = b[i]
            if c == 34 || c == 39 || c == 96 {
                let q = c
                let s = i + 1
                var j = s
                while j < end, b[j] != q { if b[j] == 92 { j += 1 }; j += 1 }
                if offset >= s, offset <= min(j, end) { return NSRange(location: s, length: min(j, end) - s) }
                i = j + 1
                continue
            }
            i += 1
        }
        return nil
    }

    /// Class token at `offset` in a class attribute value.
    static func htmlClassSite(_ b: NWBuf, loc: NWHtml.Loc, offset: Int) -> NWClassSite? {
        guard loc.kind == .attrValue, isClassAttribute(loc.attrName), let v = loc.valueRange else { return nil }
        let name = loc.attrName.lowercased()
        let bound = name != "class" && name != "classname" && name != "classlist" || loc.quote == 123
        var list = v
        if bound {
            guard let inner = innerString(b, in: v, offset: offset) else { return nil }
            list = inner
        } else {
            // inside `{{ ... }}` / `<?php ... ?>` / `@class([...])`: only an inner string literal counts
            var i = v.location
            while i < NSMaxRange(v) {
                if b[i] == 123 || b[i] == 60, let e = NWHtml.serverEnd(b, i) {
                    if offset >= i, offset <= e {
                        guard let inner = innerString(b, in: NSRange(location: i, length: min(e, NSMaxRange(v)) - i), offset: offset) else { return nil }
                        list = inner
                        break
                    }
                    i = e; continue
                }
                i += 1
            }
        }
        guard offset >= list.location, offset <= NSMaxRange(list) else { return nil }
        return NWClassSite(tokenRange: tokenRange(b, in: list, offset: offset), listRange: list)
    }

    static func tokenRange(_ b: NWBuf, in list: NSRange, offset: Int) -> NSRange {
        var s = offset, e = offset
        func stop(_ c: unichar) -> Bool { NWChar.isSpace(c) || c == 34 || c == 39 || c == 96 || c == 44 || c == 59 }
        while s > list.location, !stop(b[s - 1]) { s -= 1 }
        while e < NSMaxRange(list), !stop(b[e]) { e += 1 }
        return NSRange(location: s, length: e - s)
    }

    private static let classCallRegex = try! NSRegularExpression(pattern: #"\b(?:cn|clsx|classnames|classNames|twMerge|twJoin|cva|tw|cx|tv|clx|cls|classes)\s*(?:<[^>]*>)?\([^()]*$"#)
    private static let classAttrRegex = try! NSRegularExpression(pattern: #"(?:\bclass|\bclassName|\bclassList|ngClass|:class|\[class\]|class:list)\s*=\s*[\{\[\(]?\s*[^"'`=;]*$"#)

    /// String literal in JS / TS / JSX containing the caret when it is a class list (className=, cn(...), clsx(...), tw`...`).
    static func scriptClassSite(_ b: NWBuf, _ caret: Int) -> NWClassSite? {
        guard caret <= b.count else { return nil }
        // line state: which quote (if any) is open at the caret
        var ls = caret
        while ls > 0, b[ls - 1] != 10 { ls -= 1 }
        var quote: unichar = 0
        var qStart = -1
        var i = ls
        while i < caret {
            let c = b[i]
            if quote != 0 {
                if c == 92 { i += 2; continue }
                if c == quote { quote = 0 }
            } else if c == 34 || c == 39 || c == 96 { quote = c; qStart = i }
            else if c == 47, i + 1 < caret, b[i + 1] == 47 { return nil }          // line comment before the caret
            i += 1
        }
        guard quote != 0, qStart >= 0 else { return nil }
        // markup inside a template literal: `<td class="border|`
        if quote == 96 {
            var q = caret - 1
            while q > qStart, b[q] != 34, b[q] != 39 { q -= 1 }
            if q > qStart {
                let attr = b.str(max(qStart + 1, q - 24), q)
                if attr.range(of: #"(?:class|className)\s*=\s*$"#, options: .regularExpression) != nil {
                    var e = caret
                    while e < b.count, b[e] != b[q], b[e] != 10, b[e] != 96 { e += 1 }
                    let list = NSRange(location: q + 1, length: max(0, e - (q + 1)))
                    return NWClassSite(tokenRange: tokenRange(b, in: list, offset: caret), listRange: list)
                }
            }
        }
        var e = caret
        while e < b.count, b[e] != quote, b[e] != 10 { if b[e] == 92 { e += 1 }; e += 1 }
        e = min(e, b.count)
        let list = NSRange(location: qStart + 1, length: max(0, e - (qStart + 1)))
        // context before the opening quote
        func has(_ re: NSRegularExpression, _ s: String) -> Bool { re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil }
        let lineBefore = b.str(ls, qStart)
        if quote == 96, qStart > 0 {                                                // tw`...`
            let tag = b.str(max(ls, qStart - 12), qStart)
            if tag.hasSuffix("tw") || tag.hasSuffix("twMerge") { return NWClassSite(tokenRange: tokenRange(b, in: list, offset: caret), listRange: list) }
        }
        var ctx = lineBefore
        if ctx.trimmingCharacters(in: .whitespaces).isEmpty || ctx.trimmingCharacters(in: .whitespaces).hasSuffix(",") || ctx.trimmingCharacters(in: .whitespaces).hasSuffix("(") {
            // multi-line argument list: look at the previous lines (up to 8) for the opening call / attribute
            var s = ls
            var lines = 0
            var acc = ctx
            while s > 0, lines < 8 {
                var ps = s - 1
                while ps > 0, b[ps - 1] != 10 { ps -= 1 }
                acc = b.str(ps, s - 1) + "\n" + acc
                s = ps; lines += 1
                if acc.contains(";") && lines > 1 { break }
            }
            ctx = acc
        }
        if has(classCallRegex, ctx) || has(classAttrRegex, ctx) { return NWClassSite(tokenRange: tokenRange(b, in: list, offset: caret), listRange: list) }
        return nil
    }
}
