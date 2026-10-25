import AppKit

/// HTML completion (tags, attributes, values, class / id lists, paths), hover and navigation (class -> CSS, id, href / src).
enum NWHtmlService {
    static let booleanAttrs: Set<String> = ["hidden", "disabled", "required", "readonly", "checked", "selected", "multiple", "autofocus", "async", "defer", "controls", "autoplay", "loop",
                                            "muted", "novalidate", "open", "inert", "itemscope", "nomodule", "playsinline", "reversed", "allowfullscreen", "default", "ismap", "formnovalidate",
                                            "popover", "contenteditable", "draggable", "spellcheck"]

    static func projectClasses(_ p: NWProject, limit: Int) -> [(name: String, detail: String)] { NWCssService.projectNames(p, ids: false, limit: limit) }

    // MARK: completion

    static func complete(_ p: NWProject, _ b: NWBuf, _ loc: NWHtml.Loc, caret: Int, url: URL, tw: NWTailwind?, manual: Bool) -> [CompletionItem] {
        switch loc.kind {
        case .tagName: return tagItems(b, loc, caret: caret, manual: manual)
        case .attrName: return attrNameItems(b, loc, caret: caret, url: url, manual: manual)
        case .attrValue: return attrValueItems(p, b, loc, caret: caret, url: url, tw: tw)
        default: return []
        }
    }

    private static func tagItems(_ b: NWBuf, _ loc: NWHtml.Loc, caret: Int, manual: Bool) -> [CompletionItem] {
        let start = loc.nameRange.location
        let range = NSRange(location: start, length: max(0, caret - start))
        let nextIsGT = caret < b.count && b[caret] == 62
        if loc.isClose {
            var items: [CompletionItem] = []
            var seen = Set<String>()
            for (i, name) in loc.stack.reversed().enumerated() where seen.insert(name).inserted {
                items.append(CI.make(name, .property, detail: "close", insert: nextIsGT ? name : name + ">", sort: String(format: "%03d", i), range: range))
            }
            return items
        }
        guard caret > start || manual else { return [] }
        var items: [CompletionItem] = []
        for t in NWHtmlData.tags {
            let insert: String
            if nextIsGT || t.isVoid { insert = t.name }
            else { insert = t.name + ">$0</" + t.name + ">" }
            items.append(CI.make(t.name, .property, detail: t.isVoid ? "void element" : "element", insert: insert, snippet: insert.contains("$"), sort: sortKey(t.name), doc: t.doc, range: range))
        }
        return items
    }

    private static func sortKey(_ name: String) -> String { ["div": "00", "span": "01", "a": "02", "p": "03", "img": "04", "ul": "05", "li": "06", "button": "07", "input": "08", "form": "09"][name] ?? "1" + name }

    private static func attrNameItems(_ b: NWBuf, _ loc: NWHtml.Loc, caret: Int, url: URL, manual: Bool) -> [CompletionItem] {
        var start = caret
        if loc.attrRange.length > 0, caret >= loc.attrRange.location, caret <= NSMaxRange(loc.attrRange) { start = loc.attrRange.location }
        else { while start > 0, !NWChar.isSpace(b[start - 1]), b[start - 1] != 60, b[start - 1] != 34, b[start - 1] != 39, b[start - 1] != 62 { start -= 1 } }
        let range = NSRange(location: start, length: max(0, caret - start))
        let prefix = b.str(start, caret)
        guard !prefix.isEmpty || manual || (caret > 0 && NWChar.isSpace(b[caret - 1])) else { return [] }
        let tag = loc.tag.lowercased()
        let nextIsEq = caret < b.count && b[caret] == 61
        var items: [CompletionItem] = []
        var seen = loc.existing
        let ext = url.pathExtension.lowercased()
        func add(_ name: String, doc: String, kind: String = "attribute", sort: String) {
            guard seen.insert(name.lowercased()).inserted else { return }
            let isBool = booleanAttrs.contains(name)
            let insert = nextIsEq || isBool ? name : name + "=\"$1\"$0"
            items.append(CI.make(name, .value, detail: kind, insert: insert, snippet: insert.contains("$"), sort: sort, doc: doc, range: range))
        }
        for a in NWHtmlData.attrs(for: tag) { add(a.name, doc: a.doc, kind: "<\(tag)>", sort: "0" + a.name) }
        for a in NWHtmlData.globalAttrs { add(a.name, doc: a.doc, kind: "global", sort: "1" + a.name) }
        if ext == "vue" || prefix.hasPrefix(":") || prefix.hasPrefix("v-") || prefix.hasPrefix("@") {
            for (n, d) in NWHtmlData.vueAttrs { add(n, doc: d, kind: "vue", sort: "2" + n) }
        }
        if prefix.hasPrefix("wire") || url.lastPathComponent.hasSuffix(".blade.php") { for n in NWHtmlData.livewireAttrs { add(n, doc: "Livewire directive.", kind: "livewire", sort: "3" + n) } }
        if prefix.hasPrefix("x-") || prefix.hasPrefix("@") || prefix.hasPrefix(":") { for n in NWHtmlData.alpineAttrs { add(n, doc: "Alpine.js directive.", kind: "alpine", sort: "3" + n) } }
        for n in NWHtmlData.eventHandlers { add(n, doc: "Event handler content attribute.", kind: "event", sort: "4" + n) }
        for n in NWHtmlData.ariaAttrs { add(n, doc: "WAI-ARIA attribute.", kind: "aria", sort: "5" + n) }
        if prefix.hasPrefix("data") { add("data-", doc: "Custom data attribute.", kind: "data", sort: "1data-") }
        return items
    }

    private static func attrValueItems(_ p: NWProject, _ b: NWBuf, _ loc: NWHtml.Loc, caret: Int, url: URL, tw: NWTailwind?) -> [CompletionItem] {
        guard let v = loc.valueRange else { return [] }
        let name = loc.attrName.lowercased()
        if NWService.isClassAttribute(name) {
            guard let site = NWService.htmlClassSite(b, loc: loc, offset: caret) else { return [] }
            return classItems(p, b, site: site, caret: caret, url: url, tw: tw)
        }
        if name == "style" {
            let pos = NWCss.position(b, from: v.location, caret: caret, lang: .css, declarationsOnly: true)
            return NWCssService.complete(p, b, pos, caret: caret, lang: .css, url: url, tw: tw, manual: true, from: v.location)
        }
        let tag = loc.tag.lowercased()
        // enumerated values
        if let attr = NWHtmlData.attr(name, tag: tag), !attr.values.isEmpty {
            let listy = ["rel", "sandbox", "role", "autocomplete", "sizes"].contains(name)
            var start = v.location
            if listy { start = caret; while start > v.location, !NWChar.isSpace(b[start - 1]) { start -= 1 } }
            let range = NSRange(location: start, length: max(0, caret - start))
            return attr.values.map { CI.make($0, .value, detail: attr.name, sort: $0, doc: attr.doc, range: range) }
        }
        if ["href", "src", "action", "poster", "data", "formaction", "srcset", "content"].contains(name) {
            return pathItems(p, b, v: v, caret: caret, url: url, name: name, tag: tag)
        }
        if name == "for" || name == "aria-labelledby" || name == "aria-describedby" || name == "aria-controls" || name == "headers" || name == "list" {
            let ids = documentIDs(b)
            var start = caret
            while start > v.location, !NWChar.isSpace(b[start - 1]) { start -= 1 }
            return ids.map { CI.make($0, .value, detail: "id", range: NSRange(location: start, length: caret - start)) }
        }
        return []
    }

    static func classItems(_ p: NWProject, _ b: NWBuf, site: NWClassSite, caret: Int, url: URL, tw: NWTailwind?) -> [CompletionItem] {
        var project = NWCssService.projectNames(p, ids: false, limit: 900, skipPath: url.path)
        // classes of this document's <style> blocks
        var own: [String] = []
        for r in NWHtml.styleBlocks(b) { own.append(contentsOf: NWCss.index(b, lang: .css, from: r.location, to: NSMaxRange(r)).sels.filter { !$0.isId }.map(\.name)) }
        var seen = Set<String>()
        own = own.filter { seen.insert($0).inserted }
        project.removeAll { seen.contains($0.name) }
        let ownItems = own.map { (name: $0, detail: "this file") }
        let extra = ownItems + project
        if let tw { return NWTailwindService.complete(tw, p, b, site: site, caret: caret, url: url, extraClasses: extra) }
        let ts = site.tokenRange.location
        let range = NSRange(location: ts, length: max(0, caret - ts))
        return extra.map { CI.make($0.name, .class, detail: $0.detail, sort: $0.detail == "this file" ? "0" + $0.name : "1" + $0.name, range: range) }
    }

    static func documentIDs(_ b: NWBuf) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        NWHtml.eachAttribute(b) { _, attr, _, value, _ in
            if attr.lowercased() == "id" { let s = b.str(value.location, NSMaxRange(value)); if !s.isEmpty, !s.contains("{"), seen.insert(s).inserted { out.append(s) } }
        }
        return out
    }

    private static func pathItems(_ p: NWProject, _ b: NWBuf, v: NSRange, caret: Int, url: URL, name: String, tag: String) -> [CompletionItem] {
        let typed = b.str(v.location, caret)
        if typed.hasPrefix("#") { return documentIDs(b).map { CI.make("#" + $0, .value, detail: "id", range: NSRange(location: v.location, length: caret - v.location)) } }
        if name == "content" || typed.contains("{{") || typed.contains("<?") || typed.hasPrefix("http") || typed.hasPrefix("mailto") || typed.hasPrefix("//") { return [] }
        let slash = typed.lastIndex(of: "/")
        let dirPart = slash.map { String(typed[typed.startIndex...$0]) } ?? ""
        let base = (url.path as NSString).deletingLastPathComponent
        var dirPath: String
        if dirPart.hasPrefix("/") {
            dirPath = LaravelFS.isDir(p.root + "/public" + dirPart) ? p.root + "/public" + dirPart : p.root + dirPart
        } else { dirPath = base + "/" + dirPart }
        dirPath = (dirPath as NSString).standardizingPath
        guard LaravelFS.isDir(dirPath) else { return [] }
        let fileStart = v.location + (dirPart as NSString).length
        let range = NSRange(location: fileStart, length: max(0, caret - fileStart))
        var items: [CompletionItem] = []
        for e in FastProject.readEntries(dirPath, fileSuffix: []).prefix(400) {
            if e.isDir { if NWProject.skipDirs.contains(e.name) { continue } ; items.append(CI.make(e.name + "/", .folder, detail: "folder", sort: "0" + e.name, range: range)) }
            else { items.append(CI.make(e.name, .file, detail: "file", sort: "1" + e.name, range: range)) }
        }
        if dirPart.isEmpty { items.append(CI.make("../", .folder, detail: "folder", sort: "~..", range: range)) }
        return items
    }

    // MARK: hover / definition

    static func lookup(_ p: NWProject, _ b: NWBuf, _ loc: NWHtml.Loc, offset: Int, url: URL, tw: NWTailwind?, usages: Bool = false) -> NPHit? {
        switch loc.kind {
        case .tagName:
            let r = loc.nameRange
            guard r.length > 0, let t = NWHtmlData.tagMap[loc.tag.lowercased()] else { return nil }
            var md = "**<\(t.name)>**\n\n\(t.doc)"
            let attrs = NWHtmlData.attrs(for: t.name).prefix(8).map { "`\($0.name)`" }
            if !attrs.isEmpty { md += "\n\nAttributes: " + attrs.joined(separator: " ") }
            return NPHit(range: r, targets: [], markdown: md, kind: "html-tag")
        case .attrName:
            let r = loc.attrRange
            guard r.length > 0 else { return nil }
            let name = loc.attrName
            if let a = NWHtmlData.attr(name, tag: loc.tag) {
                var md = "**\(a.name)**\n\n\(a.doc)"
                if !a.values.isEmpty { md += "\n\nValues: " + a.values.prefix(12).map { "`\($0)`" }.joined(separator: " ") }
                return NPHit(range: r, targets: [], markdown: md, kind: "html-attr")
            }
            let l = name.lowercased()
            if l.hasPrefix("data-") { return NPHit(range: r, targets: [], markdown: "**\(name)**\n\nCustom data attribute (`dataset.\(camel(String(l.dropFirst(5))))`).", kind: "html-attr") }
            if l.hasPrefix("aria-") { return NPHit(range: r, targets: [], markdown: "**\(name)**\n\nWAI-ARIA attribute.", kind: "html-attr") }
            if l.hasPrefix("on"), NWHtmlData.eventHandlers.contains(l) { return NPHit(range: r, targets: [], markdown: "**\(name)**\n\nEvent handler content attribute.", kind: "html-attr") }
            if let v = NWHtmlData.vueAttrs.first(where: { $0.0 == name }) { return NPHit(range: r, targets: [], markdown: "**\(v.0)**\n\n\(v.1)", kind: "html-attr") }
            return nil
        case .attrValue:
            guard let v = loc.valueRange else { return nil }
            let name = loc.attrName.lowercased()
            if NWService.isClassAttribute(name) {
                guard let site = NWService.htmlClassSite(b, loc: loc, offset: offset), site.tokenRange.length > 0 else { return nil }
                return classLookup(p, b, site: site, url: url, tw: tw, usages: usages)
            }
            if name == "id" {
                let id = b.str(v.location, NSMaxRange(v))
                guard !id.isEmpty, !id.contains("{") else { return nil }
                let defs = NWCssService.classDefinitions(p, name: id, b: nil, lang: .css, url: nil, from: 0, ids: true) + styleBlockTargets(b, url: url, name: id, ids: true)
                guard !defs.isEmpty else { return nil }
                return NPHit(range: v, targets: defs, markdown: "", kind: "html-id")
            }
            if ["href", "src", "action", "poster", "data", "formaction"].contains(name) {
                let ref = b.str(v.location, NSMaxRange(v))
                if ref.hasPrefix("#"), ref.count > 1 {
                    let id = String(ref.dropFirst())
                    var out: [NPTarget] = []
                    NWHtml.eachAttribute(b) { _, attr, _, value, _ in if attr.lowercased() == "id", b.str(value.location, NSMaxRange(value)) == id { out.append(NWNav.target(path: url.path, offset: value.location, text: b.ns)) } }
                    return out.isEmpty ? nil : NPHit(range: v, targets: out, markdown: "", kind: "html-anchor")
                }
                guard let path = NWNav.resolveFile(ref, from: (url.path as NSString).deletingLastPathComponent, root: p.root) else { return nil }
                return NPHit(range: v, targets: [NWNav.target(path: path, offset: 0)], markdown: "", kind: "html-file")
            }
            if name == "for" || name == "aria-labelledby" || name == "aria-describedby" || name == "aria-controls" {
                let id = b.str(v.location, NSMaxRange(v))
                var out: [NPTarget] = []
                NWHtml.eachAttribute(b) { _, attr, _, value, _ in if attr.lowercased() == "id", b.str(value.location, NSMaxRange(value)) == id { out.append(NWNav.target(path: url.path, offset: value.location, text: b.ns)) } }
                return out.isEmpty ? nil : NPHit(range: v, targets: out, markdown: "", kind: "html-id")
            }
            return nil
        default: return nil
        }
    }

    private static func camel(_ s: String) -> String {
        var out = "", up = false
        for ch in s { if ch == "-" { up = true } else { out.append(up ? Character(ch.uppercased()) : ch); up = false } }
        return out
    }

    private static func styleBlockTargets(_ b: NWBuf, url: URL, name: String, ids: Bool) -> [NPTarget] {
        var out: [NPTarget] = []
        for r in NWHtml.styleBlocks(b) {
            for s in NWCss.index(b, lang: .css, from: r.location, to: NSMaxRange(r)).sels where s.name == name && s.isId == ids { out.append(NWNav.target(path: url.path, offset: Int(s.offset), text: b.ns)) }
        }
        return out
    }

    private static func classLookup(_ p: NWProject, _ b: NWBuf, site: NWClassSite, url: URL, tw: NWTailwind?, usages: Bool) -> NPHit? {
        let r = site.tokenRange
        let token = b.str(r.location, NSMaxRange(r))
        var md = ""
        if let tw, let hit = NWTailwindService.lookup(tw, p, b, site: site, offset: r.location, url: url) { md = hit.markdown }
        if !usages, !md.isEmpty { return NPHit(range: r, targets: [], markdown: md, kind: "html-class") }      // hover on a Tailwind class: no project scan
        let name = token.split(separator: ":", omittingEmptySubsequences: false).last.map(String.init) ?? token
        var targets = styleBlockTargets(b, url: url, name: name, ids: false)
        targets += NWCssService.classDefinitions(p, name: name, b: nil, lang: .css, url: nil, from: 0)
        if !targets.isEmpty, md.isEmpty {
            let rules = NWCssService.selectorRules(p, name: name, isId: false, b: nil, lang: .css, url: nil, from: 0, limit: 3)
            md = rules.map { "```css\n\($0.text)\n```\n*\($0.file)*" }.joined(separator: "\n\n")
        }
        guard !md.isEmpty || !targets.isEmpty else { return nil }
        return NPHit(range: r, targets: targets, markdown: md, kind: "html-class")
    }
}
