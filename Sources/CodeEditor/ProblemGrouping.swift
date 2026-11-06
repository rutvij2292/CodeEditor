import Foundation

/// PhpStorm-style grouping for the Problems panel's "Inspections on Current File" tab: category, then inspection, then problems.
struct InspectionGroup {
    struct Inspection {
        let name: String
        let severity: Int                                           // most severe (lowest number) of its items
        var items: [(url: URL, d: FileProblems.Diagnostic)]
    }
    let category: String
    var inspections: [Inspection]
}

enum ProblemGrouping {
    static func category(for d: FileProblems.Diagnostic) -> String {
        guard let s = d.source, !s.isEmpty else { return "General" }
        switch s.lowercased() {
        case "php", "intelephense": return "PHP"
        case "js", "ts", "typescript", "javascript", "tsserver": return "JavaScript"
        case "python", "py": return "Python"
        case "css", "html", "vue", "tailwind", "tailwindcss": return "Web"
        default: return s.prefix(1).uppercased() + s.dropFirst()
        }
    }

    static func inspectionName(for d: FileProblems.Diagnostic) -> String {
        if let c = d.code, !c.isEmpty { return c }
        return String(d.message.replacingOccurrences(of: "\n", with: " ").prefix(40))
    }

    static func group(_ files: [FileProblems]) -> [InspectionGroup] {
        var table: [String: [String: [(url: URL, d: FileProblems.Diagnostic)]]] = [:]
        for f in files {
            for d in f.diagnostics { table[category(for: d), default: [:]][inspectionName(for: d), default: []].append((f.url, d)) }
        }
        return table.keys.sorted().map { cat in
            let ins = table[cat]!.keys.sorted().map { name -> InspectionGroup.Inspection in
                let items = table[cat]![name]!
                return .init(name: name, severity: items.map { $0.d.severity }.min() ?? 2, items: items)
            }
            return InspectionGroup(category: cat, inspections: ins)
        }
    }
}
