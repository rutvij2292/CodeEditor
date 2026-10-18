import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
    let tree = FileTreeController()
    let tabs = TabHost()
    var editors: [String: EditorTab] = [:]
    var rootURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        tabs.onClose = { [weak self] id in self?.close(id) }
        let sidebarVC = NSViewController(); sidebarVC.view = tree.scrollView
        let contentVC = NSViewController(); contentVC.view = tabs
        let sidebarItem = NSSplitViewItem(viewController: sidebarVC)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 500
        sidebarItem.canCollapse = true
        let contentItem = NSSplitViewItem(viewController: contentVC)
        contentItem.minimumThickness = 300
        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(contentItem)
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1200, height: 800))
        DispatchQueue.main.async { split.splitView.setPosition(260, ofDividerAt: 0) }
        window.title = "CodeEditor"
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        // CE_SNAPSHOT runs headless for verification: no window shown, no focus stolen.
        let headless = ProcessInfo.processInfo.environment["CE_SNAPSHOT"] != nil
        if !headless {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        tree.onOpen = { [weak self] url in self?.open(url) }
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        for arg in args {
            let url = URL(fileURLWithPath: arg)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue { openFolder(url) } else {
                if rootURL == nil { openFolder(url.deletingLastPathComponent()) }
                open(url)
            }
        }
        if ProcessInfo.processInfo.environment["CE_SNAPSHOT"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                let v = window.contentView!
                let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/ce_snap.png"))
                fputs("snapshot done\n", stderr)
                NSApp.terminate(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func openFolder(_ url: URL) {
        rootURL = url
        window.title = url.lastPathComponent
        tree.setRoot(url)
    }

    func open(_ url: URL) {
        let id = url.path
        if editors[id] != nil { tabs.select(id); return }
        guard let editor = EditorTab(url: url) else { NSSound.beep(); return }
        editors[id] = editor
        editor.onDirtyChange = { [weak self, weak editor] in
            self?.tabs.setTitle((editor?.isDirty == true ? "● " : "") + url.lastPathComponent, for: id)
        }
        tabs.add(id: id, title: url.lastPathComponent, view: editor.view)
        window.makeFirstResponder(editor.textView)
    }

    var current: EditorTab? { tabs.selectedID.flatMap { editors[$0] } }

    func close(_ id: String) {
        tabs.remove(id)
        editors[id] = nil
    }

    @objc func openFolderPanel(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { openFolder(url) }
    }
    @objc func save(_ sender: Any?) { current?.save() }
    @objc func closeTab(_ sender: Any?) {
        guard let id = tabs.selectedID else { window.performClose(nil); return }
        close(id)
    }

    func buildMenu() {
        let main = NSMenu()
        func add(_ title: String, _ items: [(String, Selector?, String)]) {
            let top = NSMenuItem(); main.addItem(top)
            let menu = NSMenu(title: title); top.submenu = menu
            for (t, sel, key) in items {
                if t == "-" { menu.addItem(.separator()); continue }
                menu.addItem(NSMenuItem(title: t, action: sel, keyEquivalent: key))
            }
        }
        add("App", [("Quit CodeEditor", #selector(NSApplication.terminate(_:)), "q")])
        add("File", [("Open Folder…", #selector(openFolderPanel(_:)), "o"),
                     ("Save", #selector(save(_:)), "s"),
                     ("Close Tab", #selector(closeTab(_:)), "w")])
        add("Edit", [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"), ("-", nil, ""),
                     ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                     ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a"),
                     ("-", nil, ""), ("Find…", #selector(NSTextView.performFindPanelAction(_:)), "f")])
        // Find menu item needs tag 1 (showFindInterface) to open the find bar.
        main.item(at: 2)?.submenu?.items.last?.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(ProcessInfo.processInfo.environment["CE_SNAPSHOT"] != nil ? .prohibited : .regular)
app.run()
