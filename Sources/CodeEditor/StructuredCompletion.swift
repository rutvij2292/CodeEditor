import Foundation

/// Context-aware key / value completion for YAML (docker-compose / Sail, GitHub Actions workflows, any YAML via keys already
/// used in the file) and JSON (package.json, composer.json, tsconfig.json, .eslintrc). Key vs value is decided from the
/// indentation (YAML) or a small tokenizer (JSON); tables live in StructuredSchemas.swift. Everything is offline and synchronous.
enum StructuredCompletion {
    static func register() {
        CompletionRegistry.register(StructuredProvider(), forExtensions: ["yml", "yaml", "json", "jsonc", "json5", ""])
    }

    static func items(for ctx: CompletionContext) -> [CompletionItem] {
        let ext = ctx.fileExtension.lowercased()
        if ext == "yml" || ext == "yaml" { return yamlItems(ctx) }
        return jsonItems(ctx)
    }

    // MARK: - YAML context

    struct YLine {
        var indent = 0
        var dash = false
        var keyCol = 0
        var key: String?
        var value: String?
        var blank = true
        var docSep = false
    }

    struct YAMLCtx {
        enum Pos { case none, key, value }
        var pos = Pos.none
        var path: [String] = []
        var parents: [(key: String, col: Int, line: Int)] = []
        var key: String?
        var prefixRange = NSRange(location: 0, length: 0)
        var prefix = ""
        var inSeqItem = false
        var keyCol = 0
        var lineIndex = 0
        var siblings: [String: String] = [:]
        var afterColonNoSpace = false
        var inExpression = false
        var flow = false
    }

    private static func unquote(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, let f = t.first, (f == "\"" || f == "'"), t.last == f { t = String(t.dropFirst().dropLast()) }
        return t
    }

    /// Splits a line into indentation, sequence dashes, key and value. Quotes and flow brackets are respected.
    static func parseLine(_ line: String) -> YLine {
        var l = YLine()
        let u = Array(line.utf16)
        var i = 0
        while i < u.count, u[i] == 32 { i += 1 }
        l.indent = i
        guard i < u.count else { return l }
        if u[i] == 35 { return l }                                    // comment
        l.blank = false
        if i == 0, line.hasPrefix("---") || line.hasPrefix("...") { l.docSep = true; return l }
        while i < u.count, u[i] == 45, i + 1 == u.count || u[i + 1] == 32 {
            l.dash = true
            i += 1
            while i < u.count, u[i] == 32 { i += 1 }
        }
        l.keyCol = i
        var q: UInt16 = 0
        var depth = 0
        var j = i
        while j < u.count {
            let c = u[j]
            if q != 0 { if c == q { q = 0 }; j += 1; continue }
            if c == 34 || c == 39 { if j == i || u[j - 1] == 32 || u[j - 1] == 91 || u[j - 1] == 123 || u[j - 1] == 44 { q = c }; j += 1; continue }
            if c == 91 || c == 123 { depth += 1 } else if c == 93 || c == 125 { depth = max(0, depth - 1) }
            else if c == 35, j > i, u[j - 1] == 32 { break }           // trailing comment
            else if c == 58, depth == 0, j + 1 == u.count || u[j + 1] == 32 {
                let k = String(utf16CodeUnits: Array(u[i..<j]), count: j - i)
                l.key = unquote(k)
                var rest = String(utf16CodeUnits: Array(u[(j + 1)...]), count: u.count - j - 1)
                if let r = rest.range(of: " #") { rest = String(rest[..<r.lowerBound]) }
                let v = rest.trimmingCharacters(in: .whitespaces)
                l.value = v.isEmpty ? nil : v
                return l
            }
            j += 1
        }
        let rest = String(utf16CodeUnits: Array(u[i..<min(j, u.count)]), count: min(j, u.count) - i).trimmingCharacters(in: .whitespaces)
        l.value = rest.isEmpty ? nil : rest
        return l
    }

    private static func lineIndex(_ ns: NSString, _ caret: Int) -> (idx: Int, start: Int) {
        var idx = 0, start = 0
        var i = 0
        while i < caret {
            if ns.character(at: i) == 10 { idx += 1; start = i + 1 }
            i += 1
        }
        return (idx, start)
    }

    static func yamlContext(_ text: String, caret: Int) -> YAMLCtx {
        let ns = text as NSString
        let caret = max(0, min(caret, ns.length))
        let (li, ls) = lineIndex(ns, caret)
        var ctx = YAMLCtx()
        ctx.prefixRange = NSRange(location: caret, length: 0)
        ctx.lineIndex = li
        let before = ns.substring(with: NSRange(location: ls, length: caret - ls))
        let u = Array(before.utf16)
        // inside a comment?
        var qc: UInt16 = 0
        for (k, c) in u.enumerated() {
            if qc != 0 { if c == qc { qc = 0 }; continue }
            if c == 34 || c == 39 { if k == 0 || u[k - 1] == 32 || u[k - 1] == 58 || u[k - 1] == 91 || u[k - 1] == 44 { qc = c }; continue }
            if c == 35, k == 0 || u[k - 1] == 32 { return ctx }
        }
        if before.hasPrefix("---") || before.hasPrefix("...") { return ctx }
        var i = 0
        while i < u.count, u[i] == 32 { i += 1 }
        var dashCol = -1
        while i < u.count, u[i] == 45, i + 1 < u.count, u[i + 1] == 32 {
            dashCol = i
            i += 1
            while i < u.count, u[i] == 32 { i += 1 }
        }
        if i == u.count, dashCol < 0, !u.isEmpty, u.allSatisfy({ $0 == 32 }) { /* empty indented line: key position */ }
        if i < u.count, u[i] == 45, i + 1 == u.count { return ctx }              // "-" without its space yet
        let keyCol = i
        ctx.keyCol = keyCol
        let lines = text.components(separatedBy: "\n")
        // key separator before the caret
        var q: UInt16 = 0
        var depth = 0
        var colon: Int?
        var j = i
        while j < u.count {
            let c = u[j]
            if q != 0 { if c == q { q = 0 }; j += 1; continue }
            if c == 34 || c == 39 { if j == i || u[j - 1] == 32 || u[j - 1] == 91 || u[j - 1] == 123 || u[j - 1] == 44 { q = c }; j += 1; continue }
            if c == 91 || c == 123 { depth += 1 } else if c == 93 || c == 125 { depth = max(0, depth - 1) }
            else if c == 58, depth == 0, j + 1 == u.count || u[j + 1] == 32 { colon = j; break }
            j += 1
        }
        func str(_ a: Int, _ b: Int) -> String { b > a ? String(utf16CodeUnits: Array(u[a..<b]), count: b - a) : "" }
        if let colon {
            let key = unquote(str(keyCol, colon))
            guard !key.isEmpty else { return ctx }
            var vs = colon + 1
            while vs < u.count, u[vs] == 32 { vs += 1 }
            ctx.afterColonNoSpace = colon + 1 == u.count
            var prefixStart = vs
            let value = str(vs, u.count)
            if let r = value.range(of: "${{", options: .backwards), !value[r.upperBound...].contains("}}") { ctx.inExpression = true }
            if value.hasPrefix("[") || value.hasPrefix("{") {
                ctx.flow = true
                var k = u.count
                while k > vs, ![91, 123, 44].contains(u[k - 1]) { k -= 1 }
                prefixStart = k
                while prefixStart < u.count, u[prefixStart] == 32 { prefixStart += 1 }
            } else if let f = value.first, f == "\"" || f == "'", value.dropFirst().firstIndex(of: f) == nil {
                prefixStart = vs + 1
            }
            ctx.pos = .value
            ctx.key = key
            ctx.prefixRange = NSRange(location: ls + prefixStart, length: u.count - prefixStart)
            ctx.prefix = str(prefixStart, u.count)
            ctx.parents = parents(lines, line: li, bound: keyCol)
            ctx.path = ctx.parents.map(\.key)
            ctx.siblings = siblings(lines, line: li, keyCol: keyCol)
            return ctx
        }
        let typed = str(i, u.count)
        if typed.contains(" "), !typed.hasPrefix("\"") , !typed.hasPrefix("'") { return ctx }
        ctx.pos = .key
        ctx.prefix = typed
        ctx.prefixRange = NSRange(location: ls + i, length: u.count - i)
        if dashCol >= 0 {
            ctx.inSeqItem = true
            ctx.parents = parents(lines, line: li, bound: dashCol + 1)
        } else {
            ctx.parents = parents(lines, line: li, bound: keyCol)
            ctx.siblings = siblings(lines, line: li, keyCol: keyCol)
        }
        ctx.path = ctx.parents.map(\.key)
        return ctx
    }

    /// Enclosing keys by indentation: nearest line above with a smaller key column and no inline value, repeatedly.
    static func parents(_ lines: [String], line: Int, bound: Int) -> [(key: String, col: Int, line: Int)] {
        var out: [(String, Int, Int)] = []
        var b = bound
        var i = min(line, lines.count) - 1
        while i >= 0, b > 0 {
            let l = parseLine(lines[i])
            if l.docSep { break }
            if !l.blank, let k = l.key, l.keyCol < b, l.value == nil {
                out.insert((k, l.keyCol, i), at: 0)
                b = l.keyCol
            }
            i -= 1
        }
        return out
    }

    /// key -> value of the keys in the same mapping as `line` (same column), excluding the line itself.
    static func siblings(_ lines: [String], line: Int, keyCol: Int) -> [String: String] {
        var out: [String: String] = [:]
        var i = line - 1
        while i >= 0 {
            let l = parseLine(lines[i])
            i -= 1
            if l.docSep { break }
            if l.blank { continue }
            if let k = l.key, l.keyCol == keyCol { out[k] = l.value ?? ""; if l.dash { break }; continue }
            if (l.key != nil ? l.keyCol : l.indent) < keyCol { break }
        }
        i = line + 1
        while i < lines.count {
            let l = parseLine(lines[i])
            i += 1
            if l.docSep { break }
            if l.blank { continue }
            if l.dash, l.indent < keyCol { break }
            if let k = l.key, l.keyCol == keyCol, !l.dash { out[k] = l.value ?? ""; continue }
            if (l.key != nil ? l.keyCol : l.indent) < keyCol { break }
        }
        return out
    }

    /// Keys under a top-level key (e.g. the service names under `services:`).
    static func topLevelChildren(_ lines: [String], of top: String) -> [String] {
        guard let start = lines.firstIndex(where: { let l = parseLine($0); return l.key == top && l.keyCol == 0 && !l.dash && l.value == nil }) else { return [] }
        var col: Int?
        var out: [String] = []
        for line in lines[(start + 1)...] {
            let l = parseLine(line)
            if l.blank { continue }
            if l.docSep || (l.key != nil && l.keyCol == 0 && !l.dash) || (l.indent == 0 && !l.dash) { break }
            guard let k = l.key else { continue }
            if col == nil { col = l.keyCol }
            if l.keyCol == col, !l.dash { out.append(k) }
        }
        return out
    }

    // MARK: - YAML items

    private static func item(_ label: String, insert: String? = nil, kind: CompletionKind, detail: String = "", doc: String = "", sort: String, range: NSRange) -> CompletionItem {
        CI.make(label, kind, detail: detail, insert: insert, sort: sort + label.lowercased(), doc: doc, range: range)
    }

    static func yamlItems(_ cc: CompletionContext) -> [CompletionItem] {
        let c = yamlContext(cc.text, caret: cc.caret)
        guard c.pos != .none else { return [] }
        let schema = SchemaTable.forFile(cc.fileURL)
        let lines = cc.text.components(separatedBy: "\n")
        let isWorkflow = cc.fileURL.standardizedFileURL.path.contains("/.github/workflows/")
        var out: [CompletionItem] = []
        var seen = Set<String>()
        func add(_ it: CompletionItem) { if seen.insert(it.label + it.kind.rawValue).inserted { out.append(it) } }
        let range = c.prefixRange

        // ${{ }} expressions (GitHub Actions)
        if c.pos == .value, c.inExpression, isWorkflow {
            return expressionItems(prefix: c.prefix, range: range)
        }

        switch c.pos {
        case .key:
            let node = schema?.walk(c.path)
            var scalarList = false
            if c.inSeqItem, let node, node.children.isEmpty { scalarList = true }
            if scalarList, let node {
                for v in listValues(node) { add(valueItem(v, c, range: range)) }
                for n in referencedNames(path: c.path, lines: lines, isWorkflow: isWorkflow) { add(valueItem(n, c, range: range)) }
                for v in genericValues(lines, key: c.path.last ?? "", exclude: seen) { add(valueItem(v, c, range: range, generic: true)) }
                return out
            }
            if let node {
                // `with:` of a known action
                if c.path.last == "with", isWorkflow, let p = c.parents.last {
                    let sib = siblings(lines, line: p.line, keyCol: p.col)
                    if let uses = sib["uses"] {
                        let action = unquote(uses).components(separatedBy: "@").first ?? ""
                        for name in (StructuredSchemas.actionInputs[action] ?? "").split(separator: "|") where c.siblings[String(name)] == nil {
                            add(item(String(name), insert: name + ": ", kind: .property, detail: action, sort: "0", range: range))
                        }
                    }
                }
                let named = node.named
                for ch in named where c.siblings[ch.key] == nil {
                    let hasValues = !ch.values.isEmpty
                    let container = !ch.children.isEmpty
                    let kind: CompletionKind = hasValues && !container ? .keyword : .property
                    let ins = hasValues && !container ? ch.key + ":" : (container ? ch.key + ":" : ch.key + ": ")
                    add(item(ch.key, insert: c.inSeqItem && node.kv ? ch.key + "=" : ins, kind: kind,
                             detail: container ? "mapping" : (hasValues ? "enum" : "value"), doc: ch.doc, sort: "0", range: range))
                }
                // names defined elsewhere in the file
                for n in referencedNames(path: c.path, lines: lines, isWorkflow: isWorkflow) where c.siblings[n] == nil {
                    add(item(n, insert: n + ":", kind: .keyword, detail: "defined in this file", sort: "1", range: range))
                }
                if node.key == "services" || (c.path == ["services"]) {
                    for (name, doc) in sailServices { add(item(name, insert: name + ":", kind: .module, detail: "common service", doc: doc, sort: "2", range: range)) }
                }
                if let pkg = packageSuggestions(path: c.path, file: cc.fileURL) {
                    for p in pkg where c.siblings[p] == nil { add(item(p, insert: p + ": ", kind: .module, detail: "package", sort: "2", range: range)) }
                }
            }
            for k in genericKeys(lines, exclude: Set(c.siblings.keys)) { add(item(k, insert: k + ":", kind: .property, detail: "used in this file", sort: "8", range: range)) }
        case .value:
            let key = c.key ?? ""
            let parentNode = schema?.walk(c.path)
            var values = parentNode?.child(key)?.values ?? []
            if values.isEmpty, let w = parentNode?.wildcard { values = w.values }
            for v in values { add(valueItem(v, c, range: range)) }
            for n in referencedNames(path: c.path + [key], lines: lines, isWorkflow: isWorkflow) { add(valueItem(n, c, range: range)) }
            for v in genericValues(lines, key: key, exclude: seen) { add(valueItem(v, c, range: range, generic: true)) }
        case .none: break
        }
        return out
    }

    private static func valueItem(_ v: String, _ c: YAMLCtx, range: NSRange, generic: Bool = false) -> CompletionItem {
        let text = (c.afterColonNoSpace && c.pos == .value ? " " : "") + v
        let item = CI.make(v, .enumMember, detail: generic ? "used in this file" : "value", insert: text, sort: (generic ? "8" : "0") + v.lowercased(), range: range)
        var it = item
        it.filterText = v
        return it
    }

    private static func listValues(_ node: SchemaNode) -> [String] {
        var vals = node.values
        if vals.isEmpty, node.kv { vals = node.named.map { $0.key + "=" } }
        return vals
    }

    /// Service / job / network names defined in the file that the current key refers to.
    private static func referencedNames(path: [String], lines: [String], isWorkflow: Bool) -> [String] {
        guard let last = path.last else { return [] }
        if isWorkflow {
            if last == "needs" { return topLevelChildren(lines, of: "jobs") }
            return []
        }
        switch last {
        case "depends_on", "links", "extends": return topLevelChildren(lines, of: "services")
        case "networks": return path.count > 1 ? topLevelChildren(lines, of: "networks") : []
        case "volumes": return path.count > 1 ? topLevelChildren(lines, of: "volumes").map { $0 + ":" } : []
        default: return []
        }
    }

    private static func packageSuggestions(path: [String], file: URL) -> [String]? {
        guard file.lastPathComponent == "package.json", let last = path.last,
              ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"].contains(last) else { return nil }
        return StructuredSchemas.npmPackages.split(separator: "|").map(String.init)
    }

    /// Distinct keys used anywhere in the file (and its other YAML documents), most frequent first.
    static func genericKeys(_ lines: [String], exclude: Set<String>) -> [String] {
        var count: [String: Int] = [:]
        for line in lines {
            let l = parseLine(line)
            if let k = l.key, !k.isEmpty, k.count < 48, !exclude.contains(k) { count[k, default: 0] += 1 }
        }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(40).map(\.key)
    }

    static func genericValues(_ lines: [String], key: String, exclude: Set<String>) -> [String] {
        guard !key.isEmpty else { return [] }
        var count: [String: Int] = [:]
        for line in lines {
            let l = parseLine(line)
            if l.key == key, let v = l.value, v.count < 60, !v.hasPrefix("["), !v.hasPrefix("{"), !v.hasPrefix("|"), !v.hasPrefix(">"), !v.hasPrefix("&"), !v.hasPrefix("*") { count[v, default: 0] += 1 }
        }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(15).map(\.key)
    }

    private static let sailServices: [(String, String)] = [
        ("laravel.test", "Laravel Sail application container"), ("mysql", "MySQL database"), ("mariadb", "MariaDB database"),
        ("pgsql", "PostgreSQL database"), ("redis", "Redis"), ("valkey", "Valkey (Redis fork)"), ("memcached", "Memcached"),
        ("meilisearch", "Meilisearch full-text search"), ("typesense", "Typesense search"), ("minio", "MinIO S3-compatible storage"),
        ("mailpit", "Mailpit mail catcher"), ("selenium", "Selenium for Dusk browser tests"), ("soketi", "Soketi WebSocket server"),
        ("nginx", "Nginx web server"), ("php", "PHP-FPM"), ("queue", "Queue worker"), ("scheduler", "Scheduler"), ("node", "Node / Vite dev server"),
    ]

    private static let exprRoots: [(String, String)] = [
        ("github", "Workflow run context"), ("env", "Environment variables"), ("vars", "Repository variables"), ("job", "Current job"),
        ("jobs", "Reusable workflow jobs"), ("steps", "Step outputs"), ("runner", "Runner context"), ("secrets", "Secrets"),
        ("strategy", "Matrix strategy"), ("matrix", "Matrix values"), ("needs", "Outputs of needed jobs"), ("inputs", "Workflow inputs"),
    ]
    private static let exprMembers: [String: [String]] = [
        "github": ["actor", "action", "base_ref", "event", "event_name", "event_path", "head_ref", "job", "ref", "ref_name", "ref_type", "repository",
                   "repository_owner", "run_attempt", "run_id", "run_number", "server_url", "sha", "token", "workflow", "workspace", "triggering_actor"],
        "runner": ["os", "arch", "name", "temp", "tool_cache"],
        "job": ["status", "container", "services"],
        "strategy": ["fail-fast", "job-index", "job-total", "max-parallel"],
    ]
    private static let exprFunctions = ["contains", "startsWith", "endsWith", "format", "join", "toJSON", "fromJSON", "hashFiles", "always", "success", "failure", "cancelled"]

    static func expressionItems(prefix: String, range: NSRange) -> [CompletionItem] {
        var out: [CompletionItem] = []
        let p = prefix.trimmingCharacters(in: .whitespaces)
        // "github.re" -> members of github, replacing "re"
        if let dot = p.lastIndex(of: ".") {
            let head = String(p[..<dot]).components(separatedBy: CharacterSet(charactersIn: " (!,&|=")).last ?? ""
            let tail = String(p[p.index(after: dot)...])
            let r = NSRange(location: range.location + range.length - tail.utf16.count, length: tail.utf16.count)
            for m in exprMembers[head] ?? [] { out.append(CI.make(m, .property, detail: head, sort: "0" + m, range: r)) }
            return out
        }
        for (n, d) in exprRoots { out.append(CI.make(n, .variable, detail: "context", sort: "0" + n, doc: d, range: range)) }
        for f in exprFunctions { out.append(CI.make(f, .function, detail: "function", sort: "1" + f, range: range)) }
        return out
    }

    // MARK: - JSON context

    struct JSONCtx {
        enum Pos { case none, key, value }
        var pos = Pos.none
        var path: [String] = []
        var key: String?
        var inString = false
        var prefixRange = NSRange(location: 0, length: 0)
        var prefix = ""
        var siblings = Set<String>()
        var inArray = false
    }

    private struct Frame { var isObject: Bool; var key: String?; var expectKey = true; var seen = Set<String>() }

    static func jsonContext(_ text: String, caret: Int) -> JSONCtx {
        let ns = text as NSString
        let end = max(0, min(caret, ns.length))
        var ctx = JSONCtx()
        ctx.prefixRange = NSRange(location: end, length: 0)
        var stack: [Frame] = []
        var i = 0
        func at(_ k: Int) -> unichar { ns.character(at: k) }
        while i < end {
            let c = at(i)
            switch c {
            case 32, 9, 10, 13, 44, 58:
                if c == 44, !stack.isEmpty { stack[stack.count - 1].expectKey = true; stack[stack.count - 1].key = nil }
                if c == 58, !stack.isEmpty { stack[stack.count - 1].expectKey = false }
                i += 1
            case 123: stack.append(Frame(isObject: true)); i += 1
            case 91: stack.append(Frame(isObject: false, expectKey: false)); i += 1
            case 125, 93: if !stack.isEmpty { stack.removeLast() }; i += 1
            case 47:
                if i + 1 < ns.length, at(i + 1) == 47 {
                    while i < end, at(i) != 10 { i += 1 }
                    if i >= end { return ctx }
                } else if i + 1 < ns.length, at(i + 1) == 42 {
                    i += 2
                    while i + 1 < end, !(at(i) == 42 && at(i + 1) == 47) { i += 1 }
                    if i + 1 >= end { return ctx }
                    i += 2
                } else { i += 1 }
            case 34, 39:
                let q = c
                let s = i
                i += 1
                var closed = false
                while i < end {
                    if at(i) == 92 { i += 2; continue }
                    if at(i) == q { closed = true; i += 1; break }
                    i += 1
                }
                if !closed {
                    // caret inside this string
                    guard let top = stack.last else { return ctx }
                    ctx.inString = true
                    ctx.prefixRange = NSRange(location: s + 1, length: end - s - 1)
                    ctx.prefix = ns.substring(with: ctx.prefixRange)
                    finish(&ctx, stack, key: top.isObject && top.expectKey)
                    return ctx
                }
                if var top = stack.popLast() {
                    if top.isObject, top.expectKey {
                        top.key = StructTape.unquote(ns.substring(with: NSRange(location: s, length: i - s)), json: true)
                        top.seen.insert(top.key!)
                    }
                    stack.append(top)
                }
            default:
                i += 1
            }
        }
        guard let top = stack.last else { return ctx }
        // bare token before the caret
        var s = end
        while s > 0 {
            let c = at(s - 1)
            if (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 45 || c == 46 { s -= 1 } else { break }
        }
        ctx.prefixRange = NSRange(location: s, length: end - s)
        ctx.prefix = ns.substring(with: ctx.prefixRange)
        finish(&ctx, stack, key: top.isObject && top.expectKey)
        return ctx
    }

    private static func finish(_ ctx: inout JSONCtx, _ stack: [Frame], key isKey: Bool) {
        guard let top = stack.last else { return }
        ctx.path = stack.dropLast().compactMap { $0.isObject ? $0.key : nil }
        ctx.inArray = !top.isObject
        if top.isObject {
            if isKey { ctx.pos = .key; ctx.siblings = top.seen; if let k = top.key { ctx.siblings.remove(k) } }
            else if let k = top.key { ctx.pos = .value; ctx.key = k }
        } else {
            ctx.pos = .value
            ctx.key = nil
            // array element: values belong to the array's key
            ctx.path = stack.dropLast().compactMap { $0.isObject ? $0.key : nil }
        }
    }

    static func jsonItems(_ cc: CompletionContext) -> [CompletionItem] {
        let c = jsonContext(cc.text, caret: cc.caret)
        guard c.pos != .none else { return [] }
        let schema = SchemaTable.forFile(cc.fileURL)
        var out: [CompletionItem] = []
        var seen = Set<String>()
        func add(_ it: CompletionItem) { if seen.insert(it.label).inserted { out.append(it) } }
        let range = c.prefixRange
        switch c.pos {
        case .key:
            if let node = schema?.walk(c.path) {
                for ch in node.named where !c.siblings.contains(ch.key) {
                    let ins = c.inString ? ch.key : "\"\(ch.key)\": "
                    add(CI.make(ch.key, .property, detail: ch.children.isEmpty ? (ch.values.isEmpty ? "value" : "enum") : "object", insert: ins,
                                sort: "0" + ch.key.lowercased(), doc: ch.doc, range: range))
                }
                if let pkg = packageSuggestions(path: c.path, file: cc.fileURL) {
                    for p in pkg where !c.siblings.contains(p) {
                        add(CI.make(p, .module, detail: "package", insert: c.inString ? p : "\"\(p)\": \"^\"", sort: "2" + p, range: range))
                    }
                }
            }
            // keys used elsewhere in this file
            var count: [String: Int] = [:]
            if cc.text.utf8.count < 2_000_000, let re = try? NSRegularExpression(pattern: "\"([A-Za-z0-9_@./$:-]{1,48})\"\\s*:", options: []) {
                let ns = cc.text as NSString
                for m in re.matches(in: cc.text, range: NSRange(location: 0, length: ns.length)).prefix(20000) {
                    let k = ns.substring(with: m.range(at: 1))
                    if !c.siblings.contains(k) { count[k, default: 0] += 1 }
                }
            }
            for (k, _) in count.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(30) {
                add(CI.make(k, .property, detail: "used in this file", insert: c.inString ? k : "\"\(k)\": ", sort: "8" + k.lowercased(), range: range))
            }
        case .value:
            let key = c.key ?? c.path.last ?? ""
            let node: SchemaNode?
            if c.key != nil { node = schema?.walk(c.path + [key]) } else { node = schema?.walk(c.path) }
            var values = node?.values ?? []
            if values.isEmpty, c.key != nil, let p = schema?.walk(c.path), let w = p.wildcard { values = w.values }
            for v in values {
                let bare = v == "true" || v == "false" || v == "null" || Double(v) != nil || v.hasPrefix("[") || v.hasPrefix("{") || v.hasPrefix("\"")
                let ins = c.inString ? v.replacingOccurrences(of: "\"", with: "\\\"") : (bare ? v : "\"\(v.replacingOccurrences(of: "\"", with: "\\\""))\"")
                var item = CI.make(v.hasPrefix("\"") ? String(v.dropFirst().dropLast()) : v, .enumMember, detail: "value", insert: v.hasPrefix("\"") && c.inString ? String(v.dropFirst().dropLast()) : ins,
                                   sort: "0" + v.lowercased(), range: range)
                item.filterText = item.label
                add(item)
            }
        case .none: break
        }
        return out
    }
}

final class StructuredProvider: CompletionProvider {
    let triggerCharacters = [" ", "\"", "-", ".", "{"]
    func complete(_ context: CompletionContext, deliver: @escaping ([CompletionItem], Bool) -> Void) {
        let name = context.fileURL.lastPathComponent.lowercased()
        let ext = context.fileExtension.lowercased()
        // Extension-less files: only .eslintrc. Plain JSON/YAML files still get "keys already used in this file".
        guard ext != "" || name == ".eslintrc" else { deliver([], false); return }
        if context.triggerCharacter == " " {
            // only after "key:" (value position); never on every space
            let ns = context.text as NSString
            let c = context.caret
            guard ext == "yml" || ext == "yaml", c >= 2, ns.character(at: c - 2) == 58 else { deliver([], false); return }
        }
        deliver(StructuredCompletion.items(for: context), false)
    }
    func cancel() {}
}
