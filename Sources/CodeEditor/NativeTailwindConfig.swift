import Foundation

/// Value of a JS expression as far as a Tailwind config needs it (no evaluation: literals, object / array nesting,
/// `colors.x.y` references, `theme('a.b')` calls, arrow functions returning an object).
indirect enum NWJV {
    case str(String)
    case num(String)
    case obj([(key: String, val: NWJV)])
    case arr([NWJV])
    case ref([String])
    case call(String, [NWJV])
    case fn
    case unknown

    var string: String? {
        switch self {
        case .str(let s): return s
        case .num(let n): return n
        default: return nil
        }
    }
    var entries: [(key: String, val: NWJV)]? { if case .obj(let e) = self { return e }; return nil }
    func get(_ key: String) -> NWJV? { entries?.last { $0.key == key }?.val }
}

/// Minimal tolerant JavaScript literal parser for tailwind.config.{js,cjs,mjs,ts}.
struct NWJSParser {
    let b: NWBuf
    var i = 0
    var env: [String: NWJV] = [:]
    var root: NWJV?
    var depth = 0

    init(_ b: NWBuf) { self.b = b }

    // MARK: lexical helpers

    private mutating func skipWS() {
        while i < b.count {
            let c = b[i]
            if NWChar.isSpace(c) { i += 1 }
            else if c == 47, i + 1 < b.count, b[i + 1] == 47 { while i < b.count, b[i] != 10 { i += 1 } }
            else if c == 47, i + 1 < b.count, b[i + 1] == 42 { i += 2; while i + 1 < b.count, !(b[i] == 42 && b[i + 1] == 47) { i += 1 }; i += 2 }
            else { break }
        }
    }
    private func isIdentStart(_ c: unichar) -> Bool { NWChar.isNameStart(c) || c == 36 }
    private func isIdentChar(_ c: unichar) -> Bool { isIdentStart(c) || NWChar.isDigit(c) }
    private mutating func ident() -> String {
        let s = i
        while i < b.count, isIdentChar(b[i]) { i += 1 }
        return b.str(s, i)
    }
    private mutating func string() -> String {
        let q = b[i]; i += 1
        var out = [unichar]()
        while i < b.count, b[i] != q {
            if b[i] == 92, i + 1 < b.count {
                i += 1
                let e = b[i]
                out.append(e == 110 ? 10 : e == 116 ? 9 : e)
            } else { out.append(b[i]) }
            i += 1
        }
        i += 1
        return String(utf16CodeUnits: out, count: out.count)
    }
    private mutating func skipBalanced(_ open: unichar, _ close: unichar) {
        var d = 0
        while i < b.count {
            let c = b[i]
            if c == 34 || c == 39 || c == 96 { _ = string(); continue }
            if c == 47, i + 1 < b.count, b[i + 1] == 47 || b[i + 1] == 42 { skipWS(); continue }
            if c == open { d += 1 } else if c == close { d -= 1; if d == 0 { i += 1; return } }
            i += 1
        }
    }
    /// After an expression we do not model (operators, ternaries, spreads of calls): skip to the next delimiter.
    private mutating func skipExpressionTail() {
        var d = 0
        while i < b.count {
            let c = b[i]
            if c == 34 || c == 39 || c == 96 { _ = string(); continue }
            if c == 40 || c == 91 || c == 123 { d += 1 } else if c == 41 || c == 93 || c == 125 { if d == 0 { return }; d -= 1 }
            else if (c == 44 || c == 59), d == 0 { return }
            i += 1
        }
    }

    // MARK: values

    mutating func parseValue() -> NWJV {
        depth += 1; defer { depth -= 1 }
        guard depth < 40 else { return .unknown }
        skipWS()
        guard i < b.count else { return .unknown }
        var v = parsePrimary()
        skipWS()
        if i < b.count {
            let c = b[i]
            if c == 61, i + 1 < b.count, b[i + 1] == 62 { i += 2; v = parseArrowBody() }       // ident => ...
            else if matches("satisfies") || matches("as ") { skipExpressionTail() }          // TS type assertions keep the value
            else if [43, 45, 42, 47, 37, 63, 58, 124, 38, 60, 62, 33, 61].contains(c) {      // + - * / % ? : | & < > ! = : not modelled
                skipExpressionTail()
                if case .obj = v {} else { v = .unknown }
            }
        }
        return v
    }

    private func matches(_ s: String) -> Bool {
        var k = i
        for u in s.utf16 { guard k < b.count, b[k] == u else { return false }; k += 1 }
        return true
    }

    private mutating func parsePrimary() -> NWJV {
        let c = b[i]
        switch c {
        case 123: return parseObject()
        case 91: return parseArray()
        case 34, 39: return .str(string())
        case 96:
            let s = string()
            return .str(s)
        case 40:                                                       // (a, b) => ... or (expr)
            let save = i
            skipBalanced(40, 41)
            skipWS()
            if i + 1 < b.count, b[i] == 61, b[i + 1] == 62 { i += 2; return parseArrowBody() }
            let end = i
            i = save + 1
            let v = parseValue()
            i = end
            return v
        default: break
        }
        if NWChar.isDigit(c) || c == 45 || c == 46 || c == 43 {
            let s = i
            i += 1
            while i < b.count, NWChar.isDigit(b[i]) || b[i] == 46 || b[i] == 101 || b[i] == 95 { i += 1 }
            return .num(b.str(s, i))
        }
        if isIdentStart(c) {
            let name = ident()
            switch name {
            case "function":
                skipWS(); if i < b.count, isIdentStart(b[i]) { _ = ident() }
                skipWS(); if i < b.count, b[i] == 40 { skipBalanced(40, 41) }
                return parseBlockReturn()
            case "async":
                return parseValue()
            case "true", "false", "null", "undefined": return .str(name)
            case "new", "typeof", "await":
                skipExpressionTail(); return .unknown
            default: break
            }
            return parsePath(name)
        }
        i += 1
        return .unknown
    }

    private mutating func parsePath(_ first: String) -> NWJV {
        var path = [first]
        while i < b.count {
            let c = b[i]
            if c == 46, i + 1 < b.count, isIdentStart(b[i + 1]) { i += 1; path.append(ident()); continue }
            if c == 46, i + 2 < b.count, b[i + 1] == 46 { break }
            if c == 91 {
                i += 1; skipWS()
                if i < b.count, b[i] == 34 || b[i] == 39 { path.append(string()) }
                else if i < b.count, NWChar.isDigit(b[i]) { let s = i; while i < b.count, NWChar.isDigit(b[i]) || b[i] == 46 { i += 1 }; path.append(b.str(s, i)) }
                else { while i < b.count, b[i] != 93 { i += 1 } }
                skipWS(); if i < b.count, b[i] == 93 { i += 1 }
                continue
            }
            if c == 40 {                                                // call
                i += 1
                var args: [NWJV] = []
                while i < b.count {
                    skipWS()
                    if i >= b.count { break }
                    if b[i] == 41 { i += 1; break }
                    if b[i] == 44 { i += 1; continue }
                    let before = i
                    args.append(parseValue())
                    if i == before { i += 1 }
                }
                let callee = path.joined(separator: ".")
                skipWS()
                if i < b.count, b[i] == 46 { skipExpressionTail(); return .unknown }       // call(...).chain
                return .call(callee, args)
            }
            break
        }
        // single identifier followed by `=>` is an arrow function parameter
        let save = i
        skipWS()
        if i + 1 < b.count, b[i] == 61, b[i + 1] == 62, path.count == 1 { i += 2; return parseArrowBody() }
        i = save
        if path.count == 1, let known = env[first] { return known }
        if let head = env[path[0]] , path.count > 1 { return NWJSParser.member(head, Array(path.dropFirst())) }
        return .ref(path)
    }

    /// `require('tailwindcss/colors')` -> the colors reference, `require('tailwindcss/defaultTheme')` -> the default theme.
    static func normalizeRequire(_ v: NWJV) -> NWJV {
        if case .call("require", let args) = v, let mod = args.first?.string {
            if mod.hasSuffix("tailwindcss/colors") { return .ref(["colors"]) }
            if mod.hasSuffix("tailwindcss/defaultTheme") { return .ref(["defaultTheme"]) }
            if mod.hasSuffix("tailwindcss/defaultConfig") { return .ref(["defaultTheme"]) }
        }
        return v
    }

    static func member(_ v: NWJV, _ path: [String]) -> NWJV {
        var cur = v
        for p in path {
            if let n = cur.get(p) { cur = n } else if case .ref(let r) = cur { return .ref(r + [p]) } else { return .unknown }
        }
        return cur
    }

    private mutating func parseArrowBody() -> NWJV {
        skipWS()
        guard i < b.count else { return .unknown }
        if b[i] == 123 { return parseBlockReturn() }
        return parseValue()
    }

    /// `{ ... return <expr> ... }` -> the returned expression (only a top-level `return` is considered).
    private mutating func parseBlockReturn() -> NWJV {
        skipWS()
        guard i < b.count, b[i] == 123 else { return .fn }
        let start = i
        var d = 0, k = i
        var returnAt = -1
        while k < b.count {
            let c = b[k]
            if c == 34 || c == 39 || c == 96 { let q = c; k += 1; while k < b.count, b[k] != q { if b[k] == 92 { k += 1 }; k += 1 }; k += 1; continue }
            if c == 47, k + 1 < b.count, b[k + 1] == 47 { while k < b.count, b[k] != 10 { k += 1 }; continue }
            if c == 123 || c == 40 || c == 91 { d += 1 } else if c == 125 || c == 41 || c == 93 { d -= 1; if d == 0 { k += 1; break } }
            else if d == 1, c == 114, k + 6 < b.count, b.str(k, k + 6) == "return", !isIdentChar(b[k + 6]), k == 0 || !isIdentChar(b[k - 1]) { returnAt = k + 6 }
            k += 1
        }
        let end = k
        defer { i = end }
        guard returnAt >= 0 else { i = end; _ = start; return .fn }
        i = returnAt
        return parseValue()
    }

    private mutating func parseObject() -> NWJV {
        i += 1
        var out: [(key: String, val: NWJV)] = []
        while i < b.count {
            skipWS()
            guard i < b.count else { break }
            let c = b[i]
            if c == 125 { i += 1; break }
            if c == 44 { i += 1; continue }
            let before = i
            if c == 46, i + 2 < b.count, b[i + 1] == 46, b[i + 2] == 46 {
                i += 3
                out.append(("...", parseValue()))
                continue
            }
            var key = ""
            if c == 34 || c == 39 { key = string() }
            else if c == 91 { skipBalanced(91, 93); key = "?" }
            else if NWChar.isDigit(c) { let s = i; while i < b.count, NWChar.isDigit(b[i]) || b[i] == 46 { i += 1 }; key = b.str(s, i) }
            else if isIdentStart(c) { key = ident() }
            else { i += 1; continue }
            skipWS()
            if i < b.count, b[i] == 58 { i += 1; out.append((key, parseValue())) }
            else if i < b.count, b[i] == 40 { skipBalanced(40, 41); skipWS(); if i < b.count, b[i] == 123 { skipBalanced(123, 125) }; out.append((key, .fn)) }
            else if key == "get" || key == "async" || key == "set" { continue }
            else { out.append((key, env[key] ?? .ref([key]))) }
            if i == before { i += 1 }
        }
        return .obj(out)
    }

    private mutating func parseArray() -> NWJV {
        i += 1
        var out: [NWJV] = []
        while i < b.count {
            skipWS()
            guard i < b.count else { break }
            if b[i] == 93 { i += 1; break }
            if b[i] == 44 { i += 1; continue }
            let before = i
            if b[i] == 46, i + 2 < b.count, b[i + 1] == 46, b[i + 2] == 46 { i += 3 }
            out.append(parseValue())
            if i == before { i += 1 }
        }
        return .arr(out)
    }

    // MARK: top level

    /// Reads declarations (`const x = ...`, imports) and the exported config object.
    mutating func parseModule() {
        while i < b.count {
            skipWS()
            guard i < b.count else { break }
            let c = b[i]
            if c == 34 || c == 39 || c == 96 { _ = string(); continue }
            guard isIdentStart(c) else { i += 1; continue }
            let before = i
            let word = ident()
            switch word {
            case "const", "let", "var":
                skipWS()
                guard i < b.count, isIdentStart(b[i]) else { continue }
                let name = ident()
                skipWS()
                if i < b.count, b[i] == 58 { while i < b.count, b[i] != 61, b[i] != 10 { i += 1 } }      // TS type annotation
                if i < b.count, b[i] == 61 {
                    i += 1
                    env[name] = NWJSParser.normalizeRequire(parseValue())
                    if name == "config" || name == "tailwindConfig" { root = root ?? env[name] }
                }
            case "import":
                skipWS()
                var names: [String] = []
                while i < b.count, b[i] != 39, b[i] != 34, b[i] != 59, b[i] != 10 || names.isEmpty {
                    if isIdentStart(b[i]) { let n = ident(); if n != "from", n != "type", n != "as" { names.append(n) } } else { i += 1 }
                }
                if i < b.count, b[i] == 34 || b[i] == 39 {
                    let mod = string()
                    let v: NWJV = mod.hasSuffix("tailwindcss/colors") ? .ref(["colors"]) : mod.hasSuffix("defaultTheme") ? .ref(["defaultTheme"]) : .unknown
                    for n in names { env[n] = v }
                } else if i < b.count, b[i] == 10 || b[i] == 59 { i += 1 }
            case "module":
                skipWS()
                if i < b.count, b[i] == 46 {
                    i += 1
                    if ident() == "exports" { skipWS(); if i < b.count, b[i] == 61 { i += 1; root = parseValue() } }
                }
            case "export":
                skipWS()
                if matches("default") { i += 7; root = parseValue() }
            default:
                if i == before { i += 1 }
            }
        }
    }

    /// The config object, following identifier / defineConfig() indirections.
    func rootObject() -> NWJV? {
        var v = root
        for _ in 0..<4 {
            switch v {
            case .some(.ref(let r)) where r.count == 1: v = env[r[0]]
            case .some(.call(_, let args)): v = args.first
            default: return v
            }
        }
        return v
    }
}

// MARK: - Loader

struct NWTailwindState {
    var tw: NWTailwind?
    var inputs: [(path: String, stamp: Int64)]
    var listEpoch: Int
}

enum NWTailwindLoader {
    static let configNames = ["tailwind.config.js", "tailwind.config.ts", "tailwind.config.cjs", "tailwind.config.mjs"]

    /// Nearest Tailwind setup for `near` (a directory inside the project): config file / CSS entry / package dependency.
    static func resolve(_ p: NWProject, near: String? = nil) -> NWTailwind? {
        let scope = scopeDir(p, near: near)
        if var st = p.tailwindStates[scope] {
            let fresh = st.listEpoch == p.listEpoch && st.inputs.allSatisfy { LaravelFS.mtime($0.path) == $0.stamp }
            if fresh { return st.tw }
            st.tw = nil
        }
        let t0 = NPStats.now()
        let (tw, inputs) = build(p, scope: scope)
        p.tailwindStates[scope] = NWTailwindState(tw: tw, inputs: inputs.map { ($0, LaravelFS.mtime($0)) }, listEpoch: p.listEpoch)
        p.tailwindBuildNs = NPStats.now() &- t0
        return tw
    }

    /// Directory whose tailwind.config.* applies: nearest ancestor of `near` (up to the root) holding one, else the root.
    static func scopeDir(_ p: NWProject, near: String?) -> String {
        guard var dir = near else { return p.root }
        if !dir.hasPrefix(p.root) { return p.root }
        for _ in 0..<12 {
            if configNames.contains(where: { LaravelFS.isFile(dir + "/" + $0) }) { return dir }
            if dir == p.root { break }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.count < p.root.count { break }
            dir = parent
        }
        return p.root
    }

    private static func packageInfo(_ dir: String) -> (hasTailwind: Bool, major: Int, v4Plugin: Bool) {
        guard let d = FileManager.default.contents(atPath: dir + "/package.json"), d.count < 400_000,
              let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return (false, 0, false) }
        var deps: [String: Any] = [:]
        for k in ["dependencies", "devDependencies", "peerDependencies"] { if let m = json[k] as? [String: Any] { deps.merge(m) { a, _ in a } } }
        let ver = (deps["tailwindcss"] as? String) ?? ""
        let digits = ver.drop { !$0.isNumber }.prefix { $0.isNumber }
        let v4plugin = deps["@tailwindcss/vite"] != nil || deps["@tailwindcss/postcss"] != nil || deps["@tailwindcss/cli"] != nil
        return (!ver.isEmpty || v4plugin, Int(digits) ?? 0, v4plugin)
    }

    private static func build(_ p: NWProject, scope: String) -> (NWTailwind?, [String]) {
        var inputs: [String] = []
        let pkg = packageInfo(scope)
        if LaravelFS.isFile(scope + "/package.json") { inputs.append(scope + "/package.json") }
        // CSS entries: `@import "tailwindcss"` (v4) / `@tailwind` (v3) / `@theme`
        var v4Entries: [String] = [], hasTailwindCSS = false
        for path in p.allCSSFiles where path.hasPrefix(scope + "/") {
            guard let idx = p.cssIndex(path: path) else { continue }
            for at in idx.ats {
                if at.name == "import", at.params.hasPrefix("\"tailwindcss") || at.params.hasPrefix("'tailwindcss") || at.params.hasPrefix("url(\"tailwindcss") { v4Entries.append(path); hasTailwindCSS = true; break }
                if at.name == "tailwind" { hasTailwindCSS = true }
                if at.name == "theme" || at.name == "config" || at.name == "plugin" && v4Entries.isEmpty { if at.name == "theme" { v4Entries.append(path) } }
            }
        }
        var configPath: String?
        for n in configNames where LaravelFS.isFile(scope + "/" + n) { configPath = scope + "/" + n; break }
        // `@config "./tailwind.config.js"` in a v4 entry
        if configPath == nil {
            for e in v4Entries { if let idx = p.cssIndex(path: e), let at = idx.ats.first(where: { $0.name == "config" }) {
                let rel = at.params.trimmingCharacters(in: CharacterSet(charactersIn: "\"'; "))
                let abs = (e as NSString).deletingLastPathComponent + "/" + rel
                if LaravelFS.isFile(abs) { configPath = (abs as NSString).standardizingPath; break }
            } }
        }
        guard configPath != nil || hasTailwindCSS || pkg.hasTailwind else { return (nil, inputs) }
        let v4 = !v4Entries.isEmpty && (pkg.major >= 4 || pkg.major == 0 || pkg.v4Plugin) && v4Entries.contains { path in
            p.cssIndex(path: path)?.ats.contains { $0.name == "import" && $0.params.contains("tailwindcss") } == true
        }
        let tw = NWTailwind.makeDefault(version: v4 ? 4 : 3)
        if let cp = configPath {
            inputs.append(cp)
            tw.inputs.append(cp)
            if let text = FastProject.readRaw(cp) { applyConfig(tw, text: text) }
        }
        if v4 || !v4Entries.isEmpty {
            var seen = Set<String>()
            for e in v4Entries { applyCSS(tw, p, path: e, seen: &seen, depth: 0) }
            inputs.append(contentsOf: seen)
            tw.inputs.append(contentsOf: v4Entries)
        }
        return (tw, inputs)
    }

    // MARK: v3 config

    static func applyConfig(_ tw: NWTailwind, text: NSString) {
        var parser = NWJSParser(NWBuf(text))
        parser.parseModule()
        guard let root = parser.rootObject(), root.entries != nil else { return }
        if let pre = root.get("prefix")?.string { tw.prefix = pre }
        if let imp = root.get("important") { tw.important = imp.string == "true" ? "true" : imp.string }
        if let dm = root.get("darkMode") {
            if let s = dm.string { tw.darkMode = s }
            if case .arr(let a) = dm { tw.darkMode = a.first?.string ?? "media"; if a.count > 1, let sel = a[1].string { tw.darkSelector = sel } }
        }
        if let plugins = root.get("plugins"), case .arr(let list) = plugins {
            for p in list {
                if case .call(let callee, let args) = p, callee == "require", let name = args.first?.string {
                    if name.contains("typography") { for n in ["prose", "prose-sm", "prose-base", "prose-lg", "prose-xl", "prose-2xl", "prose-invert", "not-prose"] { tw.extraNames.insert(n) } }
                    if name.contains("forms") { tw.extraNames.insert("form-input"); tw.extraNames.insert("form-select"); tw.extraNames.insert("form-checkbox") }
                    if name.contains("container-queries") { tw.extraNames.insert("@container") }
                }
            }
        }
        guard let theme = root.get("theme"), let entries = theme.entries else { return }
        var extend: NWJV?
        for (key, val) in entries {
            if key == "extend" { extend = val; continue }
            if key == "..." { continue }
            apply(tw, key: key, val: val, replace: true)
        }
        if let ext = extend?.entries { for (key, val) in ext where key != "..." { apply(tw, key: key, val: val, replace: false) } }
    }

    private static func resolveRef(_ tw: NWTailwind, _ v: NWJV) -> NWJV {
        switch v {
        case .ref(let r):
            if r.first == "colors" || r.first == "defaultTheme" && r.count > 1 && r[1] == "colors" {
                let path = Array(r.dropFirst(r.first == "colors" ? 1 : 2))
                return colorNode(path)
            }
            if r.first == "defaultTheme", r.count >= 2 {
                if let m = NWTailwind.parsedDefaults[r[1]] ?? (r[1] == "spacing" ? NWTailwind.parsedDefaults["spacing"] : nil) {
                    return .obj(m.map { ($0.key, NWJV.str($0.value)) })
                }
            }
            tw.unresolved += 1
            return .unknown
        case .call("require", _): return resolveRef(tw, NWJSParser.normalizeRequire(v))
        case .call(let callee, let args) where callee == "theme" || callee.hasSuffix(".theme"):
            guard let path = args.first?.string else { return .unknown }
            return themeLookup(tw, path).map { .str($0) } ?? .unknown
        default: return v
        }
    }

    private static func colorNode(_ path: [String]) -> NWJV {
        if path.isEmpty { return .obj(NWTailwind.palette.map { fam, shades in (fam, NWJV.obj(shades.map { ($0.key, NWJV.str($0.value)) })) }) }
        let fam = path[0]
        if let shades = NWTailwind.palette[fam] {
            if path.count > 1 { return shades[path[1]].map { .str($0) } ?? .unknown }
            return .obj(shades.map { ($0.key, NWJV.str($0.value)) })
        }
        let basic = ["inherit": "inherit", "current": "currentColor", "transparent": "transparent", "black": "#000", "white": "#fff"]
        if let v = basic[fam] { return .str(v) }
        // legacy names
        let legacy = ["lightBlue": "sky", "warmGray": "stone", "trueGray": "neutral", "coolGray": "gray", "blueGray": "slate"]
        if let n = legacy[fam], let shades = NWTailwind.palette[n] { return .obj(shades.map { ($0.key, NWJV.str($0.value)) }) }
        return .unknown
    }

    static func themeLookup(_ tw: NWTailwind, _ path: String) -> String? {
        let parts = path.split(separator: ".", maxSplits: 1).map(String.init)
        guard let key = parts.first else { return nil }
        let rest = parts.count > 1 ? parts[1] : "DEFAULT"
        if key == "colors" { return tw.colors[rest.replacingOccurrences(of: ".", with: "-")] ?? tw.colors[rest] }
        return tw.maps[key]?[rest] ?? tw.maps[key]?[rest.replacingOccurrences(of: ".", with: "-")]
    }

    private static func flatten(_ tw: NWTailwind, _ v: NWJV, prefix: String, into out: inout [String: String], key: String) {
        let node = resolveRef(tw, v)
        switch node {
        case .str(let s): out[prefix.isEmpty ? "DEFAULT" : prefix] = s
        case .num(let n): out[prefix.isEmpty ? "DEFAULT" : prefix] = n
        case .obj(let entries):
            for (k, val) in entries {
                if k == "..." {
                    if case .obj = resolveRef(tw, val) { flatten(tw, val, prefix: prefix, into: &out, key: key) }
                    continue
                }
                if k == "DEFAULT" { flatten(tw, val, prefix: prefix, into: &out, key: key); continue }
                let name = prefix.isEmpty ? k : prefix + "-" + k
                flatten(tw, val, prefix: name, into: &out, key: key)
            }
        case .arr(let items):
            if key == "fontFamily" {
                out[prefix] = items.compactMap { $0.string }.map { $0.contains(" ") && !$0.hasPrefix("\"") && !$0.hasPrefix("var(") ? "\"\($0)\"" : $0 }.joined(separator: ", ")
            } else if key == "fontSize" {
                let size = items.first?.string ?? ""
                var lh = ""
                if items.count > 1 { lh = items[1].string ?? items[1].get("lineHeight")?.string ?? "" }
                out[prefix] = lh.isEmpty ? size : size + "|" + lh
            } else if key == "screens" { break }
        case .call, .ref, .fn, .unknown: out[prefix.isEmpty ? "DEFAULT" : prefix] = "?"; tw.unresolved += 1
        }
    }

    private static func apply(_ tw: NWTailwind, key: String, val: NWJV, replace: Bool) {
        if key == "colors" {
            var flat: [String: String] = [:]
            let node = resolveRef(tw, val)
            if case .obj(let es) = node {
                for (k, v) in es {
                    if k == "..." { flatten(tw, v, prefix: "", into: &flat, key: key); continue }
                    flatten(tw, v, prefix: k == "DEFAULT" ? "" : k, into: &flat, key: key)
                }
            }
            if replace { tw.colors = flat } else { tw.colors.merge(flat) { _, new in new } }
            return
        }
        if key == "screens" {
            var m: [String: String] = [:]
            if case .obj(let es) = resolveRef(tw, val) {
                for (k, v) in es where k != "..." {
                    if let s = v.string { m[k] = s }
                    else if let mx = v.get("max")?.string, v.get("min") == nil { m[k] = "@max:" + mx }
                    else if let mn = v.get("min")?.string { m[k] = mn }
                    else if let raw = v.get("raw")?.string { m[k] = "@raw:" + raw }
                }
            }
            if replace { tw.maps["screens"] = m } else { tw.maps["screens", default: [:]].merge(m) { _, new in new } }
            return
        }
        var flat: [String: String] = [:]
        flatten(tw, val, prefix: "", into: &flat, key: key)
        if flat.isEmpty { if replace { tw.maps[key] = [:] }; return }
        if replace { tw.maps[key] = flat } else { tw.maps[key, default: [:]].merge(flat) { _, new in new } }
    }

    // MARK: v4 CSS (@theme / @utility / @custom-variant)

    static func applyCSS(_ tw: NWTailwind, _ p: NWProject, path: String, seen: inout Set<String>, depth: Int) {
        guard depth < 4, seen.insert(path).inserted, let text = FastProject.readRaw(path) else { return }
        let b = NWBuf(text)
        guard let idx = p.cssIndex(path: path) else { return }
        for at in idx.ats where at.name == "import" {
            let raw = at.params
            guard let q = raw.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { continue }
            let rest = raw[raw.index(after: q)...]
            guard let e = rest.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { continue }
            let rel = String(rest[rest.startIndex..<e])
            if rel.hasPrefix("tailwindcss") || rel.hasPrefix("http") || !(rel.hasPrefix(".") || rel.hasPrefix("/")) && !rel.hasSuffix(".css") { continue }
            let abs = ((path as NSString).deletingLastPathComponent + "/" + rel as NSString).standardizingPath
            if LaravelFS.isFile(abs) { applyCSS(tw, p, path: abs, seen: &seen, depth: depth + 1) }
        }
        for prop in idx.props where prop.inTheme && prop.name.hasPrefix("--") {
            let name = String(prop.name.dropFirst(2))
            let value = b.str(Int(prop.valueStart), Int(prop.valueEnd))
            applyThemeVar(tw, name: name, value: value)
        }
        for at in idx.ats {
            switch at.name {
            case "utility":
                let n = at.params
                guard !n.isEmpty, !n.hasSuffix("*") else { continue }
                var k = Int(at.offset)
                while k < b.count, b[k] != 123 { k += 1 }
                var d = 0, e = k
                while e < b.count { if b[e] == 123 { d += 1 } else if b[e] == 125 { d -= 1; if d == 0 { break } }; e += 1 }
                if k < e { tw.customUtilities[n] = b.str(k + 1, e).trimmingCharacters(in: .whitespacesAndNewlines) }
            case "custom-variant":
                let parts = at.params.split(separator: " ", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { continue }
                var sel = parts[1].trimmingCharacters(in: .whitespaces)
                if sel.hasPrefix("("), let close = sel.lastIndex(of: ")") { sel = String(sel[sel.index(after: sel.startIndex)..<close]) }
                if sel.hasPrefix("{") { continue }
                tw.customVariants[parts[0]] = sel
            default: break
            }
        }
    }

    private static let nsMap: [(prefix: String, key: String)] = [
        ("color-", "colors"), ("spacing-", "spacing"), ("breakpoint-", "screens"), ("font-weight-", "fontWeight"), ("font-", "fontFamily"), ("text-", "fontSize"),
        ("leading-", "lineHeight"), ("tracking-", "letterSpacing"), ("radius-", "borderRadius"), ("shadow-", "boxShadow"), ("blur-", "blur"),
        ("ease-", "transitionTimingFunction"), ("animate-", "animation"), ("container-", "maxWidth"), ("aspect-", "aspectRatio"),
    ]

    static func applyThemeVar(_ tw: NWTailwind, name: String, value: String) {
        if name == "*" && value == "initial" { tw.colors = [:]; for (k, _) in tw.maps where k != "spacing" { tw.maps[k] = [:] }; return }
        if name == "spacing" { tw.spacingBase = value; return }
        for (prefix, key) in nsMap {
            if name == String(prefix.dropLast()) + "-*" && value == "initial" {
                if key == "colors" { tw.colors = [:] } else { tw.maps[key] = [:] }
                return
            }
            guard name.hasPrefix(prefix) else { continue }
            let n = String(name.dropFirst(prefix.count))
            if key == "colors" { tw.colors[n] = value; return }
            if key == "fontSize" {
                if n.hasSuffix("--line-height") {
                    let base = String(n.dropLast("--line-height".count))
                    let cur = tw.maps["fontSize"]?[base]?.split(separator: "|").first.map(String.init) ?? ""
                    tw.maps["fontSize", default: [:]][base] = cur + "|" + value
                } else if let ex = tw.maps["fontSize"]?[n], ex.contains("|") { tw.maps["fontSize", default: [:]][n] = value + "|" + (ex.split(separator: "|").last.map(String.init) ?? "") }
                else { tw.maps["fontSize", default: [:]][n] = value }
                return
            }
            tw.maps[key, default: [:]][n] = value
            return
        }
    }
}
