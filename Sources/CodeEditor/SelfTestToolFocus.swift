import AppKit

/// CE_SELFTEST: tool-window number keys toggle + focus, Escape / Shift-Escape, tab cycling, hide-all, tooltips.
enum SelfTestToolFocus {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    private static func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    static func run(w: ProjectWindow) {
        guard w.bottom.has("find"), w.bottom.has("problems") else { check("tool focus: panels installed", false); return }
        w.focusEditor()

        w.toggleTool("problems")
        check("tool focus: number key shows the tool", w.bottom.isVisible && w.bottom.selectedID == "problems")
        w.focusTool("problems")                       // the real call focuses on the next run-loop turn
        check("tool focus: focus moves into the tool", w.isBottomFocused)
        w.toggleTool("problems")
        check("tool focus: pressed again inside, it hides and returns to the editor", !w.bottom.isVisible && !w.isBottomFocused)

        w.toggleTool("find")
        w.focusTool("find")
        check("tool focus: Find focuses its query field", w.isBottomFocused && w.window.firstResponder != nil)
        let hide = key(53, "\u{1b}", .shift)
        _ = w.bottom.view.performKeyEquivalent(with: hide)
        check("tool focus: Shift-Escape hides the panel and goes back to the editor", !w.bottom.isVisible && !w.isBottomFocused)

        w.toggleTool("find")
        w.focusEditor()
        w.toggleTool("find")
        check("tool focus: visible but unfocused tool takes focus instead of hiding", w.bottom.isVisible)

        let before = w.bottom.selectedID
        w.bottom.cycle(1)
        check("tool focus: cycling moves to another tab", w.bottom.selectedID != before)
        w.bottom.cycle(-1)
        check("tool focus: cycling back returns", w.bottom.selectedID == before)

        w.focusTool("find")
        _ = w.bottom.view.performKeyEquivalent(with: key(30, "}", [.command, .shift]))
        check("tool focus: Shift-Cmd-] inside the panel cycles tabs", w.bottom.selectedID != before)

        w.bottom.hide()
        w.toggleHideAllTools()
        check("tool focus: hide-all collapses what was open", !w.bottom.isVisible && (w.hiddenTools != nil || !w.isSidebarVisible))
        w.toggleHideAllTools()
        check("tool focus: hide-all again restores", w.hiddenTools == nil)

        check("tool focus: tab tooltips carry the shortcut", BottomPanel.shortcutHints["find"] == "⌘3" && BottomPanel.shortcutHints["git"] == "⌘9")
        w.bottom.hide()
        w.focusEditor()
    }
}
