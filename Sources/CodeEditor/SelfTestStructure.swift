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
    }
}
