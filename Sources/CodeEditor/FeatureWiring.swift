import AppKit

/// Connects independently built features (Find in Files, ...) to a project window's tool panel and menu actions.
extension ProjectWindow {
    func installFeaturePanels() {
        guard let root, !hasToolPanel("find") else { return }
        let find = FindPanelController(
            root: root,
            files: { [weak self] in self?.projectFiles ?? [] },
            openFile: { [weak self] url, line, column in self?.open(url, line: line); self?.current?.textView.goToLine(line, column: column) },
            openBuffer: { [weak self] url in self?.editors[url.standardizedFileURL.path] })
        find.openMatch = { [weak self] match in
            self?.open(match.url, line: match.line)
            self?.current?.textView.goToLine(match.line, column: match.column)
        }
        findPanel = find
        registerToolPanel(id: "find", title: "Find", view: find.view) { close in find.onClose = close }
        onFindInFiles = { [weak self] in self?.showFind(replace: false) }
        onReplaceInFiles = { [weak self] in self?.showFind(replace: true) }
    }

    /// Cmd-Shift-F / Cmd-Shift-R: opens the Find panel seeded with the current single-line selection.
    func showFind(replace: Bool) {
        guard let find = findPanel else { return }
        var seed: String?
        if let tv = current?.textView, tv.selectedRange().length > 0 {
            let text = (tv.string as NSString).substring(with: tv.selectedRange())
            if !text.contains("\n"), text.count <= 200 { seed = text }
        }
        showToolPanel("find") { find.show(seed: seed, replaceMode: replace) }
    }
}
