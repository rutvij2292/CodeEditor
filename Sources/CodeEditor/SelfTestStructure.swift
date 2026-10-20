import AppKit

/// CE_SELFTEST: the persistent Structure tool window (outline rows, lazy install, number key).
enum SelfTestStructure {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    static func run(w: ProjectWindow) {
        let php = """
        <?php
        namespace App;

        class Cart {
            public function add($x) { return 1; }
            public function total() { return 2; }
        }
        function helper() {}
        """
        let rows = StructurePanelController.extract(text: php, fileExtension: "php")
        let titles = rows.map(\.title)
        check("structure: php outline lists class, methods and function in source order",
              titles.contains("Cart") && titles.contains("add") && titles.contains("total") && titles.contains("helper")
              && titles.firstIndex(of: "Cart")! < titles.firstIndex(of: "add")!)
        check("structure: rows carry 1-based lines", rows.first { $0.title == "total" }?.line == 6)
        let md = StructurePanelController.extract(text: "# Title\n\ntext\n\n## Part\n", fileExtension: "md")
        check("structure: markdown headings", md.map(\.title).contains("Title") && md.map(\.title).contains("Part"))

        check("structure: nothing is built until the first use", !w.hasToolPanel("structure") && w.structurePanel == nil)
        w.toggleTool("structure")
        check("structure: Cmd-7 installs and shows the tool", w.hasToolPanel("structure") && w.isStructureVisible)
        w.toggleTool("structure")
        w.bottom.hide()
        w.focusEditor()

        // Reopen Closed Tab
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ce-reopen-\(getpid())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("reopen.txt")
        try? "one\ntwo\nthree\n".write(to: f, atomically: true, encoding: .utf8)
        w.open(f, line: 3)
        let id = f.standardizedFileURL.path
        check("reopen: file is open", w.editors[id] != nil)
        _ = w.close(id)
        check("reopen: closing removes the tab", w.editors[id] == nil)
        w.reopenClosedTab()
        check("reopen: Cmd-Shift-T brings the closed file back", w.editors[id] != nil)
        check("reopen: at the line it was closed on", w.editors[id]?.textView.lineAndColumn.line == 3)
        _ = w.close(id)
        try? FileManager.default.removeItem(at: f)
        w.reopenClosedTab()
        check("reopen: a file deleted meanwhile is skipped", w.editors[id] == nil)
    }
}
