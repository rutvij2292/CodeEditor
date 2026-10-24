import Foundation

// Undefined class references, unused / duplicate imports.

extension NPDiagContext {
    private static let reservedNames: Set<String> = [
        "self", "static", "parent", "int", "float", "string", "bool", "array", "callable", "iterable", "object", "mixed", "void", "null", "false",
        "true", "never", "integer", "double", "boolean", "resource", "numeric", "scalar", "list", "class", "namespace",
    ]
    private static let modifiers: Set<String> = ["public", "protected", "private", "static", "readonly", "var", "final", "abstract"]

    // MARK: Class reference extraction

    /// Token indices of identifiers used as class names, in a position where PHP requires a class.
    func classRefs() -> [Int] {
        var refs = Set<Int>()
        var inParams = [Bool](repeating: false, count: n)
        func addType(_ k: Int) {
            guard isIdent(k), !isMember(k) else { return }
            refs.insert(k)
        }
        var i = 0
        while i < n {
            let t = toks[i]
            if inImport[i] { i += 1; continue }
            if t.kind == .ident, !isMember(i) {
                let l = lower(i)
                switch l {
                case "new":
                    if i + 1 < n, isIdent(i + 1) { addType(i + 1) }
                case "extends", "implements":
                    var j = i + 1
                    while j < n, isIdent(j) {
                        addType(j); j += 1
                        if punct(j, ",") { j += 1 } else { break }
                    }
                case "instanceof":
                    if i + 1 < n, isIdent(i + 1) { addType(i + 1) }
                case "catch":
                    if i + 1 < n, punct(i + 1, "("), lex.match[i + 1] > i + 1 {
                        for k in (i + 2)..<lex.match[i + 1] where toks[k].kind == .ident { addType(k) }
                    }
                case "use":
                    if kind[i] == 1, i + 1 < n, isIdent(i + 1) {
                        var j = i + 1
                        while j < n, isIdent(j) {
                            addType(j); j += 1
                            if punct(j, ",") { j += 1 } else { break }
                        }
                    }
                case "function", "fn":
                    functionTypes(i, &refs, &inParams)
                default:
                    if i + 1 < n, isDColon(i + 1) { addType(i) }
                }
            } else if t.kind == .punct, t.ch == 35, i + 1 < n, punct(i + 1, "["), lex.match[i + 1] > i + 1 {       // #[Attribute]
                let open = i + 1, close = lex.match[open]
                var k = open + 1
                var expectName = true
                while k < close {
                    let tk = toks[k]
                    if tk.kind == .ident, expectName { addType(k); expectName = false }
                    if tk.kind == .punct, tk.ch == 44 { expectName = true }
                    if tk.kind == .punct, tk.ch == 40, lex.match[k] > k { k = lex.match[k] }
                    k += 1
                }
            } else if t.kind == .variable, kind[i] == 1, !inParams[i] {
                // typed property: modifiers then type tokens then $name
                var j = i - 1
                var types: [Int] = []
                var sawModifier = false
                while j >= 0, j > i - 12 {
                    let tk = toks[j]
                    if tk.kind == .ident {
                        let lj = lower(j)
                        if Self.modifiers.contains(lj) { sawModifier = true } else if lj != "set" && lj != "get" { types.append(j) }
                    } else if tk.kind == .punct, [63, 124, 38, 40, 41].contains(tk.ch) {
                    } else { break }
                    j -= 1
                }
                if sawModifier { for k in types { addType(k) } }
            }
            i += 1
        }
        return refs.sorted()
    }

    private func functionTypes(_ f: Int, _ refs: inout Set<Int>, _ inParams: inout [Bool]) {
        var j = f + 1
        if punct(j, "&") { j += 1 }
        if kw(f, "function"), isIdent(j) { j += 1 }
        guard j < n, punct(j, "("), lex.match[j] > j else { return }
        let p = j, c = lex.match[p]
        for k in (p + 1)..<c { inParams[k] = true }
        var k = p + 1
        while k < c {
            var after = false
            segment: while k < c {
                let t = toks[k]
                if t.kind == .punct {
                    if t.ch == 44 { k += 1; break segment }
                    if t.ch == 35, k + 1 < c, punct(k + 1, "["), lex.match[k + 1] > k { k = lex.match[k + 1] + 1; continue }
                    if t.ch == 61 {
                        k += 1
                        while k < c, !punct(k, ",") {
                            if toks[k].kind == .punct, [40, 91, 123].contains(toks[k].ch), lex.match[k] > k { k = lex.match[k] + 1 } else { k += 1 }
                        }
                        continue
                    }
                    k += 1; continue
                }
                if t.kind == .variable { after = true; k += 1; continue }
                if t.kind == .ident, !after, !Self.modifiers.contains(lower(k)), !isMember(k) { refs.insert(k) }
                k += 1
            }
        }
        // closure `use (...)` then return type
        var r = c + 1
        if kw(r, "use"), punct(r + 1, "("), lex.match[r + 1] > r { r = lex.match[r + 1] + 1 }
        if punct(r, ":") {
            r += 1
            var steps = 0
            while r < n, steps < 40 {
                let t = toks[r]
                if t.kind == .punct, t.ch == 123 || t.ch == 59 || t.ch == PHPTok.fat || t.ch == 44 { break }
                if t.kind == .ident, !isMember(r) { refs.insert(r) }
                r += 1; steps += 1
            }
        }
    }

    // MARK: Project facts

    private var composerFacts: (vendorReady: Bool, classmap: Bool, prefixes: [String]) {
        let root = fp.path
        var vendorReady = LaravelFS.isFile(root + "/vendor/composer/autoload_psr4.php") && VendorIndex.enabled
        if vendorReady {
            // Classmap-only packages (PHPUnit, Mockery ...) are known only to the vendor index: judge vendor names once it is loaded.
            let idx = VendorIndex.shared(for: URL(fileURLWithPath: root))
            _ = idx.find(fqn: "")                       // maps the on-disk table when it exists (a few ms)
            if !idx.isReady {
                vendorReady = false
                idx.refreshIfNeeded { if idx.isReady { NotificationCenter.default.post(name: NativePHPDiagController.settingsDidChange, object: nil) } }
            }
        }
        var classmap = false
        if let d = FileManager.default.contents(atPath: root + "/composer.json"), let s = String(data: d, encoding: .utf8) {
            classmap = s.contains("\"classmap\"") || s.contains("\"exclude-from-classmap\"") && false
        }
        let prefixes = fp.lp.psr4.filter { entry in entry.dirs.contains { !$0.contains("/vendor/") } }.map { $0.prefix }
        return (vendorReady, classmap, prefixes)
    }

    /// Short names (lowercased) of types declared in composer `autoload.files` (e.g. Mockery, which is loaded through a file, not an autoloader).
    private var autoloadFileTypes: Set<String> {
        let key = fp.path
        let stamp = LaravelFS.mtime(key + "/vendor/composer/autoload_files.php") &+ LaravelFS.mtime(key + "/composer.json") &* 31
        NPDiagContext.filesLock.lock()
        if let hit = NPDiagContext.filesCache[key], hit.stamp == stamp { NPDiagContext.filesLock.unlock(); return hit.names }
        NPDiagContext.filesLock.unlock()
        var names = Set<String>()
        let re = try? NSRegularExpression(pattern: #"(?m)^[ \t]*(?:(?:abstract|final|readonly)[ \t]+)*(?:class|interface|trait|enum)[ \t]+([A-Za-z_]\w*)"#)
        for f in Self.autoloadFilePaths(root: key) {
            guard let t = FastProject.read(f), t.length < 600_000 else { continue }
            for m in re?.matches(in: t as String, range: NSRange(location: 0, length: t.length)) ?? [] { names.insert(t.substring(with: m.range(at: 1)).lowercased()) }
        }
        NPDiagContext.filesLock.lock()
        NPDiagContext.filesCache[key] = (stamp, names)
        if NPDiagContext.filesCache.count > 4 { NPDiagContext.filesCache = [key: (stamp, names)] }
        NPDiagContext.filesLock.unlock()
        return names
    }

    private static func autoloadFilePaths(root: String) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ p: String) { if seen.insert(p).inserted, LaravelFS.isFile(p) { out.append(p) } }
        if let t = FastProject.read(root + "/vendor/composer/autoload_files.php") {
            let re = try? NSRegularExpression(pattern: #"\$(vendorDir|baseDir)\s*\.\s*'([^']+)'"#)
            for m in re?.matches(in: t as String, range: NSRange(location: 0, length: t.length)) ?? [] {
                add((t.substring(with: m.range(at: 1)) == "vendorDir" ? root + "/vendor" : root) + t.substring(with: m.range(at: 2)))
            }
        }
        if let d = FileManager.default.contents(atPath: root + "/composer.json"), let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            for key in ["autoload", "autoload-dev"] { for f in ((obj[key] as? [String: Any])?["files"] as? [String]) ?? [] { add(root + "/" + f) } }
        }
        return Array(out.prefix(60))
    }

    private var aliasNames: Set<String> {
        var out = Set(FastProject.facadeAliases.keys.map { $0.lowercased() })
        if let t = FastProject.read(fp.path + "/config/app.php") {
            let re = try? NSRegularExpression(pattern: #"['"]([A-Za-z_][A-Za-z0-9_]*)['"]\s*=>"#)
            let s = t as NSString
            for m in re?.matches(in: t as String, range: NSRange(location: 0, length: min(s.length, 200_000))) ?? [] {
                out.insert(s.substring(with: m.range(at: 1)).lowercased())
            }
        }
        return out
    }

    /// `use App\Models;` followed by `Models\Post`: the import names a namespace, not a class.
    private func isNamespaceImport(_ imp: NPImport) -> Bool {
        let prefix = imp.alias.lowercased() + "\\"
        for i in 0..<n where toks[i].kind == .ident && !inImport[i] && lower(i).hasPrefix(prefix) { return true }
        let rel = imp.fqn.replacingOccurrences(of: "\\", with: "/")
        for entry in fp.lp.psr4 where imp.fqn.hasPrefix(entry.prefix) || (imp.fqn + "\\").hasPrefix(entry.prefix) {
            let rest = imp.fqn.count >= entry.prefix.count ? String(rel.dropFirst(entry.prefix.replacingOccurrences(of: "\\", with: "/").count)) : ""
            for d in entry.dirs where LaravelFS.isDir(d + "/" + rest) { return true }
        }
        return false
    }

    // MARK: Pass

    func namesPass(classes: Bool, imports wantImports: Bool) -> [NPDiag] {
        guard namespaceCount <= 1 else { return [] }
        var out: [NPDiag] = []
        let facts = composerFacts
        let aliases = aliasNames
        let fileTypes = autoloadFileTypes
        let optOut = ns.range(of: "class_alias(", options: .literal).location != NSNotFound || ns.range(of: "spl_autoload_register(", options: .literal).location != NSNotFound
        func judgeable(_ fqn: String) -> Bool {
            if facts.prefixes.contains(where: { fqn.hasPrefix($0) }) { return true }
            return facts.vendorReady && !facts.classmap
        }
        func exists(_ fqn: String) -> Bool {
            if localTypes.contains(fqn.lowercased()) { return true }
            if NPDiagBuiltins.contains(fqn) || PHPStubs.hasClass(fqn) { return true }
            if fqn.hasPrefix("Facades\\") { return true }
            if fp.classPath(fqn) != nil { return true }
            if !fqn.contains("\\"), aliases.contains(fqn.lowercased()) { return true }
            if fileTypes.contains((fqn.split(separator: "\\").last.map(String.init) ?? fqn).lowercased()) { return true }
            return false
        }
        var badAliases = Set<String>()

        // Imports: undefined, duplicate, unused.
        var seenFqn: [String: Int] = [:]
        var seenAlias: [String: String] = [:]
        let words = wantImports ? wordSet : []
        for imp in imports where imp.kind == "class" {
            let fl = imp.fqn.lowercased(), al = imp.alias.lowercased()
            if classes, !optOut, judgeable(imp.fqn), !exists(imp.fqn), !isNamespaceImport(imp) {
                badAliases.insert(al)
                out.append(NPDiag(range: imp.range, severity: classSeverity, message: "Undefined class '\(imp.fqn)'", code: "undefined-class", group: .classes))
                continue
            }
            guard wantImports else { continue }
            if let prevAlias = seenAlias[al] {
                if prevAlias == fl {
                    out.append(NPDiag(range: imp.range, severity: 2, message: "Duplicate import of '\(imp.fqn)'", code: "duplicate-import", group: .imports))
                } else {
                    out.append(NPDiag(range: imp.range, severity: 1, message: "Cannot use '\(imp.fqn)' as '\(imp.alias)' because the name is already in use",
                                      code: "duplicate-import", group: .imports))
                }
                continue
            }
            seenAlias[al] = fl
            seenFqn[fl] = imp.nameTok
            if localTypes.contains(al) || localTypes.contains((namespace.isEmpty ? al : namespace.lowercased() + "\\" + al)) { continue }
            if !words.contains(al) {
                out.append(NPDiag(range: imp.range, severity: 4, message: "Unused import '\(imp.fqn)'", code: "unused-import", group: .imports))
            }
        }

        // Undefined class references.
        if classes, !optOut {
            var reported = 0
            for i in classRefs() {
                let written = text(i)
                let lw = written.lowercased()
                if Self.reservedNames.contains(lw) { continue }
                if written.contains("$") { continue }
                let (fqn, via) = resolve(written)
                if let via, badAliases.contains(via.alias.lowercased()) { continue }
                if fqn.isEmpty || exists(fqn) { continue }
                if !judgeable(fqn) { continue }
                // An unqualified name in the global namespace may be a runtime alias we cannot see.
                if namespace.isEmpty, via == nil, !written.contains("\\") { continue }
                out.append(NPDiag(range: range(i), severity: classSeverity, message: "Undefined class '\(written.hasPrefix("\\") ? String(written.dropFirst()) : written)'",
                                  code: "undefined-class", group: .classes))
                reported += 1
                if reported >= 60 { break }
            }
        }
        return out
    }
}
