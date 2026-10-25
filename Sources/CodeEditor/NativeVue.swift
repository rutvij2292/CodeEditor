import AppKit

/// Native Vue template service: Cmd-click / Cmd-hover / hover / Cmd-B / Alt-F7 and completion inside `<template>` of single file components
/// (custom component tags and their props / emits / slots, template expressions and directives, assets, router links). Mirrors the native
/// PHP / JS engines: a per-project serial utility queue, lazy file lists, byte-capped summary caches, no timers and no background work.
/// Nothing answers unless it is provable; every miss falls through to the previous chain (native JS / web, then the Vue language server).
enum NativeVue {
    static let enabledKey = "vue.native"
    static let nativeOnlyKey = "vue.nativeOnly"

    /// DEFAULT ON: Volar and the TypeScript server are not started for Vue projects (Settings > Languages turns them back on).
    /// You keep native template navigation, hover, usages and completion; you lose template type checking, inferred-type hover,
    /// rename and type errors until native covers them.
    static var nativeOnly: Bool {
        get { UserDefaults.standard.object(forKey: nativeOnlyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: nativeOnlyKey) }
    }

    /// Settings > Languages: 'Native Vue template service' (default ON).
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func handles(_ url: URL) -> Bool { enabled && url.pathExtension.lowercased() == "vue" }

    static func root(for url: URL) -> String { NativeWeb.root(for: url) }

    // MARK: lookups (hover, Cmd-click, Cmd-B)

    /// Synchronous lookup (tests, Cmd-B). Main thread callers wait on the project's queue.
    static func lookup(url: URL, text: NSString, offset: Int, root: String? = nil) -> NPHit? {
        guard handles(url) else { return nil }
        let p = NVProject.shared(root: root ?? self.root(for: url))
        return p.queue.sync { NVService.lookup(p, url: url, text: text, offset: offset) }
    }

    static func lookupAsync(url: URL, text: NSString, offset: Int, completion: @escaping (NPHit?) -> Void) {
        guard handles(url) else { completion(nil); return }
        let p = NVProject.shared(root: root(for: url))
        let snapshot = NSString(string: text as String)
        p.queue.async {
            let hit = NVService.lookup(p, url: url, text: snapshot, offset: offset)
            DispatchQueue.main.async { completion(hit) }
        }
    }

    static func goToDefinition(in tab: EditorTab, at offset: Int) -> Bool {
        guard handles(tab.url) else { return false }
        let text = tab.textView.string as NSString
        guard let hit = lookup(url: tab.url, text: text, offset: offset), !hit.targets.isEmpty else { return false }
        return NativePHP.open(hit, from: tab, offset: offset)
    }

    // MARK: memory / invalidation

    static func invalidate(root: URL) { NVProject.existing(root: root.standardizedFileURL.path)?.markDirty() }

    /// Drops every cached summary and file list. Safe at any time; called on memory pressure, when the app is hidden and in power-saver mode.
    static func trimMemory() {
        NVProject.trimAll()
        malloc_zone_pressure_relief(nil, 0)
    }

    private static var hooksInstalled = false
    private static var pressureSource: DispatchSourceMemoryPressure?

    static func installMemoryHooks() {
        guard !hooksInstalled else { return }
        hooksInstalled = true
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        src.setEventHandler { trimMemory() }
        src.resume()
        pressureSource = src
        let nc = NotificationCenter.default
        nc.addObserver(forName: PowerState.didChange, object: nil, queue: .main) { _ in
            if PowerState.shared.saver { DispatchQueue.global(qos: .utility).async { trimMemory() } }
        }
        nc.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { _ in
            DispatchQueue.global(qos: .utility).async { trimMemory() }
        }
    }

    static func register() {
        CompletionRegistry.register(NativeVueProvider(), forExtensions: ["vue"])
    }
}

// MARK: - Per-project state

final class NVProject {
    private static let registryLock = NSLock()
    private static var registry: [String: NVProject] = [:]

    static func shared(root: String) -> NVProject {
        registryLock.lock(); defer { registryLock.unlock() }
        if let p = registry[root] { return p }
        let p = NVProject(root: root)
        registry[root] = p
        return p
    }
    static func existing(root: String) -> NVProject? {
        registryLock.lock(); defer { registryLock.unlock() }
        return registry[root]
    }
    static func trimAll() {
        registryLock.lock(); let all = Array(registry.values); registryLock.unlock()
        for p in all { p.queue.async { p.dropCaches() } }
    }
    static var all: [NVProject] { registryLock.lock(); defer { registryLock.unlock() }; return Array(registry.values) }

    let root: String
    let queue: DispatchQueue
    private let lock = NSLock()
    private var dirty = true
    private var cache: [String: (stamp: Int64, comp: VSComp)] = [:]
    private var lru: [String] = []
    private var cost = 0
    nonisolated(unsafe) static var statPaths: [String: Int] = [:]
    nonisolated(unsafe) static var statBuilds = 0, statBuildNs: UInt64 = 0     // dev counters (bench)
    static let maxEntries = 160
    static let maxCost = 1_500_000
    static let maxFileBytes = 700_000

    private var vueList: [String] = []
    private var codeList: [String] = []
    private var listed = false
    private let listLock = NSLock()
    private var globalsMemo: [NVGlobal]?
    private var autoMemo: [String: String]?
    private var routeMemo: [String: [NPTarget]] = [:]

    init(root: String) {
        self.root = root
        queue = DispatchQueue(label: "nativevue.\(root)", qos: .utility)
    }

    func markDirty() { lock.lock(); dirty = true; globalsMemo = nil; autoMemo = nil; implicitDirs = nil; routeMemo.removeAll(); lock.unlock() }

    func dropCaches() {
        lock.lock()
        cache.removeAll(); lru.removeAll(); cost = 0
        exportCache.removeAll(); exportCost = 0
        globalsMemo = nil; autoMemo = nil; routeMemo.removeAll()
        dirty = true
        lock.unlock()
        listLock.lock(); vueList = []; codeList = []; listed = false; listLock.unlock()
    }

    var cachedSummaries: Int { lock.lock(); defer { lock.unlock() }; return cache.count + exportCache.count }
    var cachedCost: Int { lock.lock(); defer { lock.unlock() }; return cost }
    var isListed: Bool { listLock.lock(); defer { listLock.unlock() }; return listed }

    // MARK: summaries

    /// Summary of a file on disk (`.vue`, or a JS / TS module for barrels and entry files), cached by mtime.
    func comp(path: String) -> VSComp? {
        let stamp = LaravelFS.mtime(path)
        guard stamp != 0 else { return nil }
        lock.lock()
        if let c = cache[path], c.stamp == stamp {
            if let i = lru.lastIndex(of: path) { lru.remove(at: i) }
            lru.append(path)
            lock.unlock()
            return c.comp
        }
        lock.unlock()
        guard let text = FastProject.readRaw(path), text.length <= Self.maxFileBytes * (path.hasSuffix(".d.ts") ? 2 : 1) else { return nil }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let c = NVProject.build(path: path, text: text)
        NVProject.statBuilds += 1; NVProject.statPaths[path, default: 0] += 1; NVProject.statBuildNs += DispatchTime.now().uptimeNanoseconds &- t0
        c.stamp = stamp
        lock.lock()
        if let old = cache.removeValue(forKey: path) { cost -= old.comp.cost; if let i = lru.lastIndex(of: path) { lru.remove(at: i) } }
        while (cache.count >= Self.maxEntries || cost + c.cost > Self.maxCost), let victim = lru.first {
            lru.removeFirst()
            if let v = cache.removeValue(forKey: victim) { cost -= v.comp.cost }
        }
        cache[path] = (stamp, c); lru.append(path); cost += c.cost
        lock.unlock()
        return c
    }

    private var exportCache: [String: (stamp: Int64, comp: VSComp)] = [:]
    private var exportCost = 0

    /// Imports / exports / declarations of a plain module (barrels, `index.d.ts` of a component library): no props, no templates. Small and capped separately
    /// so a scan over many library imports never evicts the real component summaries.
    func exportsComp(path: String) -> VSComp? {
        let stamp = LaravelFS.mtime(path)
        guard stamp != 0 else { return nil }
        lock.lock()
        if let c = exportCache[path], c.stamp == stamp { lock.unlock(); return c.comp }
        lock.unlock()
        guard let text = FastProject.readRaw(path), text.length <= 1_400_000 else { return nil }
        let c = VSBuild.script(path: path, text: text, scanGlobals: false)
        c.stamp = stamp
        lock.lock()
        if exportCost + c.cost > 700_000 { exportCache.removeAll(); exportCost = 0 }
        exportCache[path] = (stamp, c); exportCost += c.cost
        lock.unlock()
        return c
    }

    static func build(path: String, text: NSString) -> VSComp {
        if path.hasSuffix(".d.ts") { return VSBuild.declaration(path: path, text: text) }
        if path.hasSuffix(".vue") { return VSBuild.component(path: path, text: text) }
        return VSBuild.script(path: path, text: text, scanGlobals: true)
    }

    private var liveMemo: (path: String, text: NSString, comp: VSComp)?

    /// Summary of an open buffer (unsaved edits count). The last one is memoised.
    func liveComp(path: String, text: NSString) -> VSComp {
        if let m = liveMemo, m.path == path, m.text === text || m.text.isEqual(to: text as String) { return m.comp }
        let c = NVProject.build(path: path, text: text)
        liveMemo = (path, NSString(string: text as String), c)
        return c
    }

    // MARK: file lists (lazy; rebuilt when FSEvents mark the project dirty)

    static let skipDirs: Set<String> = ["node_modules", "vendor", ".git", "storage", ".idea", ".vscode", "dist", "build", "coverage", "target", "__pycache__",
                                        ".venv", ".next", ".nuxt", ".svelte-kit", ".cache", "bower_components", "tmp", "temp", "logs", ".turbo", ".output"]
    static let codeExts: Set<String> = ["js", "mjs", "ts", "jsx", "tsx", "cjs", "mts"]
    static let maxVue = 8000
    static let maxCode = 6000

    private func ensureLists() {
        lock.lock(); let wasDirty = dirty; dirty = false; lock.unlock()
        listLock.lock(); defer { listLock.unlock() }
        if listed, !wasDirty { return }
        var vue: [String] = [], code: [String] = []
        var stack: [(String, Int)] = [(root, 0)]
        var visited = 0
        while let (dir, depth) = stack.popLast(), visited < 80_000 {
            for e in FastProject.readEntries(dir, fileSuffix: []) {
                visited += 1
                if e.isDir {
                    if depth < 12, !Self.skipDirs.contains(e.name), !(dir == root + "/public" && e.name == "build") { stack.append((dir + "/" + e.name, depth + 1)) }
                    continue
                }
                let lower = e.name.lowercased()
                if lower.hasSuffix(".vue") { if vue.count < Self.maxVue { vue.append(dir + "/" + e.name) } }
                else if let dot = lower.lastIndex(of: ".") {
                    let ext = String(lower[lower.index(after: dot)...])
                    if Self.codeExts.contains(ext), !lower.hasSuffix(".min.js"), !lower.hasSuffix(".d.ts"), code.count < Self.maxCode { code.append(dir + "/" + e.name) }
                }
            }
        }
        vue.sort(); code.sort()
        vueList = vue; codeList = code; listed = true
    }

    var vueFiles: [String] { ensureLists(); listLock.lock(); defer { listLock.unlock() }; return vueList }
    var codeFiles: [String] { ensureLists(); listLock.lock(); defer { listLock.unlock() }; return codeList }

    // MARK: module resolution (NativeJSResolve / NativeJSAlias, called not duplicated)

    func resolve(_ spec: String, from file: String) -> String? {
        let m = NJSProject.shared(root: NativeJS.root(for: URL(fileURLWithPath: file))).modules
        if let r = m.resolve(spec, from: file) { return r }
        // a nested package (nwidart Modules/X with its own package.json / vite.config) does not see the aliases of the application's root config
        if !spec.hasPrefix("."), !spec.hasPrefix("/"), m.root != root, let r = NJSProject.shared(root: root).modules.resolve(spec, from: root + "/__vue_probe.vue") { return r }
        // `@/x` / `~/x` that no config declares: laravel-vite-plugin aliases `@` to resources/js, Vue CLI / Vite templates use src, Nuxt the project root
        if spec.hasPrefix("@/") || spec.hasPrefix("~/") {
            let rest = String(spec.dropFirst(2))
            for dir in implicitAliasDirs() { if let r = m.tryModule(dir + "/" + rest) { return NJSModules.canonicalCase(r) } }
        }
        return nil
    }

    private var implicitDirs: [String]?

    private func implicitAliasDirs() -> [String] {
        lock.lock(); if let d = implicitDirs { lock.unlock(); return d }; lock.unlock()
        var dirs: [String] = []
        var hay = ""
        for n in ["package.json"] + NJSModules.aliasConfigNames {
            if LaravelFS.isFile(root + "/" + n), let d = FileManager.default.contents(atPath: root + "/" + n), d.count < 200_000 { hay += String(decoding: d, as: UTF8.self) }
        }
        if hay.contains("laravel-vite-plugin") || hay.contains("laravel-mix") { dirs.append(root + "/resources/js") }
        dirs += [root + "/src", root + "/app", root + "/resources/js", root]
        dirs = dirs.filter { LaravelFS.isDir($0) }
        lock.lock(); implicitDirs = dirs; lock.unlock()
        return dirs
    }

    func beginRequest() { NJSProject.shared(root: root).modules.beginRequest() }

    // MARK: derived project knowledge (memoised until dirty)

    func memoGlobals(_ make: () -> [NVGlobal]) -> [NVGlobal] {
        lock.lock(); if let g = globalsMemo { lock.unlock(); return g }; lock.unlock()
        let g = make()
        lock.lock(); globalsMemo = g; lock.unlock()
        return g
    }

    func memoAuto(_ make: () -> [String: String]) -> [String: String] {
        lock.lock(); if let g = autoMemo { lock.unlock(); return g }; lock.unlock()
        let g = make()
        lock.lock(); autoMemo = g; lock.unlock()
        return g
    }

    func memoRoute(_ key: String, _ make: () -> [NPTarget]) -> [NPTarget] {
        lock.lock(); if let g = routeMemo[key] { lock.unlock(); return g }; lock.unlock()
        let g = make()
        lock.lock(); if routeMemo.count > 200 { routeMemo.removeAll() }; routeMemo[key] = g; lock.unlock()
        return g
    }
}

struct NVGlobal {
    var key: String
    var file: String
    var reg: VSReg
}

// MARK: - Summary builders

enum VSBuild {
    static let emitNames: Set<String> = ["emit", "$emit"]

    private static func scanEmitCalls(_ tk: VSTokens, into c: VSComp) {
        guard c.emitCalls.count < 80 else { return }
        var i = 0
        while i + 2 < tk.count {
            if tk[i].kind == .ident, emitNames.contains(tk[i].text), tk[i + 1].isP("("), tk[i + 2].kind == .str, c.emitCalls.count < 80 {
                if !c.emitCalls.contains(where: { $0.name == tk[i + 2].text }) {
                    c.emitCalls.append(VSEmitDecl(name: tk[i + 2].text, loc: tk[i + 2].s, len: tk[i + 2].e - tk[i + 2].s))
                }
            }
            i += 1
        }
    }

    static func component(path: String, text: NSString, light: Bool = false) -> VSComp {
        let c = VSComp()
        c.path = path
        for b in VSSFC.blocks(text) {
            if b.tag == "template", b.lang.isEmpty || b.lang == "html" { c.templateRange = b.content }
            guard b.tag == "script", b.src == nil, b.content.length > 0, b.content.length <= 700_000 else { continue }
            if b.isSetup { c.isSetup = true }
            let tk = VSLex.run(VSLex.chars(text, b.content), base: b.content.location)
            var parser = VSScriptParser(tk: tk, ns: text, comp: c, setup: b.isSetup)
            parser.topLevel()
            if b.isSetup {
                parser.parseMacros()
                if c.setupInsert == nil { c.setupInsert = b.content.location }
            }
            if !light { scanEmitCalls(tk, into: c) }
        }
        if light { return c }
        if let tr = c.templateRange, tr.length > 0, tr.length < 1_500_000 {
            let t = VSTemplate.scan(text, range: tr)
            if let f = t.elems.first { c.rootOffset = f.tagStart }
            for e in t.elems where e.name == "slot" && c.slots.count < 40 {
                var name = "default"
                var props: [String] = []
                for a in e.attrs {
                    if a.name == "name", let v = a.value { name = text.substring(with: v) }
                    else if a.name.hasPrefix(":") || a.name.hasPrefix("v-bind:") {
                        let n = a.name.hasPrefix(":") ? String(a.name.dropFirst()) : String(a.name.dropFirst(7))
                        if n == "name", let v = a.value { let s = text.substring(with: v).trimmingCharacters(in: CharacterSet(charactersIn: "'\" ")); if !s.isEmpty, !s.contains(" ") { name = s } }
                        else { props.append(n) }
                    }
                }
                if !c.slots.contains(where: { $0.name == name }) { c.slots.append(VSSlotDecl(name: name, loc: e.tagStart, props: props)) }
            }
        }
        return c
    }

    /// Plain JS / TS module: imports, exports, declarations (and global `app.component('X', Y)` registrations when asked).
    static func script(path: String, text: NSString, scanGlobals: Bool) -> VSComp {
        let c = VSComp()
        c.path = path
        guard text.length > 0, text.length <= 800_000 else { return c }
        let tk = VSLex.run(VSLex.chars(text, NSRange(location: 0, length: text.length)))
        var parser = VSScriptParser(tk: tk, ns: text, comp: c, setup: false)
        parser.topLevel()
        if scanGlobals {
            var i = 0
            while i + 4 < tk.count {
                if tk[i].isP("."), tk[i + 1].isI("component"), tk[i + 2].isP("("), tk[i + 3].kind == .str, tk[i + 4].isP(",") {
                    var reg = VSReg(key: tk[i + 3].text, loc: tk[i + 3].s)
                    let close = tk.match[i + 2] > i + 2 ? tk.match[i + 2] : min(tk.count, i + 40)
                    let v = i + 5
                    if v < close, tk[v].kind == .ident, v + 1 == close || tk[v + 1].isP(",") { reg.valueIdent = tk[v].text }
                    var q = v
                    while q + 2 < close { if tk[q].isI("import"), tk[q + 1].isP("("), tk[q + 2].kind == .str { reg.spec = tk[q + 2].text; break }; q += 1 }
                    if reg.valueIdent != nil || reg.spec != nil { c.globalRegs.append(reg) }
                }
                i += 1
            }
        }
        return c
    }

    /// `.d.ts` of a library component (PrimeVue style): `declare const X: DefineComponent<XProps, XSlots, XEmits>` + the interfaces.
    static func declaration(path: String, text: NSString) -> VSComp {
        let c = VSComp()
        c.path = path
        c.isDeclaration = true
        guard text.length > 0, text.length <= 1_400_000 else { return c }
        let tk = VSLex.run(VSLex.chars(text, NSRange(location: 0, length: text.length)))
        var parser = VSScriptParser(tk: tk, ns: text, comp: c, setup: false)
        parser.topLevel()
        for i in 0..<tk.count where tk[i].isI("DefineComponent") && i + 2 < tk.count && tk[i + 1].isP("<") {
            // const name: `declare const X: DefineComponent<`
            var n = i - 1
            while n > 0, !tk[n].isP(":") { n -= 1 }
            if n > 0, tk[n - 1].kind == .ident { c.declName = tk[n - 1].text; c.rootOffset = tk[n - 1].s }
            var args: [String] = []
            var k = i + 2
            var depth = 0
            while k < tk.count, args.count < 4 {
                if tk[k].isP(">"), depth == 0 { break }
                if tk[k].kind == .ident, depth == 0, k == i + 2 || tk[k - 1].isP(",") { args.append(tk[k].text) }
                if tk[k].isP("<") { depth += 1 } else if tk[k].isP(">") { depth -= 1 }
                k += 1
            }
            if let propsName = args.first, let o = parser.typeBodies[propsName] {
                for m in parser.typeMembers(o) where !m.isCall {
                    var p = VSPropDecl(name: m.name, loc: tk[m.idx].s, len: tk[m.idx].e - tk[m.idx].s, doc: parser.docText(m.idx))
                    p.type = parser.slice(m.typeStart, m.typeEnd, cap: 90); p.required = !m.optional
                    c.props.append(p)
                }
                let base = propsName.hasSuffix("Props") ? String(propsName.dropLast(5)) : propsName
                for en in [base + "EmitsOptions", base + "Emits"] {
                    guard let eo = parser.typeBodies[en] else { continue }
                    for m in parser.typeMembers(eo) {
                        var e = VSEmitDecl(name: m.name, loc: tk[m.idx].s, len: tk[m.idx].e - tk[m.idx].s, sig: parser.slice(m.typeStart, m.typeEnd, cap: 90), doc: parser.docText(m.idx))
                        if m.isCall { e.sig = parser.slice(m.typeStart, m.typeEnd, cap: 90) }
                        c.emits.append(e)
                    }
                    break
                }
            }
            if args.count > 1, let so = parser.typeBodies[args[1]] {
                for m in parser.typeMembers(so) where !m.isCall {
                    c.slots.append(VSSlotDecl(name: m.name, loc: tk[m.idx].s, props: [], doc: parser.docText(m.idx)))
                }
            }
            break
        }
        return c
    }
}
