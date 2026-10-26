import AppKit

/// CompletionProvider for Vue templates: component tag names (imported, registered, global, auto-imported, and project components with an
/// auto-added `<script setup>` import), props / events / slots after a component tag, and bindings inside expressions.
/// Everything else in a template (HTML attributes, classes, directives) stays with the native web provider.
final class NativeVueProvider: CompletionProvider {
    let triggerCharacters = ["<", " ", ":", "@", "#", "-"]
    private var token = 0

    func complete(_ context: CompletionContext, deliver: @escaping ([CompletionItem], Bool) -> Void) {
        token += 1
        let mine = token
        guard NativeVue.handles(context.fileURL), context.text.utf8.count < 2_000_000 else { deliver([], false); return }
        let p = NVProject.shared(root: NativeVue.root(for: context.fileURL))
        p.queue.async { [weak self] in
            guard let self, self.token == mine else { return }
            deliver(NVComplete.items(p, context), false)
        }
    }

    func cancel() { token += 1 }
}

enum NVComplete {
    static func relativePath(from dir: String, to file: String) -> String {
        let a = dir.split(separator: "/").map(String.init), b = file.split(separator: "/").map(String.init)
        var i = 0
        while i < a.count, i < b.count - 1, a[i] == b[i] { i += 1 }
        let ups = a.count - i
        let rest = b[i...].joined(separator: "/")
        return (ups == 0 ? "./" : String(repeating: "../", count: ups)) + rest
    }

    static func items(_ p: NVProject, _ ctx: CompletionContext) -> [CompletionItem] {
        let file = (ctx.fileURL.standardizedFileURL.path as NSString).standardizingPath
        let ns = NSString(string: ctx.text)
        let caret = min(ctx.caret, ns.length)
        p.beginRequest()
        let blocks = VSSFC.blocks(ns)
        guard let tb = blocks.first(where: { $0.tag == "template" && ($0.lang.isEmpty || $0.lang == "html") }),
              caret >= tb.content.location, caret <= NSMaxRange(tb.content) else { return [] }
        let trunc = NSRange(location: tb.content.location, length: caret - tb.content.location)
        let tpl = VSTemplate.scan(ns, range: trunc)
        let cur = p.liveComp(path: file, text: ns)

        if let io = tpl.openInterp {
            let parent = tpl.openStack.last ?? -1
            _ = io
            return expressionItems(ns, caret: caret, tpl: tpl, cur: cur, scopeElement: parent, ownSlots: true)
        }
        if let last = tpl.elems.last, last.openEnd < 0 {
            let ei = tpl.elems.count - 1
            if last.attrs.isEmpty, !last.afterNameWhitespace {
                let r = NSRange(location: last.nameRange.location, length: caret - last.nameRange.location)
                return tagItems(p, cur: cur, file: file, ns: ns, range: r, prefix: ns.substring(with: r))
            }
            if let a = last.attrs.last, a.valueOpen, let v = a.value {
                guard NVService.isBoundExpression(a.name), caret >= v.location else { return [] }
                if a.name == "v-for" || NVService.isSlotAttr(a.name) { return [] }
                return expressionItems(ns, caret: caret, tpl: tpl, cur: cur, scopeElement: ei, ownSlots: false)
            }
            // attribute name position
            var start = caret
            if let a = last.attrs.last, a.value == nil, !last.afterNameWhitespace, NSMaxRange(a.nameRange) == caret { start = a.nameRange.location }
            else if let a = last.attrs.last, a.value != nil, let v = a.value, NSMaxRange(v) + 1 >= caret, !last.afterNameWhitespace { return [] }
            return attrItems(p, tpl: tpl, ei: ei, cur: cur, file: file, ns: ns, range: NSRange(location: start, length: caret - start))
        }
        // `<` typed right before the caret (no name yet)
        var k = caret
        while k > tb.content.location, ns.character(at: k - 1) != 60, VSLex.isIdPart(ns.character(at: k - 1)) || ns.character(at: k - 1) == 45 || ns.character(at: k - 1) == 46 { k -= 1 }
        if k > tb.content.location, ns.character(at: k - 1) == 60, k == caret || true {
            let r = NSRange(location: k, length: caret - k)
            if k == caret || VSLex.isIdStart(ns.character(at: k)) { return tagItems(p, cur: cur, file: file, ns: ns, range: r, prefix: ns.substring(with: r)) }
        }
        return []
    }

    // MARK: tag names

    static func tagItems(_ p: NVProject, cur: VSComp, file: String, ns: NSString, range: NSRange, prefix: String) -> [CompletionItem] {
        let kebabStyle = prefix.contains("-") || (prefix.first?.isLowercase == true && !prefix.isEmpty && cur.imports.isEmpty)
        func label(_ n: String) -> String { kebabStyle ? VSName.kebab(n) : n }
        var seen = Set<String>()
        var out: [CompletionItem] = []
        func add(_ name: String, detail: String, sort: String, doc: String = "", edits: [(range: NSRange, text: String)] = []) {
            let pn = VSName.pascal(name)
            guard !pn.isEmpty, seen.insert(pn).inserted else { return }
            let nextIsGT = NSMaxRange(range) < ns.length && ns.character(at: NSMaxRange(range)) == 62
            let shown = label(pn)
            var it = nextIsGT ? CI.make(shown, .class, detail: detail, sort: sort + pn, doc: doc, filter: pn + " " + VSName.kebab(pn), range: range)
                              : CI.make(shown, .class, detail: detail, insert: shown + ">$0</" + shown + ">", snippet: true, sort: sort + pn, doc: doc, filter: pn + " " + VSName.kebab(pn), range: range)
            it.additionalEdits = edits
            out.append(it)
        }
        for imp in cur.imports where !imp.typeOnly && imp.local.first?.isUppercase == true && (cur.isSetup || cur.regs.contains { $0.valueIdent == imp.local }) {
            add(imp.local, detail: "import '\(imp.spec)'", sort: "0")
        }
        for r in cur.regs { add(r.key, detail: "components", sort: "0") }
        for d in cur.decls where cur.isSetup && d.kind != .imp && d.name.first?.isUppercase == true && (d.initCall == "defineComponent" || d.initCall == "defineAsyncComponent" || d.spec != nil) { add(d.name, detail: "binding", sort: "0") }
        for g in p.globals() { add(g.key, detail: "global component", sort: "1") }
        for (name, path) in p.autoComponents() { add(name, detail: "auto-imported · " + path.replacingOccurrences(of: p.root + "/", with: ""), sort: "1") }
        // project components that are not available yet: completing them adds the import to <script setup>
        if cur.isSetup, let insert = cur.setupInsert, !prefix.isEmpty {
            let dir = (file as NSString).deletingLastPathComponent
            let semi: Bool = {
                guard cur.setupHasImport, insert > 0, insert <= ns.length else { return true }
                return ns.character(at: insert - 1) == 59
            }()
            var n = 0
            for f in p.vueFiles where f != file && n < 80 {
                var base = ((f as NSString).lastPathComponent as NSString).deletingPathExtension
                if base.lowercased() == "index" { base = ((f as NSString).deletingLastPathComponent as NSString).lastPathComponent }
                let name = VSName.pascal(base)
                guard name.first?.isUppercase == true, !seen.contains(name), Fuzzy.score(Array(prefix.lowercased()), in: name) != nil || name.lowercased().contains(prefix.lowercased()) else { continue }
                let rel = relativePath(from: dir, to: f)
                let line = "import \(name) from '\(rel)'" + (semi ? ";" : "")
                let edit = (range: NSRange(location: insert, length: 0), text: cur.setupHasImport ? "\n" + line : "\n" + line + "\n")
                add(name, detail: "import " + p.relativeToRoot(f), sort: "2", doc: "Adds `\(line)` to `<script setup>`", edits: [edit])
                n += 1
            }
        }
        return out
    }

    // MARK: attributes of a component tag

    static func attrItems(_ p: NVProject, tpl: VSTemplate, ei: Int, cur: VSComp, file: String, ns: NSString, range: NSRange) -> [CompletionItem] {
        let el = tpl.elems[ei]
        let typed = ns.substring(with: range)
        var oi = ei
        var slotMode = typed.hasPrefix("#") || typed.hasPrefix("v-slot:")
        if el.name.lowercased() == "template", el.parent >= 0, slotMode || typed.isEmpty { oi = el.parent; if typed.isEmpty { slotMode = true } }
        let owner = tpl.elems[oi]
        guard NVProject.isComponentTag(owner.name), let ref = p.resolveTag(owner.name, file: file, cur: cur) else { return [] }
        guard let tc = ref.path == file ? cur : p.comp(path: ref.path) else { return [] }
        var present = Set<String>()
        for (i, a) in el.attrs.enumerated() where !(i == el.attrs.count - 1 && NSMaxRange(a.nameRange) == range.location + range.length && a.value == nil) {
            switch NVService.classify(a.name) {
            case .prop(let n): present.insert("p:" + VSName.camel(n))
            case .event(let n): present.insert("e:" + VSName.camel(n))
            case .model(let n): present.insert("p:" + VSName.camel(n ?? "modelValue"))
            default: break
            }
        }
        var out: [CompletionItem] = []
        enum Mode { case bound, event, slot, model, plain }
        var mode: Mode = .plain
        var prefix = ""
        if typed.hasPrefix(":") { mode = .bound; prefix = ":" }
        else if typed.hasPrefix("v-bind:") { mode = .bound; prefix = "v-bind:" }
        else if typed.hasPrefix("@") { mode = .event; prefix = "@" }
        else if typed.hasPrefix("v-on:") { mode = .event; prefix = "v-on:" }
        else if typed.hasPrefix("#") { mode = .slot; prefix = "#" }
        else if typed.hasPrefix("v-slot:") { mode = .slot; prefix = "v-slot:" }
        else if typed.hasPrefix("v-model:") { mode = .model; prefix = "v-model:" }
        else if slotMode { mode = .slot; prefix = "#" }
        func kebabIfNeeded(_ n: String) -> String { n.contains(where: { $0.isUppercase }) ? VSName.kebab(n) : n }
        if mode == .plain || mode == .bound || mode == .model {
            for pr in tc.props where !present.contains("p:" + VSName.camel(pr.name)) {
                let shown = kebabIfNeeded(pr.name)
                let t = pr.type.lowercased()
                let isBool = t == "boolean", isString = t == "string"
                let label: String, insert: String
                var snippet = true
                switch mode {
                case .bound, .model: label = prefix + shown; insert = label + "=\"$0\""
                default:
                    label = shown
                    if isBool { insert = shown; snippet = false } else if isString { insert = shown + "=\"$0\"" } else { insert = ":" + shown + "=\"$0\"" }
                }
                out.append(CI.make(label, .property, detail: (pr.required ? "required · " : "") + (pr.type.isEmpty ? "prop" : pr.type), insert: insert, snippet: snippet,
                                   sort: (pr.required ? "0" : "1") + shown, doc: pr.doc, filter: label + " " + pr.name, range: range))
            }
        }
        if mode == .event || (mode == .plain && typed.isEmpty) {
            for em in tc.emits where !present.contains("e:" + VSName.camel(em.name)) {
                let label = (mode == .event ? prefix : "@") + em.name
                out.append(CI.make(label, .method, detail: em.sig.isEmpty ? "event" : em.sig, insert: label + "=\"$0\"", snippet: true, sort: "3" + em.name, doc: em.doc, filter: label, range: range))
            }
        }
        if mode == .slot {
            for sl in tc.slots {
                let label = prefix + sl.name
                out.append(CI.make(label, .field, detail: sl.props.isEmpty ? "slot" : "slot { " + sl.props.joined(separator: ", ") + " }", insert: label, sort: "4" + sl.name, doc: sl.doc, filter: label, range: range))
            }
        }
        return out
    }

    // MARK: expressions

    static func expressionItems(_ ns: NSString, caret: Int, tpl: VSTemplate, cur: VSComp, scopeElement: Int, ownSlots: Bool) -> [CompletionItem] {
        var s = caret
        while s > 0, VSLex.isIdPart(ns.character(at: s - 1)) { s -= 1 }
        if s > 0, ns.character(at: s - 1) == 46 { return [] }                         // member access: needs types
        var seen = Set<String>()
        var out: [CompletionItem] = []
        func add(_ name: String, _ kind: CompletionKind, _ detail: String, sort: String) {
            guard seen.insert(name).inserted else { return }
            out.append(CI.make(name, kind, detail: detail, sort: sort + name))
        }
        if scopeElement >= 0 {
            for v in tpl.scope(of: scopeElement, ns: ns, includeOwnSlots: ownSlots).reversed() { add(v.name, .variable, v.kind, sort: "0") }
        }
        for d in cur.decls {
            let kind: CompletionKind = d.kind == .function || d.kind == .method ? .function : d.kind == .class ? .class : d.kind == .computed || d.kind == .data ? .property : .variable
            add(d.name, kind, d.kind == .imp ? "import" : d.initCall.map { "\($0)()" } ?? "", sort: "1")
        }
        for pr in cur.props { add(pr.name, .property, pr.type.isEmpty ? "prop" : "prop · " + pr.type, sort: "1") }
        return out
    }
}

extension NVService {
    static func isSlotAttr(_ n: String) -> Bool { VSTemplate.isSlotAttr(n) }
}

extension NVProject {
    func relativeToRoot(_ f: String) -> String { f.hasPrefix(root + "/") ? String(f.dropFirst(root.count + 1)) : f }
}
