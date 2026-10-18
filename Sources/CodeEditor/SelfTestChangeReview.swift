import AppKit

/// CE_SELFTEST checks for Claude change review: pure hunk accept / reject (LF, CRLF, no final newline), disk writes that keep
/// encoding and symlinks, baseline capture, memory caps, the store's accept / reject flows, the panel and the gutter wiring.
enum SelfTestChangeReview {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("review: " + name, ok()) }

    private static func wait(_ condition: @escaping () -> Bool, timeout: TimeInterval = 5, then next: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() || Date() > deadline { next(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: poll)
        }
        DispatchQueue.main.async(execute: poll)
    }

    static func run(w: ProjectWindow, then done: @escaping () -> Void) {
        pureChecks()
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ce-review-\(getpid())")
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        diskChecks(dir: dir)
        storeChecks(dir: dir) {
            gutterChecks(w: w, dir: dir) {
                try? fm.removeItem(at: dir)
                done()
            }
        }
    }

    // MARK: pure

    private static func pureChecks() {
        let two = "a\nb\nc\nd\ne\nf\n"
        let edited = "a\nB\nc\nd\ne\nf\ng\n"      // hunk 0: b -> B (old 1..<2), hunk 1: add g (old 6..<6)
        let hunks = GitGutter.hunks(old: two, new: edited)
        check("two hunks found", hunks.count == 2 && hunks[0].old == 1..<2 && hunks[1].old == 6..<6)
        check("counts", HunkActions.counts(baseline: two, current: edited) == (added: 2, removed: 1)
              && HunkActions.counts(baseline: two, current: two) == (0, 0))
        check("reject first hunk leaves the second", HunkActions.rejecting(old: 1..<2, baseline: two, current: edited) == "a\nb\nc\nd\ne\nf\ng\n")
        check("reject second hunk leaves the first", HunkActions.rejecting(old: 6..<6, baseline: two, current: edited) == "a\nB\nc\nd\ne\nf\n")
        let afterBoth = HunkActions.rejecting(old: 1..<2, baseline: two, current: edited).flatMap { HunkActions.rejecting(old: 6..<6, baseline: two, current: $0) }
        check("rejecting every hunk restores the baseline exactly", afterBoth == two)
        check("stale hunk is refused", HunkActions.rejecting(old: 3..<4, baseline: two, current: edited) == nil
              && HunkActions.accepting(old: 3..<4, baseline: two, current: edited) == nil)
        let accepted = HunkActions.accepting(old: 1..<2, baseline: two, current: edited)
        check("accept advances the baseline over one hunk", accepted == "a\nB\nc\nd\ne\nf\n"
              && HunkActions.counts(baseline: accepted ?? "", current: edited) == (added: 1, removed: 0))
        check("accepting every hunk makes baseline equal current",
              accepted.flatMap { HunkActions.accepting(old: 6..<6, baseline: $0, current: edited) } == edited)

        // CRLF
        let crlfBase = "a\r\nb\r\nc\r\n"
        let crlfNew = "a\r\nB\r\nc\r\nd\r\n"
        check("crlf: reject keeps CRLF endings", HunkActions.rejecting(old: 1..<2, baseline: crlfBase, current: crlfNew) == "a\r\nb\r\nc\r\nd\r\n")
        check("crlf: reject an insertion", HunkActions.rejecting(old: 3..<3, baseline: crlfBase, current: crlfNew) == "a\r\nB\r\nc\r\n")
        check("crlf: full reject equals baseline", HunkActions.rejecting(old: 1..<2, baseline: crlfBase, current: crlfNew)
              .flatMap { HunkActions.rejecting(old: 3..<3, baseline: crlfBase, current: $0) } == crlfBase)
        // LF baseline restored into a CRLF buffer takes the buffer's endings.
        check("crlf: LF baseline lines get the buffer's CRLF", HunkActions.rejecting(old: 1..<2, baseline: "a\nb\nc\n", current: "a\r\nB\r\nc\r\n") == "a\r\nb\r\nc\r\n")

        // no final newline
        check("eof: baseline w/o final newline, line appended", HunkActions.rejecting(old: 1..<2, baseline: "a\nb", current: "a\nb\nc") == "a\nb")
        check("eof: agent removed the final newline, reject restores it", HunkActions.rejecting(old: 1..<2, baseline: "a\nb\n", current: "a\nb") == "a\nb\n")
        check("eof: agent added a final newline, reject removes it", HunkActions.rejecting(old: 1..<2, baseline: "a\nb", current: "a\nb\n") == "a\nb")
        check("eof: deletion of the last line restores it", HunkActions.rejecting(old: 2..<3, baseline: "a\nb\nc\n", current: "a\nb\n") == "a\nb\nc\n")
        check("empty current restores whole baseline", HunkActions.rejecting(old: 0..<2, baseline: "a\nb\n", current: "") == "a\nb\n")
        check("empty baseline: reject removes everything", HunkActions.rejecting(old: 0..<0, baseline: "", current: "x\ny\n") == "")
    }

    // MARK: disk

    private static func diskChecks(dir: URL) {
        let fm = FileManager.default
        // UTF-16 LE with BOM keeps its encoding.
        let u16 = dir.appendingPathComponent("u16.txt")
        let body = "a\nb\n".data(using: .utf16LittleEndian)!
        try? (Data([0xFF, 0xFE]) + body).write(to: u16)
        let u16Edited = "a\nB\n".data(using: .utf16LittleEndian)!
        try? (Data([0xFF, 0xFE]) + u16Edited).write(to: u16)
        check("disk: hunk reject writes", HunkActions.rejectOnDisk(old: 1..<2, baseline: "a\nb\n", url: u16))
        let bytes = [UInt8](((try? Data(contentsOf: u16)) ?? Data()))
        check("disk: UTF-16 LE BOM kept", bytes.starts(with: [0xFF, 0xFE]) && HunkActions.readDisk(u16)?.text == "a\nb\n")

        // CRLF file on disk
        let crlf = dir.appendingPathComponent("crlf.txt")
        try? "a\r\nB\r\nc\r\n".write(to: crlf, atomically: true, encoding: .utf8)
        check("disk: crlf hunk reject", HunkActions.rejectOnDisk(old: 1..<2, baseline: "a\r\nb\r\nc\r\n", url: crlf)
              && (try? String(contentsOf: crlf)) == "a\r\nb\r\nc\r\n")

        // Symlink: the link stays a link, the target changes.
        let target = dir.appendingPathComponent("real.txt"), link = dir.appendingPathComponent("link.txt")
        try? "x\nNEW\n".write(to: target, atomically: true, encoding: .utf8)
        try? fm.removeItem(at: link)
        try? fm.createSymbolicLink(at: link, withDestinationURL: target)
        check("disk: symlinked file restore", HunkActions.writeDisk("x\nold\n", to: link)
              && (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil && (try? String(contentsOf: target)) == "x\nold\n")
        // Missing file is created (agent deleted it).
        let gone = dir.appendingPathComponent("sub/gone.txt")
        check("disk: restore recreates a deleted file", HunkActions.writeDisk("back\n", to: gone) && (try? String(contentsOf: gone)) == "back\n")
    }

    // MARK: store

    private static func write(_ text: String, _ url: URL) { try? text.write(to: url, atomically: true, encoding: .utf8) }

    private static func storeChecks(dir: URL, then next: @escaping () -> Void) {
        let fm = FileManager.default
        let root = dir.appendingPathComponent("proj")
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let a = root.appendingPathComponent("a.txt"), b = root.appendingPathComponent("b.txt"), c = root.appendingPathComponent("c.txt")
        write("1\n2\n3\n", a); write("x\r\ny\r\n", b); write("p\nq\n", c)
        let store = ChangeReviewStore(root: root)
        var clock = Date(timeIntervalSince1970: 1_000_000)
        store.now = { clock += 10; return clock }
        var agent: (id: Int, title: String)?
        store.activeAgent = { agent }
        var buffers: [String: String] = [:]
        store.preimage = { buffers[$0] }
        var headCalls = 0
        var heads: [String: String] = [:]
        store.headProvider = { headCalls += 1; return heads[$0.lastPathComponent] }
        var changes = 0
        store.onChange = { changes += 1 }
        let pa = VCSKind.canonical(a.standardizedFileURL.path), pb = VCSKind.canonical(b.standardizedFileURL.path), pc = VCSKind.canonical(c.standardizedFileURL.path)

        // No agent tab active: nothing is attributed.
        write("1\nTWO\n3\n", a)
        store.noteChanges([a.path]) {
            check("changes without an active agent tab are ignored", store.sessions.isEmpty)
            // Agent active, buffer pre-image known.
            agent = (7, "Claude Code")
            buffers[pa] = "1\n2\n3\n"
            store.noteChanges([a.path, root.appendingPathComponent(".git/index").path]) {
                let e = store.pendingEntry(pa)
                check("baseline captured from the open buffer", e?.baseline == "1\n2\n3\n" && e?.source == .preimage)
                check("session titled after the agent tab, +/- counted", store.sessions.count == 1 && store.sessions[0].title == "Claude Code" && e?.added == 1 && e?.removed == 1)
                check(".git paths are not tracked", store.sessions[0].entries.count == 1)
                check("timestamps recorded", (e?.first ?? .distantPast) > Date(timeIntervalSince1970: 1_000_000))
                write("1\nTWO\n3\n4\n", a)
                buffers[pa] = "SHOULD NOT REPLACE BASELINE"
                store.noteChanges([a.path]) {
                    let e2 = store.pendingEntry(pa)
                    check("second change keeps the first baseline and updates counts", e2?.baseline == "1\n2\n3\n" && e2?.added == 2 && e2?.removed == 1 && (e2?.last ?? .distantPast) > (e2?.first ?? .distantFuture))
                    // HEAD fallback when no buffer pre-image.
                    heads["b.txt"] = "x\r\ny\r\n"
                    write("x\r\nY\r\n", b)
                    store.noteChanges([b.path]) {
                        let eb = store.pendingEntry(pb)
                        check("HEAD is the fallback baseline", eb?.baseline == "x\r\ny\r\n" && eb?.source == .head && headCalls == 1)
                        // Untracked file: listed without baseline, never rejectable.
                        write("p\nq\nr\n", c)
                        store.noteChanges([c.path]) {
                            let ec = store.pendingEntry(pc)
                            check("no pre-image and no HEAD: listed without baseline", ec != nil && ec?.baseline == nil && ec?.note != nil)
                            check("rejecting a file without baseline fails and stays pending", ec.map { store.rejectFile($0) } == false && store.pendingEntry(pc) != nil)
                            finish()
                        }
                    }
                }
            }
        }

        func finish() {
            check("badge count", store.pendingFileCount == 3)
            // Accept one hunk of a.txt (the append), keep the other.
            let cur = (try? String(contentsOf: a)) ?? ""
            let hunks = GitGutter.hunks(old: store.pendingEntry(pa)?.baseline ?? "", new: cur)
            check("accept hunk advances baseline", hunks.count == 2 && store.acceptHunk(path: pa, old: hunks[1].old, current: cur)
                  && store.pendingEntry(pa)?.baseline == "1\n2\n3\n4\n" && store.pendingEntry(pa)?.added == 1)
            check("accepting a stale hunk fails", !store.acceptHunk(path: pa, old: 40..<41, current: cur))
            // Reject file b: restores the CRLF baseline exactly; the FS event of our own write does not relist it.
            let eb = store.pendingEntry(pb)!
            check("reject file restores baseline bytes", store.rejectFile(eb) && (try? String(contentsOf: b)) == "x\r\ny\r\n" && eb.state == .rejected && store.pendingEntry(pb) == nil)
            store.noteChanges([b.path]) {
                check("own restore is not recorded again", store.pendingEntry(pb) == nil)
                // Reject-all: a.txt restored, c.txt (no baseline) counts as failure.
                let failed = store.rejectAll()
                check("reject all restores files and reports the ones without baseline", failed == 1 && (try? String(contentsOf: a)) == "1\n2\n3\n4\n")
                check("accept all resolves what is left", { store.acceptAll(); return store.pendingFileCount == 0 }())
                check("accept drops the baseline (memory)", store.totalBaselineBytes == 0)
                check("onChange fired", changes > 5)
                store.clearResolved()
                check("clear removes resolved entries and empty sessions", store.sessions.isEmpty)
                bridgeAndCaps(store: store, root: root)
            }
        }

        func bridgeAndCaps(store: ChangeReviewStore, root: URL) {
            // Bridge edits: exact original, own session when no agent tab is active.
            agent = nil
            let d = root.appendingPathComponent("d.txt")
            store.recordBridgeEdit(url: d, original: "old\n", new: "new\nmore\n")
            let ed = store.pendingEntry(VCSKind.canonical(d.standardizedFileURL.path))
            check("bridge edit recorded with exact original", ed?.baseline == "old\n" && ed?.source == .bridge && store.sessions.first?.id == ChangeReviewStore.bridgeSessionID && ed?.added == 2 && ed?.removed == 1)
            check("bridge edit identical to original is not a change", { store.recordBridgeEdit(url: root.appendingPathComponent("same.txt"), original: "s\n", new: "s\n"); return store.sessions[0].entries.count == 1 }())

            // Caps.
            let capped = ChangeReviewStore(root: root)
            capped.activeAgent = { (1, "Agent") }
            ChangeReviewStore.maxFileBytes = 10
            capped.recordBridgeEdit(url: root.appendingPathComponent("big.txt"), original: "0123456789ABCDEF\n", new: "changed\n")
            check("file over the per-file cap keeps no baseline", capped.sessions[0].entries[0].baseline == nil && capped.sessions[0].entries[0].note != nil && capped.totalBaselineBytes == 0)
            ChangeReviewStore.maxFileBytes = 512 * 1024
            ChangeReviewStore.maxTotalBytes = 30
            for i in 0..<5 { capped.recordBridgeEdit(url: root.appendingPathComponent("t\(i).txt"), original: "aaaaaaaaaa\n", new: "b\n") }   // 11 bytes each
            check("total baseline bytes stay under the cap", capped.totalBaselineBytes <= 30 && capped.sessions[0].entries.count == 6)
            ChangeReviewStore.maxTotalBytes = 24 * 1024 * 1024
            ChangeReviewStore.maxFilesPerSession = 3
            let few = ChangeReviewStore(root: root)
            few.activeAgent = { (1, "Agent") }
            for i in 0..<6 { few.recordBridgeEdit(url: root.appendingPathComponent("f\(i).txt"), original: "o\n", new: "n\n") }
            check("files per session are capped", few.sessions[0].entries.count == 3)
            ChangeReviewStore.maxFilesPerSession = 200
            ChangeReviewStore.maxSessions = 2
            let many = ChangeReviewStore(root: root)
            var aid = 0
            many.activeAgent = { (aid, "Agent \(aid)") }
            for i in 1...4 { aid = i; many.recordBridgeEdit(url: root.appendingPathComponent("s\(i).txt"), original: "o\n", new: "n\n") }
            check("sessions are capped (oldest dropped)", many.sessions.count == 2 && many.sessions.map(\.id) == [3, 4])
            ChangeReviewStore.maxSessions = 12
            panelChecks(root: root, then: next)
        }

        func panelChecks(root: URL, then next: @escaping () -> Void) {
            let s = ChangeReviewStore(root: root)
            s.activeAgent = { (3, "Codex") }
            let p1 = root.appendingPathComponent("p1.txt"), p2 = root.appendingPathComponent("p2.txt")
            write("new1\n", p1); write("new2\n", p2)
            s.recordBridgeEdit(url: p1, original: "old1\n", new: "new1\n")
            s.recordBridgeEdit(url: p2, original: "old2\n", new: "new2\n")
            let panel = ChangeReviewPanel(store: s)
            s.onChange = { panel.reload() }
            panel.reload()
            check("panel lists a session row then its files", panel.rows.count == 3 && { if case .session = panel.rows[0] { return true } else { return false } }())
            var shown: String?
            panel.showDiff = { shown = $0.rel }
            panel.click(row: 0)
            check("clicking a session row opens no diff", shown == nil)
            panel.click(row: 1)
            check("clicking a file opens its diff", shown != nil)
            if case .file(_, let e) = panel.rows[1] {
                let c = panel.diffContents(for: e)
                check("diff shows baseline vs current", c.old.hasPrefix("old") && c.new.hasPrefix("new") && c.ext == "txt")
            }
            var asked = 0
            panel.confirm = { _ in asked += 1; return false }
            panel.reject(panel.rows[0])
            check("session reject asks first and honours Cancel", asked == 1 && s.pendingFileCount == 2 && (try? String(contentsOf: p1)) == "new1\n")
            panel.confirm = { _ in asked += 1; return true }
            panel.reject(panel.rows[0])
            check("session reject restores every file", s.pendingFileCount == 0 && (try? String(contentsOf: p1)) == "old1\n" && (try? String(contentsOf: p2)) == "old2\n")
            let rendered = ChangeReviewPanel.text(for: panel.rows[0]).string
            check("session row text names the agent", rendered.contains("Codex"))
            next()
        }
    }

    // MARK: gutter + window integration

    private static func gutterChecks(w: ProjectWindow, dir: URL, then next: @escaping () -> Void) {
        guard let store = w.changeReview else { check("window has a change review store", false); next(); return }
        check("window has store, panel and bottom tool", w.changeReviewPanel != nil && w.hasToolPanel("claude-changes"))
        let root = w.root ?? dir
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)   // the earlier checks removed it
        let file = root.appendingPathComponent("review-gutter.txt")
        write("one\ntwo\nthree\n", file)
        w.open(file)
        guard let tab = w.current, VCSKind.canonical(tab.url.standardizedFileURL.path) == VCSKind.canonical(file.standardizedFileURL.path) else { check("editor opened (\(w.current?.url.path ?? "nil") vs \(file.path))", false); next(); return }
        let path = tab.url.standardizedFileURL.path
        let savedAgent = store.activeAgent
        store.activeAgent = { (42, "Claude Code") }
        // The agent writes the file; the FS batch arrives before the editor reloads (as in ProjectWindow.processChanges).
        write("one\n2\nthree\nfour\n", file)
        store.noteChanges([file.path]) {
            let entry = store.pendingEntry(VCSKind.canonical(path))
            check("window store baselines from the clean editor buffer", entry?.baseline == "one\ntwo\nthree\n" && entry?.source == .preimage)
            check("panel badge shows pending count", w.changeReviewPanel != nil && store.pendingFileCount >= 1)
            tab.reloadIfChangedOnDisk()
            guard let c = GitGutter.controller(for: tab) else { check("git gutter controller exists for the tab", false); store.activeAgent = savedAgent; next(); return }
            wait({ c.reviewBaseline != nil && c.hunks.count == 2 }) {
                check("gutter compares against the review baseline", c.reviewBaseline == "one\ntwo\nthree\n" && c.hunks.count == 2)
                guard let h = c.hunks.first(where: { $0.old == 1..<2 }) else { check("hunk for the changed line", false); store.activeAgent = savedAgent; next(); return }
                // Reject in the gutter: buffer edit (undoable), saved to disk, entry shrinks.
                check("gutter reject applies", c.revert(h))
                check("gutter reject is one undo step", tab.textView.string == "one\ntwo\nthree\nfour\n" && tab.textView.undoManager?.canUndo == true)
                wait({ (try? String(contentsOf: file)) == "one\ntwo\nthree\nfour\n" && store.pendingEntry(VCSKind.canonical(path))?.added == 1 }) {
                    check("reject saved to disk and counts updated", (try? String(contentsOf: file)) == "one\ntwo\nthree\nfour\n" && store.pendingEntry(VCSKind.canonical(path))?.added == 1)
                    // Accept the remaining hunk through the same path the popover uses.
                    wait({ c.hunks.count == 1 }) {
                        if let h2 = c.hunks.first { c.onReviewAccept?(h2, tab.textView.string) }
                        check("gutter accept resolves the entry", store.pendingEntry(VCSKind.canonical(path)) == nil)
                        wait({ c.reviewBaseline == nil }) {
                            check("gutter falls back to HEAD when nothing is pending", c.reviewBaseline == nil)
                            store.activeAgent = savedAgent
                            store.clearResolved()
                            w.close(path)
                            next()
                        }
                    }
                }
            }
        }
    }
}
