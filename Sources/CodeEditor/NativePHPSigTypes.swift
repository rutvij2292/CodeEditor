import Foundation

// Docblock-aware type inference for FTEval (phase 2a): `@return` / `@var` / `@param` types (unions, `static`, `$this`,
// `Collection<int, Foo>`, `Foo[]`, `class-string<T>`, basic `@template`), property types, `@property` / `@method` tags, the auth
// user (`auth()->user()`, `Auth::user()`, `$request->user()`, from config/auth.php), container helpers (`app(Foo::class)`,
// `app('cache')`) and facade roots (`Cache::` -> CacheManager via getFacadeAccessor). Everything is computed on demand per request
// and cached in the FTEval instance only (docblocks via NPFiles, which is capped).

extension FTEval {
    static let guardFQN = "Illuminate\\Contracts\\Auth\\Guard"
    static let authFacade = "Illuminate\\Support\\Facades\\Auth"
    static let requestFQN = "Illuminate\\Http\\Request"

    /// Container / facade accessor aliases (`app('cache')`, `getFacadeAccessor() { return 'cache'; }`).
    static let containerAliases: [String: String] = [
        "cache": "Illuminate\\Cache\\CacheManager", "cache.store": "Illuminate\\Cache\\Repository", "db": "Illuminate\\Database\\DatabaseManager",
        "db.connection": "Illuminate\\Database\\Connection", "auth": "Illuminate\\Auth\\AuthManager", "auth.driver": "Illuminate\\Contracts\\Auth\\Guard",
        "session": "Illuminate\\Session\\SessionManager", "session.store": "Illuminate\\Session\\Store", "log": "Illuminate\\Log\\LogManager",
        "events": "Illuminate\\Events\\Dispatcher", "files": "Illuminate\\Filesystem\\Filesystem", "filesystem": "Illuminate\\Filesystem\\FilesystemManager",
        "url": "Illuminate\\Routing\\UrlGenerator", "redirect": "Illuminate\\Routing\\Redirector", "router": "Illuminate\\Routing\\Router",
        "request": "Illuminate\\Http\\Request", "view": "Illuminate\\View\\Factory", "mail.manager": "Illuminate\\Mail\\MailManager",
        "queue": "Illuminate\\Queue\\QueueManager", "validator": "Illuminate\\Validation\\Factory", "hash": "Illuminate\\Hashing\\HashManager",
        "cookie": "Illuminate\\Cookie\\CookieJar", "config": "Illuminate\\Config\\Repository", "translator": "Illuminate\\Translation\\Translator",
        "encrypter": "Illuminate\\Encryption\\Encrypter", "blade.compiler": "Illuminate\\View\\Compilers\\BladeCompiler",
        "redis": "Illuminate\\Redis\\RedisManager", "app": "Illuminate\\Foundation\\Application", "artisan": "Illuminate\\Contracts\\Console\\Kernel",
        "bus": "Illuminate\\Contracts\\Bus\\Dispatcher", "gate": "Illuminate\\Contracts\\Auth\\Access\\Gate", "schedule": "Illuminate\\Console\\Scheduling\\Schedule",
        "http": "Illuminate\\Http\\Client\\Factory", "process": "Illuminate\\Process\\Factory", "rate.limiter": "Illuminate\\Cache\\RateLimiter",
        "auth.password": "Illuminate\\Auth\\Passwords\\PasswordBrokerManager", "broadcast": "Illuminate\\Broadcasting\\BroadcastManager",
    ]

    // MARK: Docblock access

    func fileText(of k: FTClass) -> NSString? {
        if k === cur { return ns }
        guard let p = fp.classPath(k.fqn) else { return nil }
        return NPFiles.text(p)
    }

    /// Parsed docblock above `declStart` in `k`'s file (nil when none). Cached per request.
    func docOf(_ k: FTClass, declStart: Int, key: String) -> NPDoc? {
        if let d = docCache[key] { return d.raw.isEmpty ? nil : d }
        guard let t = fileText(of: k), let d = NPDoc.leading(t, before: declStart) else { docCache[key] = NPDoc(); return nil }
        let doc = NPDoc.parse(d.text, start: d.start)
        docCache[key] = doc
        return doc
    }

    /// `@template T of Bound` names declared in a docblock (name -> resolved bound FQN or "").
    func templates(_ doc: NPDoc, owner: FTClass?) -> [String: String] {
        guard doc.raw.contains("@template"), let re = try? NSRegularExpression(pattern: #"@template(?:-covariant|-contravariant)?\s+(\w+)(?:\s+of\s+([\\\w]+))?"#) else { return [:] }
        var out: [String: String] = [:]
        let r = doc.raw as NSString
        for m in re.matches(in: doc.raw, range: NSRange(location: 0, length: r.length)) {
            let name = r.substring(with: m.range(at: 1))
            var bound = ""
            if m.range(at: 2).location != NSNotFound, let f = resolveDocName(r.substring(with: m.range(at: 2)), owner: owner) { bound = f }
            out[name] = bound
        }
        return out
    }

    // MARK: Type strings

    private static let scalarWords: Set<String> = ["null", "false", "true", "void", "mixed", "int", "float", "string", "bool", "array-key", "scalar", "never", "resource",
                                                   "callable", "object", "integer", "boolean", "double", "numeric", "array", "iterable", "list", "closure-string",
                                                   "class-string", "callable-string", "literal-string", "numeric-string", "truthy-string"]

    /// Splits `s` on `sep` outside <>, (), {}, [].
    static func splitTop(_ s: String, _ sep: Character) -> [String] {
        var out: [String] = []
        var depth = 0
        var cur = ""
        for c in s {
            if "<({[".contains(c) { depth += 1 } else if ">)}]".contains(c) { depth -= 1 }
            if c == sep, depth <= 0 { out.append(cur); cur = "" } else { cur.append(c) }
        }
        out.append(cur)
        return out
    }

    func resolveDocName(_ n: String, owner: FTClass?) -> String? {
        let o = owner ?? FTClass()
        let c = o.resolve(n)
        if fp.classPath(c) != nil { return c }
        return fp.resolveClass(n, in: owner)
    }

    static func isCollectionFQN(_ f: String) -> Bool {
        f == "Illuminate\\Support\\Collection" || f == "Illuminate\\Database\\Eloquent\\Collection" || f.hasSuffix("\\LazyCollection")
            || f == "Illuminate\\Support\\Enumerable" || f == "Illuminate\\Contracts\\Support\\Arrayable"
    }

    private func elementClass(_ t: FTType?) -> String? {
        switch t {
        case .instance(let c)?: return c
        default: return nil
        }
    }

    /// Converts a docblock / declared type text written in `owner`'s file to an FTType (union members are tried in order,
    /// null/scalars skipped). Arrays of Foo and generic collections become `.collection(Foo)` (element hint).
    func typeFromDoc(_ rawIn: String, owner: FTClass?, selfType: String, templates: [String: String] = [:], depth: Int = 0) -> FTType? {
        var raw = rawIn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, depth < 5, !raw.hasPrefix("(") else { return nil }
        if raw.hasPrefix("?") { raw.removeFirst() }
        for alt in Self.splitTop(raw, "|") {
            var a = alt.trimmingCharacters(in: .whitespaces)
            if let amp = Self.splitTop(a, "&").first { a = amp.trimmingCharacters(in: .whitespaces) }
            if a.hasPrefix("?") { a.removeFirst() }
            if a.hasPrefix("(") && a.hasSuffix(")") { a = String(a.dropFirst().dropLast()) }
            guard !a.isEmpty else { continue }
            if let t = single(a, owner: owner, selfType: selfType, templates: templates, depth: depth) { return t }
        }
        return nil
    }

    private func single(_ a: String, owner: FTClass?, selfType: String, templates: [String: String], depth: Int) -> FTType? {
        if a.hasSuffix("[]") {
            let inner = typeFromDoc(String(a.dropLast(2)), owner: owner, selfType: selfType, templates: templates, depth: depth + 1)
            return .collection(elementClass(inner))
        }
        if let lt = a.firstIndex(of: "<"), a.hasSuffix(">") {
            let base = String(a[..<lt])
            let argsText = String(a[a.index(after: lt)..<a.index(before: a.endIndex)])
            let args = Self.splitTop(argsText, ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let lb = base.lowercased()
            func argType(_ i: Int) -> FTType? {
                guard i >= 0, i < args.count else { return nil }
                return typeFromDoc(args[i], owner: owner, selfType: selfType, templates: templates, depth: depth + 1)
            }
            if ["array", "list", "non-empty-array", "non-empty-list", "iterable"].contains(lb) { return .collection(elementClass(argType(args.count - 1))) }
            if lb == "class-string" { return elementClass(argType(0)).map { .staticRef($0) } }
            guard let f = singleName(base, owner: owner, selfType: selfType, templates: [:]) else { return nil }
            if Self.isCollectionFQN(f) || f.contains("Paginator") { return .collection(elementClass(argType(args.count - 1))) }
            if f == NPResolver.eloquentBuilder || f.hasPrefix("Illuminate\\Database\\Eloquent\\Relations\\") {
                if let m = elementClass(argType(0)) { return .builder(m) }
            }
            return .instance(f)
        }
        if let f = singleName(a, owner: owner, selfType: selfType, templates: templates) { return .instance(f) }
        return nil
    }

    private func singleName(_ a: String, owner: FTClass?, selfType: String, templates: [String: String]) -> String? {
        let l = a.lowercased()
        if l == "static" || l == "self" || l == "$this" { return selfType.isEmpty ? nil : selfType }
        if l == "parent" { return owner?.extends }
        if let b = templates[a] { return b.isEmpty ? nil : b }
        if Self.scalarWords.contains(l) || FTClass.builtinTypes.contains(l) || a.contains("-") || a.contains("{") || a.contains(" ") { return nil }
        guard let c = a.unicodeScalars.first, c == "\\" || CharacterSet.letters.contains(c) || c == "_" else { return nil }
        return resolveDocName(a, owner: owner)
    }

    // MARK: Method / property / function results

    private func splitParamNames(_ params: String) -> [String] {
        Self.splitTop(params, ",").compactMap { p in
            guard let r = p.range(of: #"\$\w+"#, options: .regularExpression) else { return nil }
            return String(p[r])
        }
    }

    /// Splits the call's argument token range into per-argument token ranges (top-level commas).
    func splitArgs(_ range: (Int, Int)) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        var start = range.0
        var i = range.0
        while i < range.1 {
            let t = lex.toks[i]
            if t.kind == .punct {
                if [40, 91, 123].contains(t.ch) { if lex.match[i] > i { i = lex.match[i] + 1; continue } }
                if t.ch == 44 { out.append((start, i)); start = i + 1 }
            }
            i += 1
        }
        if start < range.1 { out.append((start, range.1)) }
        return out
    }

    /// `X::class` argument -> X's FQN.
    func classConstArg(_ r: (Int, Int)) -> String? {
        var a = r.0
        if a + 1 < r.1, lex.toks[a].kind == .ident, lex.isPunct(a + 1, ":") { a += 2 }       // named argument `abstract: Foo::class`
        guard a + 3 == r.1, lex.toks[a].kind == .ident, lex.isPunct(a + 1, code: PHPTok.dcolon), lex.isIdent(a + 2, "class") else { return nil }
        let w = lex.text(a)
        let l = w.lowercased()
        if l == "static" || l == "self" { return cur?.fqn }
        return fp.resolveClass(w, in: cur)
    }

    /// Upgrades a declared return type with the docblock `@return` (generics, `static`, templates, conditional class-string returns).
    func refineReturn(_ declared: FTType?, owner: FTClass, m: FTMethod, selfType: String, args: (Int, Int)?) -> FTType? {
        let doc = docOf(owner, declStart: m.declStart, key: owner.fqn + "::" + m.name)
        if let d = declared {
            // only a bare Collection declaration is upgraded (docblock carries the element type)
            if case .instance(let f) = d, Self.isCollectionFQN(f), let r = doc?.ret?.type, let t = typeFromDoc(r, owner: owner, selfType: selfType), case .collection = t { return t }
            return d
        }
        guard let doc, let ret = doc.ret?.type, !ret.isEmpty else { return nil }
        // conditional: ($abstract is class-string<T> ? T : mixed)
        if ret.hasPrefix("(") {
            guard let re = try? NSRegularExpression(pattern: #"^\(\s*(\$\w+)\s+is\s+class-string<"#), let mm = re.firstMatch(in: ret, range: NSRange(location: 0, length: (ret as NSString).length)),
                  let args else { return nil }
            let pname = (ret as NSString).substring(with: mm.range(at: 1))
            if let idx = splitParamNames(m.params).firstIndex(of: pname) {
                let parts = splitArgs(args)
                if idx < parts.count, let f = classConstArg(parts[idx]) { return .instance(f) }
            }
            return nil
        }
        var tmpl = templates(doc, owner: owner)
        if let cd = docOf(owner, declStart: owner.declStart, key: owner.fqn + "::class") { for (k, v) in templates(cd, owner: owner) where tmpl[k] == nil { tmpl[k] = v } }
        // method template bound by a class-string<T> parameter: `@param class-string<T> $c` + `@return T`
        let retName = ret.replacingOccurrences(of: "|null", with: "").replacingOccurrences(of: "null|", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "? "))
        if tmpl[retName] != nil, let args {
            let names = splitParamNames(m.params)
            for p in doc.params where p.type.contains("class-string<\(retName)>") {
                if let idx = names.firstIndex(of: p.name) {
                    let parts = splitArgs(args)
                    if idx < parts.count, let f = classConstArg(parts[idx]) { return .instance(f) }
                }
            }
        }
        return typeFromDoc(ret, owner: owner, selfType: selfType, templates: tmpl)
    }

    func propType(_ owner: FTClass, _ p: FTProp, selfType: String) -> FTType? {
        var declared: FTType?
        if !p.type.isEmpty, let ct = owner.classType(p.type), let r = fp.resolveClass(ct, in: nil) { declared = .instance(r) }
        let bare = FTClass.firstClassName(p.type)
        let needDoc = declared == nil || (bare.map { Self.isCollectionFQN(owner.resolve($0)) || $0.hasSuffix("Collection") } ?? true)
        if needDoc, let doc = docOf(owner, declStart: p.declStart, key: owner.fqn + "::$" + p.name), let v = doc.varType,
           let t = typeFromDoc(v, owner: owner, selfType: selfType) {
            if declared == nil { return t }
            if case .collection = t { return t }
        }
        return declared
    }

    /// `@property` / `@method` tags on the class chain (IDE-helper annotations, facade `@method static`).
    func docMemberType(_ f: String, _ member: String, isCall: Bool) -> FTType? {
        for k in hierarchy(f).prefix(6) {
            guard let doc = docOf(k, declStart: k.declStart, key: k.fqn + "::class") else { continue }
            if isCall {
                guard let m = doc.methods.first(where: { $0.name == member }) else { continue }
                var line = m.line.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("static ") { line = String(line.dropFirst(7)) }
                guard let paren = line.firstIndex(of: "(") else { continue }
                let head = line[..<paren].trimmingCharacters(in: .whitespaces)
                let words = head.split(separator: " ").map(String.init)
                guard words.count >= 2 else { continue }
                return typeFromDoc(words.dropLast().joined(separator: " "), owner: k, selfType: f)
            } else if let p = doc.props.first(where: { $0.name == member }) {
                return typeFromDoc(p.type, owner: k, selfType: f)
            }
        }
        return nil
    }

    // MARK: Functions and helpers

    /// Minimal owner for names written in a helper file: namespace + `use` imports.
    func pseudoOwner(_ text: NSString) -> FTClass {
        let k = FTClass()
        let s = text as String
        if let re = try? NSRegularExpression(pattern: #"(?m)^namespace\s+([\\\w]+)\s*;"#), let m = re.firstMatch(in: s, range: NSRange(location: 0, length: text.length)) {
            k.ns = text.substring(with: m.range(at: 1))
        }
        if let re = try? NSRegularExpression(pattern: #"(?m)^use\s+([\\\w]+)(?:\s+as\s+(\w+))?\s*;"#) {
            for m in re.matches(in: s, range: NSRange(location: 0, length: text.length)).prefix(80) {
                let full = text.substring(with: m.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: "\\"))
                let alias = m.range(at: 2).location != NSNotFound ? text.substring(with: m.range(at: 2)) : String(full.split(separator: "\\").last ?? "")
                k.uses[alias] = full
            }
        }
        return k
    }

    /// Return type of a global function from its declaration / docblock (user and vendor helper files).
    func functionReturn(_ name: String, args: (Int, Int)?) -> FTType? {
        var n = name
        if n.hasPrefix("\\") { n.removeFirst() }
        if n.contains("\\") { n = String(n.split(separator: "\\").last ?? "") }
        guard !n.isEmpty, !Self.keywords.contains(n) else { return nil }
        guard let found = NPFuncIndex.shared(root: fp.path).function(n), let t = NPFiles.text(found.path) else { return nil }
        let owner = pseudoOwner(t)
        if let sig = NPFuncIndex.signature(t, nameLoc: found.loc), !sig.ret.isEmpty,
           let ty = typeFromDoc(sig.ret, owner: owner, selfType: ""), !(isBareCollection(ty)) { return ty }
        guard let d = NPDoc.leading(t, before: found.declStart) else { return nil }
        let doc = NPDoc.parse(d.text, start: d.start)
        guard let ret = doc.ret?.type, !ret.isEmpty, !ret.hasPrefix("(") else { return nil }
        return typeFromDoc(ret, owner: owner, selfType: "", templates: templates(doc, owner: owner))
    }

    private func isBareCollection(_ t: FTType) -> Bool { if case .instance(let f) = t { return Self.isCollectionFQN(f) }; return false }

    /// `app()`, `app('cache')`, `resolve('x')`.
    func containerHelper(_ fn: String, args: (Int, Int)?) -> FTType? {
        guard let (a, b) = args else { return nil }
        if a >= b { return fn == "app" ? .instance(Self.containerAliases["app"]!) : nil }
        if lex.toks[a].kind == .string, b == a + 1 {
            let v = lex.strValue(a)
            if let c = Self.containerAliases[v] { return .instance(c) }
            if v.contains("\\"), let f = fp.resolveClass(v, in: nil) { return .instance(f) }
        }
        return nil
    }

    // MARK: Auth user

    /// `auth()->user()`, `Auth::user()`, `Auth::guard('x')`, `$request->user()`, `$guard->user()`.
    func authStep(_ f: String, _ member: String, isCall: Bool, args: (Int, Int)?) -> FTType? {
        guard isCall else { return nil }
        let isAuthFacade = f == Self.authFacade
        if member == "guard", isAuthFacade || f == Self.containerAliases["auth"] {
            authGuard = nil
            if let (a, b) = args, a < b, lex.toks[a].kind == .string { authGuard = lex.strValue(a) }
            return .instance(Self.guardFQN)
        }
        guard member == "user" else { return nil }
        let guardLike = f.hasSuffix("Guard") || f == Self.containerAliases["auth"] || hierarchy(f).contains { $0.fqn.hasSuffix("Guard") }
        let requestLike = f == Self.requestFQN || hierarchy(f).contains { $0.fqn == Self.requestFQN }
        guard isAuthFacade || guardLike || requestLike else { return nil }
        var g = authGuard
        if let (a, b) = args, a < b, lex.toks[a].kind == .string { g = lex.strValue(a) }
        return authModel(guard: g).map { .instance($0) }
    }

    /// User model class from config/auth.php (guard -> provider -> model), falling back to App\Models\User / App\User.
    func authModel(guard name: String?) -> String? {
        let key = name ?? ""
        if let c = authModelCache[key] { return c.isEmpty ? nil : c }
        var result = ""
        defer { authModelCache[key] = result }
        if let t = NPFiles.text(fp.path + "/config/auth.php") {
            let s = t as String
            let full = NSRange(location: 0, length: t.length)
            func first(_ pattern: String) -> String? {
                guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]), let m = re.firstMatch(in: s, range: full), m.numberOfRanges > 1,
                      m.range(at: 1).location != NSNotFound else { return nil }
                return t.substring(with: m.range(at: 1))
            }
            let guardName = name ?? first(#"'defaults'\s*=>\s*\[[^\]]*?'guard'\s*=>\s*(?:env\(\s*'[^']*'\s*,\s*)?'(\w+)'"#) ?? "web"
            let q = NSRegularExpression.escapedPattern(for: guardName)
            let provider = first("'\(q)'\\s*=>\\s*\\[[^\\]]*?'provider'\\s*=>\\s*'(\\w+)'") ?? "users"
            let pq = NSRegularExpression.escapedPattern(for: provider)
            if let written = first("'\(pq)'\\s*=>\\s*\\[[^\\]]*?'model'\\s*=>\\s*(?:env\\(\\s*'[^']*'\\s*,\\s*)?\\\\?([\\\\\\w]+)::class") {
                let owner = pseudoOwner(t)
                let fqn = written.contains("\\") && owner.uses[String(written.split(separator: "\\").first ?? "")] == nil ? written : owner.resolve(written)
                if fp.classPath(fqn) != nil { result = fqn }
            }
        }
        if result.isEmpty { for c in ["App\\Models\\User", "App\\User"] where fp.classPath(c) != nil { result = c; break } }
        return result.isEmpty ? nil : result
    }

    // MARK: Facade roots

    /// Root service class behind a facade (`getFacadeAccessor`: alias string or Foo::class; else the first `@see` class).
    func facadeRoot(_ f: String) -> String? {
        if let c = facadeRootCache[f] { return c.isEmpty ? nil : c }
        var result = ""
        defer { facadeRootCache[f] = result }
        let h = hierarchy(f)
        guard let k = h.first, f.hasPrefix("Illuminate\\Support\\Facades\\") || h.contains(where: { $0.fqn == "Illuminate\\Support\\Facades\\Facade" }),
              let t = fileText(of: k) else { return nil }
        if let re = try? NSRegularExpression(pattern: #"getFacadeAccessor\s*\(\s*\)[^{]*\{\s*return\s+(?:'([^']+)'|"([^"]+)"|\\?([\\\w]+)::class)"#),
           let m = re.firstMatch(in: t as String, range: NSRange(location: 0, length: t.length)) {
            for g in 1...2 where m.range(at: g).location != NSNotFound {
                let alias = t.substring(with: m.range(at: g))
                if let c = Self.containerAliases[alias] { result = c } else if alias.contains("\\"), fp.classPath(alias) != nil { result = alias }
            }
            if result.isEmpty, m.range(at: 3).location != NSNotFound {
                let c = k.resolve(t.substring(with: m.range(at: 3)))
                if fp.classPath(c) != nil { result = c }
            }
        }
        if result.isEmpty, let doc = docOf(k, declStart: k.declStart, key: k.fqn + "::class") {
            for s in doc.sees where s.contains("\\") && s.first != "h" {
                if let c = fp.resolveClass(s, in: k) { result = c; break }
            }
        }
        return result.isEmpty ? nil : result
    }

    // MARK: Docblock `@param` types for untyped / array parameters

    private static let modifiers: Set<String> = ["public", "private", "protected", "static", "final", "abstract"]

    func docParamType(_ fnTok: Int, _ name: String, declared: String) -> FTType? {
        let bare = FTClass.firstClassName(declared)
        guard declared.isEmpty || bare == nil || bare!.hasSuffix("Collection") else { return nil }
        var s = fnTok
        while s > 0, lex.toks[s - 1].kind == .ident, Self.modifiers.contains(lex.text(s - 1)) { s -= 1 }
        guard let d = NPDoc.leading(ns, before: lex.toks[s].loc) else { return nil }
        let doc = NPDoc.parse(d.text, start: d.start)
        guard let p = doc.params.first(where: { $0.name == name }), !p.type.isEmpty else { return nil }
        return typeFromDoc(p.type, owner: cur, selfType: cur?.fqn ?? "", templates: templates(doc, owner: cur))
    }
}
