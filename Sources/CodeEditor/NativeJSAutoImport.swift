import AppKit
import SwiftTreeSitter

/// Auto-import completion: while typing an identifier, exported names of other project files (and of the project's dependencies) that
/// are not in scope are offered with an `import` edit that is applied when the item is accepted. The export names come from the same
/// byte-level scan the import graph keeps (no parse), the module specifier is the shorter of the relative path and a tsconfig `paths` /
/// bundler alias, the edit joins an existing `import { ... } from` of the same module when there is one, and quote / semicolon style
/// follow the file.
extension NJSModules {
    private static let codeSuffixes = [".d.ts", ".d.mts", ".d.cts", ".tsx", ".ts", ".mts", ".cts", ".jsx", ".js", ".mjs", ".cjs"]

    private static func stripped(_ rel: String) -> String {
        var r = rel
        for s in codeSuffixes where r.hasSuffix(s) { r = String(r.dropLast(s.count)); break }
        if r.hasSuffix("/index") { r = String(r.dropLast(6)) } else if r == "index" { r = "." }
        return r
    }

    private static func relativePath(from dir: String, to target: String) -> String {
        let a = dir.split(separator: "/").map(String.init), b = target.split(separator: "/").map(String.init)
        var i = 0
        while i < a.count, i < b.count - 1, a[i] == b[i] { i += 1 }
        let ups = Array(repeating: "..", count: a.count - i)
        let rest = Array(b[i...])
        return (ups + rest).joined(separator: "/")
    }

    /// The text of an import of `target` written in `file`: relative, or an alias when that is shorter / avoids climbing out.
    func importSpecifier(from file: String, to target: String) -> String {
        let dir = (file as NSString).deletingLastPathComponent
        var rel = NJSModules.stripped(NJSModules.relativePath(from: dir, to: target))
        if !rel.hasPrefix(".") { rel = "./" + rel }
        var best = rel
        func consider(_ spec: String) {
            if best == rel { if rel.hasPrefix("../") || spec.count < rel.count { best = spec } } else if spec.count < best.count { best = spec }
        }
        if let cfg = config(for: file) {
            for r in cfg.rules where r.star {
                for t in r.targets {
                    guard let star = t.firstIndex(of: "*") else { continue }
                    let base = NJSModules.join(cfg.pathsBase, String(t[..<star]))
                    let tail = String(t[t.index(after: star)...])
                    if target.hasPrefix(base + "/") || target == base {
                        var rest = String(target.dropFirst(base.count)).drop(while: { $0 == "/" }).description
                        if !tail.isEmpty, rest.hasSuffix(tail) { rest = String(rest.dropLast(tail.count)) }
                        consider(r.prefix + NJSModules.stripped(rest) + r.suffix)
                    }
                }
            }
        }
        var d = dir
        for _ in 0..<12 {
            for n in NJSModules.aliasConfigNames where LaravelFS.isFile(d + "/" + n) {
                for a in aliases(inConfig: d + "/" + n) where target.hasPrefix(a.target + "/") {
                    consider(a.key + "/" + NJSModules.stripped(String(target.dropFirst(a.target.count + 1))))
                }
            }
            if d == "/" || d.isEmpty || LaravelFS.exists(d + "/.git") { break }
            d = (d as NSString).deletingLastPathComponent
        }
        return best
    }
}

enum NJSAutoImport {
    struct Candidate { var name: String; var spec: String; var isDefault: Bool }

    /// Identifier made from a file name (`user-card.vue` -> `UserCard`; `index.ts` -> its folder).
    static func defaultName(for path: String) -> String {
        var base = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        if base.hasSuffix(".d") { base = String(base.dropLast(2)) }
        if base == "index" { base = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent }
        var out = ""
        var up = true
        for ch in base {
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "$" { out.append(up ? Character(ch.uppercased()) : ch); up = false } else { up = true }
        }
        if let f = out.first, f.isNumber { out = "_" + out }
        return out
    }

    private static func matches(_ name: String, _ prefix: String) -> Bool {
        let n = name.lowercased(), p = prefix.lowercased()
        return n.hasPrefix(p) || (p.count >= 3 && n.contains(p))
    }

    /// Candidates for `prefix` in project files (from the scan cache) and dependencies (their typings' export names, cached).
    static func candidates(prefix: String, file: String, proj: NJSProject, env: NJSEnv, localNames: Set<String>) -> [Candidate] {
        var out: [Candidate] = []
        var seen = Set<String>()
        let scans = proj.graph.snapshot()
        for (path, s) in scans where path != file && !path.contains("/node_modules/") && path.hasPrefix(proj.root + "/") {
            guard !s.exportNames.isEmpty || s.hasDefault else { continue }
            var spec: String?
            func spec_() -> String { if let sp = spec { return sp }; let sp = proj.modules.importSpecifier(from: file, to: path); spec = sp; return sp }
            for n in s.exportNames where matches(n, prefix) && !localNames.contains(n) {
                if seen.insert(n + "\u{0}" + path).inserted { out.append(Candidate(name: n, spec: spec_(), isDefault: false)) }
            }
            if s.hasDefault {
                let dn = s.defaultName.isEmpty ? defaultName(for: path) : s.defaultName
                if !dn.isEmpty, matches(dn, prefix), !localNames.contains(dn), seen.insert(dn + "\u{0}" + path + "d").inserted { out.append(Candidate(name: dn, spec: spec_(), isDefault: true)) }
            }
            if out.count > 400 { break }
        }
        // dependencies: only for longer prefixes, within a small time budget
        if prefix.count >= 3 {
            let started = DispatchTime.now().uptimeNanoseconds
            for (dep, names) in dependencyExports(proj: proj, env: env, budgetNs: 150_000_000, started: started) {
                for n in names where matches(n, prefix) && !localNames.contains(n) && seen.insert(n + "\u{0}" + dep).inserted { out.append(Candidate(name: n, spec: dep, isDefault: false)) }
            }
        }
        out.sort { a, b in
            let ap = a.name.lowercased().hasPrefix(prefix.lowercased()), bp = b.name.lowercased().hasPrefix(prefix.lowercased())
            if ap != bp { return ap }
            if a.name.count != b.name.count { return a.name.count < b.name.count }
            return a.spec.count < b.spec.count
        }
        return Array(out.prefix(60))
    }

    private static let depLock = NSLock()
    private static var depCache: [String: [String: [String]]] = [:]       // project root -> dependency -> export names

    static func dropCaches() { depLock.lock(); depCache.removeAll(); depLock.unlock() }

    private static func dependencyNames(root: String) -> [String] {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: root + "/package.json")), case .o(let pairs)? = NJSOJ.parse(d) else { return [] }
        var out: [String] = []
        for key in ["dependencies", "devDependencies"] {
            if case .o(let deps)? = pairs.first(where: { $0.0 == key })?.1 { out += deps.map { $0.0 } }
        }
        return out.filter { !$0.hasPrefix("@types/") }
    }

    private static func dependencyExports(proj: NJSProject, env: NJSEnv, budgetNs: UInt64, started: UInt64) -> [(String, [String])] {
        depLock.lock(); var known = depCache[proj.root] ?? [:]; depLock.unlock()
        for dep in dependencyNames(root: proj.root) where known[dep] == nil {
            if DispatchTime.now().uptimeNanoseconds &- started > budgetNs { break }
            var names: [(name: String, kind: NJSKind?)] = []
            if let t = proj.modules.resolve(dep, from: proj.root + "/__autoimport.js"), NJSEnv.isCode(t) {
                env.steps = 0
                env.exportNames(t, into: &names)
            }
            var uniq: [String] = []
            var seen = Set<String>()
            for n in names where seen.insert(n.name).inserted { uniq.append(n.name); if uniq.count >= 3000 { break } }
            known[dep] = uniq
        }
        depLock.lock(); depCache[proj.root] = known; depLock.unlock()
        return known.map { ($0.key, $0.value) }
    }

    // MARK: the edit

    /// The text edit that makes `c` available in the live document, or nil when it cannot be placed safely.
    static func edit(for c: Candidate, doc: NJSDoc) -> (range: NSRange, text: String)? {
        let text = doc.text
        let imports = doc.summary.order.filter { $0.kind == .import && $0.impSource != nil }
        // style: quote and semicolon of the first import
        var quote = "'", semi = true
        if let first = imports.first, first.sigEnd <= text.length, first.declStart < first.sigEnd {
            let st = text.substring(with: NSRange(location: first.declStart, length: first.sigEnd - first.declStart))
            if let f = st.firstIndex(where: { $0 == "'" || $0 == "\"" }) { quote = String(st[f]) }
            semi = st.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(";")
        } else {
            let sample = text.substring(to: min(text.length, 4000)) as NSString
            let semis = sample.components(separatedBy: ";\n").count - 1, lines = sample.components(separatedBy: "\n").count
            semi = semis * 3 > lines
        }
        // join an existing named import of the same module
        if !c.isDefault, let same = imports.first(where: { $0.impSource == c.spec && $0.impName != "default" && $0.impName != "*" && $0.impName != "=" }) {
            let r = NSRange(location: same.declStart, length: same.sigEnd - same.declStart)
            let st = text.substring(with: r) as NSString
            let close = st.range(of: "}", options: .backwards)
            if close.location != NSNotFound {
                var p = close.location
                while p > 0, st.character(at: p - 1) == 32 || st.character(at: p - 1) == 10 { p -= 1 }
                let trailing = p > 0 && st.character(at: p - 1) == 44
                return (NSRange(location: r.location + p, length: 0), (trailing ? " " : ", ") + c.name)
            }
        }
        let line = "import " + (c.isDefault ? c.name : "{ " + c.name + " }") + " from " + quote + c.spec + quote + (semi ? ";" : "")
        // after the last import statement, else at the start of the code
        if let last = imports.max(by: { $0.sigEnd < $1.sigEnd }) {
            let lr = text.lineRange(for: NSRange(location: min(last.sigEnd, max(0, text.length - 1)), length: 0))
            return (NSRange(location: NSMaxRange(lr), length: 0), (NSMaxRange(lr) == text.length && !(text.substring(with: lr).hasSuffix("\n")) ? "\n" : "") + line + "\n")
        }
        var pos = 0
        if doc.isVue { guard let sr = doc.scriptRanges.first else { return nil }; pos = sr.location; if pos < text.length, text.character(at: pos) == 10 { pos += 1 }; return (NSRange(location: pos, length: 0), line + "\n") }
        // keep a leading comment block / shebang / 'use strict' above the import
        let head = text.substring(to: min(text.length, 600)) as NSString
        var cur = 0
        while cur < head.length {
            let lr = head.lineRange(for: NSRange(location: cur, length: 0))
            let l = head.substring(with: lr).trimmingCharacters(in: .whitespacesAndNewlines)
            if l.hasPrefix("//") || l.hasPrefix("#!") || l.hasPrefix("/*") || l.hasPrefix("*") || l.hasPrefix("'use ") || l.hasPrefix("\"use ") || l.isEmpty && cur == 0 { cur = NSMaxRange(lr); pos = cur } else { break }
        }
        return (NSRange(location: pos, length: 0), line + "\n" + (pos == 0 ? "" : ""))
    }
}

extension NativeJSProviderSupport {
    /// Auto-import items for the identifier being typed (nil / empty when the position is not a plain identifier in code).
    static func autoImportItems(proj: NJSProject, file: String, text: NSString, prefix: NSRange) -> [CompletionItem] {
        guard prefix.length >= 2 || (prefix.length >= 1 && prefix.location > 0 && text.character(at: prefix.location - 1) == 60) else { return [] }        // 2 letters, or 1 after `<`
        if prefix.location > 0 {
            let before = text.character(at: prefix.location - 1)
            if before == 46 || before == 36 || before == 35 || before == 64 { return [] }          // member access, $x, #priv, @decorator
        }
        guard let doc = NativeJS.document(path: file, text: text), doc.inScript(prefix.location) else { return [] }
        let typed = text.substring(with: prefix)
        // not inside a string, comment, template text, import / export clause or JSX attribute name
        let stop: Set<String> = ["string", "string_fragment", "comment", "template_string", "regex", "import_statement", "export_statement", "jsx_attribute", "jsx_text",
                                 "property_identifier", "shorthand_property_identifier_pattern", "type_parameters", "formal_parameters", "required_parameter"]
        if let leaf = doc.leaf(at: max(0, prefix.location + prefix.length - 1)) {
            var n: Node? = leaf
            while let c = n {
                if stop.contains(c.kind) { return [] }
                if c.kind == "variable_declarator", let nm = c.field("name"), nm.start <= prefix.location, prefix.location <= nm.end { return [] }      // naming a new variable
                n = c.parent
            }
        }
        proj.modules.beginRequest()
        let env = NJSEnv(proj: proj, doc: doc)
        // the graph (and with it the export names) is built lazily for projects that were not warmed
        if proj.graph.snapshot().isEmpty {
            var trunc = false
            let files = NJSRefs.files(proj.root, cancel: nil, truncated: &trunc)
            if files.count < NJSRefs.maxFiles { _ = proj.graph.ensureBuilt(files: files, live: [:], modules: proj.modules, stateKey: NJSRefs.listingDigest(files, [:])) }
        }
        let local = Set(doc.summary.top.keys)
        var items: [CompletionItem] = []
        for c in NJSAutoImport.candidates(prefix: typed, file: file, proj: proj, env: env, localNames: local) {
            if let leaf = doc.leaf(at: max(0, prefix.location)), env.localBinding(c.name, from: leaf) != nil { continue }
            guard let e = NJSAutoImport.edit(for: c, doc: doc) else { continue }
            var item = CompletionItem(label: c.name, insertText: c.name, kind: .variable, detail: "import from " + c.spec)
            item.additionalEdits = [e]
            item.sortText = "~" + c.name                            // below what is already in scope
            items.append(item)
        }
        return items
    }
}
