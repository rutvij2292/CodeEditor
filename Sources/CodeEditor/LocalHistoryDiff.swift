import AppKit

/// Local History: choosing a version opens a side-by-side diff (that version vs the current buffer) with a Restore button,
/// instead of replacing the buffer straight away.
extension ProjectWindow {
    func showRevisionDiff(_ revision: LocalHistory.Revision, in editor: EditorTab) {
        guard let old = LocalHistory.text(of: revision, encoding: editor.encoding) else { statusBar.flash("Could not read that version"); return }
        let current = editor.textView.string
        if old == current { statusBar.flash("That version is identical to the current text"); return }
        guard !AppEnv.headless else { return }

        let diff = SideBySideDiffView(frame: NSRect(x: 0, y: 44, width: 1100, height: 656))
        diff.autoresizingMask = [.width, .height]
        diff.show(old: old, new: current, oldTitle: LocalHistory.describe(revision), newTitle: "Current buffer",
                  fileExtension: editor.url.pathExtension)

        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 700))
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: 1100, height: 44))
        bar.autoresizingMask = [.width]
        let restore = NSButton(title: "Restore This Version", target: nil, action: nil)
        restore.bezelStyle = .rounded
        restore.bezelColor = .controlAccentColor
        restore.keyEquivalent = "\r"
        restore.keyEquivalentModifierMask = [.command]
        let close = NSButton(title: "Close", target: nil, action: nil)
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"
        let hint = NSTextField(labelWithString: "Restoring replaces the buffer; ⌘Z undoes it and nothing is saved until you save.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 14, y: 14, width: 560, height: 16)
        restore.frame = NSRect(x: 1100 - 14 - 150, y: 8, width: 150, height: 28)
        restore.autoresizingMask = [.minXMargin]
        close.frame = NSRect(x: 1100 - 14 - 150 - 8 - 80, y: 8, width: 80, height: 28)
        close.autoresizingMask = [.minXMargin]
        for v in [hint, restore, close] { bar.addSubview(v) }
        host.addSubview(diff)
        host.addSubview(bar)

        let win = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        win.isReleasedWhenClosed = false
        win.contentView = host
        DialogMemory.remember(win, as: "LocalHistoryDiff")
        win.title = "Local History – \(editor.url.lastPathComponent) – \(LocalHistory.describe(revision))"
        let actions = HistoryDiffActions(restore: { [weak self, weak editor, weak win] in
            win?.close()
            if let editor { self?.restoreRevision(revision, into: editor, confirm: false); self?.statusBar.flash("Restored — ⌘Z to undo") }
        }, close: { [weak win] in win?.close() })
        restore.target = actions; restore.action = #selector(HistoryDiffActions.doRestore)
        close.target = actions; close.action = #selector(HistoryDiffActions.doClose)
        objc_setAssociatedObject(win, &HistoryDiffActions.key, actions, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        diffWindows.append(win)
        win.center()
        win.makeKeyAndOrderFront(nil)
    }

    // MARK: Reopen closed tab

    /// Cmd-Shift-T: reopens the most recently closed file at the line it was closed on (files deleted since are skipped).
    func reopenClosedTab() {
        while let last = closedTabs.popLast() {
            guard FileManager.default.fileExists(atPath: last.url.path) else { continue }
            open(last.url, line: last.line)
            return
        }
        statusBar.flash("No closed tabs to reopen")
    }
}

private final class HistoryDiffActions: NSObject {
    static var key = 0
    let restore: () -> Void, close: () -> Void
    init(restore: @escaping () -> Void, close: @escaping () -> Void) { self.restore = restore; self.close = close }
    @objc func doRestore() { restore() }
    @objc func doClose() { close() }
}
