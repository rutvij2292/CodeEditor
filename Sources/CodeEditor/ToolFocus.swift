import AppKit

/// Cmd-1 file tree, Cmd-2 editor, Cmd-3 Claude Code; the other tool windows follow on Cmd-4...9.
/// One rule for every tool window (PhpStorm): its number key shows it AND moves focus into it; pressed again while focus is
/// inside it, the tool hides and focus returns to the editor. Escape = back to the editor (panel stays), Shift-Escape = hide
/// the tool and go back, F12 = jump to the last tool (or back), Shift-Cmd-F12 = hide / restore every tool window.
extension ProjectWindow {
    var isBottomFocused: Bool { bottom.contains(window.firstResponder) }

    func toggleTool(_ id: String) {
        guard root != nil else { return }
        if id == "terminal" { toggleTerminal(); return }
        if id == "structure" { installStructurePanel() }
        guard bottom.has(id) || id == "git" else { return }
        if bottom.isVisible, bottom.selectedID == id, isBottomFocused {
            bottom.hide()
            focusEditor()
            return
        }
        bottom.show(id) { [weak self] in self?.focusTool(id) }
    }

    /// Cmd-3: the Claude Code terminal tab, shown and focused (started on first use); pressed again inside it, hide and go back.
    func toggleClaude() {
        guard root != nil, let term = terminalPanel else { return }
        if isTerminalVisible, isTerminalFocused, term.isClaudeTabActive { hideTerminal(); focusEditor(); return }
        term.selectOrStartClaude()
        showTerminalPanel(focus: true)
    }

    /// Cmd-3: shows and focuses the terminal (its Claude tab when one is already running, otherwise whatever tab is selected; a plain shell
    /// when there is none) without launching an agent. Pressed again inside the terminal, hide it and go back to the editor.
    func focusTerminalTool() {
        guard root != nil, let term = terminalPanel else { return }
        if isTerminalVisible, isTerminalFocused { hideTerminal(); focusEditor(); return }
        term.selectClaudeIfRunning()
        showTerminalPanel(focus: true)
    }

    /// Moves focus to the tool's primary control: the commit message for Git, the query for Find, the terminal, else its first list.
    func focusTool(_ id: String) {
        switch id {
        case "git": focusGitTool()
        case "find": findPanel?.focusQuery()
        case "terminal": terminalPanel?.focusTerminal()
        default:
            let view = bottom.tools.first(where: { $0.id == id })?.view
            // An empty tool (no rows yet) still takes focus on the panel itself, so Escape / Shift-Escape work from it.
            window.makeFirstResponder(view.flatMap(ToolFocus.firstFocusable(in:)) ?? bottom.view)
        }
    }

    /// F12: from the editor go to the last tool window (showing it if hidden); from inside a tool go back to the editor.
    func jumpToLastTool() {
        if isBottomFocused { focusEditor(); return }
        guard let id = bottom.selectedID ?? bottom.tools.first?.id else { return }
        if id == "terminal" { showTerminalPanel(focus: true); return }
        bottom.show(id) { [weak self] in self?.focusTool(id) }
    }

    /// Shift-Cmd-F12: hide the sidebar and bottom panel; again to restore what was hidden.
    func toggleHideAllTools() {
        if let state = hiddenTools {
            hiddenTools = nil
            if state.sidebar, !isSidebarVisible { termDock.sidebarItem.animator().isCollapsed = false }
            if state.bottom, let id = bottom.selectedID { bottom.show(id) }
            return
        }
        let state = (sidebar: isSidebarVisible, bottom: bottom.isVisible)
        guard state.sidebar || state.bottom else { return }
        hiddenTools = state
        if state.bottom { bottom.hide() }
        if state.sidebar { termDock.sidebarItem.animator().isCollapsed = true }
        focusEditor()
    }
}

enum ToolFocus {
    /// First list (table / outline) in a tool's view that can take focus, else its first editable text field.
    static func firstFocusable(in root: NSView) -> NSView? {
        var field: NSView?
        var queue: [NSView] = [root]
        while !queue.isEmpty {
            let v = queue.removeFirst()
            if v.isHidden { continue }
            if v is NSTableView, v.acceptsFirstResponder { return v }
            if field == nil, let t = v as? NSTextField, t.isEditable, t.acceptsFirstResponder { field = t }
            queue.append(contentsOf: v.subviews)
        }
        return field
    }
}
