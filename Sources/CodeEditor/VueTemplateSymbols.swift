import Foundation

/// File Structure rows for a Vue template: component tags (nested under their parent component) and named slots (`#footer`).
/// Plain elements stay out; the list is capped so a huge template cannot flood the popup.
enum VueTemplateSymbols {
    private static let builtin: Set<String> = ["template", "slot", "transition", "transition-group", "keep-alive", "component", "teleport", "suspense", "router-view", "router-link"]
    static let maxSymbols = 300

    static func symbols(in text: String) -> [CodeSymbol] {
        let ns = text as NSString
        guard ns.length < 1_500_000,
              let tb = VSSFC.blocks(ns).first(where: { $0.tag == "template" && ($0.lang.isEmpty || $0.lang == "html") }) else { return [] }
        let tpl = VSTemplate.scan(ns, range: tb.content)
        let lines = NPLineStarts(ns)
        var out: [CodeSymbol] = []
        var owner = [Int: String]()          // element index -> nearest enclosing component (or slot) label
        for (i, e) in tpl.elems.enumerated() {
            let parentLabel = e.parent >= 0 ? owner[e.parent] : nil
            var label: String?
            if e.name.lowercased() == "template" {
                if let a = e.attrs.first(where: { $0.name.hasPrefix("#") || $0.name.hasPrefix("v-slot:") }) {
                    label = a.name.hasPrefix("#") ? a.name : "#" + a.name.dropFirst(7)
                }
            } else if !builtin.contains(e.name.lowercased()), NVProject.isComponentTag(e.name) {
                label = e.name
            }
            owner[i] = label ?? parentLabel
            guard let label, out.count < maxSymbols else { continue }
            out.append(CodeSymbol(name: label, kind: .component, line: lines.position(of: e.nameRange.location).line, container: parentLabel))
        }
        return out
    }
}
