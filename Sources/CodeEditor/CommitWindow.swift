import AppKit

/// PhpStorm-style Commit window (Cmd-K): the Git panel in its own centred window instead of a strip under the editor.
/// Esc closes it, and it closes itself after a plain commit. One per project window.
final class CommitWindowController: NSObject, NSWindowDelegate {
    private static var open: [ObjectIdentifier: CommitWindowController] = [:]

    let window: NSWindow
    let panel: GitPanelController
    private let key: ObjectIdentifier
    private var projectCloseObserver: NSObjectProtocol?

    static func existing(for project: ProjectWindow) -> CommitWindowController? { open[ObjectIdentifier(project)] }

    /// Shows (or raises) the commit window; `then` runs once the panel exists (used for Push / Update shortcuts).
    static func show(for project: ProjectWindow, then: ((GitPanelController) -> Void)? = nil) {
        if let existing = open[ObjectIdentifier(project)] { existing.present(); then?(existing.panel); return }
        guard let root = project.root else { return }
        GitRepo.repoRoot(for: root) { repo in
            guard let repo else {
                guard !AppEnv.headless else { return }
                let alert = NSAlert()
                alert.messageText = "This project is not a Git repository"
                alert.beginSheetModal(for: project.window)
                return
            }
            if let existing = open[ObjectIdentifier(project)] { existing.present(); then?(existing.panel); return }
            let controller = CommitWindowController(project: project, repo: repo)
            open[ObjectIdentifier(project)] = controller
            controller.present()
            then?(controller.panel)
        }
    }

    private init(project: ProjectWindow, repo: URL) {
        key = ObjectIdentifier(project)
        panel = GitPanelController(root: repo) { [weak project] url in
            project?.open(url)
            if !AppEnv.headless { project?.window.makeKeyAndOrderFront(nil) }
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 780),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Commit — " + (project.root?.lastPathComponent ?? repo.lastPathComponent)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 540)
        window.delegate = self
        window.tabbingMode = .disallowed
        panel.view.frame = NSRect(x: 0, y: 0, width: 1120, height: 780)
        panel.view.autoresizingMask = [.width, .height]
        window.contentView = panel.view
        if !AppEnv.headless {
            window.setFrameAutosaveName("CommitWindow")
            if !window.setFrameUsingName("CommitWindow") {
                let host = project.window.frame
                window.setFrameOrigin(NSPoint(x: host.midX - 560, y: host.midY - 390))
            }
        }
        panel.onRequestClose = { [weak self] in self?.window.performClose(nil) }
        panel.onCommitted = { [weak self] andPush in if !andPush { self?.window.close() } }
        projectCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: project.window,
                                                                      queue: .main) { [weak self] _ in self?.window.close() }
    }

    private func present() {
        if !AppEnv.headless { window.makeKeyAndOrderFront(nil) }
        panel.reload()
        DispatchQueue.main.async { [weak self] in self?.panel.focusCommitMessage() }
    }

    func windowWillClose(_ notification: Notification) {
        if let observer = projectCloseObserver { NotificationCenter.default.removeObserver(observer) }
        Self.open[key] = nil
        window.contentView = NSView()     // detach the panel so it and its repo state are released
    }
}

extension ProjectWindow {
    /// Cmd-K: the PhpStorm-style Commit window.
    func showCommitWindow(then: ((GitPanelController) -> Void)? = nil) { CommitWindowController.show(for: self, then: then) }
}
