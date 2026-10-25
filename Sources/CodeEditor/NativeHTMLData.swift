import Foundation

/// Static HTML knowledge: elements, attributes (global and per element), enumerated values, void / raw-text elements.
enum NWHtmlData {
    /// One element from the generated table (NativeWebDataGen.swift); `doc` and the attribute list are read from the literal on demand.
    struct Tag {
        let name: String
        let raw: Substring
        var doc: String { String(raw.split(separator: "\u{1}", maxSplits: 2, omittingEmptySubsequences: false).dropFirst().first ?? "") }
        var isVoid: Bool { NWHtmlData.voidTags.contains(name) }
        fileprivate var attrRecords: Substring { raw.split(separator: "\u{1}", maxSplits: 2, omittingEmptySubsequences: false).dropFirst(2).first ?? "" }
    }

    static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr", "param", "keygen"]
    static let rawTextTags: Set<String> = ["script", "style", "textarea", "title"]

    static let tags: [Tag] = NWWebDataGen.htmlTags.compactMap { line in
        guard let sep = line.firstIndex(of: "\u{1}") else { return nil }
        return Tag(name: String(line[line.startIndex..<sep]), raw: Substring(line))
    }
    static let tagMap: [String: Tag] = Dictionary(tags.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

    // MARK: attributes

    struct Attr { var name: String; var doc: String; var values: [String] }

    private static func parseAttr(_ rec: Substring) -> Attr? {
        let f = rec.split(separator: "\u{3}", maxSplits: 2, omittingEmptySubsequences: false)
        guard let n = f.first, !n.isEmpty else { return nil }
        var seen = Set<Substring>()
        let values = f.count > 2 ? f[2].split(separator: " ").filter { seen.insert($0).inserted }.map(String.init) : []
        return Attr(name: String(n), doc: f.count > 1 ? String(f[1]) : "", values: values)
    }

    static let globalAttrs: [Attr] = {
        var out = NWWebDataGen.htmlGlobalAttributes.compactMap { parseAttr(Substring($0)) }
        var have = Set(out.map(\.name))
        for extra in extraGlobals where !have.contains(extra.name) { out.append(extra); have.insert(extra.name) }
        if let i = out.firstIndex(where: { $0.name == "role" }), out[i].values.isEmpty { out[i].values = roleValues }
        return out
    }()

    private static let roleValues = "alert alertdialog application article banner button cell checkbox columnheader combobox complementary contentinfo definition dialog directory document feed figure form grid gridcell group heading img link list listbox listitem log main marquee math menu menubar menuitem menuitemcheckbox menuitemradio navigation none note option presentation progressbar radio radiogroup region row rowgroup rowheader scrollbar search searchbox separator slider spinbutton status switch tab table tablist tabpanel term textbox timer toolbar tooltip tree treegrid treeitem".split(separator: " ").map(String.init)
    private static let extraGlobals: [Attr] = [Attr(name: "id", doc: "Unique identifier of the element.", values: []), Attr(name: "class", doc: "Space separated list of the element's classes.", values: []),
                                               Attr(name: "style", doc: "Inline CSS declarations.", values: []), Attr(name: "title", doc: "Advisory information shown as a tooltip.", values: []),
                                               Attr(name: "inert", doc: "Makes the element and its subtree non-interactive.", values: []), Attr(name: "popover", doc: "Marks the element as a popover.", values: ["auto", "manual"]),
                                               Attr(name: "role", doc: "ARIA role.", values: []), Attr(name: "slot", doc: "Name of the slot the element is assigned to.", values: [])]

    static let eventHandlers: [String] = ["onclick", "ondblclick", "onchange", "oninput", "onsubmit", "onreset", "onfocus", "onblur", "onkeydown", "onkeyup", "onkeypress",
                                          "onmousedown", "onmouseup", "onmouseover", "onmouseout", "onmouseenter", "onmouseleave", "onmousemove", "onload", "onerror", "onscroll",
                                          "onresize", "oncontextmenu", "onwheel", "ondrag", "ondragstart", "ondragend", "ondragover", "ondrop", "ontouchstart", "ontouchend",
                                          "oncopy", "oncut", "onpaste", "onselect", "oninvalid", "ontoggle", "onanimationend", "ontransitionend", "onplay", "onpause", "onended"]

    static let ariaAttrs: [String] = ["aria-label", "aria-labelledby", "aria-describedby", "aria-hidden", "aria-expanded", "aria-controls", "aria-live", "aria-atomic", "aria-busy",
                                      "aria-checked", "aria-current", "aria-disabled", "aria-haspopup", "aria-invalid", "aria-modal", "aria-multiline", "aria-multiselectable",
                                      "aria-orientation", "aria-pressed", "aria-readonly", "aria-required", "aria-selected", "aria-sort", "aria-valuemax", "aria-valuemin",
                                      "aria-valuenow", "aria-valuetext", "aria-activedescendant", "aria-autocomplete", "aria-owns", "aria-placeholder", "aria-posinset",
                                      "aria-setsize", "aria-level", "aria-colcount", "aria-rowcount", "aria-errormessage", "aria-details", "aria-keyshortcuts", "aria-roledescription"]

    private static var attrCache: [String: [Attr]] = [:]
    private static let lock = NSLock()

    static func attrs(for tag: String) -> [Attr] {
        let t = tag.lowercased()
        lock.lock(); defer { lock.unlock() }
        if let c = attrCache[t] { return c }
        var parsed: [Attr] = []
        if let rec = tagMap[t]?.attrRecords { parsed = rec.split(separator: "\u{2}").compactMap { parseAttr($0) } }
        attrCache[t] = parsed
        return parsed
    }

    static func attr(_ name: String, tag: String) -> Attr? {
        let n = name.lowercased()
        return attrs(for: tag).first { $0.name.lowercased() == n } ?? globalAttrs.first { $0.name == n }
    }

    static func dropCaches() { lock.lock(); attrCache.removeAll(); lock.unlock() }

    // MARK: framework attribute names (offered only when the file kind makes them likely)

    static let vueAttrs: [(String, String)] = [("v-if", "Conditionally renders the element."), ("v-else-if", "Else-if branch of v-if."), ("v-else", "Else branch of v-if."),
                                               ("v-for", "Renders the element once per item."), ("v-model", "Two-way binding on a form input or component."),
                                               ("v-show", "Toggles the element's display."), ("v-bind", "Binds an attribute to an expression."), ("v-on", "Attaches an event listener."),
                                               ("v-html", "Sets the element's innerHTML."), ("v-text", "Sets the element's text."), ("v-slot", "Names a slot."),
                                               ("v-once", "Renders once."), ("v-pre", "Skips compilation."), ("v-cloak", "Hidden until compiled."), ("v-memo", "Memoizes a subtree."),
                                               (":class", "Binds the class attribute."), (":style", "Binds the style attribute."), (":key", "Special key for diffing."),
                                               ("@click", "Click listener."), ("@input", "Input listener."), ("@change", "Change listener."), ("@submit.prevent", "Submit listener that prevents the default."),
                                               ("ref", "Template ref."), ("key", "Special key for diffing.")]
    static let alpineAttrs: [String] = ["x-data", "x-show", "x-if", "x-for", "x-model", "x-text", "x-html", "x-bind", "x-on", "x-init", "x-ref", "x-cloak", "x-transition", "@click"]
    static let livewireAttrs: [String] = ["wire:click", "wire:model", "wire:model.live", "wire:submit", "wire:submit.prevent", "wire:loading", "wire:target", "wire:key", "wire:poll", "wire:init", "wire:navigate"]
}
