import AppKit

/// Headless checks for the window/project integration package (bottom panel, sessions, file operations, tabs, ...).
extension SelfTest {
    private static func write(_ text: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    private static func change(_ path: String, index: Character = " ", work: Character = "M",
                               conflict: Bool = false, untracked: Bool = false) -> GitChange {
        GitChange(path: path, origPath: nil, index: index, work: work, isConflict: conflict, isUntracked: untracked, isStaged: false)
    }

    static func projectChecks(app: AppDelegate, w: ProjectWindow, dir: URL, done: @escaping () -> Void) {
        let fm = FileManager.default
        let savedVendor = ProjectIndex.includeVendor
        ProjectIndex.includeVendor = false
        bottomPanelChecks(w: w)
        fileOperationChecks(w: w, dir: dir)
        tabChecks(w: w, dir: dir)
        bannerChecks(w: w, dir: dir)
        encodingChecks(w: w, dir: dir)
        integrityChecks(w: w, dir: dir)
        statusChecks(w: w, dir: dir)
        menuChecks(app: app, w: w)
        miscChecks(app: app, w: w)

        // Session round trip needs two windows over a temp project.
        sessionChecks(app: app, dir: dir)

        // Skip rules + index, then FS-burst coalescing (async).
        let skipDir = dir.appendingPathComponent("skipcheck")
        for rel in ["src/ok.php", "vendor/pkg/a.php", "storage/logs/x.log", "storage/app/keep.txt", "node_modules/m/i.js",
                    "public/build/a.js", "dist/a.js"] { write("x\n", to: skipDir.appendingPathComponent(rel)) }
        let skipIndex = ProjectIndex(root: skipDir)
        skipIndex.refresh(force: true) {
            check("index skips vendor, logs, build output, node_modules",
                  skipIndex.files.sorted() == ["src/ok.php", "storage/app/keep.txt"])
            ProjectIndex.includeVendor = true
            let withVendor = ProjectIndex(root: skipDir)
            withVendor.refresh(force: true) {
                check("includeVendor adds vendor files back", withVendor.files.contains("vendor/pkg/a.php")
                      && !withVendor.files.contains("node_modules/m/i.js"))
                ProjectIndex.includeVendor = savedVendor
                terminalChecks(app: app, w: w, dir: dir) {
                    claudeChecks(app: app, w: w, dir: dir) { coalescingChecks(w: w, dir: dir, done: done) }
                }
            }
        }
        _ = fm
    }

    // MARK: BottomPanel

    private static func bottomPanelChecks(w: ProjectWindow) {
        let suite = "ce-selftest-\(getpid())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bp = BottomPanel(defaults: defaults)
        var visibility: [Bool] = []
        var escapes = 0
        var closeRequest: (() -> Void)?
        bp.onVisibilityChange = { visibility.append($0) }
        bp.onEscape = { escapes += 1 }
        bp.register(id: "a", title: "Alpha", view: NSView())
        bp.register(id: "b", title: "Beta", view: NSView()) { closeRequest = $0 }
        check("bottom panel: first registered tool is selected, hidden", bp.selectedID == "a" && !bp.isVisible)
        bp.show("b")
        check("bottom panel: show selects and reveals", bp.isVisible && bp.selectedID == "b" && visibility == [true])
        bp.show("a")
        check("bottom panel: switching tools keeps it visible", bp.isVisible && bp.selectedID == "a" && visibility == [true])
        bp.hide()
        check("bottom panel: hide", !bp.isVisible && visibility == [true, false])
        bp.toggle("a"); bp.toggle("a")
        check("bottom panel: toggle shows then hides", !bp.isVisible && visibility == [true, false, true, false])
        bp.show("zzz")
        check("bottom panel: unknown id ignored", !bp.isVisible && bp.selectedID == "a")
        bp.setBadge("3", for: "b")
        check("bottom panel: badge set", bp.badge(for: "b") == "3" && bp.badge(for: "a") == nil)
        bp.setBadge("", for: "b")
        check("bottom panel: empty badge clears", bp.badge(for: "b") == nil)
        bp.show("b")
        closeRequest?()
        check("bottom panel: tool close request hides and refocuses editor", !bp.isVisible && escapes == 1)
        bp.view.onEscape?()
        check("bottom panel: Escape returns focus without hiding", escapes == 2)
        // Persistence of tab + height.
        let p1 = BottomPanel(defaults: defaults)
        p1.register(id: "a", title: "A", view: NSView()); p1.register(id: "b", title: "B", view: NSView())
        p1.setPersistence(key: "proj")
        p1.height = 275
        p1.show("b"); p1.hide()
        let p2 = BottomPanel(defaults: defaults)
        p2.register(id: "a", title: "A", view: NSView()); p2.register(id: "b", title: "B", view: NSView())
        p2.setPersistence(key: "proj")
        check("bottom panel: remembers selected tab and height", p2.selectedID == "b" && p2.height == 275)

        // Hosted in the window: git is the first tool; other tools register through the window.
        check("window: git is a registered tool", w.hasToolPanel("git") && w.bottom.tools.first?.id == "git")
        let label = NSTextField(labelWithString: "find")
        w.registerToolPanel(id: "find", title: "Find", view: label)
        w.showToolPanel("find")
        check("window: showToolPanel reveals the tool", w.bottom.isVisible && w.bottom.selectedID == "find")
        w.showCommit(); w.showCommit()
        check("window: Cmd-K shows git and never hides", w.bottom.isVisible && w.bottom.selectedID == "git")
        w.toggleGitPanel()
        check("window: Cmd-9 toggles git panel off", !w.bottom.isVisible)
        w.toggleGitPanel()
        check("window: Cmd-9 toggles git panel on", w.bottom.isVisible && w.bottom.selectedID == "git")
        w.bottom.hide()

        // Status bar: the terminal toggle stays on screen however long the server / language labels are.
        let sb = StatusBar(frame: NSRect(x: 0, y: 0, width: 880, height: 22))
        sb.update(line: 1044, column: 1, selected: 0, indent: "4 spaces", language: "Vue", lineEnding: "LF", branch: "feature/ta_track_download · 3 changes",
                  server: "Intelephense · 121 MB  |  JSON · 40 MB  |  TypeScript · 482 MB  |  Vue · 62 MB", encoding: "UTF-8")
        sb.setClaude(.waiting)
        check("status bar: terminal toggle is visible with long server labels", sb.terminalButtonFullyVisible)
        check("status bar: servers shown as a count", sb.serverText == "\u{2699}\u{FE0E} 4")
        check("status bar: hover lists each server and the total memory",
              sb.serverTip.contains("Intelephense · 121 MB") && sb.serverTip.contains("Vue · 62 MB") && sb.serverTip.hasSuffix("Total: 705 MB"))

        do {   // window floor: the status bar must not set the window's minimum width (it used to: 700+ pt, wider than a laptop screen)
            let t = ProjectWindow()
            if let u = w.current?.url { t.open(u) }
            t.statusBar.update(line: 1044, column: 1, selected: 0, indent: "4 spaces", language: "Vue", lineEnding: "LF",
                               branch: "feature/ta_track_download · 3 changes",
                               server: "Intelephense · 121 MB  |  JSON · 40 MB  |  TypeScript · 482 MB  |  Vue · 62 MB", encoding: "UTF-8")
            t.statusBar.setClaude(.connected(1))
            t.window.minSize = .zero; t.window.contentMinSize = .zero
            t.window.setContentSize(NSSize(width: 300, height: 600))
            t.window.contentView?.layoutSubtreeIfNeeded()
            check("window: content minimum width is small (<= 420 pt) with a file open and long status labels", (t.window.contentView?.frame.width ?? 9999) <= 420)
            t.showTerminal()
            t.window.setContentSize(NSSize(width: 300, height: 600))
            t.window.contentView?.layoutSubtreeIfNeeded()
            check("window: with the terminal docked right the content minimum stays <= 760 pt", (t.window.contentView?.frame.width ?? 9999) <= 760)
            for width in [320.0, 500.0, 880.0] {
                let bar = StatusBar(frame: NSRect(x: 0, y: 0, width: width, height: 22))
                bar.update(line: 1044, column: 1, selected: 0, indent: "4 spaces", language: "Vue", lineEnding: "LF", branch: "feature/ta_track_download · 3 changes",
                           server: "Intelephense · 121 MB  |  JSON · 40 MB  |  TypeScript · 482 MB  |  Vue · 62 MB", encoding: "UTF-8")
                check("status bar: terminal toggle visible at \(Int(width)) pt", bar.terminalButtonFullyVisible)
            }
        }

        do {   // commit panel dividers can be dragged (they used to refuse every drag)
            let gp = GitPanelController(root: URL(fileURLWithPath: NSTemporaryDirectory())) { _ in }
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            gp.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700); gp.view.autoresizingMask = [.width, .height]
            win.contentView = gp.view
            gp.view.layoutSubtreeIfNeeded()
            func find(_ v: NSView, vertical: Bool) -> NSSplitView? {
                if let sv = v as? NSSplitView, sv.isVertical == vertical { return sv }
                for c in v.subviews { if let r = find(c, vertical: vertical) { return r } }
                return nil
            }
            if let sv = find(gp.view, vertical: true) {
                sv.setPosition(300, ofDividerAt: 0); gp.view.layoutSubtreeIfNeeded()
                let moved = abs(sv.subviews[0].frame.width - 300) < 2
                sv.setPosition(600, ofDividerAt: 0); gp.view.layoutSubtreeIfNeeded()
                check("commit panel: list / diff divider can be dragged both ways", moved && abs(sv.subviews[0].frame.width - 600) < 2)
            } else { check("commit panel: list / diff divider exists", false) }
            if let rv = find(gp.view, vertical: false) {
                rv.setPosition(300, ofDividerAt: 0); gp.view.layoutSubtreeIfNeeded()
                check("commit panel: diff / message divider can be dragged", abs(rv.subviews[0].frame.height - 300) < 3)
            }
        }

        // Image viewer: which files open as images, multi-size icons, enlargement of tiny images.
        let imageFormats = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "ico", "icns", "tif", "tiff", "heic", "heif", "avif", "jp2", "tga", "psd", "pdf"]
        let notImages = ["php", "js", "ts", "json", "md", "txt", "svg", "vue", "css", "html", "lock", "env", "gz"]
        check("image viewer: common image formats open as images", imageFormats.allSatisfy { ImageViewerView.canView(URL(fileURLWithPath: "/p/file.\($0)")) })
        check("image viewer: code and text (incl. SVG) stay in the editor", notImages.allSatisfy { !ImageViewerView.canView(URL(fileURLWithPath: "/p/file.\($0)")) })
        do {
            func pngData(_ px: Int, _ color: NSColor) -> Data {
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                color.setFill(); NSRect(x: 0, y: 0, width: px, height: px).fill()
                NSGraphicsContext.restoreGraphicsState()
                return rep.representation(using: .png, properties: [:])!
            }
            func le16(_ v: Int) -> [UInt8] { [UInt8(v & 255), UInt8((v >> 8) & 255)] }
            func le32(_ v: Int) -> [UInt8] { le16(v & 0xffff) + le16((v >> 16) & 0xffff) }
            let small = pngData(16, .red), big = pngData(48, .green)
            var ico: [UInt8] = le16(0) + le16(1) + le16(2)
            let headerEnd = 6 + 32
            ico += [16, 16, 0, 0] + le16(1) + le16(32) + le32(small.count) + le32(headerEnd)
            ico += [48, 48, 0, 0] + le16(1) + le16(32) + le32(big.count) + le32(headerEnd + small.count)
            let imgDir = FileManager.default.temporaryDirectory.appendingPathComponent("ce-img-\(getpid())")
            try? FileManager.default.createDirectory(at: imgDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: imgDir) }
            let icoURL = imgDir.appendingPathComponent("multi.ico")
            try? (Data(ico) + small + big).write(to: icoURL)
            let viewer = ImageViewerView(url: icoURL)
            let hostWin = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            hostWin.contentView = viewer
            viewer.layoutSubtreeIfNeeded()
            check("image viewer: multi-size ico lists its sizes and starts on the largest", viewer.sizeCount == 2 && viewer.shownPixelWidth == 48 && viewer.infoText.contains("2 sizes"))
            let pdfURL = imgDir.appendingPathComponent("doc.pdf")
            let page = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
            try? page.dataWithPDF(inside: page.bounds).write(to: pdfURL)
            let pdfViewer = ImageViewerView(url: pdfURL)
            check("image viewer: a PDF opens with its page count", pdfViewer.sizeCount == 1 && pdfViewer.infoText.contains("1 page"))
            check("image viewer: a 48 px icon is enlarged to fill the view (not left as a speck)", viewer.displayScale >= 8)
        }

        // Bookmarks and TODO scan.
        let bm = FileManager.default.temporaryDirectory.appendingPathComponent("ce-bm-\(getpid())")
        try? FileManager.default.createDirectory(at: bm, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bm) }
        let store = BookmarkStore(root: bm)
        store.toggle(path: "/p/a.php", line: 10); store.toggle(path: "/p/a.php", line: 3); store.toggle(path: "/p/b.php", line: 1)
        check("bookmarks: toggle on and lines per file", store.lines(in: "/p/a.php") == [3, 10] && store.lines(in: "/p/b.php") == [1])
        check("bookmarks: toggle off", !store.toggle(path: "/p/b.php", line: 1) && store.lines(in: "/p/b.php").isEmpty)
        check("bookmarks: next wraps around", store.neighbour(of: "/p/a.php", line: 3, forward: true)?.line == 10
              && store.neighbour(of: "/p/a.php", line: 10, forward: true)?.line == 3)
        check("bookmarks: previous wraps around", store.neighbour(of: "/p/a.php", line: 3, forward: false)?.line == 10)
        check("bookmarks: persisted per project", BookmarkStore(root: bm).marks.count == 2)
        let ms = [FindMatch(url: bm.appendingPathComponent("a.php"), line: 2, column: 4, length: 4, lineText: "  // TODO: first"),
                  FindMatch(url: bm.appendingPathComponent("a.php"), line: 4, column: 4, length: 5, lineText: "/* FIXME broken */")]
        let rows = TodoScanner.rows(from: ms, base: bm.path)
        check("todo rows: tag, trimmed text and relative path", rows.map(\.tag) == ["TODO", "FIXME"] && rows[0].primary == "// TODO: first"
              && rows[0].secondary == "a.php:2" && rows[1].line == 4)
        check("todo scan pattern matches whole words only", (try? NSRegularExpression(pattern: TodoScanner.pattern))
              .map { $0.numberOfMatches(in: "TODOS TODO XXXX HACK", range: NSRange(location: 0, length: 20)) } == 2)

        // Split editor: two tabs side by side, one view each (no duplicated buffers); closing one unsplits.
        let host = TabHost(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let v1 = NSView(), v2 = NSView(), v3 = NSView()
        host.add(id: "/t/a", title: "a", view: v1); host.add(id: "/t/b", title: "b", view: v2); host.add(id: "/t/c", title: "c", view: v3)
        host.select("/t/a")
        check("split: refuses a tab with itself", !host.splitWith("/t/a"))
        check("split: starts", host.splitWith("/t/b") && host.isSplit && host.splitIDs?.left == "/t/a" && host.splitIDs?.right == "/t/b")
        check("split: both views are on screen, once each", v1.superview != nil && v2.superview != nil && v3.superview == nil && v1.superview !== v2.superview)
        host.select("/t/b")
        check("split: selecting the other pane's tab only activates it", host.selectedID == "/t/b" && v1.superview != nil && v2.superview != nil)
        host.select("/t/c")
        check("split: a new tab replaces the active pane", host.splitIDs?.right == "/t/c" && host.splitIDs?.left == "/t/a" && v2.superview == nil)
        host.remove("/t/c")
        check("split: closing a split tab unsplits to the other", !host.isSplit && host.selectedID == "/t/a" && v1.superview != nil)
        host.splitWith("/t/b"); host.unsplit()
        check("split: unsplit shows one view", !host.isSplit && v1.superview != nil && v2.superview == nil)
    }

    // MARK: File operations, tab retargeting, tree

    private static func fileOperationChecks(w: ProjectWindow, dir: URL) {
        let fm = FileManager.default
        let ops = dir.appendingPathComponent("ops")
        try? fm.createDirectory(at: ops, withIntermediateDirectories: true)
        let trashDir = dir.appendingPathComponent(".trashed")
        try? fm.createDirectory(at: trashDir, withIntermediateDirectories: true)
        FileOperations.trasher = { url in try fm.moveItem(at: url, to: trashDir.appendingPathComponent(url.lastPathComponent)) }

        let f = try? FileOperations.createFile(named: "new.txt", in: ops)
        check("create file", f != nil && fm.fileExists(atPath: ops.appendingPathComponent("new.txt").path))
        check("create file refuses existing", (try? FileOperations.createFile(named: "new.txt", in: ops)) == nil)
        check("invalid names rejected", !FileOperations.isValid(name: "a/b") && !FileOperations.isValid(name: "  ") && !FileOperations.isValid(name: ".."))
        check("create folder", (try? FileOperations.createFolder(named: "sub", in: ops)) != nil)
        write("hello\n", to: ops.appendingPathComponent("a.txt"))
        let renamed = try? FileOperations.rename(ops.appendingPathComponent("a.txt"), to: "b.txt")
        check("rename", renamed?.lastPathComponent == "b.txt" && !fm.fileExists(atPath: ops.appendingPathComponent("a.txt").path))
        let dup = try? FileOperations.duplicate(ops.appendingPathComponent("b.txt"))
        let dup2 = try? FileOperations.duplicate(ops.appendingPathComponent("b.txt"))
        check("duplicate names: copy, copy 2", dup?.lastPathComponent == "b copy.txt" && dup2?.lastPathComponent == "b copy 2.txt")
        let moved = try? FileOperations.move(ops.appendingPathComponent("b copy.txt"), toDirectory: ops.appendingPathComponent("sub"))
        check("move into folder", moved?.path == ops.appendingPathComponent("sub/b copy.txt").path)
        check("move into itself refused", (try? FileOperations.move(ops.appendingPathComponent("sub"), toDirectory: ops.appendingPathComponent("sub"))) == nil)
        check("move onto existing needs overwrite",
              (try? FileOperations.move(ops.appendingPathComponent("b copy 2.txt"), toDirectory: ops.appendingPathComponent("sub"))) != nil
              && { write("z", to: ops.appendingPathComponent("b copy 2.txt"))
                   return (try? FileOperations.move(ops.appendingPathComponent("b copy 2.txt"), toDirectory: ops.appendingPathComponent("sub"))) == nil }())
        check("remap path prefix", FileOperations.remap(path: "/a/b/c.txt", from: "/a/b", to: "/x") == "/x/c.txt"
              && FileOperations.remap(path: "/a/bc.txt", from: "/a/b", to: "/x") == nil)

        // Tabs follow renames, moves and deletes.
        let t1 = ops.appendingPathComponent("t1.txt"), t2 = ops.appendingPathComponent("sub/t2.txt"), t3 = ops.appendingPathComponent("t3.txt")
        write("one\n", to: t1); write("two\n", to: t2); write("three\n", to: t3)
        w.open(t1); w.open(t2); w.open(t3)
        let dirty = w.editors[t1.standardizedFileURL.path]!
        dirty.textView.string += "x"
        dirty.textView.didChangeText()
        let r1 = try! FileOperations.rename(t1, to: "t1-renamed.txt")
        w.handleFileChange(.moved(from: t1, to: r1))
        let newID = r1.standardizedFileURL.path
        check("rename retargets open tab (dirty state kept)",
              w.editors[t1.standardizedFileURL.path] == nil && w.editors[newID] === dirty && dirty.url.lastPathComponent == "t1-renamed.txt"
              && w.tabs.entries.contains { $0.id == newID && $0.title == "t1-renamed.txt" && $0.isDirty })
        let movedDir = try! FileOperations.rename(ops.appendingPathComponent("sub"), to: "sub2")
        w.handleFileChange(.moved(from: ops.appendingPathComponent("sub"), to: movedDir))
        check("folder rename retargets tabs inside it", w.editors[movedDir.appendingPathComponent("t2.txt").standardizedFileURL.path] != nil
              && w.editors[t2.standardizedFileURL.path] == nil)
        check("retargeted tab stays selectable", { w.tabs.select(newID); return w.current === dirty }())
        try? FileOperations.trash(t3)
        w.handleFileChange(.deleted(t3))
        check("delete closes the tab with a notice",
              w.editors[t3.standardizedFileURL.path] == nil && !w.tabs.entries.contains { $0.id == t3.standardizedFileURL.path }
              && w.statusBarNotice.contains("t3.txt"))
        let newDirURL = movedDir
        try? FileOperations.trash(newDirURL)
        w.handleFileChange(.deleted(newDirURL))
        check("deleting a folder closes tabs inside it", w.editors[movedDir.appendingPathComponent("t2.txt").standardizedFileURL.path] == nil)
        w.close(newID)

        // Tree drop: move with overwrite confirmation, copy from outside.
        let dropSrc = ops.appendingPathComponent("drop.txt"), dropDir = ops.appendingPathComponent("target")
        write("src", to: dropSrc); write("existing", to: dropDir.appendingPathComponent("drop.txt"))
        w.tree.confirmOverwrite = { _ in false }
        check("drop onto existing is declined without confirmation", w.tree.performDrop(urls: [dropSrc], into: dropDir, move: true).isEmpty
              && read(dropDir.appendingPathComponent("drop.txt")) == "existing")
        w.tree.confirmOverwrite = { names in names == ["drop.txt"] }
        let changes = w.tree.performDrop(urls: [dropSrc], into: dropDir, move: true)
        check("drop with confirmation overwrites and reports a move", changes == [.moved(from: dropSrc, to: dropDir.appendingPathComponent("drop.txt"))]
              && read(dropDir.appendingPathComponent("drop.txt")) == "src" && !fm.fileExists(atPath: dropSrc.path))
        let outside = fm.temporaryDirectory.appendingPathComponent("ce-outside-\(getpid())")
        write("ext", to: outside.appendingPathComponent("from-finder.txt"))
        let copied = w.tree.performDrop(urls: [outside.appendingPathComponent("from-finder.txt")], into: ops, move: false)
        check("dropping from outside copies in", copied == [.created(ops.appendingPathComponent("from-finder.txt"))]
              && fm.fileExists(atPath: outside.appendingPathComponent("from-finder.txt").path))
        try? fm.removeItem(at: outside)
        w.tree.confirmOverwrite = { _ in false }

        // Copy / paste of files.
        let pasteSrc = ops.appendingPathComponent("target/drop.txt")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([pasteSrc as NSURL])
        w.tree.paste(into: ops.appendingPathComponent("target"))
        check("paste beside the original makes a 'copy' file", read(ops.appendingPathComponent("target/drop copy.txt")) == "src")
        w.tree.paste(into: ops)
        check("paste into another folder copies the file", read(ops.appendingPathComponent("drop.txt")) == "src" && fm.fileExists(atPath: pasteSrc.path))

        // Context menu content.
        let titles = w.tree.menuItems(for: ops.appendingPathComponent("target/drop.txt")).map(\.title)
        check("tree context menu lists all commands",
              ["New File…", "New Folder…", "Rename…", "Duplicate", "Move to Trash…", "Reveal in Finder", "Copy Path",
               "Copy Relative Path", "Open in Terminal", "Collapse All"].allSatisfy(titles.contains))
        check("tree context menu on root disables rename/trash",
              w.tree.menuItems(for: nil).filter { ["Rename…", "Duplicate", "Move to Trash…"].contains($0.title) }.allSatisfy { !$0.isEnabled })
        check("new items go into the folder or beside a file", w.tree.targetDirectory(for: ops)?.path == ops.path
              && w.tree.targetDirectory(for: ops.appendingPathComponent("target/drop.txt"))?.path == ops.appendingPathComponent("target").path)
        check("tree drop of folder into itself is refused", w.tree.performDrop(urls: [ops], into: ops.appendingPathComponent("target"), move: true).isEmpty)
        FileOperations.trasher = { url in try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }

    // MARK: Tabs

    private static func tabChecks(w: ProjectWindow, dir: URL) {
        let ids = (1...5).map { dir.appendingPathComponent("tabs/f\($0).txt") }
        ids.forEach { write("x\n", to: $0); w.open($0) }
        let p = ids.map { $0.standardizedFileURL.path }
        let before = w.tabs.itemView(for: p[0])
        w.tabs.setTitle("renamed", for: p[0]); w.tabs.setDirty(true, for: p[0]); w.tabs.setTint(.systemBlue, for: p[0])
        check("tab updates are incremental (same view instance)", before != nil && w.tabs.itemView(for: p[0]) === before
              && before?.title == "renamed" && before?.isDirty == true)
        w.tabs.setTitle(ids[0].lastPathComponent, for: p[0]); w.tabs.setDirty(false, for: p[0]); w.tabs.setTint(nil, for: p[0])
        let order = w.tabs.entries.map(\.id)
        w.tabs.move(p[4], toIndex: 0)
        check("tab drag reorder moves entry", w.tabs.entries.first?.id == p[4] && w.tabs.entries.count == order.count)
        w.tabs.move(p[4], toIndex: 99)
        check("reorder clamps index", w.tabs.entries.last?.id == p[4])
        let menuTitles = w.tabMenu(for: p[1]).items.map(\.title)
        check("tab context menu", menuTitles == ["Close", "Close Others", "Close All", "Close to the Right", "", "Split Right", "", "Copy Path", "Reveal in Finder"])
        let right = w.tabs.ids(toRightOf: p[1])
        check("ids to the right", right == Array(w.tabs.entries.map(\.id).drop { $0 != p[1] }.dropFirst()))
        w.closeToTheRight(of: p[1])
        check("close to the right", w.tabs.ids(toRightOf: p[1]).isEmpty && w.tabs.entries.contains { $0.id == p[1] })
        w.closeOthers(p[1])
        check("close others", w.tabs.entries.map(\.id) == [p[1]])
        w.closeAllTabs()
        check("close all", w.tabs.entries.isEmpty && w.editors.isEmpty)
        check("tab strip shows no overflow with no tabs", !w.tabs.isOverflowing)
    }

    // MARK: Dirty buffer vs disk

    private static func bannerChecks(w: ProjectWindow, dir: URL) {
        let fm = FileManager.default
        let url = dir.appendingPathComponent("banner.txt")
        write("original\n", to: url)
        w.open(url)
        let ed = w.current!
        func externalWrite(_ text: String) {
            write(text, to: url)
            try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(Double.random(in: 5...50))], ofItemAtPath: url.path)
        }
        ed.textView.string = "mine\n"; ed.textView.didChangeText()
        externalWrite("theirs\n")
        ed.reloadIfChangedOnDisk()
        check("dirty + external change shows the banner and keeps the buffer",
              ed.isBannerVisible && ed.hasDiskConflict && ed.textView.string == "mine\n"
              && ed.bannerButtons == ["Reload", "Keep mine", "Show diff"])
        check("save refuses to overwrite a newer disk version (headless declines)", !ed.save() && read(url) == "theirs\n")
        ed.keepMine()
        check("keep mine hides the banner", !ed.isBannerVisible && !ed.hasDiskConflict)
        check("save after keep-mine overwrites", ed.save() && read(url) == "mine\n" && !ed.isDirty)
        ed.textView.string = "mine2\n"; ed.textView.didChangeText()
        externalWrite("theirs2\n")
        ed.reloadIfChangedOnDisk()
        ed.reloadFromDisk()
        check("reload takes the disk version and clears dirty", ed.textView.string == "theirs2\n" && !ed.isDirty && !ed.isBannerVisible
              && w.tabs.entries.first { $0.id == url.standardizedFileURL.path }?.isDirty == false)
        ed.textView.string = "mine3\n"; ed.textView.didChangeText()
        externalWrite("theirs3\n")
        check("save warns even if no change was noticed yet", ed.hasNewerDiskVersion && !ed.save())
        check("overwriteNewer saves anyway", ed.save(overwriteNewer: true) && read(url) == "mine3\n")
        w.close(url.standardizedFileURL.path)
    }

    // MARK: Encodings, line endings, big files

    private static func encodingChecks(w: ProjectWindow, dir: URL) {
        let crlf = dir.appendingPathComponent("crlf.txt")
        try? Data("a\r\nb\r\nc\r\n".utf8).write(to: crlf)
        w.open(crlf)
        let ed = w.current!
        check("CRLF detected", ed.eol == .crlf && ed.lineEnding == "CRLF")
        ed.textView.string += "d\n"; ed.textView.didChangeText()
        check("CRLF file saves with CRLF only", ed.save() && (try? Data(contentsOf: crlf)) == Data("a\r\nb\r\nc\r\nd\r\n".utf8))
        let lf = dir.appendingPathComponent("lf.txt")
        write("a\nb\n", to: lf)
        w.open(lf)
        w.current!.textView.string += "c\n"; w.current!.textView.didChangeText()
        check("LF file stays LF", w.current!.save() && (try? Data(contentsOf: lf)) == Data("a\nb\nc\n".utf8))
        check("line ending detection", EditorTab.detectLineEnding("a\nb\n") == .lf && EditorTab.detectLineEnding("a\r\nb\r\n") == .crlf
              && EditorTab.detectLineEnding("a\nb\nc\r\n") == .lf && EditorTab.detectLineEnding("") == .lf)

        let latin = dir.appendingPathComponent("latin1.txt")
        try? Data([0x63, 0x61, 0x66, 0xE9, 0x0A]).write(to: latin)
        check("non-UTF-8 file is diagnosed", EditorTab.loadProblem(for: latin) == .notUTF8)
        w.open(latin)
        let id = latin.standardizedFileURL.path
        let view = w.tabs.entries.first { $0.id == id }?.view as? LoadProblemView
        check("non-UTF-8 shows a message with Latin-1 option", w.placeholders[id] == .notUTF8 && w.editors[id] == nil
              && view?.actionTitles.first == "Open anyway as Latin-1" && view?.message.contains("latin1.txt") == true)
        view?.perform(0)
        check("Open anyway as Latin-1 loads the text", w.placeholders[id] == nil && w.editors[id]?.textView.string == "café\n"
              && w.editors[id]?.encoding == .isoLatin1)
        check("Latin-1 file saves back as Latin-1", { w.editors[id]!.textView.string += "x"; w.editors[id]!.textView.didChangeText()
            return w.editors[id]!.save() && (try? Data(contentsOf: latin)) == Data([0x63, 0x61, 0x66, 0xE9, 0x0A, 0x78]) }())
        w.close(id)

        let big = dir.appendingPathComponent("big.txt")
        try? Data(repeating: 0x61, count: 5_100_000).write(to: big)
        check("large file is diagnosed", EditorTab.loadProblem(for: big) == .tooLarge(5_100_000))
        w.open(big)
        let bid = big.standardizedFileURL.path
        let bview = w.tabs.entries.first { $0.id == bid }?.view as? LoadProblemView
        check("large file shows a message with read-only option", bview?.actionTitles.first == "Open read-only (first 5 MB)")
        bview?.perform(0)
        let bed = w.editors[bid]
        check("read-only open shows the first 5 MB and refuses to save",
              bed?.isReadOnly == true && (bed?.textView.string as NSString?)?.length == 5_000_000 && bed?.save() == false
              && bed?.isBannerVisible == true && bed?.textView.isEditable == false)
        w.close(bid)
        w.tabs.entries.map(\.id).forEach { w.close($0) }
    }

    // MARK: Git summary, tab colours, tree precedence

    private static func statusChecks(w: ProjectWindow, dir: URL) {
        check("git summary full", StatusBar.gitSummary(branch: "main", ahead: 1, behind: 2, changes: 3) == "⎇ main ↑1 ↓2 · 3 changes")
        check("git summary ahead only", StatusBar.gitSummary(branch: "main", ahead: 1, behind: 0, changes: 3) == "⎇ main ↑1 · 3 changes")
        check("git summary singular", StatusBar.gitSummary(branch: "dev", ahead: 0, behind: 0, changes: 1) == "⎇ dev · 1 change")
        check("git summary clean", StatusBar.gitSummary(branch: "dev", ahead: 0, behind: 0, changes: 0) == "⎇ dev")
        check("git summary no repo", StatusBar.gitSummary(branch: nil, ahead: 0, behind: 0, changes: 0) == "")

        let list = [change("a/x.php"), change("a/y.php", work: " ", untracked: true), change("b/z.php", work: " ", untracked: true),
                    change("b/w.php", index: "A", work: " "), change("c/q.php", conflict: true), change("d/m.php"),
                    change("d/u.php", work: " ", untracked: true), change("e/gone.php", work: "D")]
        func kinds(_ items: [GitChange]) -> [String: VCSKind] {
            VCSKind.kinds(for: Dictionary(items.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a }), repoRoot: dir)
        }
        for (name, items) in [("forward", list), ("reversed", list.reversed()), ("rotated", Array(list[3...] + list[..<3]))] {
            let k = kinds(items)
            check("tree status precedence (\(name)): modified > untracked, added > untracked, conflict wins, deletions ignored",
                  k[dir.appendingPathComponent("a").path] == .modified && k[dir.appendingPathComponent("b").path] == .added
                  && k[dir.appendingPathComponent("c").path] == .conflict && k[dir.appendingPathComponent("d").path] == .modified
                  && k[dir.appendingPathComponent("e").path] == nil && k[dir.path] == .conflict)
        }
        check("kind ordering", VCSKind.conflict > .modified && VCSKind.modified > .added && VCSKind.added > .untracked)

        let t = dir.appendingPathComponent("tint/changed.php"), u = dir.appendingPathComponent("tint/new.php"), n = dir.appendingPathComponent("tint/clean.php")
        [t, u, n].forEach { write("x\n", to: $0); w.open($0) }
        w.applyGitStatus(changes: [change("tint/changed.php"), change("tint/new.php", work: " ", untracked: true)],
                         info: ("main", nil, 1, 0, false), repoRoot: dir)
        func tint(_ url: URL) -> NSColor? { w.tabs.entries.first { $0.id == url.standardizedFileURL.path }?.tint }
        check("tab titles are coloured by VCS status", tint(t) == .systemBlue && tint(u) == .systemBrown && tint(n) == nil)
        check("status bar shows the git summary", w.statusBarBranchText == "⎇ main ↑1 · 2 changes")
        w.applyGitStatus(changes: [], info: ("main", nil, 0, 0, false), repoRoot: dir)
        check("tab colour clears when clean", tint(t) == nil && w.statusBarBranchText == "⎇ main")
        w.tabs.entries.map(\.id).forEach { w.close($0) }
    }

    // MARK: Menu / handlers

    private static func menuChecks(app: AppDelegate, w: ProjectWindow) {
        check("Find in Files is Cmd-Shift-F", shortcut("Find in Files…") == "⇧⌘F")
        check("Replace in Files is Cmd-Shift-R", shortcut("Replace in Files…") == "⇧⌘R")
        check("Next Problem is F2", shortcut("Next Problem") == "F2")
        check("Previous Problem is Shift-F2", shortcut("Previous Problem") == "⇧F2")
        check("Find Usages is Alt-F7", shortcut("Find Usages") == "⌥F7")
        check("Rename is Shift-F6", shortcut("Rename…") == "⇧F6")
        check("Format Document is Cmd-Opt-Shift-L", shortcut("Format Document") == "⌥⇧⌘L")
        check("Reformat Code keeps Cmd-Opt-L", shortcut("Reformat Code") == "⌥⌘L")
        check("Toggle Soft Wrap and tool windows exist", ["Toggle Soft Wrap", "Find Tool Window", "Problems Tool Window", "Git Tool Window",
                                                          "Include vendor in Go to File", "Reopen Windows on Launch"].allSatisfy { shortcut($0) != "missing" })
        check("Git panel is Cmd-9, Commit Panel Cmd-0, Go to Line Cmd-L",
              shortcut("Show Git Panel") == "⌘9" && shortcut("Commit Panel") == "⌘0" && shortcut("Go to Line…") == "⌘L")

        app.noteKey(w.window)
        var hits: [String] = []
        w.onFindInFiles = { hits.append("find") }; w.onReplaceInFiles = { hits.append("replace") }
        AppDelegate.nextProblemHandler = { _ in hits.append("next") }
        AppDelegate.previousProblemHandler = { _ in hits.append("prev") }
        AppDelegate.findUsagesHandler = { _ in hits.append("usages") }
        AppDelegate.renameHandler = { _ in hits.append("rename") }
        AppDelegate.formatHandler = { _ in hits.append("format") }
        app.findInFiles(nil); app.replaceInFiles(nil); app.nextProblem(nil); app.previousProblem(nil)
        app.findUsages(nil); app.renameSymbol(nil); app.formatDocument(nil)
        check("menu actions reach the installed handlers", hits == ["find", "replace", "next", "prev", "usages", "rename", "format"])
        w.onFindInFiles = nil; w.onReplaceInFiles = nil
        AppDelegate.nextProblemHandler = nil; AppDelegate.previousProblemHandler = nil
        AppDelegate.findUsagesHandler = nil; AppDelegate.renameHandler = nil; AppDelegate.formatHandler = nil
        app.findInFiles(nil); app.nextProblem(nil)
        check("handlers are no-ops until set", hits.count == 7)
        check("Problems panel is registered by the feature wiring", w.hasToolPanel("problems") && w.hasToolPanel("find"))
        app.showProblemsTool(nil)
        check("View > Problems shows the registered tool", w.bottom.isVisible && w.bottom.selectedID == "problems")
        w.bottom.hide()
    }

    // MARK: Active window, Go to Line, polling

    private static func miscChecks(app: AppDelegate, w: ProjectWindow) {
        let w2 = app.newWindow()
        app.noteKey(w.window)
        check("active falls back to the last key project window", app.active === w)
        app.noteKey(w2.window)
        check("active follows the last key window", app.active === w2)
        app.noteKey(NSWindow())
        check("a foreign key window (picker/panel) does not change active", app.active === w2)
        app.noteKey(w.window)
        w2.window.close()
        check("closed window is forgotten", app.active === w && !app.windows.contains { $0 === w2 })

        let cases: [(String, Int?, Int?)] = [("42", 42, 1), ("42:7", 42, 7), (" 3 : 4 ", 3, 4), ("5:", 5, 1), ("0", nil, nil),
                                             ("abc", nil, nil), ("1:2:3", nil, nil), ("", nil, nil), ("-3", nil, nil), ("4:0", nil, nil)]
        check("Go to Line parsing", cases.allSatisfy { input, line, col in
            let r = GoToLineInput.parse(input)
            return r?.line == line && r?.column == col
        })
        check("no 1 s mtime poll timer when headless (FSEvents path)", !w.usesFallbackPolling)
    }

    // MARK: Session

    private static func sessionChecks(app: AppDelegate, dir: URL) {
        let fm = FileManager.default
        let savedDir = SessionStore.directory
        SessionStore.directory = dir.appendingPathComponent("sessions")
        defer { SessionStore.directory = savedDir; SessionStore.forceEnabled = false }

        let proj = dir.appendingPathComponent("sessproj")
        let files = ["f1.txt", "f2.txt", "sub/f3.txt"].map { proj.appendingPathComponent($0) }
        files.forEach { write("0123456789\nabcdefghij\n", to: $0) }

        // Headless runs never touch saved sessions...
        SessionStore.forceEnabled = false
        SessionStore.save(Session(tabs: [.init(path: "x", caret: 1, scrollY: 0)]), for: proj)
        check("sessions are not written in headless mode", !fm.fileExists(atPath: SessionStore.fileURL(for: proj).path))
        // ...unless CE_RESTORE / forceEnabled is set.
        SessionStore.forceEnabled = true

        let w3 = app.openProject(proj)
        w3.open(files[0]); w3.open(files[1]); w3.open(files[2])
        w3.editors[files[0].standardizedFileURL.path]?.restore(caret: 5, scrollY: 0)
        w3.tabs.move(files[2].standardizedFileURL.path, toIndex: 0)
        w3.tabs.select(files[0].standardizedFileURL.path)
        w3.tree.expand(paths: [proj.appendingPathComponent("sub").path])
        w3.window.setFrame(NSRect(x: 80, y: 90, width: 900, height: 620), display: false)
        w3.bottom.height = 260
        w3.showCommit()
        w3.saveSession()
        let saved = SessionStore.load(for: proj)
        check("session file written", saved != nil && fm.fileExists(atPath: SessionStore.fileURL(for: proj).path))
        check("session captures tabs in order, selection, caret, bottom panel, expansion, frame",
              saved?.tabs.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["f3.txt", "f1.txt", "f2.txt"]
              && saved?.selected == files[0].standardizedFileURL.path
              && saved?.tabs.first { $0.path.hasSuffix("f1.txt") }?.caret == 5
              && saved?.bottom?.visible == true && saved?.bottom?.selected == "git"
              && saved?.expanded.contains { VCSKind.canonical($0) == VCSKind.canonical(proj.appendingPathComponent("sub").path) } == true
              && saved?.windowFrame?[2] == 900)
        check("session JSON round-trips", (try? JSONDecoder().decode(Session.self, from: JSONEncoder().encode(saved!))) == saved)
        w3.window.close()
        try? fm.removeItem(at: files[1])          // missing files are skipped on restore
        let w4 = app.openProject(proj)
        check("restore reopens tabs in order, skipping missing files",
              w4.tabs.entries.map { URL(fileURLWithPath: $0.id).lastPathComponent } == ["f3.txt", "f1.txt"])
        check("restore selects the saved tab and puts the caret back",
              w4.tabs.selectedID == files[0].standardizedFileURL.path && w4.current?.caretLocation == 5)
        check("restore reopens the bottom panel and window frame", w4.bottom.isVisible && w4.bottom.selectedID == "git"
              && abs(w4.window.frame.width - 900) < 1)
        check("restore re-expands the tree", w4.tree.expandedPaths().contains { VCSKind.canonical($0) == VCSKind.canonical(proj.appendingPathComponent("sub").path) })
        w4.bottom.hide()
        SessionStore.forceEnabled = false
        w4.window.close()
    }

    // MARK: FS-burst coalescing (async)

    private static func coalescingChecks(w: ProjectWindow, dir: URL, done: @escaping () -> Void) {
        w.coalesceInterval = 0.15
        let before = w.changeBatches
        for i in 0..<6 { w.filesChanged([dir.appendingPathComponent("app/burst\(i).php").path]) }
        w.filesChanged([dir.appendingPathComponent("node_modules/x/y.js").path, dir.appendingPathComponent("storage/logs/laravel.log").path,
                        dir.appendingPathComponent("vendor/p/q.php").path, dir.appendingPathComponent("public/build/app.js").path,
                        dir.appendingPathComponent(".idea/workspace.xml").path])
        check("FS events are deferred (trailing debounce)", w.changeBatches == before)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            check("a burst of FS events is processed once", w.changeBatches == before + 1)
            w.filesChanged([dir.appendingPathComponent("storage/framework/cache/a").path, dir.appendingPathComponent("dist/a.js").path,
                            dir.appendingPathComponent("coverage/index.html").path])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                check("events under skipped/build dirs are ignored", w.changeBatches == before + 1)
                w.filesChanged([dir.appendingPathComponent(".git/index").path])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    check("git metadata events still trigger a (single) refresh", w.changeBatches == before + 2)
                    done()
                }
            }
        }
    }
}
