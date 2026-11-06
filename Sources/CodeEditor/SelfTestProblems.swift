import AppKit

/// CE_SELFTEST: Problems panel — grouping, Claude evaluation parsing/cache, project scan, tabs and detail pane.
enum SelfTestProblems {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("problems: " + name, ok()) }

    static func diag(_ sev: Int = 2, _ msg: String, line: Int = 1, source: String? = nil, code: String? = nil) -> FileProblems.Diagnostic {
        FileProblems.Diagnostic(severity: sev, message: msg, line: line, column: 1, endLine: line, endColumn: 2, source: source, code: code)
    }

    static func run(w: ProjectWindow) {
        runGrouping()
    }

    static func runGrouping() {
        let a = FileProblems(url: URL(fileURLWithPath: "/p/a.php"), diagnostics: [
            diag(2, "Unused import X", source: "PHP", code: "unused-import"),
            diag(1, "Undefined variable $x", line: 4, source: "intelephense", code: "P1008"),
            diag(2, "Unused import Y", line: 2, source: "PHP", code: "unused-import")])
        let b = FileProblems(url: URL(fileURLWithPath: "/p/b.js"), diagnostics: [
            diag(2, "Something odd happened here in this file for sure", source: nil, code: nil),
            diag(1, "Unexpected token", source: "JS", code: "syntax")])
        let g = ProblemGrouping.group([a, b])
        check("grouping: categories sorted", g.map { $0.category } == ["General", "JavaScript", "PHP"])
        let php = g.first { $0.category == "PHP" }
        check("grouping: PHP inspections sorted by name", php?.inspections.map { $0.name } == ["P1008", "unused-import"])
        check("grouping: items counted", php?.inspections.first { $0.name == "unused-import" }?.items.count == 2)
        check("grouping: general uses first 40 chars of message", g.first { $0.category == "General" }?.inspections.first?.name == String("Something odd happened here in this file for sure".prefix(40)))
        check("grouping: intelephense maps to PHP, JS to JavaScript", ProblemGrouping.category(for: diag(1, "x", source: "intelephense")) == "PHP" && ProblemGrouping.category(for: diag(1, "x", source: "JS")) == "JavaScript")
    }
}
