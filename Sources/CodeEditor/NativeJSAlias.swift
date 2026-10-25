import Foundation
import SwiftTreeSitter

/// Bundler import aliases (vite.config.*, webpack.config.*, webpack.mix.js `resolve.alias`). Only aliases whose target is a literal
/// path expression are understood (`path.resolve(__dirname, 'src')`, `fileURLToPath(new URL('./src', import.meta.url))`, `'/src'`);
/// anything computed is ignored. The TypeScript server cannot follow these unless a tsconfig repeats them, so this is where native
/// resolves imports the server leaves unresolved.
struct NJSAlias {
    var key: String
    var target: String      // absolute path
}

extension NJSModules {
    static let aliasConfigNames = ["vite.config.js", "vite.config.mjs", "vite.config.ts", "vite.config.mts", "vite.config.cjs", "vite.config.cts",
                                   "webpack.config.js", "webpack.mix.js", "vue.config.js", "rspack.config.js", "rollup.config.js", "nuxt.config.ts", "nuxt.config.js"]

    private func aliasConfig(for dir: String) -> String? {
        lock.lock(); if let c = aliasConfigForDir[dir] { lock.unlock(); return c.isEmpty ? nil : c }; lock.unlock()
        var d = dir, found = ""
        for _ in 0..<12 {
            for n in NJSModules.aliasConfigNames where LaravelFS.isFile(d + "/" + n) { found = d + "/" + n; break }
            if !found.isEmpty || d == "/" || d.isEmpty || d == root { break }
            d = (d as NSString).deletingLastPathComponent
        }
        if found.isEmpty, d == root || d.isEmpty { for n in NJSModules.aliasConfigNames where LaravelFS.isFile(root + "/" + n) { found = root + "/" + n; break } }
        lock.lock(); aliasConfigForDir[dir] = found; lock.unlock()
        return found.isEmpty ? nil : found
    }

    func aliases(inConfig path: String) -> [NJSAlias] {
        let stamp = LaravelFS.mtime(path)
        lock.lock()
        if let c = aliasCache[path], c.stamp == stamp { lock.unlock(); return c.list }
        lock.unlock()
        var list: [NJSAlias] = []
        if let text = FastProject.read(path), text.length < 400_000 {
            if let doc = NJSDoc(path: path, text: text) {
                list = withExtendedLifetime(doc) { NJSAliasParser(ns: text, cfgDir: (path as NSString).deletingLastPathComponent, root: doc.root).parse() }
            }
        }
        lock.lock()
        if aliasCache.count > 16 { aliasCache.removeAll() }
        aliasCache[path] = (stamp, list)
        lock.unlock()
        return list
    }

    func resolveBundlerAlias(_ spec: String, dir: String) -> String? {
        guard !spec.hasPrefix("."), !spec.hasPrefix("/"), let cfg = aliasConfig(for: dir) else { return nil }
        // longest key first (vite checks them in order; the most specific wins for the same prefix)
        for a in aliases(inConfig: cfg).sorted(by: { $0.key.count > $1.key.count }) {
            if spec == a.key { if let r = tryModule(a.target, preferTypes: true) { return r }; continue }
            if spec.hasPrefix(a.key + "/") || (a.key.hasSuffix("/") && spec.hasPrefix(a.key)) {
                let rest = spec.dropFirst(a.key.count).drop(while: { $0 == "/" })
                if let r = tryModule(NJSModules.join(a.target, String(rest)), preferTypes: true) { return r }
            }
        }
        return nil
    }
}

struct NJSAliasParser {
    let ns: NSString
    let cfgDir: String
    let root: Node

    func parse() -> [NJSAlias] {
        var out: [NJSAlias] = []
        var stack: [Node] = [root]
        while let n = stack.popLast() {
            if n.kind == "pair", let k = n.field("key"), keyText(k) == "alias", let v = n.field("value") {
                if v.kind == "object" { out += objectAliases(v) }
                else if v.kind == "array" { out += arrayAliases(v) }
            }
            if n.namedChildCount > 0 { stack.append(contentsOf: n.kids) }
        }
        return out
    }

    private func keyText(_ n: Node) -> String? {
        switch n.kind {
        case "property_identifier", "identifier": return n.text(ns)
        case "string": return n.kids.first(where: { $0.kind == "string_fragment" })?.text(ns) ?? ""
        default: return nil
        }
    }

    private func objectAliases(_ obj: Node) -> [NJSAlias] {
        var out: [NJSAlias] = []
        for p in obj.kids where p.kind == "pair" {
            guard let k = p.field("key"), let key = keyText(k), !key.isEmpty, let v = p.field("value"), let t = eval(v) else { continue }
            out.append(NJSAlias(key: key, target: literal(v) != nil ? normalise(t) : t))
        }
        return out
    }

    private func arrayAliases(_ arr: Node) -> [NJSAlias] {
        var out: [NJSAlias] = []
        for o in arr.kids where o.kind == "object" {
            var find: String?, repl: String?
            var replIsLiteral = false
            for p in o.kids where p.kind == "pair" {
                guard let k = p.field("key"), let key = keyText(k), let v = p.field("value") else { continue }
                if key == "find", v.kind == "string" { find = keyText(v) }
                if key == "replacement" { repl = eval(v); replIsLiteral = literal(v) != nil }
            }
            if let f = find, let r = repl, !f.isEmpty { out.append(NJSAlias(key: f, target: replIsLiteral ? normalise(r) : r)) }
        }
        return out
    }

    private func normalise(_ t: String) -> String {
        if t.hasPrefix("/") { return LaravelFS.exists(t) ? NJSModules.join("/", t) : NJSModules.join(cfgDir, String(t.dropFirst())) }
        return NJSModules.join(cfgDir, t)
    }

    private func literal(_ n: Node) -> String? {
        if n.kind == "string" { return n.kids.first(where: { $0.kind == "string_fragment" })?.text(ns) ?? "" }
        if n.kind == "template_string", n.kids.allSatisfy({ $0.kind == "string_fragment" }) { return n.kids.map { $0.text(ns) }.joined() }
        return nil
    }

    /// Value of a literal path expression, or nil when it is computed.
    private func eval(_ n: Node) -> String? {
        if let s = literal(n) { return s }
        switch n.kind {
        case "identifier": return n.text(ns) == "__dirname" ? cfgDir : nil
        case "parenthesized_expression": return n.kids.first.flatMap(eval)
        case "call_expression":
            guard let f = n.field("function"), let args = n.field("arguments") else { return nil }
            let name = f.text(ns)
            let a = args.kids
            if name == "path.resolve" || name == "resolve" || name == "path.join" || name == "join" || name == "pathResolve" {
                var cur = ""
                for x in a {
                    if x.kind == "call_expression", x.field("function")?.text(ns) == "process.cwd" { cur = cfgDir; continue }
                    guard let v = eval(x) else { return nil }
                    cur = v.hasPrefix("/") ? v : NJSModules.join(cur.isEmpty ? cfgDir : cur, v)
                }
                return cur.isEmpty ? nil : cur
            }
            if name == "fileURLToPath", let u = a.first { return eval(u) }
            return nil
        case "new_expression":
            // new URL('./src', import.meta.url)
            guard let c = n.field("constructor"), c.text(ns) == "URL", let args = n.field("arguments"), let first = args.kids.first, let rel = literal(first) else { return nil }
            return NJSModules.join(cfgDir, rel)
        case "member_expression":
            // new URL(...).pathname
            if let p = n.field("property"), p.text(ns) == "pathname", let o = n.field("object") { return eval(o) }
            return nil
        default: return nil
        }
    }
}
