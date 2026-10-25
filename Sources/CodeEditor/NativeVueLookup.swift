import Foundation

/// A parsed `.vue` buffer, ready for position queries.
struct NVDoc {
    let p: NVProject
    let file: String
    let text: NSString
    let blocks: [VSBlock]
    let tpl: VSTemplate
    let cur: VSComp
    let templateRange: NSRange

    enum Site {
        case tag(Int)                         // element index, offset on its (open or close) tag name
        case attrName(Int, Int)
        case attrValue(Int, Int)
        case interp(NSRange, Int)             // expression range, parent element (-1 = root)
        case sfcSrc(String, NSRange)          // `<style src>` / `<script src>`
    }

    init?(_ p: NVProject, file: String, text: NSString, needsTemplate: Bool = true) {
        guard text.length > 0, text.length < 2_000_000 else { return nil }
        self.p = p; self.file = file; self.text = text
        blocks = VSSFC.blocks(text)
        guard let tb = blocks.first(where: { $0.tag == "template" && ($0.lang.isEmpty || $0.lang == "html") }) else {
            if needsTemplate { return nil }
            templateRange = NSRange(location: 0, length: 0); tpl = VSTemplate(); cur = p.liveComp(path: file, text: text)
            return
        }
        templateRange = tb.content
        tpl = VSTemplate.scan(text, range: tb.content)
        cur = p.liveComp(path: file, text: text)
    }

    func inTemplate(_ offset: Int) -> Bool { offset >= templateRange.location && offset <= NSMaxRange(templateRange) && templateRange.length > 0 }

    func site(at offset: Int) -> Site? {
        for b in blocks {
            if let r = b.srcRange, let s = b.src, offset >= r.location, offset <= NSMaxRange(r) { return .sfcSrc(s, r) }
        }
        guard inTemplate(offset) else { return nil }
        if let ei = tpl.tag(containing: offset) {
            let e = tpl.elems[ei]
            if offset >= e.nameRange.location, offset <= NSMaxRange(e.nameRange) { return .tag(ei) }
            for (ai, a) in e.attrs.enumerated() {
                if offset >= a.nameRange.location, offset <= NSMaxRange(a.nameRange) { return .attrName(ei, ai) }
                if let v = a.value, offset >= v.location, offset <= NSMaxRange(v) { return .attrValue(ei, ai) }
            }
            return nil
        }
        for (i, e) in tpl.elems.enumerated() {
            if let c = e.closeNameRange, offset >= c.location, offset <= NSMaxRange(c) { return .tag(i) }
        }
        for it in tpl.interps where offset >= it.range.location && offset <= NSMaxRange(it.range) { return .interp(it.range, it.parent) }
        return nil
    }

    func target(_ path: String, _ offset: Int) -> NPTarget {
        path == file ? NWNav.target(path: path, offset: offset, text: text) : NWNav.target(path: path, offset: offset)
    }

    func rel(_ path: String) -> String {
        path.hasPrefix(p.root + "/") ? String(path.dropFirst(p.root.count + 1)) : path
    }

    func compOf(_ ref: VSCompRef) -> VSComp? { ref.path == file ? cur : p.comp(path: ref.path) }

    func ref(forElement ei: Int) -> VSCompRef? {
        let e = tpl.elems[ei]
        guard NVProject.isComponentTag(e.name) else { return nil }
        return p.resolveTag(e.name, file: file, cur: cur)
    }
}

enum NVAttrKind {
    case prop(String), event(String), model(String?), slot(String), ref, isAttr, directive, other
}

enum NVService {
    // MARK: attribute classification

    static func classify(_ rawName: String) -> NVAttrKind {
        func strip(_ s: String) -> String { s.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? s }
        var n = rawName
        if n.hasPrefix(":") { n.removeFirst(); return n.isEmpty ? .other : .prop(strip(n)) }
        if n.hasPrefix("v-bind:") { return .prop(strip(String(n.dropFirst(7)))) }
        if n.hasPrefix("@") { n.removeFirst(); return n.isEmpty ? .other : .event(strip(n)) }
        if n.hasPrefix("v-on:") { return .event(strip(String(n.dropFirst(5)))) }
        if n == "v-model" || n.hasPrefix("v-model.") { return .model(nil) }
        if n.hasPrefix("v-model:") { return .model(strip(String(n.dropFirst(8)))) }
        if n == "v-slot" || n == "slot-scope" { return .slot("default") }
        if n.hasPrefix("v-slot:") { return .slot(strip(String(n.dropFirst(7)))) }
        if n.hasPrefix("#") { return .slot(strip(String(n.dropFirst()))) }
        if n.hasPrefix("v-") || n == "v-bind" { return .directive }
        if n == "ref" { return .ref }
        if n == "is" { return .isAttr }
        if n == "key" || n == "class" || n == "style" || n == "id" { return .other }
        return .prop(n)
    }

    static func isBoundExpression(_ rawName: String) -> Bool {
        if rawName.hasPrefix(":") || rawName.hasPrefix("@") || rawName.hasPrefix("v-bind:") || rawName.hasPrefix("v-on:") || rawName.hasPrefix("v-model") { return true }
        guard rawName.hasPrefix("v-") else { return false }
        return !(rawName == "v-else" || rawName == "v-pre" || rawName == "v-once" || rawName == "v-cloak" || rawName.hasPrefix("v-slot"))
    }

    static let assetAttrs: Set<String> = ["src", "href", "srcset", "poster", "xlink:href", "data-src", "data-href"]
    static let routerTags: Set<String> = ["router-link", "routerlink", "nuxt-link", "nuxtlink", "link", "inertia-link", "inertialink"]
    static let keywords: Set<String> = ["true", "false", "null", "undefined", "this", "NaN", "Infinity", "typeof", "instanceof", "new", "in", "of", "void", "delete", "await", "async", "function", "return",
                                        "$event", "$attrs", "$slots", "$props", "$refs", "$emit", "$route", "$router", "$t", "$store", "$el", "$parent", "$root", "$data", "$nextTick", "$forceUpdate",
                                        "arguments", "Math", "Date", "JSON", "Object", "Array", "String", "Number", "Boolean", "console", "window", "document", "parseInt", "parseFloat", "isNaN",
                                        "Symbol", "Promise", "Map", "Set", "RegExp", "Error", "encodeURIComponent", "decodeURIComponent", "BigInt", "Intl", "navigator", "location", "emit"]

    // MARK: lookup

    static func lookup(_ p: NVProject, url: URL, text: NSString, offset: Int) -> NPHit? {
        let file = (url.standardizedFileURL.path as NSString).standardizingPath
        p.beginRequest()
        guard let first = NVDoc(p, file: file, text: text, needsTemplate: false), first.blocks.contains(where: { $0.tag == "template" || $0.srcRange != nil }) else { return nil }
        let doc = first
        guard let site = doc.site(at: min(offset, text.length)) else { return nil }
        switch site {
        case .sfcSrc(let src, let r):
            return assetHit(doc, src, range: r)
        case .tag(let ei):
            return tagHit(doc, ei)
        case .attrName(let ei, let ai):
            return attrNameHit(doc, ei, ai)
        case .attrValue(let ei, let ai):
            return attrValueHit(doc, ei, ai, offset: offset)
        case .interp(let r, let parent):
            return exprHit(doc, r, scopeElement: parent, ownSlots: true, offset: offset, attrName: nil, element: parent)
        }
    }

    // MARK: pieces

    static func rangeOfWord(_ r: NSRange) -> NSRange { r }

    static func assetHit(_ doc: NVDoc, _ ref: String, range: NSRange) -> NPHit? {
        guard let path = doc.p.resolveAsset(ref, from: doc.file) else { return nil }
        return NPHit(range: range, targets: [NPTarget(path: path, offset: 0, line: 1, column: 1)], markdown: "`\(doc.rel(path))`", kind: "file")
    }

    static func componentMarkdown(_ doc: NVDoc, tag: String, ref: VSCompRef, comp: VSComp?) -> String {
        var s = "**<\(tag)>** — Vue component\n\n`\(doc.rel(ref.path))` _(\(ref.via))_"
        guard let c = comp else { return s }
        if !c.props.isEmpty {
            s += "\n\n**Props**"
            for pr in c.props.prefix(14) {
                s += "\n- `\(pr.name)`" + (pr.type.isEmpty ? "" : ": `\(pr.type)`") + (pr.required ? " (required)" : "") + (pr.doc.isEmpty ? "" : " — " + String(pr.doc.prefix(110)))
            }
            if c.props.count > 14 { s += "\n- … \(c.props.count - 14) more" }
        }
        if !c.emits.isEmpty { s += "\n\n**Emits** " + c.emits.prefix(14).map { "`\($0.name)`" }.joined(separator: ", ") + (c.emits.count > 14 ? ", …" : "") }
        if !c.slots.isEmpty { s += "\n\n**Slots** " + c.slots.prefix(14).map { "`\($0.name)`" }.joined(separator: ", ") + (c.slots.count > 14 ? ", …" : "") }
        return s
    }

    static func tagHit(_ doc: NVDoc, _ ei: Int) -> NPHit? {
        let e = doc.tpl.elems[ei]
        guard let ref = doc.ref(forElement: ei) else { return nil }
        let tc = doc.compOf(ref)
        let md = componentMarkdown(doc, tag: e.name, ref: ref, comp: tc)
        return NPHit(range: e.nameRange, targets: [doc.target(ref.path, ref.offset)], markdown: md, kind: "component")
    }

    /// Element owning the props / slots an attribute refers to (`#slot` on a `<template>` belongs to the parent component).
    static func owner(_ doc: NVDoc, _ ei: Int, slot: Bool) -> Int? {
        var i = ei
        if slot, doc.tpl.elems[i].name.lowercased() == "template" { i = doc.tpl.elems[i].parent }
        return i >= 0 ? i : nil
    }

    static func attrNameHit(_ doc: NVDoc, _ ei: Int, _ ai: Int) -> NPHit? {
        let e = doc.tpl.elems[ei]
        let a = e.attrs[ai]
        let kind = classify(a.name)
        var isSlot = false
        if case .slot = kind { isSlot = true }
        guard let oi = owner(doc, ei, slot: isSlot), let ref = doc.ref(forElement: oi), let tc = doc.compOf(ref) else { return nil }
        let tag = doc.tpl.elems[oi].name
        func hit(_ loc: Int, _ md: String, kind k: String) -> NPHit {
            NPHit(range: a.nameRange, targets: [doc.target(ref.path, loc)], markdown: md, kind: k)
        }
        func propMD(_ pr: VSPropDecl) -> String {
            var s = "**\(pr.name)** — prop of `<\(tag)>`" + (pr.type.isEmpty ? "" : "\n\n`\(pr.name)\(pr.required ? "" : "?"): \(pr.type)`") + (pr.required ? "  (required)" : "")
            if !pr.doc.isEmpty { s += "\n\n" + pr.doc }
            return s
        }
        func emitMD(_ em: VSEmitDecl) -> String {
            var s = "**\(em.name)** — event of `<\(tag)>`"
            if !em.sig.isEmpty { s += "\n\n`\(em.sig)`" }
            if !em.doc.isEmpty { s += "\n\n" + em.doc }
            return s
        }
        switch kind {
        case .prop(let n):
            guard let pr = tc.prop(n) ?? tc.prop(VSName.camel(n)) else { return nil }
            return hit(pr.loc, propMD(pr), kind: "prop")
        case .model(let arg):
            let names = arg.map { [$0] } ?? ["modelValue", "value"]
            for n in names { if let pr = tc.prop(n) { return hit(pr.loc, propMD(pr), kind: "prop") } }
            return nil
        case .event(let n):
            if let em = tc.emit(n) { return hit(em.loc, emitMD(em), kind: "event") }
            if let call = tc.emitCalls.first(where: { $0.name == n || $0.name == VSName.camel(n) || VSName.kebab($0.name) == n }) {
                return hit(call.loc, "**\(n)** — event emitted by `<\(tag)>` (not declared in `emits`)", kind: "event")
            }
            return nil
        case .slot(let n):
            guard let sl = tc.slots.first(where: { $0.name == n }) else { return nil }
            var md = "**\(n)** — slot of `<\(tag)>`"
            if !sl.props.isEmpty { md += "\n\nScope: " + sl.props.map { "`\($0)`" }.joined(separator: ", ") }
            if !sl.doc.isEmpty { md += "\n\n" + sl.doc }
            return hit(sl.loc, md, kind: "slot")
        default:
            return nil
        }
    }

    static func attrValueHit(_ doc: NVDoc, _ ei: Int, _ ai: Int, offset: Int) -> NPHit? {
        let e = doc.tpl.elems[ei]
        let a = e.attrs[ai]
        guard let v = a.value else { return nil }
        let raw = doc.text.substring(with: v)
        let lname = e.name.lowercased()
        let kind = classify(a.name)
        if case .ref = kind {
            guard let d = doc.cur.decl(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
            return NPHit(range: v, targets: [doc.target(doc.file, d.loc)], markdown: "```ts\n\(d.detail)\n```\n\n_template ref_", kind: "ref")
        }
        if case .isAttr = kind {
            if raw.hasPrefix("vue:") { return nil }
            guard let ref = doc.p.resolveTag(raw, file: doc.file, cur: doc.cur) else { return nil }
            return NPHit(range: v, targets: [doc.target(ref.path, ref.offset)], markdown: componentMarkdown(doc, tag: raw, ref: ref, comp: doc.compOf(ref)), kind: "component")
        }
        if NVService.isBoundExpression(a.name) {
            return exprHit(doc, v, scopeElement: ei, ownSlots: false, offset: offset, attrName: a.name, element: ei)
        }
        if case .slot = kind { return nil }
        // plain attributes: assets and router targets
        if routerTags.contains(lname), a.name == "to" || a.name == "href" {
            let path = raw.split(whereSeparator: { $0 == "?" || $0 == "#" }).first.map(String.init) ?? raw
            if path.hasPrefix("/") {
                let ts = doc.p.routeTargets(path: path, name: nil)
                if !ts.isEmpty { return NPHit(range: v, targets: ts, markdown: "route `\(path)`", kind: "route") }
            }
        }
        if assetAttrs.contains(a.name) {
            let first = a.name == "srcset" ? (raw.split(separator: " ").first.map(String.init) ?? raw) : raw
            return assetHit(doc, first, range: v)
        }
        return nil
    }

    static func exprHit(_ doc: NVDoc, _ range: NSRange, scopeElement: Int, ownSlots: Bool, offset: Int, attrName: String?, element: Int) -> NPHit? {
        var exprRange = range
        if attrName == "v-for" {                       // only the iterated expression after `in` / `of` is a reference
            let ex = VSExpr(doc.text, range)
            var inIdx: Int?
            var i = 0
            while i < ex.tk.count {
                if ex.tk[i].isI("in") || ex.tk[i].isI("of") { inIdx = i; break }
                i = ex.tk[i].kind == .punct && ex.tk.match[i] > i ? ex.tk.match[i] + 1 : i + 1
            }
            guard let k = inIdx, k + 1 < ex.tk.count else { return nil }
            let start = ex.tk[k + 1].s
            guard offset >= start else { return nil }
            exprRange = NSRange(location: start, length: NSMaxRange(range) - start)
        }
        let ex = VSExpr(doc.text, exprRange)
        guard let ti = ex.token(at: offset) else { return nil }
        let t = ex.tk[ti]
        let trange = NSRange(location: t.s, length: t.e - t.s)
        if t.kind == .str { return stringHit(doc, ex, ti, trange: trange, element: element, attrName: attrName) }
        guard t.kind == .ident, !keywords.contains(t.text) || (t.text == "emit" && false) else { return nil }
        if ex.isObjectKey(ti) { return nil }
        if ex.isMember(ti) { return memberHit(doc, ex, ti, trange: trange) }
        let name = t.text
        if let idx = ex.arrowParams[name] {
            return NPHit(range: trange, targets: [doc.target(doc.file, ex.tk[idx].s)], markdown: "```ts\n(parameter) \(name)\n```", kind: "variable")
        }
        let scopeEl = scopeElement
        let scope = scopeEl >= 0 ? doc.tpl.scope(of: scopeEl, ns: doc.text, includeOwnSlots: ownSlots) : []
        if let v = scope.last(where: { $0.name == name }) {
            if v.loc == t.s { return nil }
            return NPHit(range: trange, targets: [doc.target(doc.file, v.loc)], markdown: "```ts\n(\(v.kind)) \(name)\n```", kind: "variable")
        }
        if let d = doc.cur.decls.first(where: { $0.name == name && $0.kind != .imp }) ?? doc.cur.decl(name) {
            return declHit(doc, d, trange: trange)
        }
        if let pr = doc.cur.prop(name) {
            var md = "```ts\n(prop) \(pr.name)\(pr.required ? "" : "?")\(pr.type.isEmpty ? "" : ": " + pr.type)\n```"
            if !pr.doc.isEmpty { md += "\n\n" + pr.doc }
            return NPHit(range: trange, targets: [doc.target(doc.file, pr.loc)], markdown: md, kind: "prop")
        }
        return nil
    }

    static func declHit(_ doc: NVDoc, _ d: VSDecl, trange: NSRange) -> NPHit {
        let label: String
        switch d.kind {
        case .imp: label = "import"
        case .data: label = "data"
        case .computed: label = "computed"
        case .method: label = "method"
        case .setup: label = "setup()"
        default: label = "binding"
        }
        var md = "```ts\n\(d.detail.isEmpty ? d.name : d.detail)\n```\n\n_\(label)_"
        var targets = [doc.target(doc.file, d.loc)]
        var kind = "variable"
        if d.kind == .imp, NativeJS.handles(URL(fileURLWithPath: doc.file)),
           let hit = NativeJS.lookup(url: URL(fileURLWithPath: doc.file), text: doc.text, offset: d.loc), !hit.targets.isEmpty {
            // the imported symbol itself (other file) is the useful destination
            let other = hit.targets.filter { !($0.path == doc.file && NSLocationInRange($0.offset, NSRange(location: d.loc, length: d.len))) }
            if !other.isEmpty { targets = other; kind = hit.kind; if !hit.markdown.isEmpty { md = hit.markdown } }
        }
        return NPHit(range: trange, targets: targets, markdown: md, kind: kind)
    }

    static func memberHit(_ doc: NVDoc, _ ex: VSExpr, _ ti: Int, trange: NSRange) -> NPHit? {
        guard ti >= 2, ex.tk[ti - 2].kind == .ident else { return nil }
        let obj = ex.tk[ti - 2].text
        let name = ex.tk[ti].text
        if obj == "$refs" {
            for e in doc.tpl.elems {
                for a in e.attrs where a.name == "ref" || a.name == ":ref" {
                    if let v = a.value, doc.text.substring(with: v) == name {
                        return NPHit(range: trange, targets: [doc.target(doc.file, v.location)], markdown: "**\(name)** — template ref on `<\(e.name)>`", kind: "ref")
                    }
                }
            }
            return nil
        }
        let propsObj = obj == "$props" || (doc.cur.decl(obj).map { $0.initCall == "defineProps" || $0.initCall == "withDefaults" } ?? false)
        if propsObj, let pr = doc.cur.prop(name) {
            return NPHit(range: trange, targets: [doc.target(doc.file, pr.loc)], markdown: "```ts\n(prop) \(pr.name)\(pr.type.isEmpty ? "" : ": " + pr.type)\n```", kind: "prop")
        }
        return nil
    }

    static func stringHit(_ doc: NVDoc, _ ex: VSExpr, _ ti: Int, trange: NSRange, element: Int, attrName: String?) -> NPHit? {
        let t = ex.tk[ti]
        let inner = NSRange(location: t.s + 1, length: max(0, t.e - t.s - 2))
        // emit('event') / $emit('event')
        if ti >= 2, ex.tk[ti - 1].isP("("), ex.tk[ti - 2].kind == .ident, VSBuild.emitNames.contains(ex.tk[ti - 2].text) {
            if let em = doc.cur.emit(t.text) { return NPHit(range: inner, targets: [doc.target(doc.file, em.loc)], markdown: "**\(em.name)** — event declared by this component", kind: "event") }
            return nil
        }
        // route names / paths in `{ name: 'x' }` / `{ path: '/x' }`
        if ti >= 2, ex.tk[ti - 1].isP(":"), ex.tk[ti - 2].kind == .ident || ex.tk[ti - 2].kind == .str, ["name", "path"].contains(ex.tk[ti - 2].text),
           element >= 0, routerTags.contains(doc.tpl.elems[element].name.lowercased()) {
            let ts = ex.tk[ti - 2].text == "name" ? doc.p.routeTargets(path: nil, name: t.text) : doc.p.routeTargets(path: t.text, name: nil)
            if !ts.isEmpty { return NPHit(range: inner, targets: ts, markdown: "route `\(t.text)`", kind: "route") }
        }
        if element >= 0, routerTags.contains(doc.tpl.elems[element].name.lowercased()), attrName == ":to" || attrName == "v-bind:to", t.text.hasPrefix("/"), ti == 0 {
            let ts = doc.p.routeTargets(path: t.text, name: nil)
            if !ts.isEmpty { return NPHit(range: inner, targets: ts, markdown: "route `\(t.text)`", kind: "route") }
        }
        return assetHit(doc, t.text, range: inner)
    }
}
