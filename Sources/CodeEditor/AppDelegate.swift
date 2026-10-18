import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private(set) var windows: [ProjectWindow] = []
    private var keyMonitor: Any?
    private var shiftDown = false
    private var lastShiftUp: TimeInterval = 0

    var active: ProjectWindow? { windows.first { $0.window.isKeyWindow } ?? windows.last }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.start()
        CompletionSystem.start()
        CompletionSystem.symbolProvider = { [weak self] in self?.active?.symbolEntries ?? [] }
        LanguageServers.start()
        LanguageServers.openLocation = { [weak self] url, line, _ in self?.active?.open(url, line: line) }
        BracketColorizer.start()
        NSApp.mainMenu = MainMenu.build(app: self)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.trackDoubleShift(event)
            return event
        }

        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        for arg in args { openPath(URL(fileURLWithPath: arg)) }
        if windows.isEmpty {
            let w = newWindow()
            if !AppEnv.headless, !RecentProjects.all.isEmpty { DispatchQueue.main.async { self.showRecentProjects(nil) } }
            _ = w
        }
        Verification.scheduleIfRequested(app: self)
        SelfTest.run(app: self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windows.allSatisfy { $0.confirmCloseAll() } ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) { LanguageServers.stopAll() }

    func application(_ application: NSApplication, open urls: [URL]) { urls.forEach(openPath) }

    // MARK: Windows and projects

    @discardableResult
    func newWindow() -> ProjectWindow {
        let w = ProjectWindow()
        w.onClose = { [weak self] closed in self?.windows.removeAll { $0 === closed } }
        windows.append(w)
        if !AppEnv.headless {
            w.window.cascadeTopLeft(from: NSPoint(x: 40 + 28 * Double(windows.count % 8), y: 700 - 28 * Double(windows.count % 8)))
            w.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return w
    }

    /// A folder opens as a project; a file opens inside its project (nearest folder with .git, else its folder).
    func openPath(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
        if isDir.boolValue { openProject(url); return }
        let root = Self.projectRoot(for: url)
        let target = openProject(root)
        target.open(url)
    }

    static func projectRoot(for file: URL) -> URL {
        var dir = file.deletingLastPathComponent()
        while dir.path != "/" {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return file.deletingLastPathComponent()
    }

    @discardableResult
    func openProject(_ url: URL) -> ProjectWindow {
        let url = url.standardizedFileURL
        if let existing = windows.first(where: { $0.root == url }) {
            if !AppEnv.headless { existing.window.makeKeyAndOrderFront(nil) }
            return existing
        }
        let target = windows.first(where: { $0.root == nil }) ?? newWindow()
        target.openFolder(url)
        if !AppEnv.headless { target.window.makeKeyAndOrderFront(nil) }
        return target
    }

    // MARK: Double Shift (Search Everywhere)

    private func trackDoubleShift(_ event: NSEvent) {
        if event.type == .keyDown { shiftDown = false; lastShiftUp = 0; return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .shift {
            shiftDown = true
        } else if flags.isEmpty, shiftDown {
            shiftDown = false
            if event.timestamp - lastShiftUp < 0.35 { lastShiftUp = 0; searchEverywhere(nil) } else { lastShiftUp = event.timestamp }
        } else {
            shiftDown = false
        }
    }

    // MARK: Menu actions (forwarded to the active project window)

    @objc func openProjectPanel(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Project"
        if panel.runModal() == .OK, let url = panel.url { openProject(url) }
    }

    @objc func showRecentProjects(_ sender: Any?) {
        let host = active ?? newWindow()
        var items = RecentProjects.all.map { url in
            PickerItem(title: url.lastPathComponent, detail: (url.path as NSString).abbreviatingWithTildeInPath,
                       symbol: "folder.fill", key: url.path) { [weak self] in self?.openProject(url) }
        }
        items.append(PickerItem(title: "Open Folder…", detail: "Choose a project folder", symbol: "folder.badge.plus",
                                key: "open folder browse") { [weak self] in self?.openProjectPanel(nil) })
        QuickPicker.present(over: host.window, placeholder: "Open project…", items: items)
    }

    @objc func saveFile(_ sender: Any?) { active?.saveCurrent() }
    @objc func saveAll(_ sender: Any?) { active?.saveAll() }
    @objc func closeTab(_ sender: Any?) { active?.closeCurrentTab() }
    @objc func goToFile(_ sender: Any?) { active?.showGoToFile() }
    @objc func goToClass(_ sender: Any?) { active?.showGoToClass() }
    @objc func goToSymbol(_ sender: Any?) { active?.showGoToSymbol() }
    @objc func fileStructure(_ sender: Any?) { active?.showFileStructure() }
    @objc func recentFiles(_ sender: Any?) { active?.showRecentFiles() }
    @objc func searchEverywhere(_ sender: Any?) { active?.showSearchEverywhere() }
    @objc func findAction(_ sender: Any?) { active?.showFindAction() }
    @objc func goToLine(_ sender: Any?) { active?.goToLine() }
    @objc func goBack(_ sender: Any?) { active?.goBack() }
    @objc func goForward(_ sender: Any?) { active?.goForward() }
    @objc func previousTab(_ sender: Any?) { active?.selectTab(offset: -1) }
    @objc func nextTab(_ sender: Any?) { active?.selectTab(offset: 1) }
    @objc func focusTree(_ sender: Any?) { active?.focusTree() }
    @objc func toggleGit(_ sender: Any?) { active?.toggleGitPanel() }
    @objc func commitChanges(_ sender: Any?) { active?.showCommit() }
    @objc func pushChanges(_ sender: Any?) { active?.gitPush() }
    @objc func updateProject(_ sender: Any?) { active?.gitPull() }
    @objc func fetchChanges(_ sender: Any?) { active?.gitFetch() }
    @objc func selectOpenedFile(_ sender: Any?) { active?.selectOpenedFile() }
    @objc func collapseAll(_ sender: Any?) { active?.collapseTree() }
    @objc func themeSystem(_ sender: Any?) { Theme.setMode(.system) }
    @objc func themeLight(_ sender: Any?) { Theme.setMode(.light) }
    @objc func themeDark(_ sender: Any?) { Theme.setMode(.dark) }

    @objc private func openRecent(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String { openProject(URL(fileURLWithPath: path)) }
    }

    @objc private func clearRecent(_ sender: Any?) { RecentProjects.clear() }

    // MARK: NSMenuDelegate (Open Recent list, Appearance checkmarks)

    func menuNeedsUpdate(_ menu: NSMenu) {
        switch menu.title {
        case "Open Recent":
            menu.removeAllItems()
            for url in RecentProjects.all {
                let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = url.path
                menu.addItem(item)
            }
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            let clear = NSMenuItem(title: "Clear Menu", action: #selector(clearRecent(_:)), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        case "Appearance":
            for (item, mode) in zip(menu.items, [ThemeMode.system, .light, .dark]) { item.state = Theme.mode == mode ? .on : .off }
        default: break
        }
    }
}
