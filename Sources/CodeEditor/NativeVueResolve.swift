import Foundation

/// A resolved component: the file it lives in and where a jump lands.
struct VSCompRef {
    var path: String
    var offset: Int              // component root (template root element), the declaration for library components, else 0
    var via: String              // how it was found (shown in hover)
    var isDeclaration = false    // library `.d.ts`
}

extension NVProject {
    // MARK: tag -> component

    static let htmlTags: Set<String> = [
        "a", "abbr", "address", "area", "article", "aside", "audio", "b", "base", "bdi", "bdo", "blockquote", "body", "br", "button", "canvas", "caption", "cite", "code", "col",
        "colgroup", "data", "datalist", "dd", "del", "details", "dfn", "dialog", "div", "dl", "dt", "em", "embed", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2",
        "h3", "h4", "h5", "h6", "head", "header", "hgroup", "hr", "html", "i", "iframe", "img", "input", "ins", "kbd", "label", "legend", "li", "link", "main", "map", "mark", "menu",
        "meta", "meter", "nav", "noscript", "object", "ol", "optgroup", "option", "output", "p", "param", "picture", "pre", "progress", "q", "rp", "rt", "ruby", "s", "samp", "script",
        "search", "section", "select", "slot", "small", "source", "span", "strong", "style", "sub", "summary", "sup", "table", "tbody", "td", "template", "textarea", "tfoot", "th",
        "thead", "time", "title", "tr", "track", "u", "ul", "var", "video", "wbr", "svg", "path", "circle", "rect", "g", "line", "polyline", "polygon", "ellipse", "defs", "use",
        "symbol", "text", "tspan", "image", "clippath", "mask", "pattern", "lineargradient", "radialgradient", "stop", "foreignobject", "marker", "filter", "math", "center", "font",
        "component", "transition", "transition-group", "keep-alive", "teleport", "suspense", "router-view", "router-link", "routerlink", "routerview", "nuxt-link", "nuxtlink",
        "client-only", "clientonly", "nuxt-page", "nuxtpage", "nuxt", "nuxt-layout", "nuxtlayout", "nuxt-loading-indicator", "transitiongroup", "keepalive"
    ]

    /// Candidate tags worth resolving: anything that is not a native / built-in element spelled in lower case (`<page>` can be a global component).
    static func isComponentTag(_ tag: String) -> Bool {
        if tag.isEmpty { return false }
        if tag.contains(".") { return tag.first?.isLetter == true }
        return !htmlTags.contains(tag)
    }

    /// Does `name` (a registration key or binding) denote the tag `tag`? Vue matches the name as written, camelised or PascalCased.
    static func sameComponentName(_ name: String, _ tag: String) -> Bool {
        if name == tag { return true }
        let pn = VSName.pascal(name)
        return pn == VSName.pascal(tag) && !pn.isEmpty
    }

    func resolveTag(_ tag: String, file: String, cur: VSComp) -> VSCompRef? {
        if tag.contains(".") {
            let parts = tag.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2, let imp = cur.imports.first(where: { $0.local == parts[0] && $0.imported == "*" }),
                  let p = resolve(imp.spec, from: file) else { return nil }
            guard let t = resolveExport(parts[1], in: p, depth: 0) else { return nil }
            return makeRef(t.path, offset: t.offset, via: "namespace import")
        }
        // 1. bindings of the file itself (<script setup> imports / consts, or plain <script> imports used through `components`)
        if cur.isSetup {
            for d in cur.decls where VSName.pascal(d.name) == VSName.pascal(tag) && (d.name == tag || d.name == VSName.camel(tag) || d.name == VSName.pascal(tag)) {
                if let r = refForBinding(d, in: cur, file: file, via: "script setup") { return r }
            }
        }
        // 2. `components: { ... }`
        for reg in cur.regs where NVProject.sameComponentName(reg.key, tag) {
            if let r = refForRegistration(reg, in: cur, file: file, via: "components option") { return r }
        }
        // 3. global registration (app.component('X', Y))
        for g in globals() where NVProject.sameComponentName(g.key, tag) {
            let gc = g.file == cur.path ? cur : comp(path: g.file)
            if let gc, let r = refForRegistration(g.reg, in: gc, file: g.file, via: "global registration") { return r }
        }
        // 4. auto import (unplugin-vue-components / Nuxt / components.d.ts)
        var pname = VSName.pascal(tag)
        let auto = autoComponents()
        if let p = auto[pname] { return makeRef(p, offset: nil, via: "auto-imported component") }
        if pname.hasPrefix("Lazy"), let p = auto[String(pname.dropFirst(4))] { return makeRef(p, offset: nil, via: "auto-imported component") }
        pname = ""
        // 5. a non-setup file that imports the name without registering it (mistake) is not guessed
        return nil
    }

    private func refForBinding(_ d: VSDecl, in c: VSComp, file: String, via: String) -> VSCompRef? {
        if d.kind == .imp, let imp = c.imp(d.name) {
            guard let t = resolveSpecToComponent(imp.spec, imp.imported, from: file, depth: 0) else { return nil }
            return makeRef(t.path, offset: t.offset, via: via)
        }
        if let spec = d.spec, let t = resolveSpecToComponent(spec, "default", from: file, depth: 0) { return makeRef(t.path, offset: t.offset, via: via + " (async component)") }
        if d.kind == .const || d.kind == .function || d.kind == .class, d.initCall != nil || d.kind != .const {
            // a component defined in the same file
            if d.initCall == "defineComponent" || d.kind == .class || d.kind == .function { return VSCompRef(path: file, offset: d.loc, via: via + " (defined in this file)") }
        }
        return nil
    }

    private func refForRegistration(_ r: VSReg, in c: VSComp, file: String, via: String) -> VSCompRef? {
        if let spec = r.spec, let t = resolveSpecToComponent(spec, "default", from: file, depth: 0) { return makeRef(t.path, offset: t.offset, via: via) }
        if let v = r.valueIdent {
            if let imp = c.imp(v) {
                guard let t = resolveSpecToComponent(imp.spec, imp.imported, from: file, depth: 0) else { return nil }
                return makeRef(t.path, offset: t.offset, via: via)
            }
            if let d = c.decl(v) { return refForBinding(d, in: c, file: file, via: via) }
        }
        return nil
    }

    /// `import X from spec` / `import { X } from spec` -> the file of the component, following barrel re-exports.
    func resolveSpecToComponent(_ spec: String, _ imported: String, from file: String, depth: Int) -> (path: String, offset: Int?)? {
        guard let p = resolve(spec, from: file) else { return nil }
        if p.hasSuffix(".vue") { return (p, nil) }
        if depth < 4, let r = resolveExport(imported, in: p, depth: depth + 1) { return r }
        return (p, nil)
    }

    func resolveExport(_ name: String, in module: String, depth: Int) -> (path: String, offset: Int?)? {
        guard depth < 5 else { return nil }
        if module.hasSuffix(".vue") { return name == "default" ? (module, nil) : nil }
        if module.hasSuffix(".d.ts"), name == "default" { return nil }          // a library component's own declaration file: nothing to follow
        guard let c = exportsComp(path: module) else { return nil }
        for e in c.exports where e.name == name {
            if let spec = e.spec {
                if e.local == "*" { if let p = resolve(spec, from: module) { return (p, nil) }; continue }
                if let r = resolveSpecToComponent(spec, e.local ?? name, from: module, depth: depth + 1) { return r }
                continue
            }
            if let local = e.local {
                if let imp = c.imp(local) { if let r = resolveSpecToComponent(imp.spec, imp.imported, from: module, depth: depth + 1) { return r }; continue }
                if let d = c.decl(local) {
                    if let spec = d.spec, let r = resolveSpecToComponent(spec, "default", from: module, depth: depth + 1) { return r }
                    return (module, d.loc)
                }
            }
        }
        for star in c.starExports {
            if let p = resolve(star, from: module), let r = resolveExport(name, in: p, depth: depth + 1) { return r }
        }
        return nil
    }

    func makeRef(_ path: String, offset: Int?, via: String) -> VSCompRef {
        var p = path
        if !p.hasSuffix(".vue"), !p.hasSuffix(".d.ts") {
            // a library entry (`index.mjs`): its declarations carry the props
            let stem = (p as NSString).deletingPathExtension
            let dir = (p as NSString).deletingLastPathComponent
            for cand in [stem + ".d.ts", dir + "/index.d.ts"] where LaravelFS.isFile(cand) { p = cand; break }
        }
        if p.hasSuffix(".vue") {
            let off = offset ?? comp(path: p)?.rootOffset ?? 0
            return VSCompRef(path: p, offset: off, via: via)
        }
        if p.hasSuffix(".d.ts") {
            let c = comp(path: p)
            return VSCompRef(path: p, offset: offset ?? c?.rootOffset ?? 0, via: via, isDeclaration: true)
        }
        return VSCompRef(path: p, offset: offset ?? 0, via: via)
    }

    // MARK: global registrations

    func globals() -> [NVGlobal] {
        memoGlobals {
            var out: [NVGlobal] = []
            var examined = 0
            let needle = Array(".component(".utf8)
            for f in codeFiles where examined < 3000 && out.count < 400 {
                examined += 1
                guard let d = try? Data(contentsOf: URL(fileURLWithPath: f), options: .mappedIfSafe), d.count <= 300_000 else { continue }
                let hit = d.withUnsafeBytes { raw -> Bool in
                    guard let b = raw.baseAddress else { return false }
                    return memmem(b, d.count, needle, needle.count) != nil
                }
                guard hit, let text = NSString(data: d, encoding: String.Encoding.utf8.rawValue) else { continue }
                let c = VSBuild.script(path: f, text: text, scanGlobals: true)
                for r in c.globalRegs { out.append(NVGlobal(key: r.key, file: f, reg: r)) }
            }
            return out
        }
    }

    // MARK: auto-imported components

    func autoComponents() -> [String: String] {
        memoAuto { buildAuto() }
    }

    private func readSmall(_ path: String) -> String? {
        guard LaravelFS.isFile(path), let d = FileManager.default.contents(atPath: path), d.count < 400_000 else { return nil }
        return String(data: d, encoding: .utf8)
    }

    private func buildAuto() -> [String: String] {
        var out: [String: String] = [:]
        // 1. generated declarations list exactly what is registered
        let rx = try? NSRegularExpression(pattern: #"(\w+)\s*:\s*typeof import\('([^']+)'\)(?:\['(\w+)'\])?"#)
        for rel in ["components.d.ts", "src/components.d.ts", "resources/js/components.d.ts", "types/components.d.ts", ".nuxt/components.d.ts", "resources/js/types/components.d.ts"] {
            let f = root + "/" + rel
            guard let t = readSmall(f), let rx else { continue }
            let ns = t as NSString
            rx.enumerateMatches(in: t, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                guard let m else { return }
                let name = ns.substring(with: m.range(at: 1)), spec = ns.substring(with: m.range(at: 2))
                guard spec.hasSuffix(".vue") else { return }
                let abs = ((f as NSString).deletingLastPathComponent as NSString).appendingPathComponent(spec)
                let std = (abs as NSString).standardizingPath
                if LaravelFS.isFile(std), out[name] == nil { out[name] = std }
            }
        }
        // 2. Nuxt: components/ with directory prefixes; 3. unplugin-vue-components: configured dirs (default src/components)
        var dirs: [(String, Bool)] = []                          // (directory, nuxt style prefixes)
        let pkg = readSmall(root + "/package.json") ?? ""
        let nuxt = ["nuxt.config.ts", "nuxt.config.js", "nuxt.config.mjs"].contains { LaravelFS.isFile(root + "/" + $0) } || pkg.contains("\"nuxt\"")
        if nuxt { dirs += [(root + "/components", true), (root + "/app/components", true)] }
        for n in NJSModules.aliasConfigNames where n.hasPrefix("vite.config") || n.hasPrefix("vue.config") {
            let f = root + "/" + n
            guard let t = readSmall(f), t.contains("unplugin-vue-components") else { continue }
            var found = false
            if let r = t.range(of: #"dirs\s*:\s*\[([^\]]*)\]"#, options: .regularExpression) {
                for part in String(t[r]).components(separatedBy: CharacterSet(charactersIn: "'\"")).enumerated() where part.offset % 2 == 1 && !part.element.isEmpty && !part.element.hasPrefix("dirs") {
                    var d = part.element
                    if d.hasPrefix("./") { d.removeFirst(2) }
                    dirs.append((root + "/" + d, false)); found = true
                }
            }
            if !found { dirs.append((root + "/src/components", false)) }
        }
        guard !dirs.isEmpty else { return out }
        for (dir, prefixed) in dirs where LaravelFS.isDir(dir) {
            for f in vueFiles where f.hasPrefix(dir + "/") {
                var rel = String(f.dropFirst(dir.count + 1))
                rel = String(rel.dropLast(4))                       // .vue
                var segs = rel.split(separator: "/").map(String.init)
                guard var file = segs.popLast() else { continue }
                for suffix in [".global", ".client", ".server", ".lazy"] where file.hasSuffix(suffix) { file = String(file.dropLast(suffix.count)) }
                if file.lowercased() == "index" { file = segs.popLast() ?? file }
                let plain = VSName.pascal(file)
                if out[plain] == nil { out[plain] = f }
                if prefixed, !segs.isEmpty {
                    let prefix = segs.map { VSName.pascal($0) }.joined()
                    let name = plain.hasPrefix(prefix) ? plain : prefix + plain
                    if out[name] == nil { out[name] = f }
                }
            }
        }
        return out
    }

    // MARK: assets and routes

    /// A path written in markup (`src`, `href`, `<style src>`, `require('./x.png')`) -> existing file.
    func resolveAsset(_ ref: String, from file: String) -> String? {
        var r = ref.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t\n"))
        if let q = r.firstIndex(where: { $0 == "?" || $0 == "#" }) { r = String(r[r.startIndex..<q]) }
        guard !r.isEmpty, !r.hasPrefix("http:"), !r.hasPrefix("https:"), !r.hasPrefix("data:"), !r.hasPrefix("//"), !r.hasPrefix("mailto:"), !r.hasPrefix("tel:"),
              !r.hasPrefix("javascript:"), !r.contains("{{"), !r.contains("${"), !r.contains(" ") else { return nil }
        let pathLike = r.hasPrefix("./") || r.hasPrefix("../") || r.hasPrefix("/") || r.hasPrefix("@") || r.hasPrefix("~") || r.contains("/")
        guard pathLike else { return nil }
        let dir = (file as NSString).deletingLastPathComponent
        var cands: [String] = []
        func add(_ p: String) { cands.append((p as NSString).standardizingPath) }
        if r.hasPrefix("./") || r.hasPrefix("../") { add(dir + "/" + r) }
        else if r.hasPrefix("/") { add(root + r); add(root + "/public" + r); add(root + "/src" + r) ; add(root + "/resources" + r); add(r) }
        else if r.hasPrefix("@/") || r.hasPrefix("~/") || r.hasPrefix("~~/") || r.hasPrefix("@@/") {
            let rest = String(r.drop(while: { $0 == "@" || $0 == "~" }).dropFirst())
            if let a = resolve(r, from: file), !a.isEmpty { cands.append(a) }
            add(root + "/src/" + rest); add(root + "/" + rest); add(root + "/resources/js/" + rest); add(root + "/app/" + rest)
        } else {
            if let a = resolve(r, from: file) { cands.append(a) }
            add(dir + "/" + r); add(root + "/" + r); add(root + "/public/" + r); add(root + "/src/" + r)
            if r.hasPrefix("~") { add(root + "/node_modules/" + r.dropFirst()) }
        }
        return cands.first { LaravelFS.isFile($0) }
    }

    /// vue-router records `{ path: '/x', name: 'x', ... }` found in the project's router / routes modules (static strings only).
    func routeTargets(path: String?, name: String?) -> [NPTarget] {
        guard path != nil || name != nil else { return [] }
        let key = (path ?? "") + "\u{1}" + (name ?? "")
        return memoRoute(key) {
            var out: [NPTarget] = []
            let needle = Array((name ?? path ?? "").utf8)
            guard !needle.isEmpty else { return [] }
            let files = codeFiles
            let ordered = files.filter { $0.lowercased().contains("router") || $0.lowercased().contains("routes") } + files.filter { !($0.lowercased().contains("router") || $0.lowercased().contains("routes")) }
            var examined = 0
            for f in ordered where out.isEmpty && examined < 1500 {
                examined += 1
                guard let d = try? Data(contentsOf: URL(fileURLWithPath: f), options: .mappedIfSafe), d.count <= 400_000 else { continue }
                let has = d.withUnsafeBytes { raw -> Bool in
                    guard let b = raw.baseAddress else { return false }
                    return memmem(b, d.count, needle, needle.count) != nil
                }
                guard has, let text = NSString(data: d, encoding: String.Encoding.utf8.rawValue) else { continue }
                let c = NSString(string: text)
                if !(c.contains("component") && (c.contains("path") || c.contains("name"))) { continue }
                let tk = VSLex.run(VSLex.chars(text, NSRange(location: 0, length: text.length)))
                let ls = NPLineStarts(text)
                for i in 0..<max(0, tk.count - 2) where tk[i].kind == .ident || tk[i].kind == .str {
                    let key = tk[i].text
                    guard tk[i + 1].isP(":"), tk[i + 2].kind == .str else { continue }
                    let v = tk[i + 2].text
                    let match = (key == "name" && name != nil && v == name!) || (key == "path" && path != nil && (v == path! || "/" + v == path!))
                    guard match else { continue }
                    let pos = ls.position(of: tk[i + 2].s)
                    out.append(NPTarget(path: f, offset: tk[i + 2].s, line: pos.line, column: pos.col))
                    if out.count >= 5 { break }
                }
            }
            return out
        }
    }
}
