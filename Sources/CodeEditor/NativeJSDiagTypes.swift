import Foundation
import SwiftTreeSitter

/// Phase 4: type-level diagnostics, only where the answer is provable from declarations the engine reads exactly.
///  - TS2304 `Cannot find name 'x'` for a plain identifier used as a value that no scope, import, project / lib / @types global declares;
///  - TS2554 argument count of a call to a single, non-overloaded function declaration.
/// Off by default (`js.diag.types`): enabled by the user, or by the false-positive scan (`CE_NJS_TYPES=<dir>`) when it reports nothing.
/// Only TypeScript files are judged (tsc does not check JavaScript without checkJs) and never .vue files.
extension NativeJSDiag {
    static let typesKey = "js.diag.types"
    static var typesEnabled: Bool {
        get { UserDefaults.standard.object(forKey: typesKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: typesKey) }
    }

    private static let skipKinds: Set<String> = ["internal_module", "module", "ambient_declaration", "enum_body", "decorator", "class_heritage", "extends_clause", "implements_clause"]
    private static let neverFlag: Set<String> = ["undefined", "arguments", "globalThis", "NaN", "Infinity", "require", "module", "exports", "__dirname", "__filename", "process", "Buffer", "global", "console", "window", "document", "self"]

    private static func isValueContext(_ n: Node, _ p: Node, _ env0: NSString) -> Bool {
        switch p.kind {
        case "call_expression": return p.field("function") == n
        case "member_expression": return p.field("object") == n
        case "new_expression": return p.field("constructor") == n
        case "unary_expression": return p.field("operator")?.text(env0) != "typeof"       // `typeof undeclared` is not an error
        case "arguments", "binary_expression", "ternary_expression", "await_expression", "parenthesized_expression", "spread_element", "array",
             "template_substitution", "return_statement", "non_null_expression", "subscript_expression", "expression_statement", "sequence_expression", "jsx_expression":
            return true
        case "as_expression", "satisfies_expression": return p.kids.first == n
        case "variable_declarator": return p.field("value") == n
        case "pair": return p.field("value") == n
        case "assignment_expression": return p.field("right") == n
        case "arrow_function": return p.field("body") == n
        default: return false
        }
    }

    static func typeErrors(env: NJSEnv) -> [NPDiag] {
        let doc = env.doc
        let path = env.path
        guard doc.lang != .js, !doc.isVue, doc.text.length < 400_000, !path.hasSuffix(".d.ts"), !path.hasSuffix(".d.mts"), !path.hasSuffix(".d.cts"), !doc.root.hasError else { return [] }
        let ns = doc.text
        guard NativeJS.libsEnabled, !env.libTop("Array").isEmpty, !env.libTop("Promise").isEmpty else { return [] }        // no lib program: nothing can be judged
        if ns.range(of: "@ts-nocheck").location != NSNotFound || ns.range(of: "declare global").location != NSNotFound { return [] }
        guard env.proj.modules.programIncludes(path) == true else { return [] }
        let programDir = env.proj.modules.configPath(for: (path as NSString).deletingLastPathComponent).map { ($0 as NSString).deletingLastPathComponent } ?? env.proj.root
        if NativeJSDiag.scriptDeclarationsExist(under: programDir) { return [] }                  // global declarations the engine does not read: names cannot be judged
        var aliasNames = Set<String>()                                                           // `import a = ns.b` declares a                  // tsserver would check this file with other options
        var out: [NPDiag] = []
        var stack: [Node] = [doc.root]
        var visited = 0
        while let n = stack.popLast(), visited < 60_000, out.count < 50 {
            visited += 1
            if skipKinds.contains(n.kind) { continue }
            if n.kind == "import_alias", let nm = n.kids.first { aliasNames.insert(nm.text(ns)) }
            if n.kind == "identifier", let p = n.parent, isValueContext(n, p, ns) {
                let name = n.text(ns)
                if !neverFlag.contains(name), env.localBinding(name, from: n) == nil, doc.summary.top[name] == nil, !aliasNames.contains(name), env.resolveName(path, name).isEmpty, !name.hasPrefix("__") {
                    out.append(NPDiag(range: n.range, severity: 1, message: "Cannot find name '\(name)'.", code: "TS2304", group: .variables))
                }
            } else if n.kind == "call_expression", let d = argumentCount(n, env: env) { out.append(d) }
            if n.namedChildCount > 0 { stack.append(contentsOf: n.kids) }
        }
        return out
    }

    private static func argumentCount(_ call: Node, env: NJSEnv) -> NPDiag? {
        let ns = env.doc.text
        guard let f = call.field("function"), f.kind == "identifier", let argsNode = call.field("arguments"), call.field("type_arguments") == nil else { return nil }
        let args = argsNode.kids
        if args.contains(where: { $0.kind == "spread_element" }) { return nil }
        let name = f.text(ns)
        var declared: [NJSRes]
        if let b = env.localBinding(name, from: f) {
            guard b.kind == .function, b.declNode.kind == "function_declaration" else { return nil }
            declared = [env.resolve(b)]
        } else {
            declared = env.resolveName(env.path, name)
        }
        guard declared.count == 1, declared[0].kind == .function, !declared[0].overload, declared[0].path == env.path, env.doc.summary.top[name]?.count == 1 else { return nil }
        guard case .fn(let fn) = env.infer.ty(f), fn.tparams.isEmpty || true else { return nil }
        let required = fn.params.filter { !$0.optional && !$0.rest }.count
        let hasRest = fn.params.contains { $0.rest }
        let max = fn.params.count
        guard args.count < required || (!hasRest && args.count > max) else { return nil }
        let message: String
        if hasRest { message = "Expected at least \(required) arguments, but got \(args.count)." }
        else if required == max { message = "Expected \(max) argument\(max == 1 ? "" : "s"), but got \(args.count)." }
        else { message = "Expected \(required)-\(max) arguments, but got \(args.count)." }
        let r = args.count > max && args.count > 0 ? NSRange(location: args[max].start, length: args[args.count - 1].end - args[max].start) : f.range
        return NPDiag(range: r, severity: 1, message: message, code: "TS2554", group: .args)
    }
}

extension NJSModules {
    /// Whether the tsconfig that governs `file` (nearest one up the tree, as tsserver picks it) puts the file in its program: true / false,
    /// nil when it cannot be told (`extends` without own include, solution-style references, unreadable). No tsconfig: an inferred project.
    func programIncludes(_ file: String) -> Bool? {
        guard let p = configPath(for: (file as NSString).deletingLastPathComponent) else { return true }
        guard let (raw, _) = rawConfig(p) else { return nil }
        let dir = (p as NSString).deletingLastPathComponent
        guard file.hasPrefix(dir + "/") else { return nil }
        let rel = String(file.dropFirst(dir.count + 1))
        let ownFiles = raw["files"] as? [String]
        let ownInclude = raw["include"] as? [String]
        if raw["extends"] != nil, ownFiles == nil, ownInclude == nil { return nil }
        if let refs = raw["references"] as? [Any], !refs.isEmpty, ownInclude == nil, (ownFiles ?? []).isEmpty { return nil }
        if let f = ownFiles, f.contains(where: { NJSModules.join(dir, $0) == file }) { return true }
        let include = ownInclude ?? (ownFiles == nil ? ["**/*"] : [])
        var exclude = raw["exclude"] as? [String] ?? ["node_modules", "bower_components", "jspm_packages"]
        if let co = raw["compilerOptions"] as? [String: Any], let out = co["outDir"] as? String, raw["exclude"] == nil { exclude.append(out) }
        func matches(_ pattern: String) -> Bool {
            var pat = pattern
            while pat.hasPrefix("./") { pat.removeFirst(2) }
            if pat.hasSuffix("/") { pat.removeLast() }
            let last = pat.split(separator: "/").last.map(String.init) ?? pat
            let hasWildcardName = last.contains("*") || last.contains("?")
            var rx = "^"
            var i = pat.startIndex
            while i < pat.endIndex {
                let c = pat[i]
                if c == "*" {
                    let next = pat.index(after: i)
                    if next < pat.endIndex, pat[next] == "*" {
                        let after = pat.index(after: next)
                        if after < pat.endIndex, pat[after] == "/" { rx += "(.*/)?"; i = pat.index(after: after); continue }
                        rx += ".*"; i = after; continue
                    }
                    rx += "[^/]*"
                } else if c == "?" { rx += "[^/]" } else { rx += NSRegularExpression.escapedPattern(for: String(c)) }
                i = pat.index(after: i)
            }
            if !hasWildcardName { rx += "(/.*)?" }
            rx += "$"
            return rel.range(of: rx, options: .regularExpression) != nil
        }
        if exclude.contains(where: { matches($0) }) { return false }
        return include.contains(where: { matches($0) })
    }
}

extension NativeJSDiag {
    private static let scriptLock = NSLock()
    private static var scriptCache: [String: (at: Date, value: Bool)] = [:]

    /// True when a `.d.ts` file without top-level import / export (a script: its declarations are global) lives under `dir` outside
    /// node_modules. The engine does not read those into the global scope, so unknown names cannot be judged there.
    static func scriptDeclarationsExist(under dir: String) -> Bool {
        scriptLock.lock()
        if let c = scriptCache[dir], Date().timeIntervalSince(c.at) < 30 { scriptLock.unlock(); return c.value }
        scriptLock.unlock()
        var found = false
        var visited = 0
        let skip: Set<String> = ["node_modules", ".git", "dist", "build", "vendor", "storage", "cache", ".next", ".nuxt", "out", "coverage", "public"]
        if let en = FileManager.default.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let u as URL in en {
                visited += 1
                if visited > 40_000 { found = true; break }                                      // too big to know: do not judge
                let name = u.lastPathComponent
                if skip.contains(name) { en.skipDescendants(); continue }
                guard name.hasSuffix(".d.ts") else { continue }
                guard let t = FastProject.read(u.path), t.length < 600_000 else { found = true; break }
                if t.range(of: "^\\s*(import|export)\\b", options: .regularExpression).location == NSNotFound { found = true; break }
            }
        }
        scriptLock.lock(); scriptCache[dir] = (Date(), found); scriptLock.unlock()
        return found
    }
}
