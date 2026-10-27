import AppKit

/// Item construction helpers for the built-in providers.
enum CI {
    static func make(_ label: String, _ kind: CompletionKind, detail: String = "", insert: String? = nil, snippet: Bool = false,
                     sort: String? = nil, doc: String = "", filter: String? = nil, range: NSRange? = nil) -> CompletionItem {
        var it = CompletionItem(label: label, insertText: insert ?? label, kind: kind)
        it.detail = detail
        it.documentation = doc
        it.sortText = sort
        it.filterText = filter
        it.replaceRange = range
        it.isSnippet = snippet
        return it
    }

    /// Snippet for calling `name` with the REQUIRED parameters as named placeholders: `str_replace(${1:\$search}, ${2:\$replace}, ${3:\$subject})$0`.
    /// `params` is the text between the parentheses (PHP `string $a, int $b = 0`, JS `a, b`, Python `a, b=1`). No required parameter: `name($0)`.
    static func callInsert(_ name: String, params: String) -> String {
        var stops: [String] = []
        for raw in NPResolver.splitParams(params) {
            let p = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if p.isEmpty || p.contains("=") || p.contains("...") || p.hasPrefix("?") || p.hasPrefix("[") || p.hasPrefix("{") || p.hasSuffix("?") || p.hasSuffix("]") || p.contains("?:") || p.hasPrefix("*") { continue }
            var label = p
            if let v = p.split(separator: " ").last(where: { $0.hasPrefix("$") }) { label = String(v) }       // PHP: the variable
            else if let c = p.split(separator: ":").first, p.contains(":") { label = String(c).trimmingCharacters(in: .whitespaces) }   // TS: name: type
            else if let l = p.split(separator: " ").last { label = String(l) }
            label = label.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "$", with: "\\$").replacingOccurrences(of: "}", with: "\\}")
            stops.append("${\(stops.count + 1):\(label)}")
            if stops.count >= 6 { break }
        }
        return stops.isEmpty ? name + "($0)" : name + "(" + stops.joined(separator: ", ") + ")$0"
    }

    /// "name(args)" or "name(args): ret" or "name(args)|ret" -> function-like item; bare names become properties.
    static func member(_ entry: Substring, kind: CompletionKind = .method, sort: String? = nil, range: NSRange? = nil) -> CompletionItem {
        guard let paren = entry.firstIndex(of: "(") else {
            return make(String(entry), .property, sort: sort, range: range)
        }
        let name = String(entry[entry.startIndex..<paren])
        var rest = String(entry[paren...])
        var ret = ""
        if let bar = rest.firstIndex(of: "|") { ret = String(rest[rest.index(after: bar)...]); rest = String(rest[..<bar]) }
        else if let r = rest.range(of: "): ") { ret = String(rest[r.upperBound...]); rest = String(rest[..<rest.index(before: r.upperBound)]) .appending(")") }
        let noArgs = rest.hasPrefix("()")
        let detail = rest + (ret.isEmpty ? "" : ": " + ret)
        let inner = rest.hasPrefix("(") && rest.hasSuffix(")") ? String(rest.dropFirst().dropLast()) : ""
        return make(name, kind, detail: detail, insert: noArgs ? name + "()" : callInsert(name, params: inner), snippet: !noArgs, sort: sort,
                    doc: "```\n\(name)\(detail)\n```", range: range)
    }

    /// Splits "a(x, y) b c(z)" into entries at paren depth 0.
    static func entries(_ s: String) -> [Substring] {
        var out: [Substring] = []
        var depth = 0
        var start = s.startIndex
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "(" { depth += 1 } else if c == ")" { depth = max(0, depth - 1) }
            else if c == " ", depth == 0 {
                if start < i { out.append(s[start..<i]) }
                start = s.index(after: i)
            }
            i = s.index(after: i)
        }
        if start < s.endIndex { out.append(s[start...]) }
        return out
    }

    static func members(_ list: String, kind: CompletionKind = .method, sort: String? = nil, range: NSRange? = nil) -> [CompletionItem] {
        entries(list).map { member($0, kind: kind, sort: sort, range: range) }
    }

    static func lines(_ s: String) -> [Substring] { s.split(separator: "\n") }

    static func functions(_ s: String, tag: String = "") -> [CompletionItem] {
        lines(s).map { l in
            var it = member(l, kind: .function)
            if !tag.isEmpty { it.detail = it.detail + "  " + tag }
            return it
        }
    }

    static func expand(_ s: String) -> String { s.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\t", with: "\t") }
}

/// Wraps a generator closure as a CompletionProvider (synchronous, main thread).
final class BuiltinProvider: CompletionProvider {
    let triggerCharacters: [String]
    private let gen: (CompletionContext) -> [CompletionItem]
    init(triggers: [String] = [], _ gen: @escaping (CompletionContext) -> [CompletionItem]) {
        triggerCharacters = triggers
        self.gen = gen
    }
    func complete(_ context: CompletionContext, deliver: @escaping ([CompletionItem], Bool) -> Void) { deliver(gen(context), false) }
    func cancel() {}
}

// MARK: - Words from the current file

enum WordProvider {
    static func generate(_ ctx: CompletionContext) -> [CompletionItem] {
        let ns = ctx.text as NSString
        let len = ns.length
        guard len > 0, len < 3_000_000 else { return [] }
        let inf = CompletionLex.info(ctx)
        if CompletionLex.state(ctx) != .code && !ctx.isManual { return [] }
        let pr = ctx.prefixRange
        // Naming a tag or attribute in markup: document words are noise there (`id` offered `joint_partner_id`, `getElementById`); the HTML / Vue providers answer.
        if inf.region == .html, MarkupGate.extensions.contains(ctx.fileExtension.lowercased()) {
            let k = NWHtml.locate(NWBuf(ns), at: ctx.caret).kind
            if k == .attrName || k == .tagName { return [] }
        }
        if inf.region == .php || inf.region == .bladeExpr {
            if pr.location > 0 {
                let c = ns.character(at: pr.location - 1)
                if c == 36 || CompletionLex.before(ns, pr.location, "::") { return [] }
                if CompletionLex.before(ns, pr.location, "$this->") || CompletionLex.before(ns, pr.location, "$this?->") { return [] }
            }
        }
        if pr.length == 0 && !ctx.isManual { return [] }
        // words of a huge file: only a window around the caret is scanned (main thread; bounded to ~1-2 ms)
        var lo = 0
        var wlen = len
        if len > 300_000 { lo = max(0, min(len - 300_000, ctx.caret - 150_000)); wlen = 300_000 }
        var buf = [unichar](repeating: 0, count: wlen)
        ns.getCharacters(&buf, range: NSRange(location: lo, length: wlen))
        var q: [UInt8] = []
        for u in ns.substring(with: pr).utf16 { if u < 128 { q.append(u >= 65 && u <= 90 ? UInt8(u + 32) : UInt8(u)) } else { q = []; break } }
        let pre = q.count == pr.length ? q : []
        var seen = Set<String>()
        var out: [CompletionItem] = []
        var i = 0
        while i < wlen {
            let c = buf[i]
            guard CompletionLex.isIdent(c), !(c >= 48 && c <= 57) else { i += 1; continue }
            var j = i + 1
            while j < wlen, CompletionLex.isIdent(buf[j]) { j += 1 }
            defer { i = j }
            let n = j - i
            if n < 3 || n > 60 { continue }
            if i + lo == pr.location && j + lo >= pr.upperBound && pr.length > 0 && j - i >= 0 && i + pr.length <= j {
                // the word being typed (or extended in place)
                if ctx.caret <= j + lo { continue }
            }
            if !pre.isEmpty {
                var k = 0
                for x in i..<j {
                    var u = buf[x]
                    if u >= 65 && u <= 90 { u += 32 }
                    if k < pre.count, u == UInt16(pre[k]) { k += 1 }
                }
                if k < pre.count { continue }
            }
            let w = String(utf16CodeUnits: Array(buf[i..<j]), count: n)
            if seen.insert(w).inserted {
                var it = CompletionItem(label: w, insertText: w, kind: .text)
                it.sortText = "~" + w.lowercased()
                out.append(it)
                if out.count >= 3000 { break }
            }
        }
        return out
    }
}

// MARK: - PHP (+ Laravel)

enum PHPCompletion {
    private static let memberRegex = try! NSRegularExpression(pattern:
        #"(static\s+)?function\s+&?(\w+)\s*\(([^)]*)\)(?:\s*:\s*\??([\w\\|]+))?"#)
    private static let propRegex = try! NSRegularExpression(pattern:
        #"(?:public|protected|private|var)\s+(?:static\s+)?(?:readonly\s+)?(?:\??[\w\\|]+\s+)?\$(\w+)"#)
    private static let constRegex = try! NSRegularExpression(pattern: #"\bconst\s+(?:\??[\w\\|]+\s+)?(\w+)\s*="#)
    private static let caseRegex = try! NSRegularExpression(pattern: #"^\s*case\s+(\w+)"#, options: .anchorsMatchLines)

    private static let plainItems: [CompletionItem] = {
        var out: [CompletionItem] = []
        for k in CompletionData.phpKeywords { out.append(CI.make(k, .keyword)) }
        for k in CompletionData.phpMagic { out.append(CI.make(k, k.hasPrefix("__") && k.hasSuffix("__") ? .constant : .method, detail: "magic")) }
        for k in CompletionData.phpTypes { out.append(CI.make(k, .keyword, detail: "type")) }
        return out
    }()

    static func generate(_ ctx: CompletionContext) -> [CompletionItem] {
        let inf = CompletionLex.info(ctx)
        guard inf.region == .php || inf.region == .bladeExpr, CompletionLex.state(ctx) == .code else { return [] }
        let ns = ctx.text as NSString
        let caret = ctx.caret
        let p = ctx.prefixRange.location
        if p > 0, ns.character(at: p - 1) == 36 {
            return variables(ctx, ns, inf, dollar: NSRange(location: p - 1, length: caret - (p - 1)))
        }
        let nullsafe = CompletionLex.before(ns, p, "?->")
        if nullsafe || CompletionLex.before(ns, p, "->") {
            let objEnd = p - (nullsafe ? 3 : 2)
            if CompletionLex.before(ns, objEnd, "$this") { return thisMembers(ns, staticOnly: false) }
            if CompletionLex.before(ns, objEnd, ")") {
                // helper()->member : look for ident( ... ) chain head
                let open = ns.range(of: "(", options: .backwards, range: NSRange(location: max(0, objEnd - 80), length: max(0, objEnd - max(0, objEnd - 80))))
                if open.location != NSNotFound {
                    let name = CompletionLex.identBefore(ns, open.location)
                    if let list = CompletionData.requestFamily[name] { return CI.members(list) }
                }
            }
            if CompletionLex.before(ns, objEnd, "Auth::user()") || CompletionLex.before(ns, objEnd, "Carbon::now()") {
                return CI.members(CompletionData.requestFamily["now"]!)
            }
            return CI.members(CompletionData.eloquentInstance, sort: "z")
        }
        if CompletionLex.before(ns, p, "::") {
            let cls = CompletionLex.identBefore(ns, p - 2)
            var out: [CompletionItem] = [CI.make("class", .constant, detail: "class name")]
            if cls == "self" || cls == "static" || cls == "parent" {
                out += thisMembers(ns, staticOnly: true)
                return out
            }
            if cls == "Route" { return CI.members(CompletionData.routeMethods, sort: "a") + out }
            if let list = CompletionData.facades[cls], !list.isEmpty { return CI.members(list, sort: "a") + out }
            if let f = cls.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(f) {
                for l in CI.lines(CompletionData.eloquentStatic) { out.append(CI.member(l, kind: .method, sort: "m")) }
                out += thisMembers(ns, staticOnly: true, constantsOnly: true)
            }
            return out
        }
        if ctx.prefix.isEmpty && !ctx.isManual { return [] }
        var out = plainItems
        for l in CI.lines(CompletionData.phpFunctions) { out.append(CI.member(l, kind: .function)) }
        for l in CI.lines(CompletionData.laravelFunctions) {
            var it = CI.member(l, kind: .function)
            it.detail += "  Laravel"
            out.append(it)
        }
        out += stubItems(prefix: ctx.prefix)
        return out
    }

    private static let curatedFunctionNames: Set<String> = {
        var set = Set<String>()
        for l in CI.lines(CompletionData.phpFunctions) + CI.lines(CompletionData.laravelFunctions) {
            if let p = l.firstIndex(of: "(") { set.insert(l[l.startIndex..<p].lowercased()) }
        }
        return set
    }()

    /// Built-in functions and constants from the bundled stubs (PHPStubs) that the curated tables above do not list. Prefix matches
    /// only, capped; nothing is read for an empty prefix.
    private static func stubItems(prefix: String) -> [CompletionItem] {
        guard prefix.count >= 2 else { return [] }
        var out: [CompletionItem] = []
        for e in PHPStubs.search(kind: "f", prefix: prefix, limit: 60) where !curatedFunctionNames.contains(e.name.lowercased()) && !e.name.contains("\\") {
            let args = e.signature.drop(while: { $0 != "(" })
            let noArgs = args.hasPrefix("()")
            out.append(CI.make(e.name, .function, detail: String(args), insert: noArgs ? e.name + "()" : e.name + "($1)$0", snippet: !noArgs,
                               doc: "```\n\(e.signature)\n```\n\nPHP built-in function (\(e.extra))."))
        }
        if let f = prefix.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(f) || prefix.hasPrefix("_") {
            for e in PHPStubs.search(kind: "k", prefix: prefix, limit: 40) where !e.name.contains("\\") {
                out.append(CI.make(e.name, .constant, detail: "PHP built-in (\(e.extra))"))
            }
        }
        return out
    }

    /// `$name` variables declared earlier in the current function (or file) plus superglobals.
    private static func variables(_ ctx: CompletionContext, _ ns: NSString, _ inf: CompletionLex.Info, dollar: NSRange) -> [CompletionItem] {
        let end = dollar.location
        var start = inf.region == .bladeExpr ? 0 : inf.start
        // the nearest enclosing NAMED function (`function name(`): a closed closure before the caret must not hide the method's variables
        var limit = end
        for _ in 0..<60 {
            let r = ns.range(of: "function", options: [.backwards, .literal], range: NSRange(location: start, length: max(0, limit - start)))
            if r.location == NSNotFound { break }
            var q = r.location + r.length
            while q < end, ns.character(at: q) == 32 || ns.character(at: q) == 10 || ns.character(at: q) == 9 || ns.character(at: q) == 38 { q += 1 }
            if q < end, CompletionLex.isIdent(ns.character(at: q)) { start = r.location; break }   // named function
            limit = r.location
            if limit <= start { break }
        }
        var names = Set<String>(["this"])
        if end > start {
            var buf = [unichar](repeating: 0, count: end - start)
            ns.getCharacters(&buf, range: NSRange(location: start, length: end - start))
            var i = 0
            while i < buf.count {
                if buf[i] == 36, i + 1 < buf.count, CompletionLex.isIdent(buf[i + 1]), !(buf[i + 1] >= 48 && buf[i + 1] <= 57) {
                    var j = i + 1
                    while j < buf.count, CompletionLex.isIdent(buf[j]) { j += 1 }
                    names.insert(String(utf16CodeUnits: Array(buf[(i + 1)..<j]), count: j - i - 1))
                    i = j
                } else { i += 1 }
            }
        }
        var out: [CompletionItem] = []
        for n in names { out.append(CI.make("$" + n, .variable, detail: n == "this" ? "current object" : "variable", range: dollar)) }
        for s in CompletionData.phpSuperglobals { out.append(CI.make(s, .variable, detail: "superglobal", sort: "z" + s, range: dollar)) }
        return out
    }

    /// Members declared in the current file: `$this->` (all) or `self::` (static + constants).
    private static func thisMembers(_ ns: NSString, staticOnly: Bool, constantsOnly: Bool = false) -> [CompletionItem] {
        let full = NSRange(location: 0, length: ns.length)
        guard full.length < 2_000_000 else { return [] }
        var out: [CompletionItem] = []
        var seen = Set<String>()
        if !constantsOnly {
            memberRegex.enumerateMatches(in: ns as String, range: full) { m, _, _ in
                guard let m else { return }
                let isStatic = m.range(at: 1).location != NSNotFound
                if staticOnly && !isStatic { return }
                let name = ns.substring(with: m.range(at: 2))
                guard seen.insert("f" + name).inserted else { return }
                let args = ns.substring(with: m.range(at: 3)).replacingOccurrences(of: "\n", with: " ")
                let compact = args.split(whereSeparator: { $0 == " " }).joined(separator: " ")
                let ret = m.range(at: 4).location != NSNotFound ? ns.substring(with: m.range(at: 4)) : ""
                let detail = "(" + compact + ")" + (ret.isEmpty ? "" : ": " + ret)
                let noArgs = compact.isEmpty
                out.append(CI.make(name, .method, detail: detail, insert: noArgs ? name + "()" : name + "($1)$0", snippet: !noArgs,
                                   sort: "a" + name, doc: "```php\n\(name)\(detail)\n```"))
            }
            propRegex.enumerateMatches(in: ns as String, range: full) { m, _, _ in
                guard let m else { return }
                let line = ns.substring(with: ns.lineRange(for: m.range))
                let isStatic = line.contains("static ")
                if staticOnly && !isStatic { return }
                let name = ns.substring(with: m.range(at: 1))
                guard seen.insert("p" + name).inserted else { return }
                out.append(CI.make(staticOnly ? "$" + name : name, .property, sort: "a" + name))
            }
        }
        constRegex.enumerateMatches(in: ns as String, range: full) { m, _, _ in
            guard let m else { return }
            let name = ns.substring(with: m.range(at: 1))
            if seen.insert("c" + name).inserted { out.append(CI.make(name, .constant, sort: "a" + name)) }
        }
        caseRegex.enumerateMatches(in: ns as String, range: full) { m, _, _ in
            guard let m else { return }
            let name = ns.substring(with: m.range(at: 1))
            if seen.insert("c" + name).inserted { out.append(CI.make(name, .enumMember, sort: "a" + name)) }
        }
        return out
    }
}

// MARK: - JavaScript / TypeScript

enum JSCompletion {
    static func generate(_ ctx: CompletionContext) -> [CompletionItem] {
        let inf = CompletionLex.info(ctx)
        guard inf.region == .js, CompletionLex.state(ctx) == .code else { return [] }
        let ns = ctx.text as NSString
        let p = ctx.prefixRange.location
        let ext = ctx.fileExtension.lowercased()
        let isTS = ext == "ts" || ext == "tsx" || ext == "vue" && (ns.range(of: "lang=\"ts\"").location != NSNotFound)
        if p > 0, ns.character(at: p - 1) == 46 {
            if p >= 2, ns.character(at: p - 2) == 46 { return [] }
            if p >= 2, let d = Unicode.Scalar(ns.character(at: p - 2)), CharacterSet.decimalDigits.contains(d) { return [] }
            let obj = CompletionLex.identBefore(ns, p - 1)
            if let list = CompletionData.jsMembers[obj] { return CI.members(list, sort: "a") }
            return CI.members(CompletionData.jsGenericMembers, sort: "z")
        }
        if ctx.prefix.isEmpty && !ctx.isManual { return [] }
        var out: [CompletionItem] = []
        for k in CompletionData.jsKeywords { out.append(CI.make(k, .keyword)) }
        if isTS { for k in CompletionData.tsKeywords { out.append(CI.make(k, .keyword, detail: "TypeScript")) } }
        for g in CompletionData.jsGlobals { out.append(CI.make(g, .variable, detail: "global")) }
        if ext == "jsx" || ext == "tsx" || ext == "js" || ext == "ts" { out += CI.members(CompletionData.reactHooks, kind: .function, sort: "n") }
        if ext == "vue" {
            out += CI.members(CompletionData.vueApi, kind: .function, sort: "n")
            if ns.range(of: "<script setup").location != NSNotFound { out += CI.members(CompletionData.vueMacros, kind: .function, sort: "a") }
        }
        return out
    }
}

// MARK: - HTML / Vue

enum HTMLCompletion {
    private static let boolAttrs: Set<String> = ["disabled", "required", "checked", "readonly", "hidden", "selected", "autofocus", "multiple",
                                                 "async", "defer", "controls", "autoplay", "loop", "muted", "novalidate", "allowfullscreen", "v-else", "v-once", "v-pre", "v-cloak", "playsinline"]

    static func generate(_ ctx: CompletionContext) -> [CompletionItem] {
        guard !NativeEngines.suppressesBuiltinCompletion(.html, for: ctx.fileURL) else { return [] }    // native HTML service (NativeHTMLService.swift) answers these files
        let inf = CompletionLex.info(ctx)
        guard inf.region == .html, CompletionLex.state(ctx) == .code else { return [] }
        let ns = ctx.text as NSString
        let caret = ctx.caret
        let ext = ctx.fileExtension.lowercased()
        let isVue = ext == "vue"
        let head = NSRange(location: max(0, caret - 4000), length: min(caret, 4000))
        let lt = ns.range(of: "<", options: [.backwards, .literal], range: head).location
        let gt = ns.range(of: ">", options: [.backwards, .literal], range: head).location
        guard lt != NSNotFound, gt == NSNotFound || lt > gt else { return [] }
        if lt + 1 < caret {
            let nx = ns.character(at: lt + 1)
            if !(CompletionLex.isIdent(nx) || nx == 47) { return [] }
        }
        let tagText = ns.substring(with: NSRange(location: lt + 1, length: caret - lt - 1))
        let nextIsGT = caret < ns.length && ns.character(at: caret) == 62
        // closing tag
        if tagText.hasPrefix("/") {
            guard !tagText.contains(" "), let open = openTag(ns, before: lt) else { return [] }
            let close = "</" + open + ">"
            return [CI.make(close, .keyword, detail: "close tag", filter: "</" + open, range: NSRange(location: lt, length: caret - lt))]
        }
        // tag name
        if !tagText.contains(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            guard ctx.prefixRange.location == lt + 1 || CompletionLex.runStart(ns, caret, floor: lt + 1, { CompletionLex.isIdent($0) || $0 == 45 }) == lt + 1 else { return [] }
            let range = NSRange(location: lt + 1, length: caret - lt - 1)
            return CompletionData.htmlTags.map { t in
                if nextIsGT || CompletionData.voidTags.contains(t) { return CI.make(t, .keyword, detail: "tag", insert: t, range: range) }
                return CI.make(t, .keyword, detail: "tag", insert: t + ">$0</" + t + ">", snippet: true, range: range)
            }
        }
        // inside a tag: attribute name or value
        let tagName = String(tagText.prefix(while: { $0 != " " && $0 != "\n" && $0 != "\t" })).lowercased()
        var quote: Character?
        var attr = ""
        var cur = ""
        for ch in tagText {
            if let q = quote {
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                attr = cur.split(whereSeparator: { $0 == "=" }).first.map(String.init) ?? ""
            } else if ch == " " || ch == "\n" || ch == "\t" {
                cur = ""
            } else { cur.append(ch) }
        }
        if quote != nil {
            let a = attr.lowercased()
            if a == "class" || a == ":class" || a == "classname" { return [] }
            guard let vals = CompletionData.htmlAttrValues[a] else { return [] }
            let s = CompletionLex.runStart(ns, caret, floor: lt) { $0 != 32 && $0 != 34 && $0 != 39 && $0 != 10 }
            return CompletionData.words(vals).map { CI.make($0, .value, detail: a, range: NSRange(location: s, length: caret - s)) }
        }
        let s = CompletionLex.runStart(ns, caret, floor: lt + 1) { CompletionLex.isIdent($0) || $0 == 45 || $0 == 58 || $0 == 64 || $0 == 35 || $0 == 46 }
        if s > lt, ns.character(at: s - 1) == 61 { return [] }       // right after `=`
        let range = NSRange(location: s, length: caret - s)
        var names: [String] = CompletionData.htmlGlobalAttrs
        if let t = CompletionData.htmlTagAttrs[tagName] { names += CompletionData.words(t) }
        if isVue { names += CompletionData.vueAttrs }
        var out: [CompletionItem] = []
        for n in names {
            if !n.hasSuffix("-") && !n.hasSuffix(":") && tagText.contains(" " + n + "=") { continue }
            let open = n.hasSuffix("-") || n.hasSuffix(":")
            let base = n.split(separator: ".").first.map(String.init) ?? n
            if boolAttrs.contains(base) || open {
                out.append(CI.make(n, .property, detail: "attribute", range: range))
            } else if n == "v-for" {
                out.append(CI.make(n, .property, detail: "Vue", insert: "v-for=\"${1:item} in ${2:items}\" :key=\"${3:item.id}\"", snippet: true, range: range))
            } else {
                let isDirective = n.hasPrefix("v-") || n.hasPrefix("@") || n.hasPrefix(":") || n.hasPrefix("#")
                out.append(CI.make(n, .property, detail: isDirective ? "Vue" : "attribute", insert: n + "=\"$1\"", snippet: true, range: range))
            }
        }
        return out
    }

    private static func isLetter(_ c: unichar) -> Bool { (c >= 97 && c <= 122) || (c >= 65 && c <= 90) }

    /// Innermost unclosed element before `end` (name), by a bounded forward scan.
    static func openTag(_ ns: NSString, before end: Int) -> String? {
        let from = max(0, end - 120_000)
        let n = end - from
        guard n > 0 else { return nil }
        var b = [unichar](repeating: 0, count: n)
        ns.getCharacters(&b, range: NSRange(location: from, length: n))
        var stack: [String] = []
        var i = 0
        func has(_ s: String, at k: Int) -> Bool {
            let u = Array(s.utf16)
            guard k + u.count <= n else { return false }
            for j in 0..<u.count where b[k + j] != u[j] { return false }
            return true
        }
        while i < n {
            guard b[i] == 60 else { i += 1; continue }
            if has("<!--", at: i) {
                var j = i + 4
                while j < n, !has("-->", at: j) { j += 1 }
                i = j + 3; continue
            }
            let closing = i + 1 < n && b[i + 1] == 47
            var j = i + (closing ? 2 : 1)
            guard j < n, isLetter(b[j]) else { i += 1; continue }
            let ns0 = j
            while j < n, CompletionLex.isIdent(b[j]) || b[j] == 45 || b[j] == 58 || b[j] == 46 { j += 1 }
            let name = String(utf16CodeUnits: Array(b[ns0..<j]), count: j - ns0)
            var q: unichar = 0
            while j < n {
                if q != 0 { if b[j] == q { q = 0 } }
                else if b[j] == 34 || b[j] == 39 { q = b[j] }
                else if b[j] == 62 { break }
                j += 1
            }
            guard j < n else { return stack.last }   // the tag containing nothing yet / truncated
            let selfClosing = j > 0 && b[j - 1] == 47
            let lower = name.lowercased()
            if closing {
                if let idx = stack.lastIndex(of: name) { stack.removeSubrange(idx...) }
            } else if !selfClosing && !CompletionData.voidTags.contains(lower) {
                if lower == "script" || lower == "style" {
                    var k = j + 1
                    while k < n, !has("</" + lower, at: k) { k += 1 }
                    if k >= n { stack.append(name); return stack.last }
                    j = k - 1
                    i = k; continue
                }
                stack.append(name)
            }
            i = j + 1
        }
        return stack.last
    }
}

// MARK: - Blade

enum BladeCompletion {
    static func generate(_ ctx: CompletionContext) -> [CompletionItem] {
        guard CompletionLex.isBlade(ctx) else { return [] }
        let inf = CompletionLex.info(ctx)
        guard inf.region == .html || inf.region == .js || inf.region == .css else { return [] }
        let ns = ctx.text as NSString
        let caret = ctx.caret
        let p = ctx.prefixRange.location
        if p > 0, ns.character(at: p - 1) == 64, inf.region == .html {
            let range = NSRange(location: p - 1, length: caret - (p - 1))
            return CI.lines(CompletionData.bladeDirectives).map { l in
                let parts = l.split(separator: "|", maxSplits: 1)
                let body = CI.expand(String(parts[1]))
                return CI.make("@" + parts[0], .keyword, detail: "Blade", insert: body, snippet: body.contains("$"), range: range)
            }
        }
        if caret > 0, ns.character(at: caret - 1) == 123 {        // `{` or `{{`
            var s = caret - 1
            if s > 0, ns.character(at: s - 1) == 123 { s -= 1 }
            var e = caret
            while e < ns.length, ns.character(at: e) == 125, e - caret < 2 { e += 1 }   // auto-paired closers
            let range = NSRange(location: s, length: e - s)
            let typed = ns.substring(with: NSRange(location: s, length: caret - s))
            var out = [CI.make("{{ }}", .snippet, detail: "echo (escaped)", insert: "{{ $1 }}", snippet: true, filter: "{{", range: range)]
            if typed == "{" { out.append(CI.make("{!! !!}", .snippet, detail: "echo (raw)", insert: "{!! $1 !!}", snippet: true, filter: "{!!", range: range)) }
            return out
        }
        return []
    }
}

// MARK: - CSS

enum CSSCompletion {
    static func generate(_ ctx: CompletionContext) -> [CompletionItem] {
        guard !NativeEngines.suppressesBuiltinCompletion(.css, for: ctx.fileURL) else { return [] }    // native CSS service (NativeCSSService.swift) answers these files
        let inf = CompletionLex.info(ctx)
        guard inf.region == .css, CompletionLex.state(ctx) != .comment else { return [] }
        let ns = ctx.text as NSString
        let caret = ctx.caret
        let lineB = CompletionLex.line(before: caret, ns)
        if lineB.contains("@apply") && !lineB.contains(";") { return [] }
        let p = ctx.prefixRange.location
        if p > 0, ns.character(at: p - 1) == 64 {
            let range = NSRange(location: p - 1, length: caret - (p - 1))
            return CompletionData.cssAtRules.map { CI.make($0, .keyword, detail: "at-rule", range: range) }
        }
        // brace depth + current statement
        let from = inf.start
        var depth = 0
        var stmtStart = from
        let n = caret - from
        if n > 0, n < 400_000 {
            var buf = [unichar](repeating: 0, count: n)
            ns.getCharacters(&buf, range: NSRange(location: from, length: n))
            var inStr: unichar = 0
            var i = 0
            while i < n {
                let c = buf[i]
                if inStr != 0 { if c == 92 { i += 1 } else if c == inStr { inStr = 0 } }
                else if c == 34 || c == 39 { inStr = c }
                else if c == 47, i + 1 < n, buf[i + 1] == 42 {
                    i += 2
                    while i + 1 < n, !(buf[i] == 42 && buf[i + 1] == 47) { i += 1 }
                    i += 1
                }
                else if c == 123 { depth += 1; stmtStart = from + i + 1 }
                else if c == 125 { depth = max(0, depth - 1); stmtStart = from + i + 1 }
                else if c == 59 { stmtStart = from + i + 1 }
                i += 1
            }
        }
        let isNameChar: (unichar) -> Bool = { CompletionLex.isIdent($0) || $0 == 45 }
        if depth > 0 {
            let stmt = ns.substring(with: NSRange(location: stmtStart, length: caret - stmtStart))
            if let colon = stmt.firstIndex(of: ":") {
                let prop = stmt[stmt.startIndex..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let s = CompletionLex.runStart(ns, caret, floor: stmtStart, isNameChar)
                let range = NSRange(location: s, length: caret - s)
                var vals = CompletionData.cssGlobalValues
                if let v = CompletionData.cssValues[prop] { vals = CompletionData.words(v) + vals }
                return vals.map { CI.make($0, .value, detail: prop, range: range) }
            }
            let s = CompletionLex.runStart(ns, caret, floor: stmtStart, isNameChar)
            let range = NSRange(location: s, length: caret - s)
            if ctx.prefixRange.length == 0 && !ctx.isManual && s == caret { return [] }
            return CompletionData.cssProperties.map {
                CI.make($0, .property, detail: "property", insert: $0 + ": $1;", snippet: true, range: range)
            }
        }
        if p > 0, ns.character(at: p - 1) == 58 {
            var s = p - 1
            if s > 0, ns.character(at: s - 1) == 58 { s -= 1 }
            let range = NSRange(location: s, length: caret - s)
            return CompletionData.cssPseudo.map { t in
                let hasParen = t.hasSuffix("()")
                return CI.make(t, .keyword, detail: "pseudo", insert: hasParen ? String(t.dropLast()) + "$1)" : t, snippet: hasParen, range: range)
            }
        }
        return []
    }
}

// MARK: - Tailwind

enum TailwindCompletion {
    private static let ctxRegex = try! NSRegularExpression(pattern:
        #"(?:(?:class|className|:class|\[class\]|v-bind:class|classes)\s*=\s*[{\[(]?\s*$)|(?:\b(?:cn|clsx|twMerge|classNames|cva|tw|twJoin)\(\s*(?:[^()]*,\s*)?$)"#)

    private static let spacing = words("0 0.5 1 1.5 2 2.5 3 3.5 4 5 6 7 8 9 10 11 12 14 16 20 24 28 32 36 40 44 48 52 56 60 64 72 80 96 px")
    private static let spacingProps = words("p px py pt pr pb pl ps pe m mx my mt mr mb ml ms me gap gap-x gap-y space-x space-y inset inset-x inset-y top right bottom left")
    private static let sizeProps = words("w h size min-w min-h max-h basis")
    private static let sizeValues = words("full screen auto min max fit 1/2 1/3 2/3 1/4 3/4 1/5 2/5 3/5 4/5 1/6 5/6 1/12 svh dvh lvh")
    private static let colors = words("slate gray zinc neutral stone red orange amber yellow lime green emerald teal cyan sky blue indigo violet purple fuchsia pink rose")
    private static let shades = words("50 100 200 300 400 500 600 700 800 900 950")
    private static let colorProps = words("bg text border ring from via to fill stroke divide outline decoration accent caret placeholder shadow border-t border-b border-l border-r border-x border-y ring-offset")
    private static let baseColors = words("white black transparent current inherit")
    private static let radii = words("none sm md lg xl 2xl 3xl full")
    private static let statics = words("""
    container block inline-block inline flex inline-flex grid inline-grid hidden contents flow-root table table-row table-cell static fixed absolute relative sticky \
    visible invisible collapse isolate flex-row flex-row-reverse flex-col flex-col-reverse flex-wrap flex-nowrap flex-wrap-reverse flex-1 flex-auto flex-initial flex-none \
    grow grow-0 shrink shrink-0 items-start items-end items-center items-baseline items-stretch justify-start justify-end justify-center justify-between justify-around \
    justify-evenly justify-items-center self-auto self-start self-end self-center self-stretch content-center content-start content-end place-content-center place-items-center \
    text-left text-center text-right text-justify text-start text-end uppercase lowercase capitalize normal-case underline overline line-through no-underline italic not-italic \
    truncate text-ellipsis text-clip text-wrap text-nowrap text-balance whitespace-normal whitespace-nowrap whitespace-pre whitespace-pre-wrap break-words break-all antialiased \
    overflow-auto overflow-hidden overflow-visible overflow-scroll overflow-x-auto overflow-y-auto overflow-x-hidden overflow-y-hidden object-contain object-cover object-fill \
    object-center rounded rounded-none rounded-full pointer-events-none pointer-events-auto cursor-pointer cursor-default cursor-not-allowed cursor-wait cursor-move cursor-grab \
    select-none select-all select-text resize resize-none outline-none outline outline-dashed border border-0 border-2 border-4 border-8 border-t border-b border-l border-r \
    border-x border-y border-solid border-dashed border-dotted border-none border-collapse shadow shadow-sm shadow-md shadow-lg shadow-xl shadow-2xl shadow-inner shadow-none \
    ring ring-0 ring-1 ring-2 ring-4 ring-inset transition transition-all transition-colors transition-opacity transition-shadow transition-transform transform ease-in ease-out \
    ease-in-out ease-linear sr-only not-sr-only list-none list-disc list-decimal appearance-none aspect-auto aspect-square aspect-video blur blur-sm blur-md blur-lg backdrop-blur \
    backdrop-blur-sm backdrop-blur-md grayscale invert sepia bg-cover bg-contain bg-center bg-no-repeat bg-repeat bg-fixed bg-clip-text bg-gradient-to-r bg-gradient-to-l \
    bg-gradient-to-t bg-gradient-to-b bg-gradient-to-tr bg-gradient-to-br bg-gradient-to-tl bg-gradient-to-bl bg-linear-to-r bg-linear-to-b mx-auto my-auto ml-auto mr-auto \
    mt-auto mb-auto w-full h-full z-auto font-sans font-serif font-mono animate-spin animate-ping animate-pulse animate-bounce line-clamp-none align-middle align-top align-bottom \
    align-baseline float-left float-right float-none clear-both box-border box-content scroll-smooth snap-x snap-y snap-start snap-center touch-none will-change-transform \
    fill-current stroke-current table-auto table-fixed tabular-nums prose
    """)
    private static let variants = words("hover focus active disabled visited first last odd even focus-within focus-visible group-hover group-focus peer-focus peer-checked placeholder before after dark sm md lg xl 2xl max-sm max-md max-lg max-xl motion-safe motion-reduce print rtl ltr selection marker file open empty checked required invalid first-letter aria-selected aria-expanded data-[state=open] has-[:checked] supports-[display:grid] *")

    private static func words(_ s: String) -> [String] { CompletionData.words(s) }

    static func generate(_ ctx: CompletionContext) -> [CompletionItem] {
        if NativeEngines.suppressesBuiltinCompletion(.tailwind, for: ctx.fileURL) { return [] }   // the project's real theme answers (NativeTailwind*.swift)
        let inf = CompletionLex.info(ctx)
        let ns = ctx.text as NSString
        let caret = ctx.caret
        guard caret > 0 else { return [] }
        let isTokenStop: (unichar) -> Bool = { $0 == 32 || $0 == 34 || $0 == 39 || $0 == 96 || $0 == 10 || $0 == 9 }
        let ts = CompletionLex.runStart(ns, caret) { !isTokenStop($0) }
        guard ts == 0 || isTokenStop(ns.character(at: ts - 1)) else { return [] }
        if inf.region == .css {
            let lineB = CompletionLex.line(before: caret, ns)
            guard let r = lineB.range(of: "@apply"), !lineB[r.upperBound...].contains(";") else { return [] }
        } else {
            // find the opening quote of the current string
            var q = ts - 1
            let floor = max(0, ts - 800)
            while q >= floor, !(ns.character(at: q) == 34 || ns.character(at: q) == 39 || ns.character(at: q) == 96) {
                let c = ns.character(at: q)
                if c == 62 || c == 60 || c == 59 { return [] }     // hit `>`/`<`/`;` before any quote: not in a string
                q -= 1
            }
            guard q >= floor else { return [] }
            let ctxStart = max(floor, q - 120)
            let before = ns.substring(with: NSRange(location: ctxStart, length: q - ctxStart))
            guard ctxRegex.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) != nil else { return [] }
        }
        let token = ns.substring(with: NSRange(location: ts, length: caret - ts))
        let tokenNS = token as NSString
        var variantEnd = 0
        let colon = tokenNS.range(of: ":", options: .backwards)
        if colon.location != NSNotFound { variantEnd = colon.upperBound }
        let variantPrefix = tokenNS.substring(to: variantEnd)
        var tail = tokenNS.substring(from: variantEnd).lowercased()
        if tail.hasPrefix("!") || tail.hasPrefix("-") { tail.removeFirst() }
        let bang = tokenNS.substring(from: variantEnd).hasPrefix("!") ? "!" : ""
        let q: [UInt8] = tail.utf8.allSatisfy({ $0 < 128 }) ? Array(tail.utf8) : []
        var names: [String] = []
        func add(_ s: String) { if CompletionLex.subsequence(q, in: s) { names.append(s) } }
        for s in statics { add(s) }
        for p in spacingProps { for v in spacing { add(p + "-" + v) } }
        for p in spacingProps where p.hasPrefix("m") || ["inset", "top", "right", "bottom", "left"].contains(p) { add(p + "-auto") }
        for p in sizeProps { for v in spacing + sizeValues { add(p + "-" + v) } }
        for v in words("none xs sm md lg xl 2xl 3xl 4xl 5xl 6xl 7xl full screen-sm screen-md screen-lg screen-xl prose min max fit") { add("max-w-" + v) }
        for v in words("xs sm base lg xl 2xl 3xl 4xl 5xl 6xl 7xl 8xl 9xl") { add("text-" + v) }
        for v in words("thin extralight light normal medium semibold bold extrabold black") { add("font-" + v) }
        for v in words("none tight snug normal relaxed loose 3 4 5 6 7 8 9 10") { add("leading-" + v) }
        for v in words("tighter tight normal wide wider widest") { add("tracking-" + v) }
        for r in words("t b l r tl tr bl br s e") { for v in radii { add("rounded-" + r + "-" + v) } }
        for v in radii { add("rounded-" + v) }
        for i in 1...12 { add("grid-cols-\(i)"); add("col-span-\(i)"); add("order-\(i)"); add("col-start-\(i)"); add("col-end-\(i)") }
        for i in 1...6 { add("grid-rows-\(i)"); add("row-span-\(i)"); add("line-clamp-\(i)") }
        add("col-span-full"); add("grid-cols-none"); add("order-first"); add("order-last")
        for v in words("0 10 20 30 40 50") { add("z-" + v) }
        for v in words("0 5 10 20 25 30 40 50 60 70 75 80 90 95 100") { add("opacity-" + v) }
        for v in words("75 100 150 200 300 500 700 1000") { add("duration-" + v); add("delay-" + v) }
        for v in words("0 50 75 90 95 100 105 110 125 150") { add("scale-" + v) }
        for v in words("0 1 2 3 6 12 45 90 180") { add("rotate-" + v) }
        for v in words("0 1 2 4 8") { add("border-" + v); add("ring-" + v); add("outline-" + v); add("divide-x-" + v); add("divide-y-" + v) }
        for v in words("sm md lg xl 2xl") { add("shadow-" + v); add("blur-" + v) }
        for v in baseColors { for p in colorProps.prefix(14) { add(p + "-" + v) } }
        for c in colors { for p in colorProps { for s in shades { add(p + "-" + c + "-" + s) } } }
        var out: [CompletionItem] = []
        let range = NSRange(location: ts, length: caret - ts)
        out.reserveCapacity(names.count + variants.count)
        for n in names {
            let isColor = n.contains("-red-") || n.contains("-blue-") || n.contains("-gray-") || n.hasPrefix("bg-") || n.hasPrefix("text-") && n.dropFirst(5).first?.isLetter == true && n.split(separator: "-").count > 2
            let label = variantPrefix + bang + n
            out.append(CI.make(label, isColor ? .color : .value, detail: "tailwind", sort: n, range: range))
        }
        if variantEnd == 0 {
            for v in variants where CompletionLex.subsequence(q, in: v + ":") {
                out.append(CI.make(v + ":", .keyword, detail: "variant", sort: "~" + v, range: range))
            }
        }
        return out
    }
}

// MARK: - Snippets

enum SnippetCompletion {
    private static let php: [(String, String, String)] = [
        ("foreach", "foreach loop", "foreach ($${1:items} as $${2:item}) {\n\t$0\n}"),
        ("foreachk", "foreach with key", "foreach ($${1:items} as $${2:key} => $${3:value}) {\n\t$0\n}"),
        ("for", "for loop", "for ($${1:i} = 0; $${1:i} < ${2:count}; $${1:i}++) {\n\t$0\n}"),
        ("if", "if", "if (${1:condition}) {\n\t$0\n}"),
        ("ifelse", "if / else", "if (${1:condition}) {\n\t$2\n} else {\n\t$0\n}"),
        ("elseif", "elseif", "elseif (${1:condition}) {\n\t$0\n}"),
        ("while", "while loop", "while (${1:condition}) {\n\t$0\n}"),
        ("switch", "switch", "switch ($${1:value}) {\n\tcase ${2:1}:\n\t\t$0\n\t\tbreak;\n\tdefault:\n\t\tbreak;\n}"),
        ("match", "match expression", "match ($${1:value}) {\n\t${2:1} => $0,\n\tdefault => null,\n}"),
        ("try", "try / catch", "try {\n\t$1\n} catch (${2:\\Exception} $${3:e}) {\n\t$0\n}"),
        ("fn", "arrow function", "fn($${1:x}) => $0"),
        ("fun", "function", "function ${1:name}($2)${3}\n{\n\t$0\n}"),
        ("pubf", "public function", "public function ${1:name}($2)\n{\n\t$0\n}"),
        ("prof", "protected function", "protected function ${1:name}($2)\n{\n\t$0\n}"),
        ("prif", "private function", "private function ${1:name}($2)\n{\n\t$0\n}"),
        ("pubsf", "public static function", "public static function ${1:name}($2)\n{\n\t$0\n}"),
        ("construct", "constructor", "public function __construct($1)\n{\n\t$0\n}"),
        ("class", "class", "class ${1:Name}\n{\n\t$0\n}"),
        ("interface", "interface", "interface ${1:Name}\n{\n\t$0\n}"),
        ("trait", "trait", "trait ${1:Name}\n{\n\t$0\n}"),
        ("enum", "enum", "enum ${1:Name}: string\n{\n\tcase ${2:Value} = '${3:value}';$0\n}"),
        ("route", "Laravel route", "Route::${1|get,post,put,patch,delete|}('${2:/uri}', [${3:Controller}::class, '${4:method}'])->name('${5:name}');"),
        ("routeg", "Laravel route group", "Route::middleware('${1:auth}')->group(function () {\n\t$0\n});"),
        ("ctrl", "Laravel controller", "<?php\n\nnamespace App\\Http\\Controllers;\n\nuse Illuminate\\Http\\Request;\n\nclass ${1:Name}Controller extends Controller\n{\n\tpublic function index()\n\t{\n\t\t$0\n\t}\n}\n"),
        ("model", "Eloquent model", "<?php\n\nnamespace App\\Models;\n\nuse Illuminate\\Database\\Eloquent\\Model;\n\nclass ${1:Name} extends Model\n{\n\tprotected \\$fillable = [$0];\n}\n"),
        ("dd", "dump and die", "dd($${1:var});"),
        ("pr", "print_r pre", "echo '<pre>'; print_r($${1:var}); echo '</pre>';"),
        ("php", "PHP open tag block", "<?php $0 ?>"),
    ]
    private static let js: [(String, String, String)] = [
        ("fori", "for loop", "for (let ${1:i} = 0; ${1:i} < ${2:array}.length; ${1:i}++) {\n\t$0\n}"),
        ("forof", "for...of", "for (const ${1:item} of ${2:items}) {\n\t$0\n}"),
        ("foreach", "array forEach", "${1:array}.forEach((${2:item}) => {\n\t$0\n})"),
        ("if", "if", "if (${1:condition}) {\n\t$0\n}"),
        ("ifelse", "if / else", "if (${1:condition}) {\n\t$2\n} else {\n\t$0\n}"),
        ("fn", "function", "function ${1:name}($2) {\n\t$0\n}"),
        ("af", "arrow function const", "const ${1:name} = ($2) => {\n\t$0\n}"),
        ("afn", "async function", "async function ${1:name}($2) {\n\t$0\n}"),
        ("clg", "console.log", "console.log($1)"),
        ("imp", "import", "import ${1:name} from '${2:module}'"),
        ("impn", "import named", "import { $1 } from '${2:module}'"),
        ("expd", "export default", "export default ${1:name}"),
        ("try", "try / catch", "try {\n\t$1\n} catch (${2:error}) {\n\t$0\n}"),
        ("prom", "new Promise", "new Promise((resolve, reject) => {\n\t$0\n})"),
        ("fetch", "fetch JSON", "const ${1:res} = await fetch(${2:url})\nconst ${3:data} = await ${1:res}.json()"),
        ("us", "useState", "const [${1:state}, set${2:State}] = useState(${3:initial})"),
        ("ue", "useEffect", "useEffect(() => {\n\t$1\n\treturn () => {\n\t\t$2\n\t}\n}, [$3])"),
        ("rfc", "React function component", "export default function ${1:Component}(${2:props}) {\n\treturn (\n\t\t<div>$0</div>\n\t)\n}"),
        ("switch", "switch", "switch (${1:value}) {\n\tcase ${2:1}:\n\t\t$0\n\t\tbreak\n\tdefault:\n\t\tbreak\n}"),
        ("st", "setTimeout", "setTimeout(() => {\n\t$0\n}, ${1:1000})"),
        ("class", "class", "class ${1:Name} {\n\tconstructor($2) {\n\t\t$0\n\t}\n}"),
    ]
    private static let html: [(String, String, String)] = [
        ("html5", "HTML5 document", "<!DOCTYPE html>\n<html lang=\"${1:en}\">\n<head>\n\t<meta charset=\"UTF-8\">\n\t<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n\t<title>${2:Document}</title>\n</head>\n<body>\n\t$0\n</body>\n</html>"),
        ("ul", "unordered list", "<ul>\n\t<li>$0</li>\n</ul>"),
        ("ol", "ordered list", "<ol>\n\t<li>$0</li>\n</ol>"),
        ("table", "table", "<table>\n\t<thead>\n\t\t<tr>\n\t\t\t<th>$1</th>\n\t\t</tr>\n\t</thead>\n\t<tbody>\n\t\t<tr>\n\t\t\t<td>$0</td>\n\t\t</tr>\n\t</tbody>\n</table>"),
        ("form", "form", "<form action=\"$1\" method=\"${2|post,get|}\">\n\t$0\n</form>"),
        ("vue-sfc", "Vue single-file component", "<script setup>\n$1\n</script>\n\n<template>\n\t<div>$0</div>\n</template>\n"),
        ("vfor", "Vue v-for element", "<${1:li} v-for=\"${2:item} in ${3:items}\" :key=\"${2:item}.id\">\n\t$0\n</${1:li}>"),
    ]

    static func generate(_ ctx: CompletionContext) -> [CompletionItem] {
        let inf = CompletionLex.info(ctx)
        guard CompletionLex.state(ctx) == .code else { return [] }
        let ns = ctx.text as NSString
        let p = ctx.prefixRange.location
        if ctx.prefix.isEmpty && !ctx.isManual { return [] }
        var table: [(String, String, String)]
        switch inf.region {
        case .php, .bladeExpr:
            if p > 0 {
                let c = ns.character(at: p - 1)
                if c == 36 || c == 62 || CompletionLex.before(ns, p, "::") { return [] }
            }
            table = php
        case .js:
            if p > 0, ns.character(at: p - 1) == 46 { return [] }
            table = js
        case .html:
            // only outside tags
            let lt = ns.range(of: "<", options: [.backwards, .literal], range: NSRange(location: max(0, ctx.caret - 2000), length: min(ctx.caret, 2000))).location
            let gt = ns.range(of: ">", options: [.backwards, .literal], range: NSRange(location: max(0, ctx.caret - 2000), length: min(ctx.caret, 2000))).location
            if lt != NSNotFound, gt == NSNotFound || lt > gt { return [] }
            table = html
        case .css: return []
        }
        let scopes = LiveTemplates.scopes(for: ctx)
        table = table.filter { !LiveTemplates.shared.has($0.0, scopes: scopes) }   // live templates shadow built-in snippets
        return table.map { CI.make($0.0, .snippet, detail: $0.1, insert: $0.2, snippet: true, sort: "s" + $0.0, doc: "```\n\($0.2)\n```") }
    }
}

// MARK: - Project symbols

final class SymbolCompletionProvider: CompletionProvider {
    let triggerCharacters: [String] = []
    private static let jsExts: Set<String> = ["js", "jsx", "mjs", "cjs", "ts", "tsx", "vue"]

    func cancel() {}

    func complete(_ ctx: CompletionContext, deliver: @escaping ([CompletionItem], Bool) -> Void) {
        deliver(generate(ctx), false)
    }

    private func generate(_ ctx: CompletionContext) -> [CompletionItem] {
        guard let source = CompletionSystem.symbolProvider else { return [] }
        let inf = CompletionLex.info(ctx)
        guard CompletionLex.state(ctx) == .code else { return [] }
        let ns = ctx.text as NSString
        let p = ctx.prefixRange.location
        let isPHP: Bool
        switch inf.region {
        case .php, .bladeExpr: isPHP = true
        case .js: isPHP = false
        default: return []
        }
        if ctx.prefix.isEmpty && !ctx.isManual { return [] }
        if p > 0 {
            let c = ns.character(at: p - 1)
            if c == 36 || c == 64 || c == 46 || CompletionLex.before(ns, p, "->") || CompletionLex.before(ns, p, "::") { return [] }
        }
        var q: [UInt8] = []
        for u in ctx.prefix.lowercased().utf8 { q.append(u) }
        if q.contains(where: { $0 >= 128 }) { q = [] }
        let entries = source()
        var out: [CompletionItem] = []
        var edit: (NSRange, String)?? = nil     // lazily computed `use` insertion anchor
        var existingUses: Set<String>?
        var currentNamespace: String?
        func ensureUseInfo() {
            if edit != nil { return }
            let a = Self.useAnchor(ns)
            edit = .some(a.map { ($0.range, $0.prefix) })
            existingUses = a?.uses ?? []
            currentNamespace = a?.namespace
        }
        for e in entries {
            let s = e.symbol
            let ext = (e.relativePath as NSString).pathExtension.lowercased()
            let fromPHP = ext == "php" || ext == "phtml"
            if fromPHP != isPHP { continue }
            let kind: CompletionKind
            switch s.kind {
            case .class: kind = .class
            case .interface: kind = .interface
            case .trait: kind = .class
            case .enum: kind = .enum
            case .function: kind = .function
            case .constant: kind = .constant
            default: continue
            }
            if s.kind == .constant, let c = s.container, !c.contains("\\") { continue }   // class constants
            if !CompletionLex.subsequence(q, in: s.name) { continue }
            var it = CI.make(s.name, kind, detail: s.container ?? e.relativePath, sort: "p" + s.name.lowercased(),
                             doc: "\(e.relativePath):\(s.line)")
            if s.kind == .function {
                it.insertText = s.name + "($1)$0"; it.isSnippet = true
            }
            if isPHP, s.isType, let ns0 = s.container, !ns0.isEmpty, !CompletionLex.isBlade(ctx) {
                ensureUseInfo()
                let fqn = ns0 + "\\" + s.name
                if let a = edit ?? nil, currentNamespace != ns0, !(existingUses?.contains(s.name) ?? false) {
                    it.additionalEdits = [(a.0, a.1 + "use \(fqn);")]
                    it.detail = ns0
                }
            }
            out.append(it)
            if out.count >= 600 { break }
        }
        return out
    }

    /// Where to insert a new `use` line: after the last top-level `use`, else the namespace / declare / open-tag line.
    static func useAnchor(_ ns: NSString) -> (range: NSRange, prefix: String, uses: Set<String>, namespace: String?)? {
        var loc = 0
        var anchor: (end: Int, kind: Int)?    // kind 0 = open tag/declare, 1 = namespace, 2 = use
        var uses = Set<String>()
        var namespace: String?
        var lines = 0
        let stop = ["class ", "final ", "abstract ", "interface ", "trait ", "enum ", "function ", "readonly "]
        while loc < ns.length, lines < 400 {
            var st = 0, en = 0, ce = 0
            ns.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: loc, length: 0))
            let line = ns.substring(with: NSRange(location: st, length: ce - st)).trimmingCharacters(in: .whitespaces)
            if stop.contains(where: { line.hasPrefix($0) }) { break }
            if line.hasPrefix("<?php") || line.hasPrefix("declare(") { if anchor == nil || anchor!.kind == 0 { anchor = (ce, 0) } }
            else if line.hasPrefix("namespace ") {
                anchor = (ce, 1)
                namespace = line.dropFirst(10).trimmingCharacters(in: CharacterSet(charactersIn: "; {"))
            } else if line.hasPrefix("use "), line.hasSuffix(";") {
                anchor = (ce, 2)
                let body = line.dropFirst(4).dropLast()
                let last = body.split(whereSeparator: { $0 == "\\" || $0 == " " }).last.map(String.init) ?? ""
                uses.insert(last)
            }
            if en <= loc { break }
            loc = en
            lines += 1
        }
        guard let a = anchor else { return nil }
        return (NSRange(location: a.end, length: 0), a.kind == 2 ? "\n" : "\n\n", uses, namespace)
    }
}
