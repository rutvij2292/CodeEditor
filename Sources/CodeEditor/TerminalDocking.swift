import AppKit

/// Geometry rules for the right-docked terminal (pure, unit-tested).
enum TerminalDockMath {
    static let minTerminal: CGFloat = 320
    static let minEditor: CGFloat = 400
    static let divider: CGFloat = 1
    /// Default share of the editor area (window minus sidebar) the terminal gets.
    static let defaultShare: CGFloat = 0.42

    static func defaultWidth(total: CGFloat, sidebar: CGFloat) -> CGFloat {
        max(minTerminal, ((total - sidebar) * defaultShare).rounded())
    }

    /// Width left for the editor when the terminal is shown at `terminal` points.
    static func editorWidth(total: CGFloat, sidebar: CGFloat, terminal: CGFloat) -> CGFloat {
        total - sidebar - terminal - divider * 2
    }

    /// Auto-collapse when showing the terminal would leave the editor narrower than `minEditor`.
    static func fits(total: CGFloat, sidebar: CGFloat, terminal: CGFloat) -> Bool {
        editorWidth(total: total, sidebar: sidebar, terminal: terminal) >= minEditor
    }

    /// Keeps the terminal at least `minTerminal` wide and, when possible, leaves the editor `minEditor`.
    static func clamp(_ width: CGFloat, total: CGFloat, sidebar: CGFloat) -> CGFloat {
        let most = total - sidebar - minEditor - divider * 2
        return max(minTerminal, min(width, max(minTerminal, most)))
    }
}

/// Mutable dock state of one project window (kept out of ProjectWindow's stored properties).
final class TerminalDockState {
    let host = NSView()
    var sidebarItem: NSSplitViewItem!
    var contentItem: NSSplitViewItem!
    var terminalItem: NSSplitViewItem!
    var mainItem: NSSplitViewItem!       // the (tree | editor | terminal) split inside the root split
    /// Effective dock of this window: "right" | "bottom" (starts from Prefs, restored per project).
    var side = Prefs.terminalDock
    /// Last (or desired) width of the right dock; 0 = default share.
    var width: CGFloat = 0
    /// The terminal was collapsed because the window got too narrow; it comes back when there is room.
    var autoCollapsed = false
    var maximized = false
    var savedCollapse: (sidebar: Bool, content: Bool, main: Bool) = (false, false, false)
}

extension ProjectWindow {
    // MARK: State

    var terminalDockSide: String { termDock.side }
    var isTerminalMaximized: Bool { termDock.maximized }
    var isTerminalAutoCollapsed: Bool { termDock.autoCollapsed }

    /// Is the terminal on screen (right dock expanded, or the bottom panel showing its Terminal tab)?
    var isTerminalVisible: Bool {
        termDock.side == "bottom" ? (bottom.isVisible && bottom.selectedID == "terminal") : !termDock.terminalItem.isCollapsed
    }

    /// Width of the right dock now (or the width it will reopen at).
    var terminalDockWidth: CGFloat {
        if termDock.side == "right", !termDock.terminalItem.isCollapsed, termDock.host.frame.width > 100 { return termDock.host.frame.width }
        return termDock.width
    }

    var isTerminalFocused: Bool {
        guard let term = terminalPanel, let v = window.firstResponder as? NSView else { return false }
        return v.isDescendant(of: term.view)
    }

    private var sidebarWidth: CGFloat {
        termDock.sidebarItem.isCollapsed ? 0 : termDock.sidebarItem.viewController.view.frame.width
    }

    // MARK: Show / hide / toggle (Option-F12, Ctrl-`, status bar button)

    /// Option-F12: shows the terminal if hidden (starting a shell lazily) and focuses it, otherwise hides it.
    func toggleTerminal() {
        if isTerminalVisible { hideTerminal() } else { showTerminalPanel(focus: true) }
    }

    /// Ctrl-`: focus the terminal (showing it if needed); if it already has focus, go back to the editor.
    func toggleTerminalFocus() {
        if isTerminalVisible, isTerminalFocused { focusEditor() } else { showTerminalPanel(focus: true) }
    }

    /// Kept for existing callers (menu item "Terminal", CE_PICKER=terminal): show + focus.
    func showTerminal() { showTerminalPanel(focus: true) }

    func focusTerminal() { showTerminalPanel(focus: true) }

    func showTerminalPanel(focus: Bool) {
        guard let term = terminalPanel else { return }
        setToolPanelBadge(nil, for: "terminal")
        if termDock.side == "bottom" {
            bottom.show("terminal") { [weak term] in
                term?.startIfNeeded()
                if focus { term?.focusTerminal() }
            }
        } else {
            attachTerminalToRightHost()
            termDock.autoCollapsed = false
            if termDock.terminalItem.isCollapsed {
                if termDock.width < TerminalDockMath.minTerminal {
                    termDock.width = TerminalDockMath.defaultWidth(total: mainSplit.splitView.bounds.width, sidebar: sidebarWidth)
                }
                setTerminalCollapsed(false)
                applyTerminalWidth()
            }
            term.startIfNeeded()
            if focus { term.focusTerminal() }
        }
        updateTerminalAttention()
        scheduleSessionSave()
    }

    func hideTerminal() {
        guard terminalPanel != nil else { return }
        let hadFocus = isTerminalFocused
        if termDock.maximized { setTerminalMaximized(false) }
        termDock.autoCollapsed = false
        if termDock.side == "bottom" {
            if bottom.isVisible, bottom.selectedID == "terminal" { bottom.hide() }
        } else if !termDock.terminalItem.isCollapsed {
            if termDock.host.frame.width > 100 { termDock.width = termDock.host.frame.width }
            setTerminalCollapsed(true)
        }
        if hadFocus { focusEditor() }
        scheduleSessionSave()
    }

    /// Fills the window (width for the right dock, height for the bottom dock) with the terminal; call again to restore.
    func maximizeTerminal() { setTerminalMaximized(!termDock.maximized) }

    func setTerminalMaximized(_ on: Bool) {
        guard on != termDock.maximized else { return }
        if on {
            if !isTerminalVisible { showTerminalPanel(focus: false) }
            guard isTerminalVisible else { return }
            let d = termDock
            if d.side == "right" {
                if d.host.frame.width > 100 { d.width = d.host.frame.width }
                d.savedCollapse = (d.sidebarItem.isCollapsed, d.contentItem.isCollapsed, false)
                collapse(d.sidebarItem, true); collapse(d.contentItem, true)
            } else {
                d.savedCollapse = (false, false, d.mainItem.isCollapsed)
                collapse(d.mainItem, true)
            }
            d.maximized = true
            terminalPanel?.focusTerminal()
        } else {
            let d = termDock
            d.maximized = false
            if d.side == "right" {
                collapse(d.sidebarItem, d.savedCollapse.sidebar); collapse(d.contentItem, d.savedCollapse.content)
                applyTerminalWidth()
            } else {
                collapse(d.mainItem, d.savedCollapse.main)
                let total = rootSplit.splitView.bounds.height
                rootSplit.splitView.setPosition(max(total * 0.3, total - bottom.height), ofDividerAt: 0)
            }
        }
    }

    // MARK: Docking

    /// Moves the SAME controller/view (and its shell sessions) to the dock `Prefs.terminalDock` names; no process restarts.
    func applyTerminalDock(to side: String? = nil) {
        guard let term = terminalPanel else { return }
        let want = side ?? Prefs.terminalDock
        guard want != termDock.side else { return }
        let wasVisible = isTerminalVisible || termDock.autoCollapsed
        let hadFocus = isTerminalFocused
        if termDock.maximized { setTerminalMaximized(false) }
        if termDock.side == "right" {
            if termDock.host.frame.width > 100 { termDock.width = termDock.host.frame.width }
            termDock.autoCollapsed = false
            setTerminalCollapsed(true, animated: false)
        } else {
            if bottom.isVisible, bottom.selectedID == "terminal" { bottom.hide() }
            bottom.unregister("terminal")
        }
        term.view.removeFromSuperview()
        termDock.side = want
        if want == "bottom" { registerBottomTerminal() }
        if wasVisible { showTerminalPanel(focus: hadFocus) }
        scheduleSessionSave()
    }

    func registerBottomTerminal() {
        guard let term = terminalPanel, !bottom.has("terminal") else { return }
        bottom.register(id: "terminal", title: "Terminal", view: term.view)
    }

    private func attachTerminalToRightHost() {
        guard let term = terminalPanel else { return }
        let host = termDock.host
        guard term.view.superview !== host else { return }
        term.view.removeFromSuperview()
        term.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(term.view)
        NSLayoutConstraint.activate([
            term.view.topAnchor.constraint(equalTo: host.topAnchor), term.view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            term.view.leadingAnchor.constraint(equalTo: host.leadingAnchor), term.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
    }

    private func collapse(_ item: NSSplitViewItem, _ collapsed: Bool, animated: Bool = false) {
        guard item.isCollapsed != collapsed else { return }
        if AppEnv.headless || !animated { item.isCollapsed = collapsed } else { item.animator().isCollapsed = collapsed }
    }

    private func setTerminalCollapsed(_ collapsed: Bool, animated: Bool = true) {
        collapse(termDock.terminalItem, collapsed, animated: animated)
    }

    /// Sets the right dock to `termDock.width` (clamped so the editor keeps room when it can).
    func applyTerminalWidth() {
        let split = mainSplit.splitView
        window.contentView?.layoutSubtreeIfNeeded()
        let total = split.bounds.width
        guard total > 0, !termDock.terminalItem.isCollapsed else { return }
        let w = TerminalDockMath.clamp(termDock.width, total: total, sidebar: sidebarWidth)
        split.setPosition(total - w - split.dividerThickness, ofDividerAt: 1)
    }

    // MARK: Window resize

    /// Terminal keeps its width, the editor flexes; when the editor would drop below 400 pt the terminal folds away and
    /// returns once there is room again.
    func windowDidResize(_ notification: Notification) {
        reevaluateTerminalFit()
    }

    func reevaluateTerminalFit() {
        let d = termDock
        guard d.side == "right", !d.maximized, terminalPanel != nil else { return }
        let total = mainSplit.splitView.bounds.width
        guard total > 0 else { return }
        // The DESIRED width decides (a window shrink squeezes the live width, which must not become the new preference).
        let width = d.width >= TerminalDockMath.minTerminal ? d.width : d.host.frame.width
        let fits = TerminalDockMath.fits(total: total, sidebar: sidebarWidth, terminal: max(width, TerminalDockMath.minTerminal))
        if !d.terminalItem.isCollapsed, !fits {
            let hadFocus = isTerminalFocused
            d.autoCollapsed = true
            setTerminalCollapsed(true, animated: false)
            if hadFocus { focusEditor() }
        } else if d.autoCollapsed, d.terminalItem.isCollapsed, fits {
            d.autoCollapsed = false
            setTerminalCollapsed(false, animated: false)
            applyTerminalWidth()
        }
    }

    /// Divider drags (mouse down, not a window resize) update the preferred width; window resizes never do.
    @objc func terminalSplitDidResize(_ note: Notification) {
        let d = termDock
        guard d.side == "right", !d.maximized, !d.terminalItem.isCollapsed, !window.inLiveResize,
              NSEvent.pressedMouseButtons & 1 != 0, d.host.frame.width >= TerminalDockMath.minTerminal else { return }
        d.width = d.host.frame.width
        scheduleSessionSave()
    }

    // MARK: Attention (status bar dot, bottom tab badge)

    func updateTerminalAttention() {
        let a = terminalPanel?.attention ?? .none
        statusBar.setTerminal(attention: a)
        setToolPanelBadge(a == .done ? "\u{2713}" : (a == .activity ? "\u{2022}" : nil), for: "terminal")
    }

    // MARK: Prefs

    @objc func terminalPrefsChanged(_ note: Notification) {
        guard (note.userInfo?["key"] as? String) == "terminalDock" else { return }
        applyTerminalDock()
    }

    // MARK: Session

    func captureTerminalState() -> Session.TerminalState {
        let visible = termDock.autoCollapsed || isTerminalVisible
        return .init(dock: termDock.side, width: Double(terminalDockWidth), visible: visible)
    }

    func restoreTerminalState(_ state: Session.TerminalState?) {
        guard let state, terminalPanel != nil else { return }
        applyTerminalDock(to: state.dock == "bottom" ? "bottom" : "right")
        if state.width >= Double(TerminalDockMath.minTerminal) { termDock.width = CGFloat(state.width) }
        if state.visible { showTerminalPanel(focus: false) } else if isTerminalVisible { hideTerminal() }
    }
}
