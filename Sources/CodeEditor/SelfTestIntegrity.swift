import AppKit

/// Headless checks for buffer integrity: auto-save, minimal-diff reload + undo, symlink/permission/encoding-safe saves,
/// big and non-UTF-8 files, local history, will-save hook chaining, and the agent-edit flash.
extension SelfTest {
    // Will-save hook used by the tests (hooks cannot be unregistered, so it is switched by flags).
    private static var hookMode = "off"
    private static var hookLog: [String] = []
    private static var heldProceed: (() -> Void)?
    private static var hookInstalled = false

    private static func iw(_ text: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
    }
    private static func ir(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
    private static func bytes(_ url: URL) -> [UInt8] { [UInt8]((try? Data(contentsOf: url)) ?? Data()) }

    /// Writes like an agent would: atomic replace plus a different mtime.
    private static func external(_ text: String, to url: URL) {
        try? Data(text.utf8).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double.random(in: 5...90))], ofItemAtPath: url.path)
    }

    private static func edit(_ ed: EditorTab, append text: String) {
        ed.textView.string += text
        ed.textView.didChangeText()
    }

    private static func posix(_ url: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1 }
    private static func isSymlink(_ url: URL) -> Bool { (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil }
    private static func strays(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.contains(".ce-") }
    }

    static func integrityChecks(w: ProjectWindow, dir: URL) {
        let fm = FileManager.default
        let base = dir.appendingPathComponent("integrity")
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        w.tabs.entries.map(\.id).forEach { w.close($0) }
        if !hookInstalled {
            hookInstalled = true
            EditorEvents.onWillSave { tab, proceed in
                guard hookMode != "off" else { proceed(); return }
                hookLog.append("h1")
                tab.textView.string += "// formatted\n"
                tab.textView.didChangeText()
                proceed()
            }
            EditorEvents.onWillSave { _, proceed in
                guard hookMode != "off" else { proceed(); return }
                hookLog.append("h2")
                if hookMode == "async" { heldProceed = proceed } else { proceed() }
            }
        }
        reloadChecks(w: w, base: base)
        hunkChecks()
        autoSaveChecks(w: w, base: base)
        safeSaveChecks(w: w, base: base)
        encodingRoundTripChecks(w: w, base: base)
        largeFileChecks(w: w, base: base)
        historyChecks(w: w, base: base)
        hookChecks(w: w, base: base)
        if let out = AppEnv.value("CE_SELFTEST_PNG") { renderStates(w: w, base: base, outDir: out) }
        w.tabs.entries.map(\.id).forEach { w.close($0) }
    }

    // MARK: Minimal-diff reload and undo

    private static func reloadChecks(w: ProjectWindow, base: URL) {
        let url = base.appendingPathComponent("reload.txt")
        let old = (1...20).map { "line \($0)\n" }.joined()
        iw(old, to: url)
        w.open(url)
        let ed = w.current!
        let ns = old as NSString
        ed.textView.setSelectedRange(NSRange(location: ns.range(of: "line 15").location + 2, length: 0))
        let newText = old.replacingOccurrences(of: "line 3\n", with: "line three\nextra A\nextra B\n")
        external(newText, to: url)
        ed.reloadIfChangedOnDisk()
        check("reload: clean buffer takes the disk text and stays clean", ed.textView.string == newText && !ed.isDirty)
        let caretLine15 = (newText as NSString).range(of: "line 15").location + 2
        check("reload: caret after the change maps through the edit", ed.textView.selectedRange() == NSRange(location: caretLine15, length: 0))
        check("reload: lastExternalChange records the changed lines",
              w.lastExternalChange?.firstLine == 3 && w.lastExternalChange?.lastLine == 5 && w.lastExternalChange?.wholeText == false
              && w.lastExternalChange?.url == url)
        check("reload: status bar says it was reloaded and how to undo", w.statusBarNotice == "Reloaded from disk (agent edit?)  ⌘Z to undo")
        check("reload: the changed lines flash", ed.isFlashing && ed.flashBandCount >= 3)
        ed.textView.undoManager?.undo()
        check("reload: Cmd-Z restores the text from before the reload", ed.textView.string == old)
        check("reload: after undo the buffer is dirty versus disk", ed.isDirty)
        ed.textView.undoManager?.redo()
        check("reload: redo re-applies the external edit", ed.textView.string == newText)
        ed.save(overwriteNewer: true)

        // Caret inside the replaced region, and a selection straddling it.
        let a = "one\ntwo\nthree\nfour\n"
        iw(a, to: url); ed.reloadFromDisk(); ed.keepMine()
        check("reload: setup text", ed.textView.string == a)
        ed.textView.setSelectedRange(NSRange(location: 4, length: 9))   // "two\nthree\n"
        external("one\n2\nthree\nFOUR\n", to: url)
        ed.reloadIfChangedOnDisk()
        check("reload: selection is mapped, not reset", ed.textView.selectedRange().location == 4 && ed.textView.selectedRange().length > 0
              && ed.textView.string == "one\n2\nthree\nFOUR\n")

        // Pure edits above the scroll anchor keep the scroll offset.
        ed.scrollView.contentView.scroll(to: NSPoint(x: 0, y: 0))
        check("reload: scroll position preserved", ed.scrollY == 0)

        // Nothing changed -> no undo entry, no flash message churn.
        let notice = w.lastExternalChange?.date
        ed.reloadIfChangedOnDisk()
        check("reload: unchanged disk is a no-op", w.lastExternalChange?.date == notice)

        // Dirty "Reload" button is undoable too and the discarded edits land in local history.
        edit(ed, append: "unsaved work\n")
        external("disk wins\n", to: url)
        ed.reloadIfChangedOnDisk()
        check("reload: dirty buffer shows banner and is untouched", ed.hasDiskConflict && ed.textView.string.contains("unsaved work"))
        ed.pressBannerButton("Reload")
        check("reload: banner Reload takes disk text", ed.textView.string == "disk wins\n" && !ed.isDirty && !ed.isBannerVisible)
        check("reload: discarded edits are in local history",
              LocalHistory.revisions(for: url).contains { LocalHistory.text(of: $0)?.contains("unsaved work") == true })
        ed.textView.undoManager?.undo()
        check("reload: even a discard can be undone", ed.textView.string.contains("unsaved work") && ed.isDirty)

        // Literal comparison: a pure Unicode-normalisation change is a real change.
        iw("caf\u{e9}\n", to: url); ed.reloadFromDisk()
        external("cafe\u{301}\n", to: url)
        ed.reloadIfChangedOnDisk()
        check("reload: canonically-equivalent text still reloads literally",
              (ed.textView.string as NSString).isEqual(to: "cafe\u{301}\n"))

        // Large diff: single whole replacement, still undoable.
        let big = base.appendingPathComponent("bigreload.txt")
        let oldBig = (0..<25_000).map { "old line number \($0)\n" }.joined()
        iw(oldBig, to: big)
        w.open(big)
        let be = w.current!
        let newBig = (0..<25_000).map { "NEW different \($0 * 7)\n" }.joined()
        external(newBig, to: big)
        be.reloadIfChangedOnDisk()
        check("reload: huge diff falls back to one whole replace", be.textView.string == newBig && !be.isDirty
              && w.lastExternalChange?.ranges.count == 1)
        be.textView.undoManager?.undo()
        check("reload: huge diff is still undoable", be.textView.string == oldBig)
        let hs = EditorTab.hunks(from: oldBig, to: newBig)
        check("hunks: huge middle yields a single exact hunk", hs.count == 1)
        w.close(big.standardizedFileURL.path)
        w.close(url.standardizedFileURL.path)
    }

    private static func hunkChecks() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        let vocab = ["a\n", "b\n", "\n", "e\u{301}\n", "\u{e9}\n", "c\r\n", "x", "日本\n", "😀\n", "same line\n"]
        var exact = true
        for _ in 0..<400 {
            func make() -> String { (0..<next(14)).map { _ in vocab[next(vocab.count)] }.joined() }
            let old = make(), new = make()
            let hunks = EditorTab.hunks(from: old, to: new)
            let m = NSMutableString(string: old)
            for h in hunks.reversed() { m.replaceCharacters(in: h.old, with: h.text) }
            if !(m as NSString).isEqual(to: new) { exact = false; break }
            if hunks.isEmpty != (old as NSString).isEqual(to: new) { exact = false; break }
        }
        check("hunks: 400 random pairs reproduce the new text exactly (literal compare)", exact)
        let h = EditorTab.hunks(from: "a\nb\nc\nd\n", to: "a\nB\nc\nd\nE\n")
        check("hunks: minimal regions", h == [EditorTab.Hunk(old: NSRange(location: 2, length: 2), text: "B\n"),
                                              EditorTab.Hunk(old: NSRange(location: 8, length: 0), text: "E\n")])
        let hs = [EditorTab.Hunk(old: NSRange(location: 10, length: 5), text: "xy"), EditorTab.Hunk(old: NSRange(location: 20, length: 0), text: "abc")]
        check("hunks: position mapping", EditorTab.map(3, through: hs) == 3 && EditorTab.map(10, through: hs) == 10
              && EditorTab.map(12, through: hs) == 12 && EditorTab.map(15, through: hs) == 12 && EditorTab.map(20, through: hs) == 17
              && EditorTab.map(21, through: hs) == 21 + 3 - 3)
    }

    // MARK: Auto-save

    private static func autoSaveChecks(w: ProjectWindow, base: URL) {
        let suite = "ce-selftest-autosave-\(getpid())"
        let saved = AutoSave.defaults
        AutoSave.defaults = UserDefaults(suiteName: suite)!
        defer { AutoSave.defaults.removePersistentDomain(forName: suite); AutoSave.defaults = saved }

        check("autosave: defaults are on for focus loss/tab switch, off for idle",
              AutoSave.focusLossEnabled && AutoSave.tabSwitchEnabled && AutoSave.idleSeconds == 0)
        let a = base.appendingPathComponent("auto-a.txt"), b = base.appendingPathComponent("auto-b.txt")
        iw("a\n", to: a); iw("b\n", to: b)
        w.open(a)
        let ea = w.current!
        edit(ea, append: "more\n")
        AutoSave.focusLossEnabled = false
        check("autosave: focus-loss toggle off skips", ea.autoSave(.focusLoss) == .skipped("disabled") && ir(a) == "a\n")
        AutoSave.focusLossEnabled = true
        check("autosave: focus loss saves a modified buffer", ea.autoSave(.focusLoss) == .saved && ir(a) == "a\nmore\n" && !ea.isDirty)
        check("autosave: clean buffer is skipped", ea.autoSave(.focusLoss) == .skipped("clean"))

        edit(ea, append: "tab\n")
        w.open(b)
        check("autosave: switching tabs saves the tab left behind", ir(a) == "a\nmore\ntab\n" && !ea.isDirty)
        edit(ea, append: "x\n")
        AutoSave.tabSwitchEnabled = false
        w.open(a)
        w.open(b)
        check("autosave: tab-switch toggle off leaves the buffer dirty", ea.isDirty && ir(a) == "a\nmore\ntab\n")
        AutoSave.tabSwitchEnabled = true
        w.open(a)
        w.autoSaveAll(.focusLoss)
        check("autosave: window-wide focus loss saves every dirty tab", ir(a) == "a\nmore\ntab\nx\n")

        // Never over a newer disk version: banner instead.
        edit(ea, append: "mine\n")
        external("agent wrote this\n", to: a)
        check("autosave: newer disk version is not overwritten",
              ea.autoSave(.focusLoss) == .skipped("disk newer") && ir(a) == "agent wrote this\n")
        check("autosave: dirty-vs-disk banner is shown", ea.isBannerVisible && ea.hasDiskConflict
              && ea.bannerButtons == ["Reload", "Keep mine", "Show diff"] && ea.textView.string.contains("mine"))
        check("autosave: stays out of the way while the conflict is open", ea.autoSave(.focusLoss) == .skipped("disk conflict"))
        w.autoSaveAll(.tabSwitch)
        check("autosave: window-wide triggers also respect the conflict", ir(a) == "agent wrote this\n")
        ea.pressBannerButton("Keep mine")
        check("autosave: after Keep mine auto-save may write", ea.autoSave(.focusLoss) == .saved && ir(a)?.contains("mine") == true)

        // IME composition.
        edit(ea, append: "typing\n")
        ea.textView.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let composing = ea.textView.hasMarkedText()
        let outcome = ea.autoSave(.focusLoss)
        check("autosave: never during IME composition", composing && outcome == .skipped("composing"))
        ea.textView.unmarkText()
        ea.textView.string = ea.textView.string.replacingOccurrences(of: "ni", with: "")
        ea.textView.didChangeText()
        check("autosave: resumes after composition", ea.autoSave(.focusLoss) == .saved)

        // Idle timer.
        AutoSave.idleSeconds = 30
        edit(ea, append: "idle\n")
        check("autosave: idle timer armed by an edit", ea.hasPendingIdleSave && AutoSave.enabled(for: .idle))
        AutoSave.idleSeconds = 0
        edit(ea, append: "idle2\n")
        check("autosave: idle off by default", !ea.hasPendingIdleSave && ea.autoSave(.idle) == .skipped("disabled"))
        ea.save()

        // Deleted file, read-only buffers, lossy decode.
        edit(ea, append: "gone\n")
        try? FileManager.default.removeItem(at: a)
        check("autosave: vanished file is not recreated silently",
              ea.autoSave(.focusLoss) == .skipped("missing on disk") && !FileManager.default.fileExists(atPath: a.path) && ea.isDeletedOnDisk)
        check("autosave: deleted banner offers Recreate / Save As / Close", ea.bannerButtons == ["Recreate", "Save As…", "Close"])
        ea.pressBannerButton("Recreate")
        check("autosave: Recreate writes the buffer back", ir(a)?.hasSuffix("gone\n") == true && !ea.isDirty && !ea.isBannerVisible)
        let hugeRO = base.appendingPathComponent("huge-auto.txt")
        try? Data(repeating: 0x61, count: 5_200_000).write(to: hugeRO)
        w.open(hugeRO)
        (w.tabs.entries.first { $0.id == hugeRO.standardizedFileURL.path }?.view as? LoadProblemView)?.perform(0)
        let ro = w.editors[hugeRO.standardizedFileURL.path]!
        check("autosave: truncated lossy read-only buffer is never saved", ro.isLossyDecoded && ro.isReadOnly
              && ro.autoSave(.focusLoss) == .skipped("clean") && !ro.save())
        w.close(hugeRO.standardizedFileURL.path)
        w.tabs.entries.map(\.id).forEach { w.close($0) }
    }

    // MARK: Symlinks, permissions, attributes, line endings, BOM

    private static func safeSaveChecks(w: ProjectWindow, base: URL) {
        let fm = FileManager.default
        let dir = base.appendingPathComponent("safe")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Symlinked file.
        let real = dir.appendingPathComponent("real.txt"), link = dir.appendingPathComponent("link.txt")
        iw("target\n", to: real)
        try? fm.createSymbolicLink(at: link, withDestinationURL: real)
        w.open(link)
        var ed = w.current!
        edit(ed, append: "via link\n")
        check("symlink: save succeeds", ed.save())
        check("symlink: the link is still a link and the target has the text", isSymlink(link) && ir(real) == "target\nvia link\n")
        external("changed by agent\n", to: real)
        ed.reloadIfChangedOnDisk()
        check("symlink: changes to the target are noticed through the link", ed.textView.string == "changed by agent\n")
        w.close(link.standardizedFileURL.path)

        // Symlinked directory.
        let realDir = dir.appendingPathComponent("realdir"), linkDir = dir.appendingPathComponent("linkdir")
        iw("inside\n", to: realDir.appendingPathComponent("f.txt"))
        try? fm.createSymbolicLink(at: linkDir, withDestinationURL: realDir)
        w.open(linkDir.appendingPathComponent("f.txt"))
        ed = w.current!
        edit(ed, append: "more\n")
        check("symlinked dir: save writes into the real directory", ed.save() && isSymlink(linkDir)
              && ir(realDir.appendingPathComponent("f.txt")) == "inside\nmore\n" && strays(in: realDir).isEmpty)
        w.close(linkDir.appendingPathComponent("f.txt").standardizedFileURL.path)

        // Dangling symlink is followed to its destination (recreated there).
        let dangling = dir.appendingPathComponent("dangling.txt"), destination = dir.appendingPathComponent("created-later.txt")
        try? fm.createSymbolicLink(atPath: dangling.path, withDestinationPath: "created-later.txt")
        check("symlink: resolve follows a dangling link", FileIO.resolve(dangling).lastPathComponent == "created-later.txt")
        check("symlink: FileIO.write through a dangling link creates the target",
              (try? FileIO.write(Data("hi\n".utf8), to: dangling)) != nil && isSymlink(dangling) && ir(destination) == "hi\n")

        // Permissions and attributes.
        let exec = dir.appendingPathComponent("run.sh")
        iw("#!/bin/sh\necho hi\n", to: exec)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)
        let attr = "com.example.ce-test"
        _ = setxattr(exec.path, attr, "v1", 2, 0, 0)
        w.open(exec)
        ed = w.current!
        edit(ed, append: "echo more\n")
        check("perms: save keeps the exec bit", ed.save() && posix(exec) == 0o755 && ir(exec)?.hasSuffix("echo more\n") == true)
        var buffer = [CChar](repeating: 0, count: 8)
        let got = getxattr(exec.path, attr, &buffer, 8, 0, 0)
        check("perms: extended attributes survive the save", got == 2 && String(cString: buffer) == "v1")
        let private600 = dir.appendingPathComponent("secret.txt")
        iw("s\n", to: private600)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: private600.path)
        try? FileIO.write(Data("t\n".utf8), to: private600)
        check("perms: 0600 stays 0600", posix(private600) == 0o600 && strays(in: dir).isEmpty)
        let fresh = dir.appendingPathComponent("fresh.txt")
        try? FileIO.write(Data("n\n".utf8), to: fresh)
        let mask = umask(0); umask(mask)
        check("perms: new files follow the umask", posix(fresh) == Int(0o666 & ~mask))
        w.close(exec.standardizedFileURL.path)

        // Directory that cannot hold a temp file: in-place fallback.
        let locked = dir.appendingPathComponent("locked")
        iw("v1\n", to: locked.appendingPathComponent("f.txt"))
        try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        let lockedWrite = (try? FileIO.write(Data("v2\n".utf8), to: locked.appendingPathComponent("f.txt"))) != nil
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        check("write: unwritable directory falls back to in-place and leaves no temp file",
              lockedWrite && ir(locked.appendingPathComponent("f.txt")) == "v2\n" && strays(in: locked).isEmpty)

        // CRLF + BOM.
        let crlfBom = dir.appendingPathComponent("crlfbom.txt")
        try? Data([0xEF, 0xBB, 0xBF] + Array("a\r\nb\r\n".utf8)).write(to: crlfBom)
        w.open(crlfBom)
        ed = w.current!
        check("bom: UTF-8 BOM is not part of the buffer", ed.hasBOM && !ed.textView.string.contains("\u{FEFF}") && ed.encodingName == "UTF-8 BOM"
              && ed.eol == .crlf)
        edit(ed, append: "c\n")
        check("bom: saving keeps BOM and CRLF", ed.save() && bytes(crlfBom) == [0xEF, 0xBB, 0xBF] + Array("a\r\nb\r\nc\r\n".utf8))
        w.close(crlfBom.standardizedFileURL.path)

        // Read-only file: banner offers Overwrite.
        let ro = dir.appendingPathComponent("readonly.txt")
        iw("ro\n", to: ro)
        try? fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: ro.path)
        w.open(ro)
        ed = w.current!
        edit(ed, append: "edit\n")
        check("readonly: save is refused, file untouched", !ed.save() && ir(ro) == "ro\n" && ed.isDirty)
        check("readonly: banner explains and offers Overwrite / Save As", ed.bannerMessage.contains("read-only") && ed.bannerButtons == ["Overwrite", "Save As…"])
        check("readonly: auto-save does not retry while the error is showing", ed.autoSave(.focusLoss) == .skipped("save error pending"))
        ed.pressBannerButton("Overwrite")
        check("readonly: Overwrite writes and keeps the file read-only", ir(ro) == "ro\nedit\n" && posix(ro) == 0o444 && !ed.isDirty
              && strays(in: dir).isEmpty)
        w.close(ro.standardizedFileURL.path)

        // File deleted (clean buffer) and replaced by a directory.
        let gone = dir.appendingPathComponent("gone.txt")
        iw("still here\n", to: gone)
        w.open(gone)
        ed = w.current!
        try? fm.removeItem(at: gone)
        ed.reloadIfChangedOnDisk()
        check("deleted: clean buffer keeps text and shows Recreate / Save As", ed.isDeletedOnDisk && ed.textView.string == "still here\n"
              && ed.bannerButtons == ["Recreate", "Save As…", "Close"])
        iw("is back\n", to: gone)
        ed.reloadIfChangedOnDisk()
        check("deleted: reappearing file reloads and clears the banner", !ed.isDeletedOnDisk && !ed.isBannerVisible && ed.textView.string == "is back\n")
        try? fm.removeItem(at: gone)
        try? fm.createDirectory(at: gone, withIntermediateDirectories: true)
        ed.reloadIfChangedOnDisk()
        check("directory: replaced-by-directory banner offers Save As", ed.bannerMessage.contains("directory") && ed.bannerButtons == ["Save As…"])
        edit(ed, append: "x\n")
        check("directory: save fails, directory untouched, no temp files", !ed.save() && FileIO.kind(gone) == .directory && strays(in: dir).isEmpty)
        let elsewhere = dir.appendingPathComponent("moved-away.txt")
        check("save as: retargets the tab and writes", w.saveEditor(ed, as: elsewhere) && ir(elsewhere) == "is back\nx\n"
              && w.editors[elsewhere.standardizedFileURL.path] === ed && w.editors[gone.standardizedFileURL.path] == nil && !ed.isDirty)
        w.close(elsewhere.standardizedFileURL.path)
        try? fm.removeItem(at: gone)
    }

    // MARK: Encodings

    private static func encodingRoundTripChecks(w: ProjectWindow, base: URL) {
        let dir = base.appendingPathComponent("enc")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // UTF-16 LE with BOM opens directly and round-trips.
        let u16 = dir.appendingPathComponent("u16.txt")
        let u16bytes: [UInt8] = [0xFF, 0xFE] + Array("héllo\n".utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        try? Data(u16bytes).write(to: u16)
        w.open(u16)
        var ed = w.current!
        w.refreshStatus()
        check("utf16: BOM detected, text decoded, name shown in the status bar",
              ed.textView.string == "héllo\n" && ed.encoding == .utf16LittleEndian && ed.encodingName == "UTF-16 LE" && w.statusBarEncoding == "UTF-16 LE")
        edit(ed, append: "!")
        check("utf16: saves back as UTF-16 LE with BOM", ed.save() && bytes(u16) == u16bytes + [0x21, 0x00])
        w.close(u16.standardizedFileURL.path)

        // Windows-1252, Shift-JIS and GB18030 via the placeholder; Reopen with encoding on an open tab.
        func openAs(_ name: String, _ raw: [UInt8], action: Int) -> EditorTab? {
            let url = dir.appendingPathComponent(name)
            try? Data(raw).write(to: url)
            w.open(url)
            let id = url.standardizedFileURL.path
            (w.tabs.entries.first { $0.id == id }?.view as? LoadProblemView)?.perform(action)
            return w.editors[id]
        }
        ed = openAs("cp1252.txt", [0x93, 0x68, 0x69, 0x94, 0x0A], action: 1)!
        check("cp1252: smart quotes decode (Latin-1 would show control characters)",
              ed.textView.string == "“hi”\n" && ed.encodingName == "Windows-1252")
        edit(ed, append: "x")
        check("cp1252: saved back in Windows-1252", ed.save() && bytes(ed.url) == [0x93, 0x68, 0x69, 0x94, 0x0A, 0x78])
        let sjis: [UInt8] = [0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA, 0x0A]
        ed = openAs("sjis.txt", sjis, action: 2)!
        check("sjis: opens as Shift-JIS and round-trips", ed.textView.string == "日本語\n" && ed.encodingName == "Shift-JIS"
              && { edit(ed, append: ""); ed.textView.string += "\n"; ed.textView.didChangeText(); return ed.save() && bytes(ed.url) == sjis + [0x0A] }())
        let gb: [UInt8] = [0xD6, 0xD0, 0xCE, 0xC4, 0x0A]
        ed = openAs("gb.txt", gb, action: 0)!
        check("reopen: placeholder Latin-1 first", ed.encoding == .isoLatin1)
        check("reopen: Reopen with encoding re-decodes as GB18030", w.reopenCurrentTab(encoding: TextEncodings.gb18030)
              && w.current!.textView.string == "中文\n" && w.current!.encodingName == "GB18030")
        w.refreshStatus()
        check("reopen: status bar shows the new encoding", w.statusBarEncoding == "GB18030")
        ed = w.current!
        check("reopen: untouched file is not rewritten", ed.save() && bytes(ed.url) == gb)
        check("reopen: undecodable choice keeps the tab", !w.reopenCurrentTab(encoding: .utf8) && w.current === ed)
        // Save with encoding.
        check("save-with-encoding: switches and marks dirty", w.setCurrentSaveEncoding(.utf16LittleEndian) && ed.isDirty && ed.encodingName == "UTF-16 LE")
        check("save-with-encoding: writes the chosen encoding with BOM", ed.save() && bytes(ed.url) == [0xFF, 0xFE, 0x2D, 0x4E, 0x87, 0x65, 0x0A, 0x00])
        w.close(ed.url.standardizedFileURL.path)

        // Unrepresentable characters never get silently dropped or re-encoded.
        let l1 = dir.appendingPathComponent("l1.txt")
        try? Data([0x63, 0x61, 0x66, 0xE9, 0x0A]).write(to: l1)
        w.open(l1)
        (w.tabs.entries.first { $0.id == l1.standardizedFileURL.path }?.view as? LoadProblemView)?.perform(0)
        ed = w.editors[l1.standardizedFileURL.path]!
        edit(ed, append: "日\n")
        check("encoding: unrepresentable character refuses to save", !ed.save() && bytes(l1) == [0x63, 0x61, 0x66, 0xE9, 0x0A]
              && ed.bannerMessage.contains("Latin-1") && ed.bannerButtons == ["Save as UTF-8", "Dismiss"])
        check("encoding: Save as UTF-8 is an explicit user choice", { ed.pressBannerButton("Save as UTF-8")
            return ir(l1) == "café\n日\n" && ed.encodingName == "UTF-8" }())
        w.close(l1.standardizedFileURL.path)
    }

    // MARK: Large files

    private static func largeFileChecks(w: ProjectWindow, base: URL) {
        let dir = base.appendingPathComponent("large")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let big = dir.appendingPathComponent("big.txt")
        try? Data(repeating: 0x61, count: 5_100_000).write(to: big)
        let id = big.standardizedFileURL.path
        w.open(big)
        let view = w.tabs.entries.first { $0.id == id }?.view as? LoadProblemView
        check("large: placeholder offers read-only and Open anyway",
              view?.actionTitles.prefix(2).map { $0 } == ["Open read-only (first 5 MB)", "Open anyway (editable, features off)"])
        view?.perform(0)
        var ed = w.editors[id]!
        check("large: truncated open is read-only, flagged large, with the 'too large' banner",
              ed.isReadOnly && ed.isLargeFile && ed.bannerMessage.hasPrefix("File too large to edit") && ed.bannerButtons == ["Open anyway"])
        ed.pressBannerButton("Open anyway")
        ed = w.editors[id]!
        check("large: Open anyway loads everything, editable, features-off flag set",
              !ed.isReadOnly && ed.isLargeFile && (ed.textView.string as NSString).length == 5_100_000 && ed.textView.isEditable)
        edit(ed, append: "z")
        check("large: auto-save skips large files, explicit save works", ed.autoSave(.focusLoss) == .skipped("large file") && ed.save()
              && bytes(big).count == 5_100_001)
        w.close(id)
        let normal = dir.appendingPathComponent("small.txt")
        iw("small\n", to: normal)
        w.open(normal)
        check("large: ordinary files are not flagged", w.current?.isLargeFile == false)
        w.close(normal.standardizedFileURL.path)
        let huge = dir.appendingPathComponent("huge.bin")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        if let h = try? FileHandle(forWritingTo: huge) { try? h.truncate(atOffset: 51_000_000); try? h.close() }
        w.open(huge)
        let hv = w.tabs.entries.first { $0.id == huge.standardizedFileURL.path }?.view as? LoadProblemView
        check("large: over 50 MB only offers the truncated read-only view", hv?.actionTitles == ["Open read-only (first 5 MB)", "Reveal in Finder"])
        w.close(huge.standardizedFileURL.path)
        try? FileManager.default.removeItem(at: huge)
        try? FileManager.default.removeItem(at: big)
    }

    // MARK: Local history

    private static func historyChecks(w: ProjectWindow, base: URL) {
        let fm = FileManager.default
        let savedLimits = (LocalHistory.maxRevisionsPerFile, LocalHistory.maxBytesPerFile, LocalHistory.maxTotalBytes)
        defer { (LocalHistory.maxRevisionsPerFile, LocalHistory.maxBytesPerFile, LocalHistory.maxTotalBytes) = savedLimits }
        let f = base.appendingPathComponent("hist.txt")
        iw("v0\n", to: f)
        let t0 = Date().addingTimeInterval(-1000)
        check("history: snapshot stores a revision", LocalHistory.snapshot(Data("one\n".utf8), of: f, now: t0))
        check("history: identical content is deduplicated", !LocalHistory.snapshot(Data("one\n".utf8), of: f, now: t0.addingTimeInterval(1))
              && LocalHistory.revisions(for: f).count == 1)
        LocalHistory.snapshot(Data("two\n".utf8), of: f, now: t0.addingTimeInterval(2))
        LocalHistory.snapshot(Data("one\n".utf8), of: f, now: t0.addingTimeInterval(3))
        let revs = LocalHistory.revisions(for: f)
        check("history: re-seen content moves to newest; newest first", revs.count == 2 && LocalHistory.text(of: revs[0]) == "one\n"
              && LocalHistory.text(of: revs[1]) == "two\n")
        check("history: files over 2 MB are skipped", !LocalHistory.snapshot(Data(repeating: 0x61, count: 2_000_001), of: f))
        LocalHistory.maxRevisionsPerFile = 3
        for i in 0..<6 { LocalHistory.snapshot(Data("rev \(i)\n".utf8), of: f, now: t0.addingTimeInterval(10 + Double(i))) }
        let capped = LocalHistory.revisions(for: f)
        check("history: keeps only the last N revisions per file", capped.count == 3 && LocalHistory.text(of: capped[0]) == "rev 5\n")
        LocalHistory.maxRevisionsPerFile = 50
        LocalHistory.maxBytesPerFile = 30
        for i in 0..<5 { LocalHistory.snapshot(Data(String(repeating: "x", count: 10 + i).utf8), of: f, now: t0.addingTimeInterval(100 + Double(i))) }
        check("history: per-file byte cap evicts the oldest", LocalHistory.revisions(for: f).reduce(0) { $0 + $1.size } <= 30
              && !LocalHistory.revisions(for: f).isEmpty)
        LocalHistory.maxBytesPerFile = 5_000_000
        let realRoot = LocalHistory.root
        LocalHistory.root = base.appendingPathComponent("hist-evict")
        defer { LocalHistory.root = realRoot }
        let g = base.appendingPathComponent("hist-other.txt")
        LocalHistory.snapshot(Data(String(repeating: "g", count: 500).utf8), of: g, now: t0.addingTimeInterval(500))
        LocalHistory.snapshot(Data(String(repeating: "f", count: 500).utf8), of: f, now: t0.addingTimeInterval(600))
        LocalHistory.evict(totalLimit: 600)
        let leftG = LocalHistory.revisions(for: g).count, leftF = LocalHistory.revisions(for: f)
        check("history: total cap evicts least-recently-used across files", leftG == 0 && leftF.first.map { LocalHistory.text(of: $0)?.hasPrefix("f") == true } == true)

        // Saving snapshots what was on disk; restore is one undoable edit.
        let r = base.appendingPathComponent("hist-save.txt")
        iw("first\n", to: r)
        w.open(r)
        let ed = w.current!
        edit(ed, append: "second\n")
        ed.save()
        check("history: a save keeps the previous disk text", LocalHistory.revisions(for: r).contains { LocalHistory.text(of: $0) == "first\n" })
        external("agent version\n", to: r)
        ed.reloadIfChangedOnDisk()
        check("history: an external reload keeps the replaced text", LocalHistory.revisions(for: r).contains { LocalHistory.text(of: $0) == "first\nsecond\n" })
        let first = LocalHistory.revisions(for: r).first { LocalHistory.text(of: $0) == "first\n" }!
        check("history: restore replaces the buffer and leaves it dirty",
              w.restoreRevision(first, into: ed, confirm: false) && ed.textView.string == "first\n" && ed.isDirty && ir(r) == "agent version\n")
        ed.textView.undoManager?.undo()
        check("history: restore is undoable", ed.textView.string == "agent version\n" || { fputs("DEBUG got \(ed.textView.string.debugDescription)\n", stderr); return false }())
        w.showLocalHistory()
        check("history: the picker lists revisions", !QuickPicker.shownTitles.isEmpty && QuickPicker.shownTitles.count == LocalHistory.revisions(for: r).count)
        QuickPicker.dismiss()
        w.close(r.standardizedFileURL.path)
        _ = fm
    }

    // MARK: Will-save hook chaining

    private static func hookChecks(w: ProjectWindow, base: URL) {
        let f = base.appendingPathComponent("hook.txt")
        iw("body\n", to: f)
        w.open(f)
        let ed = w.current!
        hookMode = "sync"; hookLog = []
        edit(ed, append: "typed\n")
        check("hooks: chained hooks run in order, hook edits are written", ed.save() && hookLog == ["h1", "h2"]
              && ir(f) == "body\ntyped\n// formatted\n" && !ed.isDirty)

        hookMode = "async"; hookLog = []; heldProceed = nil
        edit(ed, append: "more\n")
        var completed: Bool?
        let immediate = ed.save { completed = $0 }
        check("hooks: async hook defers the write", !immediate && completed == nil && hookLog == ["h1", "h2"] && ir(f) == "body\ntyped\n// formatted\n")
        check("hooks: a second save while one is pending is ignored", !ed.save() && hookLog == ["h1", "h2"])
        heldProceed?()
        check("hooks: proceed performs the write and reports it", completed == true && ir(f)?.hasSuffix("more\n// formatted\n") == true && !ed.isDirty)
        heldProceed?()
        check("hooks: a repeated proceed is ignored", ir(f)?.components(separatedBy: "// formatted").count == 3)

        hookLog = []; heldProceed = nil
        edit(ed, append: "auto\n")
        let outcome = ed.autoSave(.focusLoss)
        check("hooks: auto-save with an async hook is pending", outcome == .pending && ed.isDirty)
        external("agent beat the formatter\n", to: f)
        heldProceed?()
        check("hooks: disk changed while the formatter ran -> nothing overwritten, banner shown",
              ir(f) == "agent beat the formatter\n" && ed.hasDiskConflict && ed.isDirty)
        hookMode = "off"
        ed.pressBannerButton("Keep mine")
        ed.save()
        w.close(f.standardizedFileURL.path)
    }

    // MARK: PNGs of the banner states and the flash (CE_SELFTEST_PNG=<dir>)

    private static func renderStates(w: ProjectWindow, base: URL, outDir: String) {
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("shot.php")
        let text = "<?php\n\nclass Greeter\n{\n    public function hello(string $name): string\n    {\n        return \"Hello, $name\";\n    }\n}\n"
        iw(text, to: url)
        w.open(url)
        let ed = w.current!
        w.tabs.entries.map(\.id).filter { $0 != url.standardizedFileURL.path }.forEach { w.close($0) }
        w.window.setContentSize(NSSize(width: 1100, height: 420))
        func shot(_ name: String) {
            for (mode, suffix) in [(ThemeMode.light, "light"), (.dark, "dark")] {
                Theme.setMode(mode)
                Verification.render(w.window.contentView!, to: "\(outDir)/\(name)_\(suffix).png")
            }
            Theme.setMode(.system)
        }
        external(text.replacingOccurrences(of: "Hello, $name", with: "Hi there, $name!"), to: url)
        ed.reloadIfChangedOnDisk()
        shot("flash")
        edit(ed, append: "// mine\n")
        external("changed\n", to: url)
        ed.reloadIfChangedOnDisk()
        shot("conflict")
        ed.keepMine(); ed.save(overwriteNewer: true)
        try? FileManager.default.removeItem(at: url)
        ed.reloadIfChangedOnDisk()
        shot("deleted")
        iw(text, to: url)
        ed.reloadIfChangedOnDisk()
        try? FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        edit(ed, append: "// x\n")
        ed.save()
        shot("readonly")
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        let big = base.appendingPathComponent("shot-big.txt")
        try? Data(repeating: 0x61, count: 5_100_000).write(to: big)
        w.open(big)
        (w.tabs.entries.first { $0.id == big.standardizedFileURL.path }?.view as? LoadProblemView)?.perform(0)
        shot("toolarge")
        w.close(big.standardizedFileURL.path)
        try? FileManager.default.removeItem(at: big)
        w.close(url.standardizedFileURL.path)
    }
}
