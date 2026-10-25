import AppKit

/// What Alt-F7 was asked about: a component (its file), optionally one of its props / events.
struct NVUsageTarget {
    var path: String
    var display: String
    var prop: String?            // declared prop name
    var event: String?
}

enum NVRefs {
    /// Component (or component prop / event) under the caret in a template; the SFC block tags (`<template>`, `<script>`) stand for the file's own component.
    static func identify(_ doc: NVDoc, offset: Int) -> NVUsageTarget? {
        for b in doc.blocks where b.tag == "template" || b.tag == "script" {
            let nameRange = NSRange(location: b.open.location + 1, length: b.tag.utf16.count)
            if offset >= nameRange.location, offset <= NSMaxRange(nameRange) {
                let base = ((doc.file as NSString).lastPathComponent as NSString).deletingPathExtension
                return NVUsageTarget(path: doc.file, display: VSName.pascal(base))
            }
        }
        guard doc.inTemplate(offset), let site = doc.site(at: offset) else { return nil }
        switch site {
        case .tag(let ei):
            guard let ref = doc.ref(forElement: ei) else { return nil }
            return NVUsageTarget(path: ref.path, display: doc.tpl.elems[ei].name)
        case .attrName(let ei, let ai):
            let a = doc.tpl.elems[ei].attrs[ai]
            let kind = NVService.classify(a.name)
            var isSlot = false
            if case .slot = kind { isSlot = true }
            guard let oi = NVService.owner(doc, ei, slot: isSlot), let ref = doc.ref(forElement: oi), let tc = doc.compOf(ref) else { return nil }
            let tag = doc.tpl.elems[oi].name
            switch kind {
            case .prop(let n):
                guard let pr = tc.prop(n) else { return nil }
                return NVUsageTarget(path: ref.path, display: "\(tag) :\(pr.name)", prop: pr.name)
            case .model(let arg):
                for n in arg.map({ [$0] }) ?? ["modelValue", "value"] { if let pr = tc.prop(n) { return NVUsageTarget(path: ref.path, display: "\(tag) v-model:\(pr.name)", prop: pr.name) } }
                return nil
            case .event(let n):
                guard let em = tc.emit(n) else { return nil }
                return NVUsageTarget(path: ref.path, display: "\(tag) @\(em.name)", event: em.name)
            default: return nil
            }
        default: return nil
        }
    }

    private static func lineInfo(_ text: NSString, _ offset: Int) -> (line: Int, col: Int, snippet: String) {
        let o = max(0, min(offset, text.length))
        let lr = text.lineRange(for: NSRange(location: o, length: 0))
        var line = 1
        var i = 0
        while i < lr.location {
            let r = text.range(of: "\n", options: [], range: NSRange(location: i, length: lr.location - i))
            if r.location == NSNotFound { break }
            line += 1; i = NSMaxRange(r)
        }
        let snippet = text.substring(with: lr).trimmingCharacters(in: .whitespacesAndNewlines)
        return (line, o - lr.location + 1, snippet.count > 160 ? String(snippet.prefix(160)) : snippet)
    }

    /// Every template usage of the component across the project (plus the import / registration lines), prefiltered by file text.
    static func collect(_ p: NVProject, target: NVUsageTarget, liveTexts: [String: NSString], cancel: CancelToken?, cap: Int = 400) -> [NPRefHit] {
        p.beginRequest()
        let T = target.path
        let base = ((T as NSString).lastPathComponent as NSString).deletingPathExtension
        var global: Set<String> = []
        for g in p.globals() {
            guard let gc = p.comp(path: g.file) else { continue }
            if let r = p.resolveRegistrationPath(g.reg, in: gc, file: g.file), r == T { global.insert(g.key) }
        }
        for (name, path) in p.autoComponents() where path == T { global.insert(name) }
        var needles = Set<String>([VSName.pascal(base), VSName.kebab(VSName.pascal(base))])
        for g in global { needles.insert(g); needles.insert(VSName.kebab(g)) }
        needles = needles.filter { !$0.isEmpty }
        var out: [NPRefHit] = []
        var seenFiles = Set<String>()
        var files = p.vueFiles
        for k in liveTexts.keys where !files.contains(k) { files.append(k) }
        for f in files {
            if cancel?.isCancelled == true || out.count >= cap { break }
            guard seenFiles.insert(f).inserted else { continue }
            let text: NSString
            if let live = liveTexts[f] { text = live }
            else {
                guard let d = try? Data(contentsOf: URL(fileURLWithPath: f), options: .mappedIfSafe), d.count <= 900_000 else { continue }
                let hit = d.withUnsafeBytes { raw -> Bool in
                    guard let b = raw.baseAddress else { return false }
                    return needles.contains { n in let u = Array(n.utf8); return memmem(b, d.count, u, u.count) != nil }
                }
                guard hit, let t = NSString(data: d, encoding: String.Encoding.utf8.rawValue) else { continue }
                text = t
            }
            guard needles.contains(where: { text.range(of: $0, options: .literal).location != NSNotFound }) else { continue }
            let c = VSBuild.component(path: f, text: text, light: true)
            var names = Set<String>(global)
            var importHits: [NPRefHit] = []
            for imp in c.imports where !imp.typeOnly {
                guard let t = p.resolveSpecToComponent(imp.spec, imp.imported, from: f, depth: 0), t.path == T else { continue }
                names.insert(imp.local)
                let li = lineInfo(text, imp.loc)
                importHits.append(NPRefHit(path: f, range: NSRange(location: imp.loc, length: imp.len), line: li.line, column: li.col, snippet: li.snippet, role: .import))
            }
            for reg in c.regs {
                if let r = p.resolveRegistrationPath(reg, in: c, file: f), r == T { names.insert(reg.key) }
            }
            guard !names.isEmpty, let tr = c.templateRange, tr.length > 0 else { continue }
            let tpl = VSTemplate.scan(text, range: tr)
            var hits: [NPRefHit] = []
            for e in tpl.elems where names.contains(where: { NVProject.sameComponentName($0, e.name) }) && !e.name.contains(".") {
                if let prop = target.prop {
                    for a in e.attrs {
                        var matches = false
                        switch NVService.classify(a.name) {
                        case .prop(let n): matches = VSName.camel(n) == VSName.camel(prop)
                        case .model(let arg): matches = VSName.camel(arg ?? "modelValue") == VSName.camel(prop)
                        default: break
                        }
                        if matches { let li = lineInfo(text, a.nameRange.location); hits.append(NPRefHit(path: f, range: a.nameRange, line: li.line, column: li.col, snippet: li.snippet, role: .usage)) }
                    }
                } else if let ev = target.event {
                    for a in e.attrs {
                        if case .event(let n) = NVService.classify(a.name), VSName.camel(n) == VSName.camel(ev) {
                            let li = lineInfo(text, a.nameRange.location); hits.append(NPRefHit(path: f, range: a.nameRange, line: li.line, column: li.col, snippet: li.snippet, role: .usage))
                        }
                    }
                } else {
                    let li = lineInfo(text, e.nameRange.location)
                    hits.append(NPRefHit(path: f, range: e.nameRange, line: li.line, column: li.col, snippet: li.snippet, role: .usage))
                }
            }
            if target.prop != nil || target.event != nil { out += hits }
            else if !hits.isEmpty { out += importHits + hits }
        }
        return out
    }
}

extension NVProject {
    func resolveRegistrationPath(_ r: VSReg, in c: VSComp, file: String) -> String? {
        if let spec = r.spec { return resolveSpecToComponent(spec, "default", from: file, depth: 0)?.path }
        if let v = r.valueIdent, let imp = c.imp(v) { return resolveSpecToComponent(imp.spec, imp.imported, from: file, depth: 0)?.path }
        return nil
    }
}

enum NativeVueUI {
    static var presentHook: ((_ title: String, _ items: [PickerItem]) -> Void)?
    private static var token: CancelToken?
    private static let queue = DispatchQueue(label: "nativevue.refs", qos: .utility)

    static func cancel() { token?.cancel(); token = nil }

    static func liveTexts(_ w: ProjectWindow) -> [String: NSString] {
        var out: [String: NSString] = [:]
        for (path, tab) in w.editors where tab.isDirty && path.hasSuffix(".vue") { out[(path as NSString).standardizingPath] = tab.textView.string as NSString }
        return out
    }

    /// True when native took the request (results arrive asynchronously). False: the next handler (native JS, then the language server) answers.
    @discardableResult
    static func findUsages(_ w: ProjectWindow) -> Bool {
        guard let tab = w.current, NativeVue.handles(tab.url) else { return false }
        let text = tab.textView.string as NSString
        let offset = tab.textView.selectedRange().location
        let p = NVProject.shared(root: NativeVue.root(for: tab.url))
        let file = (tab.url.standardizedFileURL.path as NSString).standardizingPath
        let target: NVUsageTarget? = p.queue.sync {
            p.beginRequest()
            guard let doc = NVDoc(p, file: file, text: text, needsTemplate: false) else { return nil }
            return NVRefs.identify(doc, offset: offset)
        }
        guard let target else { return false }
        cancel()
        let t = CancelToken()
        token = t
        let live = liveTexts(w)
        let window = w.window
        let root = p.root
        queue.async {
            let hits = NVRefs.collect(p, target: target, liveTexts: live, cancel: t)
            DispatchQueue.main.async {
                guard !t.isCancelled else { return }
                token = nil
                let usages = hits.filter { $0.role == .usage }
                var title = "Usages of <\(target.display)> (\(usages.count) in \(Set(usages.map(\.path)).count) files)"
                if hits.count >= 400 { title += " - capped" }
                let items = NativePHPUI.items(for: hits, root: root)
                if usages.isEmpty, LanguageServers.findUsages(in: tab) { return }       // native found nothing: the server may know better
                if let h = presentHook { h(title, items); return }
                QuickPicker.present(over: window, placeholder: title, items: items)
            }
        }
        return true
    }
}
