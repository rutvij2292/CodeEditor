import AppKit

/// Headless verification hooks: CE_SNAPSHOT renders the window (and optionally a picker) to PNGs, then quits.
enum Verification {
    static func render(_ view: NSView, to path: String) {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    static func scheduleIfRequested(app: AppDelegate) {
        guard AppEnv.value("CE_SNAPSHOT") != nil else { return }
        let shot = AppEnv.value("CE_SNAPSHOT_PATH") ?? "/tmp/ce_snap.png"
        let picker = AppEnv.value("CE_PICKER")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let w = app.active else { return }
            if let m = AppEnv.value("CE_VIEWER") { ViewerSystem.decorate(w, mode: m) }
            switch picker {
            case "files": w.showGoToFile()
            case "recent": w.showRecentFiles()
            case "actions": w.showFindAction()
            case "everywhere": w.showSearchEverywhere()
            case "projects": app.showRecentProjects(nil)
            case "git": w.toggleGitPanel()
            case "terminal": w.showTerminal()
            case _ where BranchVerification.isBranchPicker(picker): BranchVerification.start(picker!, w)
            case "commit": w.showCommitWindow()
            case "pr-prompt", "pr-resolver", "pr-success": PRSnapshots.render(picker!, to: shot)
            case "problems": w.showToolPanel("problems")
            case "find":
                w.showToolPanel("find") { w.findPanel?.show(seed: AppEnv.value("CE_FIND_QUERY") ?? "function", replaceMode: AppEnv.value("CE_FIND_REPLACE") != nil) }
            case "term-right", "term-bottom", "term-max", "term-narrow": decorateTerminal(w, mode: picker!)
            case "bottom": decorateBottom(w)
            case "tabs": decorateTabs(w)
            case "completion":
                if let tv = w.current?.textView {
                    tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
                    tv.triggerCompletion(nil)
                }
            default: break
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + ((picker == "git" || BranchVerification.isBranchPicker(picker) || picker == "find" || picker == "problems" || picker == "commit") ? 3.5 : picker == "completion" ? 2.2 : 1.6)) {
            if let w = app.active?.window.contentView { render(w, to: shot) }
            if picker == "completion", let w = app.active, let tab = w.current {
                let popupPath = shot.replacingOccurrences(of: ".png", with: "_popup.png")
                CompletionPopup.shared.snapshot(to: popupPath)
                composeCompletion(window: w.window, tab: tab, baseShot: shot, popupShot: popupPath)
            }
            if picker == "commit", let w = app.active, let c = CommitWindowController.existing(for: w), let v = c.window.contentView {
                render(v, to: shot.replacingOccurrences(of: ".png", with: "_commit.png"))
            }
            if let p = picker, BranchVerification.isBranchPicker(p), let w = app.active { BranchVerification.finish(p, shot: shot, w) }
            if picker != nil, !BranchVerification.isBranchPicker(picker), !["git", "completion", "bottom", "tabs", "commit", "term-right", "term-bottom", "term-max", "term-narrow"].contains(picker!) { QuickPicker.snapshot(to: shot.replacingOccurrences(of: ".png", with: "_picker.png")) }
            fputs("snapshot done\n", stderr)
            NSApp.terminate(nil)
        }
    }

    /// CE_PICKER=term-right|term-bottom|term-max|term-narrow: the terminal docked beside / below the editor with a sample
    /// AI-CLI screen, a finished background tab (green dot) and the status bar toggle.
    private static func decorateTerminal(_ w: ProjectWindow, mode: String) {
        guard let term = w.terminalPanel else { return }
        w.window.setContentSize(NSSize(width: mode == "term-narrow" ? 820 : 1360, height: 820))
        if mode == "term-bottom" { Prefs.terminalDock = "bottom" }
        w.showTerminalPanel(focus: false)
        let e = "\u{1b}["
        term.feedSample("\(e)1m\(e)38;5;208m\u{2726} Claude Code\(e)0m  \(e)2mv2.1\(e)0m\r\n\(e)2m~/proj  main\(e)0m\r\n\r\n"
            + "\(e)36m>\(e)0m Refactor @app/Http/Controllers/UserController.php:12-40 to use a form request\r\n\r\n"
            + "\(e)32m\u{25CF}\(e)0m I'll extract validation into \(e)1mStoreUserRequest\(e)0m.\r\n"
            + "  \(e)32m+\(e)0m app/Http/Requests/StoreUserRequest.php\r\n"
            + "  \(e)33m~\(e)0m app/Http/Controllers/UserController.php\r\n\r\n"
            + "\(e)2m\u{2733} Working\u{2026} (12s \u{00B7} esc to interrupt)\(e)0m\r\n")
        TerminalPanelController.isUserLooking = { _ in false }
        term.newTab()
        term.simulateBell(tab: term.activeIndex)
        term.select(0)
        if mode == "term-max" { w.maximizeTerminal() }
        if mode == "term-narrow" { w.window.contentView?.layoutSubtreeIfNeeded(); w.reevaluateTerminalFit() }
        w.updateTerminalAttention()
    }

    /// CE_PICKER=bottom: the bottom panel with Git / Find / Problems tabs, a badge, and sample tool content.
    private static func decorateBottom(_ w: ProjectWindow) {
        func sample(_ lines: [String]) -> NSView {
            let label = NSTextField(wrappingLabelWithString: lines.joined(separator: "\n"))
            label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            label.textColor = Theme.foreground
            let host = NSView()
            label.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(label)
            NSLayoutConstraint.activate([label.topAnchor.constraint(equalTo: host.topAnchor, constant: 10),
                                         label.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12)])
            return host
        }
        w.registerToolPanel(id: "find", title: "Find", view: sample(["app/Http/UserController.php:12   return $user;", "resources/app.js:3   const user = 1"]))
        w.registerToolPanel(id: "problems", title: "Problems", view: sample(["app/Cache.php:4  Undefined variable $x"]))
        w.setToolPanelBadge("12", for: "problems")
        w.setToolPanelBadge("2", for: "find")
        w.showToolPanel("find")
    }

    /// CE_PICKER=tabs: many tabs with a dirty dot and VCS colours, plus the status bar's Git summary.
    private static func decorateTabs(_ w: ProjectWindow) {
        guard let root = w.root else { return }
        let files = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { !$0.hasDirectoryPath }.sorted { $0.path < $1.path }
        for url in files.prefix(AppEnv.value("CE_TABS").flatMap(Int.init) ?? 6) { w.open(url) }
        if let first = w.editors.values.first {
            first.textView.string += " "
            first.textView.didChangeText()
        }
        let rel = files.map { url -> String in
            let p = VCSKind.canonical(url.path), r = VCSKind.canonical(root.path)
            return p.hasPrefix(r + "/") ? String(p.dropFirst(r.count + 1)) : p
        }
        func change(_ i: Int, index: Character = " ", work: Character = "M", conflict: Bool = false, untracked: Bool = false) -> GitChange? {
            guard rel.indices.contains(i) else { return nil }
            return GitChange(path: rel[i], origPath: nil, index: index, work: work, isConflict: conflict, isUntracked: untracked, isStaged: false)
        }
        let changes = [change(0), change(1, work: " ", untracked: true), change(2, index: "A", work: " "), change(3, conflict: true)].compactMap { $0 }
        w.applyGitStatus(changes: changes, info: ("main", nil, 1, 0, false), repoRoot: root)
        w.tabs.select(w.tabs.entries[min(1, max(0, w.tabs.entries.count - 1))].id)
        for item in w.tree.menuItems(for: files.first) { fputs("tree menu: \(item.isSeparatorItem ? "-----" : item.title + (item.isEnabled ? "" : " (disabled)"))\n", stderr) }
    }

    /// Draws the popup snapshot onto the editor render just below the caret, like it appears on screen.
    private static func composeCompletion(window: NSWindow, tab: EditorTab, baseShot: String, popupShot: String) {
        guard let base = NSImage(contentsOfFile: baseShot), let popup = NSImage(contentsOfFile: popupShot),
              let content = window.contentView else { return }
        let length = (tab.textView.string as NSString).length
        let screen = tab.textView.firstRect(forCharacterRange: NSRange(location: length, length: 0), actualRange: nil)
        let caret = content.convert(window.convertFromScreen(screen), from: nil)
        let scale = base.size.width / content.bounds.width
        let margin: CGFloat = 6 * scale
        let pw = popup.size.width - margin * 2, ph = popup.size.height - margin * 2
        let x = caret.minX * scale - 4 * scale
        let y = caret.minY * scale - ph - 3 * scale        // below the caret line (AppKit origin is bottom-left)
        let out = NSImage(size: base.size)
        out.lockFocus()
        base.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
        popup.draw(in: NSRect(x: x, y: y, width: pw, height: ph),
                   from: NSRect(x: margin, y: margin, width: pw, height: ph), operation: .sourceOver, fraction: 1)
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: baseShot.replacingOccurrences(of: ".png", with: "_composite.png")))
    }
}
