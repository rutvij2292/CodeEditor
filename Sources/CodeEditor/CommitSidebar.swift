import AppKit

/// PhpStorm-style Commit tool window: Cmd-K swaps the Commit panel into the left sidebar slot in place of the file tree;
/// Cmd-K again (or Esc) swaps the tree back. The panel is built lazily on first use and nothing runs while it is hidden.
final class CommitSidebar {
    /// Tab id of the diff preview in the editor area (not a file: ignored by sessions and file-keyed lookups).
    static let diffTabID = "git-diff:preview"

    private weak var project: ProjectWindow?
    let container: NSView
    private let treeView: NSView
    private(set) var panel: GitPanelController?
    private(set) var isShowing = false
    private var wasCollapsed = false
    private weak var previousResponder: NSResponder?
    private var repoRoot: URL?
    /// File whose diff the preview tab shows (repo-relative); nil when there is no preview tab.
    private var previewPath: String?

    init(project: ProjectWindow, container: NSView, treeView: NSView) {
        self.project = project
        self.container = container
        self.treeView = treeView
    }

    /// Cmd-K: shows the panel; with the panel focused it hides; with it showing but unfocused (or the sidebar collapsed) it
    /// expands the sidebar and focuses the message box instead.
    func toggle(then: ((GitPanelController) -> Void)? = nil) {
        guard isShowing, let project, let panel else { show(then: then); return }
        let focusedInside = (project.window.firstResponder as? NSView)?.isDescendant(of: panel.view) == true
        if focusedInside, !project.termDock.sidebarItem.isCollapsed { hide(); return }
        if !project.isTerminalMaximized { project.termDock.sidebarItem.isCollapsed = false }
        panel.focusCommitMessage()
        project.toolStrip?.refresh()
    }

    /// Refreshes the panel after in-app git or file events (save, checkout); no-op while hidden, never polls.
    func reloadIfShowing() { if isShowing { panel?.reload() } }

    /// Resolves the repository (alerting when there is none), then shows the panel.
    func show(then: ((GitPanelController) -> Void)? = nil) {
        guard let project, let root = project.root else { return }
        if isShowing { panel?.reload(); panel?.focusCommitMessage(); if let panel { then?(panel) }; return }
        GitRepo.repoRoot(for: root) { [weak self, weak project] repo in
            guard let self, let project else { return }
            guard let repo else {
                guard !AppEnv.headless else { return }
                let alert = NSAlert()
                alert.messageText = "This project is not a Git repository"
                alert.beginSheetModal(for: project.window)
                return
            }
            self.show(repo: repo, then: then)
        }
    }

    /// Shows the panel for an already-resolved repository root.
    func show(repo: URL, then: ((GitPanelController) -> Void)? = nil) {
        guard let project, !project.isTerminalMaximized else { return }
        if panel == nil || repoRoot != repo { build(repo: repo, project: project) }
        guard let panel else { return }
        if !isShowing {
            previousResponder = project.window.firstResponder
            wasCollapsed = project.termDock.sidebarItem.isCollapsed
            project.termDock.sidebarItem.isCollapsed = false
            treeView.isHidden = true
            panel.view.isHidden = false
            isShowing = true
            project.toolStrip?.refresh()
        }
        panel.reload()
        DispatchQueue.main.async { [weak panel] in panel?.focusCommitMessage() }
        then?(panel)
    }

    /// Swaps the file tree back, restores the sidebar's collapsed state and returns focus to the editor.
    func hide(restoreFocus: Bool = true) {
        guard isShowing, let project else { return }
        isShowing = false
        panel?.view.isHidden = true
        treeView.isHidden = false
        if project.isTerminalMaximized {
            project.termDock.savedCollapse.sidebar = wasCollapsed      // the maximized layout owns the sidebar; restore it on un-maximize
        } else {
            project.termDock.sidebarItem.isCollapsed = wasCollapsed
        }
        if restoreFocus { project.focusEditor() }
        project.toolStrip?.refresh()
    }

    /// Opens (or re-titles and selects) the single diff preview tab for the file selected in the panel's tree.
    func showDiffTab() {
        guard let project, let panel, let path = panel.selectedPath else { return }
        previewPath = path
        project.showAuxiliaryTab(id: Self.diffTabID, title: Self.title(for: path), view: panel.diffHost)
    }

    func closeDiffTab() {
        previewPath = nil
        project?.closeAuxiliaryTab(Self.diffTabID)
    }

    private static func title(for path: String) -> String { (path as NSString).lastPathComponent + " (diff)" }

    /// After a refresh: close the preview when its file no longer has changes; follow the selection if the refresh moved it.
    private func syncDiffTab() {
        guard let path = previewPath, let panel, let project else { return }
        if !project.tabs.entries.contains(where: { $0.id == Self.diffTabID }) { previewPath = nil; return }   // closed by the user
        if !panel.hasDiff(for: path) { closeDiffTab(); return }
        if let selected = panel.selectedPath, selected != path {
            previewPath = selected
            project.tabs.setTitle(Self.title(for: selected), for: Self.diffTabID)
        }
    }

    private func build(repo: URL, project: ProjectWindow) {
        panel?.view.removeFromSuperview()
        repoRoot = repo
        let p = GitPanelController(root: repo, layout: .sidebar) { [weak project] url in project?.open(url) }
        p.onStatusChange = { [weak project] in project?.refreshGitStatus(); project?.tree.refresh() }
        p.onRequestClose = { [weak self] in self?.hide() }
        p.onFocusEditor = { [weak self] in self?.hide() }
        p.onShowBranches = { [weak project] in if let w = project?.window { project?.branches.showPopup(over: w) } }
        p.onCommitted = { [weak self] andPush in if !andPush { self?.hide() } }
        p.onPushed = { [weak self] in if self?.panel?.committedAndPushing == true { self?.hide() } }
        p.onShowDiff = { [weak self] in self?.showDiffTab() }
        p.onSummaryChange = { [weak self, weak project] summary in
            project?.setToolPanelBadge(summary.changes > 0 ? "\(summary.changes)" : nil, for: "git")
            self?.syncDiffTab()
        }
        p.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(p.view)
        NSLayoutConstraint.activate([
            p.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            p.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            p.view.topAnchor.constraint(equalTo: container.topAnchor),
            p.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        p.view.isHidden = true
        panel = p
    }
}

extension ProjectWindow {
    /// Cmd-K: the PhpStorm-style Commit panel in the left sidebar (a second Cmd-K swaps the file tree back).
    func toggleCommitPanel() { commitSidebar.toggle() }
    /// Shows the Commit panel (never hides it); `then` runs once it exists (Push / Update / Fetch entry points).
    func showCommitPanel(then: ((GitPanelController) -> Void)? = nil) { commitSidebar.show(then: then) }
}
