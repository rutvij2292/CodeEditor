import Foundation
import SwiftTreeSitter

/// A resolved definition (a symbol, a member, or a whole file) in some file.
struct NJSRes {
    var path: String
    var name: String
    var kind: NJSKind
    var loc: Int
    var len: Int
    var declStart: Int
    var sigEnd: Int
    var docStart = -1, docEnd = -1
    var keyword: String?
    var typeName: String?
    var initCall: String?
    var aliasOf: String?
    var valueMembers: [NJSMember] = []
    var returnMembers: [NJSMember] = []
    var members: [NJSMember] = []
    var heritage: [String] = []
    var siblings: [NJSMember]?          // members of the enclosing namespace (heritage names resolve there first)
    var fileTop = false
    var owner: String?
    var local = false                   // declared inside a function / block of the current document

    init(path: String, sym s: NJSSym) {
        self.path = path; name = s.name; kind = s.kind; loc = s.loc; len = s.len; declStart = s.declStart; sigEnd = s.sigEnd
        docStart = s.docStart; docEnd = s.docEnd; keyword = s.keyword; typeName = s.typeName; initCall = s.initCall; aliasOf = s.aliasOf; valueMembers = s.valueMembers; returnMembers = s.returnMembers; members = s.members; heritage = s.heritage
    }
    init(path: String, member m: NJSMember, owner: String?, siblings: [NJSMember]? = nil) {
        self.path = path; name = m.name; kind = m.kind; loc = m.loc; len = m.len; declStart = m.declStart; sigEnd = m.sigEnd
        docStart = m.docStart; docEnd = m.docEnd; typeName = m.typeName; members = m.sub ?? []; heritage = m.heritage
        self.owner = owner; self.siblings = siblings
    }
    init(fileTop path: String) {
        self.path = path; name = (path as NSString).lastPathComponent; kind = .namespace; loc = 0; len = 0; declStart = 0; sigEnd = 0; fileTop = true
    }
    init(path: String, anon: NJSExport, name: String) {
        self.path = path; self.name = name; kind = .variable; loc = 0; len = 0; declStart = 0; sigEnd = 0
        if case .anon(let l, let n, let d, let s, let ds, let de) = anon { loc = l; len = n; declStart = d; sigEnd = s; docStart = ds; docEnd = de }
    }
}

/// What an expression evaluates to, as far as the native engine can tell.
struct NJSTV {
    var res: [NJSRes]
    var isStatic: Bool
    var module: String?
    var valueMembers: [NJSMember]?       // `ref({...})`: members of what `.value` holds
    var valuePath: String?
}

/// Per-project state: serial queue, module resolver and a byte-capped LRU of file summaries (no trees are kept).
final class NJSProject {
    private static let regLock = NSLock()
    private static var registry: [String: NJSProject] = [:]
    static func shared(root: String) -> NJSProject {
        regLock.lock(); defer { regLock.unlock() }
        if let p = registry[root] { return p }
        let p = NJSProject(root: root)
        registry[root] = p
        return p
    }
    static func trimAll() {
        regLock.lock(); let all = Array(registry.values); regLock.unlock()
        for p in all { p.queue.async { p.trim() } }
    }
    static var all: [NJSProject] { regLock.lock(); defer { regLock.unlock() }; return Array(registry.values) }

    let root: String
    let queue: DispatchQueue
    let modules: NJSModules
    let graph = NJSImportGraph()
    private let lock = NSLock()
    private var cache: [String: NJSSummary] = [:]
    private var lru: [String] = []
    private var cost = 0
    static let maxCost = 3_000_000
    static let maxEntries = 400

    init(root: String) {
        self.root = root
        queue = DispatchQueue(label: "nativejs.\(root)", qos: .utility)
        modules = NJSModules(root: root)
    }

    var cachedSummaries: Int { lock.lock(); defer { lock.unlock() }; return cache.count }
    var cachedCost: Int { lock.lock(); defer { lock.unlock() }; return cost }

    func trim() {
        lock.lock(); cache.removeAll(); lru.removeAll(); cost = 0; lock.unlock()
        modules.trim()
        graph.clear()
    }

    func summary(path: String) -> NJSSummary? {
        let stamp = LaravelFS.mtime(path)
        if stamp == 0 { return nil }
        lock.lock()
        if let s = cache[path], s.stamp == stamp {
            if let i = lru.lastIndex(of: path), i != lru.count - 1 { lru.remove(at: i); lru.append(path) }
            lock.unlock(); return s
        }
        lock.unlock()
        guard let text = FastProject.read(path), let doc = NJSDoc(path: path, text: text, maxChars: 1_000_000, skipMinified: true) else { return nil }      // a tree costs ~26 bytes per character while it lives
        let s = doc.summary
        s.stamp = stamp
        lock.lock()
        if let old = cache[path] { cost -= old.cost; lru.removeAll { $0 == path } }
        cache[path] = s; lru.append(path); cost += s.cost
        while (cost > NJSProject.maxCost || cache.count > NJSProject.maxEntries) && lru.count > 1 {
            let k = lru.removeFirst()
            if let o = cache.removeValue(forKey: k) { cost -= o.cost }
        }
        lock.unlock()
        return s
    }
}

/// Texts of the few files whose lines a request has to show (definition targets, hover): at most 3 files / 600K characters, replaced
/// least recently used first (NPFiles keeps up to 3M characters = 6 MB for the PHP engine).
enum NJSTexts {
    private static let lock = NSLock()
    private static var entries: [(path: String, stamp: Int64, text: NSString)] = []

    static func text(_ path: String) -> NSString? {
        let st = LaravelFS.mtime(path)
        lock.lock()
        if let i = entries.firstIndex(where: { $0.path == path && $0.stamp == st }) { let e = entries.remove(at: i); entries.append(e); lock.unlock(); return e.text }
        lock.unlock()
        guard let t = FastProject.read(path) else { return nil }
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.path == path }
        entries.append((path, st, t))
        var total = entries.reduce(0) { $0 + $1.text.length }
        while entries.count > 3 || (total > 600_000 && entries.count > 1) { total -= entries.removeFirst().text.length }
        return t
    }

    static func clear() { lock.lock(); entries.removeAll(); lock.unlock() }
}

/// Results of resolving names in files other than the document, shared by every environment of one find-usages search
/// (the files do not change while it runs).
final class NJSMemo {
    private let lock = NSLock()
    private var top: [String: [NJSRes]] = [:]
    private var exports: [String: [NJSRes]] = [:]
    func top(_ k: String) -> [NJSRes]? { lock.lock(); defer { lock.unlock() }; return top[k] }
    func setTop(_ k: String, _ v: [NJSRes]) { lock.lock(); top[k] = v; lock.unlock() }
    func exports(_ k: String) -> [NJSRes]? { lock.lock(); defer { lock.unlock() }; return exports[k] }
    func setExports(_ k: String, _ v: [NJSRes]) { lock.lock(); exports[k] = v; lock.unlock() }
}

/// One request: the live document of the file being edited plus the project caches.
final class NJSEnv {
    let proj: NJSProject
    let doc: NJSDoc
    let path: String
    var memo: NJSMemo?
    var steps = 0                       // safety valve against pathological re-export / heritage cycles

    init(proj: NJSProject, doc: NJSDoc) { self.proj = proj; self.doc = doc; path = doc.path }

    func summary(_ p: String) -> NJSSummary? { p == path ? doc.summary : proj.summary(path: p) }
    func text(_ p: String) -> NSString? { p == path ? doc.text : NJSTexts.text(p) }

    static func isCode(_ p: String) -> Bool { NJSModules.codeExts.contains((p as NSString).pathExtension.lowercased()) }

    // MARK: top level / exports

    /// Top-level symbols named `name` of `file`, following import bindings to their definitions.
    func resolveTop(_ file: String, _ name: String, depth: Int = 0) -> [NJSRes] {
        if let m = memo, file != path { let k = file + "\u{0}" + name; if let r = m.top(k) { return r }; let r = resolveTopUncached(file, name, depth: depth); if steps < 400 { m.setTop(k, r) }; return r }
        return resolveTopUncached(file, name, depth: depth)
    }

    private func resolveTopUncached(_ file: String, _ name: String, depth: Int) -> [NJSRes] {
        steps += 1
        guard depth < 8, steps < 400, let s = summary(file), let syms = s.top[name] else { return [] }
        var out: [NJSRes] = []
        for sym in syms {
            if sym.kind == .import { out += followImport(sym, from: file, depth: depth + 1) } else { out.append(NJSRes(path: file, sym: sym)) }
        }
        return out
    }

    func followImport(_ sym: NJSSym, from file: String, depth: Int) -> [NJSRes] {
        guard let spec = sym.impSource, let imp = sym.impName, let target = proj.modules.resolve(spec, from: file) else { return [] }
        if !NJSEnv.isCode(target) { return imp == "default" || imp == "*" || imp == "=" ? [NJSRes(fileTop: target)] : [] }
        if target.hasSuffix(".vue") { return imp == "default" || imp == "*" || imp == "=" ? [NJSRes(fileTop: target)] : exportOf(target, imp, depth: depth + 1) }
        switch imp {
        case "*": return [NJSRes(fileTop: target)]
        case "default":
            let d = exportOf(target, "default", depth: depth + 1)
            if !d.isEmpty { return d }
            if let s = summary(target), let eq = s.exportEquals { return resolveTop(target, eq, depth: depth + 1) }   // export = X (esModuleInterop)
            if let s = summary(target), s.commonJS { return cjsRoot(target, depth: depth + 1) }
            return []
        case "=":
            let d = cjsRoot(target, depth: depth + 1)
            if !d.isEmpty { return d }
            if let s = summary(target), let eq = s.exportEquals { return resolveTop(target, eq, depth: depth + 1) }
            return []
        default: return exportOf(target, imp, depth: depth + 1)
        }
    }

    /// What `require('./x')` evaluates to: `module.exports = X` (a named local), else the module itself (its `exports.y` members).
    func cjsRoot(_ target: String, depth: Int) -> [NJSRes] {
        guard let s = summary(target), s.commonJS else { return [] }
        if case .local? = s.exports["="] { let r = exportOf(target, "=", depth: depth); if !r.isEmpty { return r } }
        return [NJSRes(fileTop: target)]
    }

    func exportOf(_ file: String, _ name: String, depth: Int = 0) -> [NJSRes] {
        if let m = memo, file != path { let k = file + "\u{0}" + name; if let r = m.exports(k) { return r }; let r = exportOfUncached(file, name, depth: depth); if steps < 400 { m.setExports(k, r) }; return r }
        return exportOfUncached(file, name, depth: depth)
    }

    private func exportOfUncached(_ file: String, _ name: String, depth: Int) -> [NJSRes] {
        steps += 1
        guard depth < 8, steps < 400, let s = summary(file) else { return [] }
        if let e = s.exports[name] {
            switch e {
            case .local(let n):
                let r = resolveTop(file, n, depth: depth + 1)
                if !r.isEmpty { return r }
            case .reexport(let spec, let nm):
                if let t = proj.modules.resolve(spec, from: file) {
                    if !NJSEnv.isCode(t) { return nm == "default" ? [NJSRes(fileTop: t)] : [] }
                    return exportOf(t, nm, depth: depth + 1)
                }
                return []
            case .moduleNS(let spec):
                return proj.modules.resolve(spec, from: file).map { [NJSRes(fileTop: $0)] } ?? []
            case .anon:
                return [NJSRes(path: file, anon: e, name: name == "default" || name == "=" ? "default" : name)]
            }
        }
        if let eq = s.exportEquals, name != "default" {                  // `export = NS`: the members of NS are the module's exports
            for base in resolveTop(file, eq, depth: depth + 1) {
                if let m = base.members.first(where: { $0.name == name }) { return [NJSRes(path: base.path, member: m, owner: base.name, siblings: base.members)] }
            }
        }
        if name != "default" {
            for star in s.stars {
                guard let t = proj.modules.resolve(star, from: file), NJSEnv.isCode(t) else { continue }
                let r = exportOf(t, name, depth: depth + 1)
                if !r.isEmpty { return r }
            }
        }
        if !s.isModule && !s.commonJS, let syms = s.top[name] {           // ambient script (.d.ts without import / export): everything is global
            return syms.map { NJSRes(path: file, sym: $0) }
        }
        return []
    }

    // MARK: types

    /// Resolves a (possibly dotted) type / class name written in `file`.
    func resolveTypeRef(_ name: String, in file: String, siblings: [NJSMember]? = nil) -> [NJSRes] {
        let parts = name.split(separator: ".").map(String.init)
        guard let first = parts.first else { return [] }
        if parts.count == 1 {
            if let sib = siblings?.first(where: { $0.name == first }) { return [NJSRes(path: file, member: sib, owner: nil, siblings: siblings)] }
            return resolveTop(file, first)
        }
        var cur = resolveTop(file, first)
        for part in parts.dropFirst() {
            var next: [NJSRes] = []
            for c in cur {
                if c.fileTop { next += exportOf(c.path, part) }
                else if let m = c.members.first(where: { $0.name == part }) { next.append(NJSRes(path: c.path, member: m, owner: c.name, siblings: c.members)) }
            }
            cur = next
            if cur.isEmpty { break }
        }
        return cur
    }

    /// Members named `name` of a class-like definition, walking `extends` chains.
    func members(of r: NJSRes, name: String, isStatic: Bool, depth: Int = 0) -> [NJSRes] {
        steps += 1
        guard depth < 10, steps < 400 else { return [] }
        let flexible = r.kind != .class
        let direct = r.members.filter { $0.name == name && (flexible || $0.isStatic == isStatic) }
        if !direct.isEmpty { return direct.map { NJSRes(path: r.path, member: $0, owner: r.name, siblings: r.members) } }
        var out: [NJSRes] = []
        for h in r.heritage {
            for base in resolveTypeRef(h, in: r.path, siblings: r.siblings) where !(base.path == r.path && base.loc == r.loc) {
                out += members(of: base, name: name, isStatic: isStatic, depth: depth + 1)
            }
            if !out.isEmpty { break }
        }
        return out
    }

    func tv(of res: [NJSRes]) -> NJSTV? {
        var out: [NJSRes] = []
        var isStatic = false
        var module: String?
        var valueM: [NJSMember]?, valueP: String?
        for r in res {
            if r.fileTop { module = r.path; continue }
            switch r.kind {
            case .class, .enum, .namespace: out.append(r); isStatic = true
            case .variable, .constant, .property, .parameter, .getter:
                if let t = r.typeName { out += resolveTypeRef(t, in: r.path, siblings: r.siblings).filter { $0.kind != .function } }
                if !r.members.isEmpty { out.append(r) }             // properties declared by an object literal (also: the keys handed to a factory)
                if !r.valueMembers.isEmpty { valueM = r.valueMembers; valueP = r.path }
                if r.typeName == nil, let c = r.initCall, let v = tvOfResult(resolveTypeRef(c, in: r.path)) { out += v.res }       // const x = f(): the declared return type of f
            case .function, .method:
                break
            default: break
            }
        }
        if out.isEmpty && module == nil && valueM == nil { return nil }
        return NJSTV(res: out, isStatic: isStatic, module: module, valueMembers: valueM, valuePath: valueP)
    }

    func instance(of typeName: String, in file: String, siblings: [NJSMember]? = nil) -> NJSTV? {
        let r = resolveTypeRef(typeName, in: file, siblings: siblings).filter { $0.kind == .class || $0.kind == .interface || $0.kind == .typeAlias || $0.kind == .enum }
        return r.isEmpty ? nil : NJSTV(res: r, isStatic: false, module: nil)
    }

    func memberOf(_ t: NJSTV, _ name: String) -> [NJSRes] {
        var out: [NJSRes] = []
        if let m = t.module { out += exportOf(m, name) }
        for r in t.res { out += members(of: r, name: name, isStatic: t.isStatic) }
        return out
    }

    /// The type of the value a member / function result produces (declared return / property types only).
    /// Vue's reactivity factories: whatever the overload, the result is a Ref family interface and `.value` is declared there.
    private static let vueRefs: [String: String] = ["ref": "Ref", "shallowRef": "ShallowRef", "toRef": "Ref", "customRef": "Ref", "computed": "ComputedRef"]

    /// A synthetic holder of properties declared at some literal's keys.
    static func container(_ path: String, _ members: [NJSMember]) -> NJSRes {
        let sym = NJSSym(name: "(object)", kind: .variable, loc: 0, len: 0, declStart: 0, sigEnd: 0)
        sym.members = members
        return NJSRes(path: path, sym: sym)
    }

    func tvOfResult(_ res: [NJSRes], depth: Int = 0) -> NJSTV? {
        for r in res {
            if !r.returnMembers.isEmpty { return NJSTV(res: [NJSEnv.container(r.path, r.returnMembers)], isStatic: false, module: nil) }
            if let a = r.aliasOf, depth < 3, let v = tvOfResult(resolveTop(r.path, a), depth: depth + 1) { return v }
            if let iface = NJSEnv.vueRefs[r.name], r.path.contains("/@vue/reactivity/"), let v = instance(of: iface, in: r.path) { return v }
            if let t = r.typeName, let v = instance(of: t, in: r.path, siblings: r.siblings) { return v }
        }
        return nil
    }

    // MARK: expressions of the live document

    func typeOf(_ n: Node, depth: Int = 0) -> NJSTV? {
        guard depth < 12 else { return nil }
        switch n.kind {
        case "this":
            var p = n.parent
            while let c = p {
                switch c.kind {
                case "class_declaration", "abstract_class_declaration":
                    guard let nm = c.field("name")?.text(doc.text) else { return nil }
                    let r = resolveTop(path, nm).filter { $0.path == path && $0.kind == .class }
                    var staticCtx = false
                    var q: Node? = n.parent
                    while let x = q, x != c { if x.kind == "method_definition" || x.kind == "field_definition" || x.kind == "public_field_definition" { staticCtx = x.allKids.contains { $0.kind == "static" }; break }; q = x.parent }
                    return r.isEmpty ? nil : NJSTV(res: r, isStatic: staticCtx, module: nil)
                case "function_expression", "function_declaration", "generator_function", "generator_function_declaration", "class":
                    return nil
                case "method_definition":
                    if c.parent?.kind != "class_body" { return nil }          // a method of an object literal binds its own `this`
                    p = c.parent
                default: p = c.parent
                }
            }
            return nil
        case "identifier":
            let name = n.text(doc.text)
            if let b = localBinding(name, from: n) {
                if let t = b.typeName, localBinding(t.split(separator: ".").first.map(String.init) ?? t, from: n) != nil { return nil }   // a local type (type parameter, local class)
                if let v = tv(of: [resolve(b)]) ?? bindingType(b) { return v }
                if b.typeName == nil, b.declNode.kind == "variable_declarator", b.declNode.field("name")?.kind == "identifier", let init_ = b.declNode.field("value"), init_.kind == "call_expression" { return typeOf(init_, depth: depth + 1) }
                return nil
            }
            return tv(of: resolveTop(path, name))
        case "member_expression":
            guard let o = n.field("object"), let p = n.field("property"), let base = typeOf(o, depth: depth + 1) else { return nil }
            if p.text(doc.text) == "value", let vm = base.valueMembers, let vp = base.valuePath { return NJSTV(res: [NJSEnv.container(vp, vm)], isStatic: false, module: nil) }
            let found = memberOf(base, p.text(doc.text))
            return tv(of: found)
        case "call_expression":
            guard let f = n.field("function") else { return nil }
            switch f.kind {
            case "identifier":
                let name = f.text(doc.text)
                if let b = localBinding(name, from: f) { return tvOfResult([resolve(b)]) }
                return tvOfResult(resolveTop(path, name))
            case "member_expression":
                guard let o = f.field("object"), let p = f.field("property"), let base = typeOf(o, depth: depth + 1) else { return nil }
                return tvOfResult(memberOf(base, p.text(doc.text)))
            default: return nil
            }
        case "new_expression":
            guard let c = n.field("constructor"), c.kind == "identifier" || c.kind == "member_expression" else { return nil }
            return instance(of: c.text(doc.text), in: path)
        case "parenthesized_expression", "non_null_expression":
            return n.kids.first.flatMap { typeOf($0, depth: depth + 1) }
        case "as_expression", "satisfies_expression", "type_assertion":
            if let t = n.kids.last, let nm = NJSExtractor(doc: doc).typeName(t) { return instance(of: nm, in: path) }
            return nil
        default: return nil
        }
    }

    func bindingType(_ b: NJSLocal) -> NJSTV? {
        if let t = b.typeName { return instance(of: t, in: path) }
        return nil
    }
}
