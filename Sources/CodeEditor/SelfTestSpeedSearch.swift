import AppKit

/// CE_SELFTEST: speed search in the file tree (type to jump among loaded rows, step through matches, hand off to Go to File).
enum SelfTestSpeedSearch {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    static func run(w: ProjectWindow) {
        let tree = w.tree, outline = tree.outline
        func name(_ row: Int) -> String { (outline.item(atRow: row) as? FileNode)?.url.lastPathComponent ?? "" }
        guard outline.numberOfRows >= 2 else { check("speed search: tree has rows", false); return }
        let target = (0..<outline.numberOfRows).map(name).first { $0.count >= 3 } ?? name(0)
        let probe = String(target.prefix(3))

        check("speed search: plain letters seed a search", SpeedSearch.seed(from: key("a", [])) == "a")
        check("speed search: Command shortcuts do not", SpeedSearch.seed(from: key("n", .command)) == nil)
        check("speed search: arrows / space / return do not",
              SpeedSearch.seed(from: key("\u{F700}", [])) == nil && SpeedSearch.seed(from: key(" ", [])) == nil
              && SpeedSearch.seed(from: key("\r", [])) == nil)

        var widened: String?
        tree.onSearchEverywhere = { widened = $0 }
        w.window.makeFirstResponder(outline)
        tree.speed.testBegin(String(probe.prefix(1)))
        check("speed search: first key opens the field", tree.speed.isActive)
        tree.speed.testType(probe)
        check("speed search: selects a matching row", outline.selectedRow >= 0 && name(outline.selectedRow).lowercased().contains(probe.lowercased().prefix(1)))
        check("speed search: match letters are reported for highlighting", !tree.speed.matchedIndices(in: target).isEmpty)
        let before = outline.selectedRow
        tree.speed.testStep(1)
        check("speed search: stepping stays on a match", tree.speed.matches.contains(outline.selectedRow))
        if tree.speed.matches.count == 1 { check("speed search: single match keeps selection", outline.selectedRow == before) }

        tree.speed.testType("zzzqqq")
        check("speed search: no match is reported", tree.speed.matches.isEmpty)
        tree.speed.end()
        check("speed search: Escape closes and refocuses the list", !tree.speed.isActive && w.window.firstResponder === outline)
        check("speed search: highlight cleared after end", tree.speed.matchedIndices(in: target).isEmpty)
        _ = widened
        tree.onSearchEverywhere = { [weak w] q in w?.showGoToFile(initialQuery: q) }
    }

    private static func key(_ chars: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0)!
    }
}
