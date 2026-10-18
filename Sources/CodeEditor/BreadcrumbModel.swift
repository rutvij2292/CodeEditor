import AppKit
import SwiftTreeSitter

/// What a symbol segment is (drives the icon). Code kinds reuse `CodeSymbol.Kind` icons.
enum BreadcrumbSymbolKind: String {
    case namespace, `class`, interface, trait, `enum`, function, method, property
    case tag, rule, key, heading, directive

    var iconName: String {
        if let code = CodeSymbol.Kind(rawValue: rawValue) { return code.iconName }
        switch self {
        case .tag: return "chevron.left.forwardslash.chevron.right"
        case .rule: return "number.square"
        case .key: return "k.square"
        case .heading: return "number"
        case .directive: return "at"
        default: return "circle"
        }
    }
}

/// One enclosing construct of the file (class, method, `@section`, JSON key, heading ...), in document order.
struct BreadcrumbNode: Equatable {
    var name: String
    var kind: BreadcrumbSymbolKind
    var range: NSRange          // UTF-16, the whole construct
    var line: Int               // 1-based first line
    var parent: Int             // index into the outline, -1 for top level
}

struct BreadcrumbOutline {
    var nodes: [BreadcrumbNode] = []

    /// Indices of the constructs enclosing `location`, outermost first.
    func chain(at location: Int) -> [Int] {
        var result: [Int] = []
        var parent = -1
        while true {
            var pick: Int?
            for (i, n) in nodes.enumerated() where n.parent == parent && n.range.location <= location {
                if pick == nil || n.range.location >= nodes[pick!].range.location { pick = i }
            }
            guard let p = pick, location <= NSMaxRange(nodes[p].range) else { break }
            result.append(p)
            parent = p
        }
        return result
    }

    func siblings(of index: Int) -> [Int] {
        let parent = nodes[index].parent
        return nodes.indices.filter { nodes[$0].parent == parent }
    }
}

/// Builds outlines. Heavy parts run off the main thread: the `Language` is resolved on the main thread by the caller.
enum BreadcrumbOutlineBuilder {
    static let maxNodes = 4000
    static let maxLength = 1_500_000

    /// Grammar keys that have a breadcrumb outline.
    static func supports(key: String?) -> Bool {
        guard let key else { return false }
        return ["php", "js", "ts", "tsx", "vue", "html", "css", "scss", "json", "md", "blade"].contains(key)
    }

    /// Main thread: grammars (for tree-sitter based kinds) that the background build needs.
    static func languages(for key: String) -> [String: Language] {
        var out: [String: Language] = [:]
        let keys = key == "vue" ? ["vue", "js", "ts"] : [key]
        for k in keys { if let l = Languages.grammar(forKey: k)?.language { out[k] = l } }
        return out
    }

    private static func parser(_ key: String, _ language: Language) -> Parser? {
        let dict = Thread.current.threadDictionary
        if let p = dict["ce.breadcrumbs.parser.\(key)"] as? Parser { return p }
        let p = Parser()
        do { try p.setLanguage(language) } catch { return nil }
        dict["ce.breadcrumbs.parser.\(key)"] = p
        return p
    }

    static func build(text: String, key: String, languages: [String: Language]) -> BreadcrumbOutline {
        guard (text as NSString).length <= maxLength else { return BreadcrumbOutline() }
        switch key {
        case "md": return BreadcrumbOutline(nodes: markdown(text))
        case "blade": return BreadcrumbOutline(nodes: blade(text))
        default: break
        }
        guard let language = languages[key], let p = parser(key, language),
              let tree = p.parse(text), let root = tree.rootNode else { return BreadcrumbOutline() }
        var w = Walker(text: text as NSString, key: key)
        w.languages = languages
        w.walk(root, parent: -1, depth: 0)
        return BreadcrumbOutline(nodes: w.nodes)
    }

    // MARK: Line scanners (Markdown, Blade)

    private static func lines(_ ns: NSString) -> [(range: NSRange, content: String)] {
        var out: [(NSRange, String)] = []
        var loc = 0
        while loc < ns.length {
            var st = 0, en = 0, ce = 0
            ns.getLineStart(&st, end: &en, contentsEnd: &ce, for: NSRange(location: loc, length: 0))
            out.append((NSRange(location: st, length: en - st), ns.substring(with: NSRange(location: st, length: ce - st))))
            loc = en
        }
        return out
    }

    static func markdown(_ text: String) -> [BreadcrumbNode] {
        let ns = text as NSString
        var nodes: [BreadcrumbNode] = []
        var stack: [(level: Int, index: Int)] = []
        var fence: String?
        for (i, line) in lines(ns).enumerated() {
            let t = line.content
            let trimmed = t.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if fence == nil { fence = marker } else if fence == marker { fence = nil }
                continue
            }
            if fence != nil { continue }
            let hashes = t.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes), t.dropFirst(hashes).first == " " else { continue }
            var title = t.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
            while title.hasSuffix("#") { title.removeLast() }
            title = title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            while let top = stack.last, top.level >= hashes {
                nodes[top.index].range.length = line.range.location - nodes[top.index].range.location
                stack.removeLast()
            }
            nodes.append(BreadcrumbNode(name: clip(title), kind: .heading,
                                        range: NSRange(location: line.range.location, length: ns.length - line.range.location),
                                        line: i + 1, parent: stack.last?.index ?? -1))
            stack.append((hashes, nodes.count - 1))
        }
        return nodes
    }

    /// Opening directive -> the directives that close it.
    private static let bladeBlocks: [String: Set<String>] = [
        "section": ["endsection", "show", "stop", "append", "overwrite"], "foreach": ["endforeach"], "forelse": ["endforelse"],
        "for": ["endfor"], "while": ["endwhile"], "if": ["endif"], "unless": ["endunless"], "isset": ["endisset"],
        "auth": ["endauth"], "guest": ["endguest"], "can": ["endcan"], "cannot": ["endcannot"],
        "env": ["endenv"], "production": ["endproduction"], "push": ["endpush"], "prepend": ["endprepend"],
        "pushonce": ["endpushonce"], "component": ["endcomponent"], "slot": ["endslot"], "switch": ["endswitch"],
        "once": ["endonce"], "verbatim": ["endverbatim"], "php": ["endphp"], "error": ["enderror"], "fragment": ["endfragment"],
        "session": ["endsession"],
    ]

    static func blade(_ text: String) -> [BreadcrumbNode] {
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: #"(?<![@\w])@(\w+)(?:[ \t]*(\((?:[^()\n]|\([^()\n]*\))*\)?))?"#) else { return [] }
        var nodes: [BreadcrumbNode] = []
        var stack: [(directive: String, index: Int)] = []
        for (i, line) in lines(ns).enumerated() {
            let content = line.content as NSString
            for m in regex.matches(in: line.content, range: NSRange(location: 0, length: content.length)) {
                let name = content.substring(with: m.range(at: 1))
                let args = m.range(at: 2).location == NSNotFound ? "" : content.substring(with: m.range(at: 2))
                let lower = name.lowercased()
                if let at = stack.lastIndex(where: { bladeBlocks[$0.directive]?.contains(lower) == true }) {
                    while stack.count > at {
                        let top = stack.removeLast()
                        nodes[top.index].range.length = NSMaxRange(line.range) - nodes[top.index].range.location
                    }
                    continue
                }
                guard bladeBlocks[lower] != nil else { continue }
                if lower == "section" || lower == "push" || lower == "prepend", args.contains(",") { continue }   // inline form, no body
                if lower == "php", !args.isEmpty { continue }                                                     // @php(...) inline
                if lower == "slot", args.isEmpty { continue }
                let label = clip(content.substring(with: m.range), 40)
                let start = line.range.location + m.range.location
                nodes.append(BreadcrumbNode(name: label, kind: .directive,
                                            range: NSRange(location: start, length: ns.length - start),
                                            line: i + 1, parent: stack.last?.index ?? -1))
                stack.append((lower, nodes.count - 1))
            }
        }
        return nodes
    }

    static func clip(_ s: String, _ n: Int = 48) -> String {
        let flat = s.split(whereSeparator: { $0.isNewline || $0 == "\t" }).joined(separator: " ")
        return flat.count <= n ? flat : String(flat.prefix(n - 1)) + "…"
    }

    // MARK: Tree-sitter walker

    private struct Walker {
        let text: NSString
        let key: String
        var languages: [String: Language] = [:]
        var nodes: [BreadcrumbNode] = []
        var lineOffset = 0, charOffset = 0      // for re-parsed Vue <script> blocks

        init(text: NSString, key: String) { self.text = text; self.key = key }

        func str(_ n: Node) -> String {
            let r = n.range
            guard r.location != NSNotFound, NSMaxRange(r) <= text.length else { return "" }
            return text.substring(with: r)
        }
        func field(_ n: Node, _ name: String) -> String? {
            n.child(byFieldName: name).map(str).flatMap { $0.isEmpty ? nil : $0 }
        }
        func firstNamed(_ n: Node, _ type: String) -> Node? {
            for i in 0..<n.namedChildCount { if let c = n.namedChild(at: i), c.nodeType == type { return c } }
            return nil
        }

        @discardableResult
        mutating func add(_ name: String, _ kind: BreadcrumbSymbolKind, _ n: Node, _ parent: Int, range: NSRange? = nil) -> Int {
            var r = range ?? n.range
            r.location += charOffset
            nodes.append(BreadcrumbNode(name: BreadcrumbOutlineBuilder.clip(name), kind: kind, range: r,
                                        line: Int(n.pointRange.lowerBound.row) + 1 + lineOffset, parent: parent))
            return nodes.count - 1
        }

        mutating func walk(_ n: Node, parent: Int, depth: Int) {
            guard nodes.count < BreadcrumbOutlineBuilder.maxNodes, depth < 200 else { return }
            let type = n.nodeType ?? ""
            var next = parent
            switch key {
            case "php": next = php(n, type, parent)
            case "js", "ts", "tsx": next = js(n, type, parent)
            case "json": next = json(n, type, parent)
            case "css", "scss": next = css(n, type, parent)
            case "html": next = html(n, type, parent)
            case "vue": next = vue(n, type, parent)
            default: break
            }
            if next == -2 { return }
            if key == "php", type == "program" || type == "compound_statement" { phpChildren(n, parent: next, depth: depth); return }
            if key == "vue", type == "script_element" { return }
            for i in 0..<n.namedChildCount { if let c = n.namedChild(at: i) { walk(c, parent: next, depth: depth + 1) } }
        }

        // PHP -------------------------------------------------------------

        /// Children of a `program`; a `namespace X;` (no body) owns everything after it up to the next namespace.
        mutating func phpChildren(_ n: Node, parent: Int, depth: Int) {
            var owner = parent
            var implicit: Int?
            for i in 0..<n.namedChildCount {
                guard let c = n.namedChild(at: i) else { continue }
                if c.nodeType == "namespace_definition", c.child(byFieldName: "body") == nil, let name = field(c, "name") {
                    if let implicit { nodes[implicit].range.length = c.range.location - nodes[implicit].range.location }
                    var r = c.range
                    r.length = text.length - r.location
                    implicit = add(name, .namespace, c, parent, range: r)
                    owner = implicit!
                    continue
                }
                walk(c, parent: owner, depth: depth + 1)
            }
        }

        mutating func php(_ n: Node, _ type: String, _ parent: Int) -> Int {
            switch type {
            case "namespace_definition":
                if n.child(byFieldName: "body") != nil, let name = field(n, "name") { return add(name, .namespace, n, parent) }
            case "class_declaration": if let s = field(n, "name") { return add(s, .class, n, parent) }
            case "interface_declaration": if let s = field(n, "name") { return add(s, .interface, n, parent) }
            case "trait_declaration": if let s = field(n, "name") { return add(s, .trait, n, parent) }
            case "enum_declaration": if let s = field(n, "name") { return add(s, .enum, n, parent) }
            case "anonymous_class": return add("class@anonymous", .class, n, parent)
            case "method_declaration": if let s = field(n, "name") { return add(s + "()", .method, n, parent) }
            case "function_definition": if let s = field(n, "name") { return add(s + "()", .function, n, parent) }
            case "assignment_expression":
                if let r = n.child(byFieldName: "right"),
                   ["anonymous_function", "anonymous_function_creation_expression", "arrow_function"].contains(r.nodeType ?? ""),
                   let l = n.child(byFieldName: "left") {
                    return add(str(l) + "()", .function, n, parent)
                }
            default: break
            }
            return parent
        }

        // JS / TS ---------------------------------------------------------

        static let jsFunctions: Set<String> = ["arrow_function", "function_expression", "function", "generator_function"]

        mutating func js(_ n: Node, _ type: String, _ parent: Int) -> Int {
            switch type {
            case "class_declaration", "abstract_class_declaration", "class":
                if let s = field(n, "name") { return add(s, .class, n, parent) }
            case "interface_declaration": if let s = field(n, "name") { return add(s, .interface, n, parent) }
            case "enum_declaration": if let s = field(n, "name") { return add(s, .enum, n, parent) }
            case "function_declaration", "generator_function_declaration":
                if let s = field(n, "name") { return add(s + "()", .function, n, parent) }
            case "method_definition":
                if let s = field(n, "name") { return add(s + "()", .method, n, parent) }
            case "variable_declarator":
                if let v = n.child(byFieldName: "value"), let name = field(n, "name") {
                    if Self.jsFunctions.contains(v.nodeType ?? "") { return add(name + "()", .function, n, parent) }
                    if v.nodeType == "class" { return add(name, .class, n, parent) }
                }
            case "public_field_definition", "field_definition":
                if let v = n.child(byFieldName: "value"), Self.jsFunctions.contains(v.nodeType ?? ""),
                   let name = field(n, "name") ?? field(n, "property") { return add(name + "()", .method, n, parent) }
            case "pair":
                if let v = n.child(byFieldName: "value"), Self.jsFunctions.contains(v.nodeType ?? ""), let k = field(n, "key") {
                    return add(k.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) + "()", .method, n, parent)
                }
            default: break
            }
            return parent
        }

        // JSON ------------------------------------------------------------

        mutating func json(_ n: Node, _ type: String, _ parent: Int) -> Int {
            if type == "pair", let k = n.child(byFieldName: "key") {
                return add(str(k).trimmingCharacters(in: CharacterSet(charactersIn: "\"")), .key, n, parent)
            }
            if type == "array" {
                // Index nodes exist for elements that are objects/arrays (so `items › [2] › name` works).
                var idx = 0
                for i in 0..<n.namedChildCount {
                    guard let c = n.namedChild(at: i), c.nodeType != "comment" else { continue }
                    if c.nodeType == "object" || c.nodeType == "array" {
                        let at = add("[\(idx)]", .key, c, parent)
                        for j in 0..<c.namedChildCount { if let g = c.namedChild(at: j) { walk(g, parent: at, depth: 100) } }
                    }
                    idx += 1
                }
                return -2           // children already handled
            }
            return parent
        }

        // CSS / SCSS ------------------------------------------------------

        static let cssBlocks: Set<String> = ["rule_set", "media_statement", "at_rule", "keyframes_statement", "supports_statement",
                                             "mixin_statement", "function_statement", "keyframe_block"]

        mutating func css(_ n: Node, _ type: String, _ parent: Int) -> Int {
            guard Self.cssBlocks.contains(type) else { return parent }
            var head = str(n)
            if let brace = head.firstIndex(of: "{") { head = String(head[..<brace]) }
            else if let semi = head.firstIndex(of: ";") { head = String(head[..<semi]) }
            head = head.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !head.isEmpty else { return parent }
            return add(head, .rule, n, parent)
        }

        // HTML ------------------------------------------------------------

        mutating func html(_ n: Node, _ type: String, _ parent: Int) -> Int {
            guard type == "element" || type == "script_element" || type == "style_element" else { return parent }
            return add(elementLabel(n), .tag, n, parent)
        }

        func elementLabel(_ n: Node) -> String {
            guard let start = firstNamed(n, "start_tag") ?? firstNamed(n, "self_closing_tag") ?? n.namedChild(at: 0),
                  let tag = firstNamed(start, "tag_name") else { return "element" }
            var label = str(tag)
            for i in 0..<start.namedChildCount {
                guard let a = start.namedChild(at: i), a.nodeType == "attribute" else { continue }
                let s = str(a)
                for (prefix, mark) in [("id=", "#"), ("class=", ".")] where s.hasPrefix(prefix) {
                    let v = s.dropFirst(prefix.count).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    label += mark == "." ? "." + (v.split(separator: " ").first.map(String.init) ?? v) : "#" + v
                }
            }
            return label
        }

        // Vue -------------------------------------------------------------

        mutating func vue(_ n: Node, _ type: String, _ parent: Int) -> Int {
            switch type {
            case "template_element": return add("template", .tag, n, parent)
            case "element": return add(elementLabel(n), .tag, n, parent)
            case "style_element": return add("style", .tag, n, parent)
            case "script_element":
                let idx = add("script", .tag, n, parent)
                if let raw = firstNamed(n, "raw_text") {
                    let head = firstNamed(n, "start_tag").map(str) ?? ""
                    let isTS = head.contains("lang=\"ts\"") || head.contains("lang='ts'") || head.contains("lang=\"tsx\"")
                    let sub = str(raw)
                    let jsKey = isTS ? "ts" : "js"
                    if let language = languages[jsKey], let p = BreadcrumbOutlineBuilder.parser(jsKey, language),
                       let tree = p.parse(sub), let r = tree.rootNode {
                        var inner = Walker(text: sub as NSString, key: jsKey)
                        inner.lineOffset = Int(raw.pointRange.lowerBound.row)
                        inner.charOffset = raw.range.location
                        inner.walk(r, parent: -1, depth: 0)
                        let base = nodes.count
                        for var m in inner.nodes {
                            m.parent = m.parent < 0 ? idx : m.parent + base
                            nodes.append(m)
                        }
                    }
                }
                return idx
            default: return parent
            }
        }
    }
}
