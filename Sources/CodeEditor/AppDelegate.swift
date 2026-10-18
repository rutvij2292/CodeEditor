import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private(set) var windows: [ProjectWindow] = []
    private var keyMonitor: Any?
    private var shiftDown = false
    private var lastShiftUp: TimeInterval = 0
    private weak var lastKeyWindow: ProjectWindow?
    /// Owns session restore (the reopen-windows list). Instances started with `--project`, or while another primary lives, don't.
    private var isPrimaryInstance = true

    // Handlers other features install (menu items call them with the active window; no-ops until set).
    static var nextProblemHandler: ((ProjectWindow) -> Void)?
    static var previousProblemHandler: ((ProjectWindow) -> Void)?
    static var findUsagesHandler: ((ProjectWindow) -> Void)?
    static var renameHandler: ((ProjectWindow) -> Void)?
    static var formatHandler: ((ProjectWindow) -> Void)?

    /// Terminal integration hooks (Edit/View menu items). The integrator connects the terminal package's APIs here;
    /// until set, Focus Terminal falls back to showing the terminal and the rest do nothing.
    struct TerminalHandlers {
        var sendFileReference: ((ProjectWindow) -> Void)?
        var sendSelectionReference: ((ProjectWindow) -> Void)?
        var sendSelectionText: ((ProjectWindow) -> Void)?
        var focus: ((ProjectWindow) -> Void)?
        var maximize: ((ProjectWindow) -> Void)?
    }
    static var terminalHandlers = TerminalHandlers()

    /// Boolean preferences behind the View/Git menu checkmarks (`NSMenuItem.representedObject` holds the key).
    static let preferenceToggles: [String: (get: () -> Bool, set: (Bool) -> Void)] = [
        "showBreadcrumbs": ({ Prefs.showBreadcrumbs }, { Prefs.showBreadcrumbs = $0 }),
        "inlineBlame": ({ Prefs.inlineBlame }, { Prefs.inlineBlame = $0 }),
        "showIndentGuides": ({ Prefs.showIndentGuides }, { Prefs.showIndentGuides = $0 }),
        "highlightCurrentLine": ({ Prefs.highlightCurrentLine }, { Prefs.highlightCurrentLine = $0 }),
        "showLineNumbers": ({ Prefs.showLineNumbers }, { Prefs.showLineNumbers = $0 }),
        "softWrap": ({ Prefs.softWrap }, { setSoftWrap($0) }),
    ]

    /// The project window menu commands act on: the key window, else the last project window that was key
    /// (a QuickPicker or other panel can be key while a command runs), else the newest window.
    var active: ProjectWindow? {
        windows.first { $0.window.isKeyWindow }
            ?? lastKeyWindow.flatMap { last in windows.first { $0 === last } }
            ?? windows.last
    }

    @objc private func windowDidBecomeKey(_ note: Notification) { noteKey(note.object as? NSWindow) }

    /// Remembers which project window was key last.
    func noteKey(_ window: NSWindow?) {
        if let project = windows.first(where: { $0.window === window }) { lastKeyWindow = project }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.start()
        applyCompletionPrefs()
        NotificationCenter.default.addObserver(forName: Prefs.didChange, object: nil, queue: .main) { [weak self] note in
            if let key = note.userInfo?["key"] as? String, key.hasPrefix("completion") { self?.applyCompletionPrefs() }
        }
        CompletionSystem.start()
        ViewerSystem.start()
        CompletionSystem.symbolProvider = { [weak self] in self?.active?.symbolEntries ?? [] }
        LanguageServers.start()
        LanguageServers.openLocation = { [weak self] url, line, _ in self?.active?.open(url, line: line) }
        PowerState.shared.start()
        BracketColorizer.start()
        GitGutter.start()
        Formatter.start()
        Self.terminalHandlers.sendFileReference = { $0.sendFileReference() }
        Self.terminalHandlers.sendSelectionReference = { $0.sendSelectionReference() }
        Self.terminalHandlers.sendSelectionText = { $0.sendSelectionText() }
        Self.terminalHandlers.focus = { $0.toggleTerminalFocus() }
        Self.terminalHandlers.maximize = { $0.maximizeTerminal() }
        BlameController.onShowCommit = { [weak self] _, url in self?.active?.showCommitWindow { $0.showHistory(for: url) } }
        LanguageServers.openProjectRoot = { [weak self] url in
            let path = url.standardizedFileURL.path
            return self?.windows.compactMap(\.root)
                .filter { path.hasPrefix($0.path + "/") }
                .max { $0.path.count < $1.path.count }
        }
        // Breadcrumb callbacks resolve their project window lazily (the tab isn't registered with a window yet when it opens).
        EditorEvents.onOpen { [weak self] tab in
            func owner() -> ProjectWindow? { self?.windows.first { $0.editors.values.contains { $0 === tab } } }
            tab.projectRoot = { owner()?.root }
            tab.onOpenURL = { url in owner()?.open(url) }
        }
        LaravelNavigator.start()
        LaravelNavigator.openLocation = { [weak self] url, line, column in
            guard let w = self?.active else { return }
            w.open(url, line: line)
            w.current?.textView.goToLine(line, column: column)
        }
        Self.installLanguageHandlers()
        // Laravel-aware targets (view(), route(), <x-…>) take precedence over the language server for Cmd-click / Cmd-B.
        LanguageServers.beforeDefinition = { tab, offset in
            guard !LaravelNavigator.targets(in: tab, at: offset).isEmpty else { return false }
            tab.textView.setSelectedRange(NSRange(location: offset, length: 0))
            return LaravelNavigator.goToDeclaration(in: tab, openLocation: { url, line, column in LaravelNavigator.openLocation?(url, line, column) },
                                                    over: tab.textView.window)
        }
        LanguageServers.suppressHoverUnderline = { tab, offset in !LaravelNavigator.targets(in: tab, at: offset).isEmpty }
        NSApp.mainMenu = MainMenu.build(app: self)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.trackDoubleShift(event)
            return event
        }

        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey(_:)),
                                               name: NSWindow.didBecomeKeyNotification, object: nil)

        installInstanceSupport()
        let launch = LaunchArguments.current
        isPrimaryInstance = !launch.isProjectLaunch && InstanceRegistry.claimPrimary()
        for url in launch.projects + launch.paths { openPath(url) }
        if launch.isProjectLaunch, windows.isEmpty, !AppEnv.headless, launch.projects.contains(where: { InstanceRegistry.owner(of: $0) != nil }) {
            NSApp.terminate(nil)      // the project is already open in another instance (which was just raised)
            return
        }
        if windows.isEmpty, isPrimaryInstance {
            SessionStore.windowsToReopen().filter { InstanceRegistry.owner(of: $0) == nil }.forEach { openProject($0) }
        }
        if windows.isEmpty {
            let w = newWindow()
            if !AppEnv.headless, !RecentProjects.all.isEmpty { DispatchQueue.main.async { self.showRecentProjects(nil) } }
            _ = w
        }
        Verification.scheduleIfRequested(app: self)
        SelfTest.run(app: self)
        Bench.run(app: self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windows.allSatisfy { $0.confirmCloseAll() } ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        TerminalPanelController.terminateAll()
        ClaudeBridge.removeAllLocksAtExit()
        windows.forEach { $0.saveSession() }
        if isPrimaryInstance { SessionStore.rememberOpenWindows(windows.compactMap(\.root)) }
        InstanceRegistry.releaseAll()
        InstanceRegistry.releasePrimary()
        LanguageServers.stopAll()
    }

    func application(_ application: NSApplication, open urls: [URL]) { urls.forEach(openPath) }

    // MARK: Windows and projects

    @discardableResult
    func newWindow() -> ProjectWindow {
        let w = ProjectWindow()
        w.onClose = { [weak self] closed in
            self?.windows.removeAll { $0 === closed }
            if let root = closed.root { InstanceRegistry.release(root) }
        }
        w.onOpenFolder = { [weak self] url in self?.openProjectRouted(url) }
        windows.append(w)
        lastKeyWindow = w
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
        if isDir.boolValue { openProjectRouted(url); return }
        let root = Self.projectRoot(for: url)
        if routeProject(root) { return }
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
        InstanceRegistry.claim(url)
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
        if panel.runModal() == .OK, let url = panel.url { openProjectRouted(url) }
    }

    @objc func showRecentProjects(_ sender: Any?) {
        let host = active ?? newWindow()
        var items = RecentProjects.all.map { url in
            PickerItem(title: url.lastPathComponent, detail: (url.path as NSString).abbreviatingWithTildeInPath,
                       symbol: "folder.fill", key: url.path) { [weak self] in self?.openProjectRouted(url) }
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
    @objc func showFileHistory(_ sender: Any?) { active?.showFileHistory() }
    @objc func showBranches(_ sender: Any?) { active?.showBranchPopup() }
    @objc func newBranch(_ sender: Any?) { active?.branches.newBranch(from: nil) }
    @objc func commitChanges(_ sender: Any?) { active?.showCommitWindow() }
    @objc func pushChanges(_ sender: Any?) { active?.showCommitWindow { $0.push() } }
    @objc func updateProject(_ sender: Any?) { active?.showCommitWindow { $0.pull() } }
    @objc func fetchChanges(_ sender: Any?) { active?.showCommitWindow { $0.fetch() } }
    @objc func selectOpenedFile(_ sender: Any?) { active?.selectOpenedFile() }
    @objc func collapseAll(_ sender: Any?) { active?.collapseTree() }
    @objc func showFindTool(_ sender: Any?) { active?.showToolPanel("find") }
    @objc func showProblemsTool(_ sender: Any?) { active?.showToolPanel("problems") }
    @objc func showGitTool(_ sender: Any?) { active?.showToolPanel("git") }
    @objc func showClaudeChangesTool(_ sender: Any?) { active?.showClaudeChanges() }
    @objc func findInFiles(_ sender: Any?) { active?.onFindInFiles?() }
    @objc func replaceInFiles(_ sender: Any?) { active?.onReplaceInFiles?() }
    @objc func nextProblem(_ sender: Any?) { active.map { Self.nextProblemHandler?($0) } }
    @objc func previousProblem(_ sender: Any?) { active.map { Self.previousProblemHandler?($0) } }
    @objc func findUsages(_ sender: Any?) { active.map { Self.findUsagesHandler?($0) } }
    @objc func renameSymbol(_ sender: Any?) { active.map { Self.renameHandler?($0) } }
    @objc func formatDocument(_ sender: Any?) { active.map { Self.formatHandler?($0) } }
    @objc func toggleReopenWindows(_ sender: Any?) { SessionStore.reopenOnLaunch.toggle() }
    @objc func focusBreadcrumbs(_ sender: Any?) { active?.current?.focusBreadcrumbs() }
    @objc func showTerminal(_ sender: Any?) { active?.toggleTerminal() }
    @objc func toggleBlameAnnotations(_ sender: Any?) { if let tab = active?.current { _ = BlameController.toggleAnnotate(for: tab) } }
    @objc func restartLanguageServers(_ sender: Any?) {
        if let root = active?.root { LanguageServers.restartAll(forRoot: root) }
    }
    @objc func toggleFormatOnSave(_ sender: Any?) { Formatter.formatOnSave.toggle() }
    @objc func toggleAutoSaveFocus(_ sender: Any?) { AutoSave.focusLossEnabled.toggle() }
    @objc func toggleAutoSaveTabSwitch(_ sender: Any?) { AutoSave.tabSwitchEnabled.toggle() }
    @objc func showLocalHistory(_ sender: Any?) { active?.showLocalHistory() }
    @objc func showSettings(_ sender: Any?) { SettingsWindowController.shared.show() }
    @objc func sendFileToTerminal(_ sender: Any?) { active.map { Self.terminalHandlers.sendFileReference?($0) } }
    @objc func sendSelectionReferenceToTerminal(_ sender: Any?) { active.map { Self.terminalHandlers.sendSelectionReference?($0) } }
    @objc func sendSelectionTextToTerminal(_ sender: Any?) { active.map { Self.terminalHandlers.sendSelectionText?($0) } }
    @objc func sendSelectionToClaude(_ sender: Any?) { active?.sendMentionToClaude() }
    @objc func focusTerminal(_ sender: Any?) {
        guard let w = active else { return }
        if let focus = Self.terminalHandlers.focus { focus(w) } else { w.showTerminal() }
    }
    @objc func maximizeTerminal(_ sender: Any?) { active.map { Self.terminalHandlers.maximize?($0) } }
    @objc func togglePreference(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let t = Self.preferenceToggles[key] else { return }
        t.set(!t.get())
    }

    /// Completion popup tuning lives in `Prefs`; `CompletionSystem` holds the live values.
    private func applyCompletionPrefs() {
        CompletionSystem.autoOpenMinChars = Prefs.completionMinChars
        CompletionSystem.debounce = TimeInterval(Prefs.completionDelayMs) / 1000
    }

    /// Cmd-Opt-L: the project's real formatter (Pint / Prettier / LSP); if none applies, the editor's safe re-indent.
    @objc func reformatCode(_ sender: Any?) {
        guard let tab = active?.current else { return }
        let fallback = { if !ViewerSystem.reformat(tab) { tab.textView.reformatCode(nil) } }
        let hasSelection = tab.textView.selectedRange().length > 0
        let finish: (Formatter.Result) -> Void = { result in
            switch result {
            case .unavailable, .failed: fallback()
            default: break
            }
        }
        if hasSelection { Formatter.formatSelection(tab, completion: finish) } else { Formatter.format(tab, completion: finish) }
    }

    @objc func toggleIncludeVendor(_ sender: Any?) {
        ProjectIndex.includeVendor.toggle()
        windows.forEach { $0.reindex() }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleReopenWindows(_:)): item.state = SessionStore.reopenOnLaunch ? .on : .off
        case #selector(toggleIncludeVendor(_:)): item.state = ProjectIndex.includeVendor ? .on : .off
        case #selector(toggleBlameAnnotations(_:)): item.state = active?.current.map { Blame.isAnnotating($0) } == true ? .on : .off
        case #selector(toggleFormatOnSave(_:)): item.state = Formatter.formatOnSave ? .on : .off
        case #selector(toggleAutoSaveFocus(_:)): item.state = AutoSave.focusLossEnabled ? .on : .off
        case #selector(toggleAutoSaveTabSwitch(_:)): item.state = AutoSave.tabSwitchEnabled ? .on : .off
        case #selector(togglePreference(_:)):
            if let key = item.representedObject as? String, let t = Self.preferenceToggles[key] { item.state = t.get() ? .on : .off }
        default: break
        }
        return true
    }

    @objc func themeSystem(_ sender: Any?) { Theme.setMode(.system) }
    @objc func themeLight(_ sender: Any?) { Theme.setMode(.light) }
    @objc func themeDark(_ sender: Any?) { Theme.setMode(.dark) }

    @objc private func openRecent(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String { openProjectRouted(URL(fileURLWithPath: path)) }
    }

    @objc private func openRecentInNewInstance(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String { openProjectInNewInstance(URL(fileURLWithPath: path)) }
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
                // Holding ⌥ swaps the row for its new-instance variant.
                let alt = NSMenuItem(title: url.lastPathComponent + " (New Instance)", action: #selector(openRecentInNewInstance(_:)), keyEquivalent: "")
                alt.target = self
                alt.representedObject = url.path
                alt.isAlternate = true
                alt.keyEquivalentModifierMask = [.option]
                menu.addItem(alt)
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

    /// Connects F2 / Shift-F2 / Alt-F7 / Shift-F6 / Format Document to the language-server features.
    private static func installLanguageHandlers() {
        func unavailable(_ window: ProjectWindow, _ title: String, _ detail: String) {
            guard !AppEnv.headless else { return }
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = detail
            alert.beginSheetModal(for: window.window)
        }
        nextProblemHandler = { w in if let tab = w.current, !LanguageServers.nextProblem(in: tab, forward: true) { NSSound.beep() } }
        previousProblemHandler = { w in if let tab = w.current, !LanguageServers.nextProblem(in: tab, forward: false) { NSSound.beep() } }
        findUsagesHandler = { w in
            guard let tab = w.current else { return }
            if !LanguageServers.findUsages(in: tab) { unavailable(w, "Find Usages isn’t available", "No language server is running for this file type yet.") }
        }
        renameHandler = { w in
            guard let tab = w.current else { return }
            if !LanguageServers.rename(in: tab, over: w.window) {
                unavailable(w, "Rename isn’t available", "The language server for this file doesn’t offer rename. Intelephense’s rename needs a premium licence.")
            }
        }
        formatHandler = { w in
            guard let tab = w.current else { return }
            Formatter.format(tab) { result in
                switch result {
                case .formatted, .unchanged: break
                case .unavailable(let reason): unavailable(w, "Format Document isn’t available", reason + "\nUse Reformat Code (⌥⌘L) to re-indent safely.")
                case .failed(let tool, let message): unavailable(w, "\(tool) could not format this file", message)
                }
            }
        }
    }
}
