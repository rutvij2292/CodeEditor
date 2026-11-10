import AppKit

/// CE_SELFTEST: the change ledger (store, recording on accept, panel).
enum SelfTestChangeLedger {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("ledger: " + name, ok()) }

    static func sym(_ name: String, line: Int = 1, add: Int = 1, rem: Int = 0) -> LedgerSymbol {
        LedgerSymbol(name: name, kind: "method", line: line, added: add, removed: rem, isNewFile: false)
    }
    static func file(_ rel: String, _ symbols: [LedgerSymbol] = []) -> LedgerFile {
        LedgerFile(rel: rel, added: symbols.reduce(0) { $0 + $1.added }, removed: symbols.reduce(0) { $0 + $1.removed }, symbols: symbols)
    }

    static func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("kode-ledger-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func run(w: ProjectWindow) {
        runStore()
        runAccept(w: w)
        runPanel(w: w)
    }

    static func runStore() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = (ChangeLedger.directory, ChangeLedger.maxSessions, ChangeLedger.maxBytes)
        defer { (ChangeLedger.directory, ChangeLedger.maxSessions, ChangeLedger.maxBytes) = saved }
        ChangeLedger.directory = dir
        let root = URL(fileURLWithPath: "/tmp/proj-a")
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        let a = ChangeLedger(root: root)
        a.record(id: "s1", title: "Add soft delete", started: t0, files: [file("app/A.php", [sym("delete")])], note: "soft delete for invoices", now: t0)
        let b = ChangeLedger(root: root)
        check("persists across instances", b.sessions.count == 1 && b.sessions[0].title == "Add soft delete" && b.sessions[0].note == "soft delete for invoices"
              && b.sessions[0].files[0].symbols[0].name == "delete")
        check("different projects use different files", ChangeLedger(root: URL(fileURLWithPath: "/tmp/proj-b")).sessions.isEmpty
              && ChangeLedger(root: root).fileURL != ChangeLedger(root: URL(fileURLWithPath: "/tmp/proj-b")).fileURL)

        a.record(id: "s1", title: "Add soft delete", started: t0, files: [file("app/B.php"), file("app/A.php", [sym("restore")])], note: "and restore", now: t0.addingTimeInterval(60))
        let m = a.sessions[0]
        check("same session merges: files by rel, notes joined, updated moves", a.sessions.count == 1 && m.files.map { $0.rel }.sorted() == ["app/A.php", "app/B.php"]
              && m.files.first { $0.rel == "app/A.php" }?.symbols.first?.name == "restore" && m.note == "soft delete for invoices\nand restore" && m.updated == t0.addingTimeInterval(60))
        a.record(id: "s1", title: "Add soft delete", started: t0, files: [], note: "", now: t0.addingTimeInterval(90))
        check("empty note adds nothing", a.sessions[0].note == "soft delete for invoices\nand restore")

        let long = String(repeating: "x", count: 2100)
        a.record(id: "s2", title: "t", started: t0, files: [], note: long, now: t0.addingTimeInterval(100))
        check("note is capped at 2,000 chars", a.sessions.first { $0.id == "s2" }?.note.count == 2000)
        let odd = "line1\nline2 🙂 ünï"
        a.setNote(odd, for: "s2")
        check("newlines and unicode round-trip", ChangeLedger(root: root).sessions.first { $0.id == "s2" }?.note == odd)
        a.record(id: "s3", title: String(repeating: "T", count: 300), started: t0, files: [file("f.php", (0..<50).map { sym("m\($0)") })], note: "", now: t0.addingTimeInterval(110))
        let s3 = a.sessions.first { $0.id == "s3" }
        check("title capped at 200, symbols at 40 per file", s3?.title.count == 200 && s3?.files[0].symbols.count == 40)
        check("searchText has lowercased note and symbol names", a.sessions.first { $0.id == "s1" }!.searchText.contains("soft delete for invoices")
              && s3!.searchText.contains("m39") && a.sessions.first { $0.id == "s1" }!.searchText.contains("restore"))

        ChangeLedger.maxSessions = 3
        for i in 0..<5 { a.record(id: "n\(i)", title: "n\(i)", started: t0, files: [], note: "", now: t0.addingTimeInterval(200 + Double(i))) }
        check("session count capped, newest kept", a.sessions.map { $0.id } == ["n4", "n3", "n2"] && ChangeLedger(root: root).sessions.count == 3)
        ChangeLedger.maxSessions = 300

        ChangeLedger.maxBytes = 2000
        let c = ChangeLedger(root: URL(fileURLWithPath: "/tmp/proj-c"))
        for i in 0..<60 { c.record(id: "c\(i)", title: "session \(i)", started: t0, files: [file("f\(i).php", [sym("method\(i)")])], note: "note \(i)", now: t0.addingTimeInterval(Double(i))) }
        let size = (try? FileManager.default.attributesOfItem(atPath: c.fileURL.path)[.size] as? Int) ?? 0
        check("saved file never exceeds maxBytes; newest kept", size > 0 && size <= 2000 && c.sessions.first?.id == "c59")
        ChangeLedger.maxBytes = 256 * 1024

        let bad = ChangeLedger(root: URL(fileURLWithPath: "/tmp/proj-bad"))
        try? "{not json".write(to: bad.fileURL, atomically: true, encoding: .utf8)
        check("corrupt file loads empty and is kept as .bak", bad.sessions.isEmpty
              && FileManager.default.fileExists(atPath: bad.fileURL.path + ".bak"))
        let future = ChangeLedger(root: URL(fileURLWithPath: "/tmp/proj-future"))
        try? #"{"version":99,"sessions":[]}"#.write(to: future.fileURL, atomically: true, encoding: .utf8)
        check("future version loads empty and is kept as .bak", future.sessions.isEmpty && FileManager.default.fileExists(atPath: future.fileURL.path + ".bak"))
        let empty = ChangeLedger(root: URL(fileURLWithPath: "/tmp/proj-empty"))
        try? Data().write(to: empty.fileURL)
        check("empty file loads empty without crashing", empty.sessions.isEmpty)

        // Over the byte cap: bulky symbol rows go before anyone's notes
        ChangeLedger.maxBytes = 30_000
        let big = ChangeLedger(root: URL(fileURLWithPath: "/tmp/proj-big"))
        for i in 0..<5 { big.record(id: "old\(i)", title: "old \(i)", started: t0, files: [file("f\(i).php", [sym("m\(i)")])], note: "my note \(i)", now: t0.addingTimeInterval(Double(i))) }
        big.record(id: "huge", title: "huge refactor", started: t0, files: (0..<200).map { f in file("app/F\(f).php", (0..<40).map { sym("method\($0)", line: $0) }) }, note: "", now: t0.addingTimeInterval(100))
        let bigSize = (try? FileManager.default.attributesOfItem(atPath: big.fileURL.path)[.size] as? Int) ?? 0
        let reloaded = ChangeLedger(root: URL(fileURLWithPath: "/tmp/proj-big"))
        check("over the cap, a huge session never wipes older sessions or their notes",
              bigSize > 0 && bigSize <= 30_000 && reloaded.sessions.first?.id == "huge" && (0..<5).allSatisfy { i in reloaded.sessions.first { $0.id == "old\(i)" }?.note == "my note \(i)" })
        ChangeLedger.maxBytes = 256 * 1024

        // A read failure must not let the next write replace a good ledger
        let ro = ChangeLedger(root: URL(fileURLWithPath: "/tmp/proj-ro"))
        ro.record(id: "keep", title: "keep me", started: t0, files: [], note: "precious", now: t0)
        let original = try? Data(contentsOf: ro.fileURL)
        chmod(ro.fileURL.path, 0o000)
        let blind = ChangeLedger(root: URL(fileURLWithPath: "/tmp/proj-ro"))
        blind.record(id: "new", title: "new", started: t0, files: [], note: "", now: t0.addingTimeInterval(5))
        chmod(ro.fileURL.path, 0o644)
        check("unreadable ledger file is never overwritten", (try? Data(contentsOf: ro.fileURL)) == original)
        blind.reload()
        check("after a successful reload the ledger works again", blind.sessions.contains { $0.id == "keep" } && !blind.sessions.contains { $0.id == "new" })

        let twice = ChangeLedger(root: URL(fileURLWithPath: "/tmp/proj-twice"))
        try? "{bad one".write(to: twice.fileURL, atomically: true, encoding: .utf8)
        _ = twice.sessions
        try? "{bad two".write(to: twice.fileURL, atomically: true, encoding: .utf8)
        twice.reload()
        check("a second corrupt file does not destroy the first .bak",
              (try? String(contentsOfFile: twice.fileURL.path + ".bak", encoding: .utf8)) == "{bad one" && (try? String(contentsOfFile: twice.fileURL.path + ".bak-1", encoding: .utf8)) == "{bad two")

        a.remove(id: "n4")
        check("remove persists", ChangeLedger(root: root).sessions.contains { $0.id == "n4" } == false)
    }

    static func runAccept(w: ProjectWindow) {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        func write(_ t: String, _ name: String) -> URL {
            let u = dir.appendingPathComponent(name)
            try? t.write(to: u, atomically: true, encoding: .utf8)
            return u
        }
        // Hook on the store
        let store = ChangeReviewStore(root: dir)
        store.activeAgent = { (1, "Agent one") }
        var calls: [(ChangeReviewStore.Session, [ChangeReviewStore.AcceptedFile], String)] = []
        store.onAccept = { s, f, n in calls.append((s, f, n)) }
        let f1 = write("new1\nx\n", "f1.txt"), f2 = write("n2\n", "f2.txt"), f3 = write("n3\n", "f3.txt")
        store.recordBridgeEdit(url: f1, original: "old1\nx\n", new: "new1\nx\n")
        store.acceptNote = "why f1"
        store.acceptFile(store.sessions[0].entries[0])
        check("accept hook: fires once with the baseline captured before it is cleared",
              calls.count == 1 && calls[0].1.count == 1 && calls[0].1[0].baseline == "old1\nx\n" && calls[0].1[0].rel == "f1.txt"
              && calls[0].1[0].added == 1 && calls[0].1[0].removed == 1 && store.sessions[0].entries[0].state == .accepted && store.sessions[0].entries[0].baseline == nil)
        check("accept hook: note is passed and reset", calls[0].2 == "why f1" && store.acceptNote == "")
        store.acceptFile(store.sessions[0].entries[0])
        check("accept hook: nothing for an already accepted entry", calls.count == 1)
        store.recordBridgeEdit(url: f2, original: "o2\n", new: "n2\n")
        store.recordBridgeEdit(url: f3, original: "o3\n", new: "n3\n")
        store.acceptAll(in: store.sessions[0])
        check("accept hook: acceptAll(in:) fires once for the whole batch", calls.count == 2 && calls[1].1.count == 2)
        var changeCount = 0
        store.onChange = { changeCount += 1 }
        let other = ChangeReviewStore(root: dir)
        var n2 = 0
        other.onAccept = { _, _, _ in n2 += 1 }
        var agent = 1
        other.activeAgent = { (agent, "A\(agent)") }
        for i in 1...2 { agent = i; other.recordBridgeEdit(url: dir.appendingPathComponent("o\(i).txt"), original: "o\n", new: "n\n") }
        other.acceptAll()
        let ns = CommitLedger.files(fromNumstat: "3\t1\tapp/A.php\n-\t-\timg/logo.png\n")
        check("commit ledger: numstat parsed (binary counts as 0)", ns.count == 2 && ns[0].rel == "app/A.php" && ns[0].added == 3 && ns[0].removed == 1 && ns[1].added == 0)
        check("accept hook: acceptAll() fires once for the current session (earlier agent sessions are retired)", n2 == 1)

        // Recorder (pure)
        let row = { (name: String, line: Int) in ChangedSymbols.Row(path: "/p/a.php", rel: "a.php", name: name, kind: .method, line: line, added: 3, removed: 1) }
        let af = ChangeReviewStore.AcceptedFile(path: "/p/a.php", rel: "a.php", baseline: "x", added: 6, removed: 2)
        let lf = LedgerRecorder.file(af, rows: [row("total", 4), row("label", 9)])
        check("recorder: symbols from rows", lf.rel == "a.php" && lf.symbols.map { $0.name } == ["total", "label"] && lf.symbols[0].line == 4 && lf.symbols[0].kind == "method"
              && lf.symbols[0].added == 3 && lf.symbols[0].removed == 1 && lf.added == 6 && lf.removed == 2)
        let plain = LedgerRecorder.file(af, rows: [ChangedSymbols.Row(path: "/p/a.txt", rel: "a.txt", name: "(file level)", kind: nil, line: 1, added: 2, removed: 0)])
        check("recorder: the '(file level)' pseudo row is not a symbol", plain.symbols.isEmpty && plain.added == 6)
        let none = LedgerRecorder.file(ChangeReviewStore.AcceptedFile(path: "/p/b.png", rel: "b.png", baseline: nil, added: 5, removed: 0), rows: [])
        check("recorder: no baseline keeps file-level counts, no symbols", none.symbols.isEmpty && none.added == 5)
        let s1 = ChangeReviewStore.Session(id: 1, title: "t", started: Date(timeIntervalSince1970: 100))
        let s2 = ChangeReviewStore.Session(id: 1, title: "t", started: Date(timeIntervalSince1970: 200))
        check("recorder: session id is stable and distinguishes restarts", LedgerRecorder.sessionID(s1) == LedgerRecorder.sessionID(s1) && LedgerRecorder.sessionID(s1) != LedgerRecorder.sessionID(s2))

        // End to end on a real file: the changed method becomes a ledger symbol
        let old = "<?php\nclass Invoice\n{\n    public function total(): int\n    {\n        return 1;\n    }\n\n    public function label(): string\n    {\n        return 'a';\n    }\n}\n"
        let new = "<?php\nclass Invoice\n{\n    public function total(): int\n    {\n        $x = 2;\n        return $x;\n    }\n\n    public function label(): string\n    {\n        return 'a';\n    }\n}\n"
        let php = write(new, "Invoice.php")
        let saved = ChangeLedger.directory
        let originalLedger = w.changeLedger
        defer { ChangeLedger.directory = saved; w.changeLedger = originalLedger }
        ChangeLedger.directory = dir.appendingPathComponent("ledger")
        let ledger = ChangeLedger(root: dir)
        w.changeLedger = ledger
        let e2e = ChangeReviewStore(root: dir)
        e2e.activeAgent = { (9, "Add totals") }
        let q = DispatchQueue(label: "kode.selftest.ledger")
        let sem = DispatchSemaphore(value: 0)
        e2e.onAccept = { s, files, note in w.recordLedger(session: s, files: files, note: note, deliverOn: q) { sem.signal() } }
        e2e.recordBridgeEdit(url: php, original: old, new: new)
        e2e.acceptNote = "totals now go through $x"
        e2e.acceptAll()
        let finished = sem.wait(timeout: .now() + 30) == .success
        let rec = q.sync { ledger.sessions.first }
        check("end to end: accepted change lands in the ledger with title, note and the changed method",
              finished && rec?.title == "Add totals" && rec?.note == "totals now go through $x"
              && rec?.files.first?.symbols.contains { $0.name.contains("total") } == true && rec?.files.first?.rel == "Invoice.php")
    }

    static func runPanel(w: ProjectWindow) {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let saved = ChangeLedger.directory
        defer { ChangeLedger.directory = saved }
        ChangeLedger.directory = dir
        let root = URL(fileURLWithPath: "/tmp/proj-panel")
        let ledger = ChangeLedger(root: root)
        let t1 = Date(timeIntervalSince1970: 1_800_000_000), t2 = t1.addingTimeInterval(86_400)
        ledger.record(id: "old", title: "Add soft delete to invoices", started: t1, files: [file("app/Invoice.php", [sym("delete", line: 12), sym("restore", line: 30)]), file("app/Other.php")],
                      note: "invoices are never really deleted now", now: t1)
        ledger.record(id: "new", title: "Refactor mailer", started: t2, files: [file("app/Mailer.php", [sym("send", line: 5, add: 4, rem: 2)])], note: "", now: t2)
        let panel = ChangeLedgerPanel(ledger: ledger, root: root)
        panel.reload()
        let rows = panel.rowDescriptions
        check("panel: newest session first, with file and symbol counts",
              rows.count == 2 && rows[0].contains("Refactor mailer") && rows[0].contains("1 file · 1 symbol") && rows[1].contains("Add soft delete to invoices") && rows[1].contains("2 files · 2 symbols"))
        check("panel: note preview in the row", rows[1].contains("invoices are never really deleted now") && !rows[0].contains(" — "))
        check("panel: selecting a session shows its note and symbols", panel.selectSession(id: "old") && panel.noteText == "invoices are never really deleted now"
              && panel.symbolRowDescriptions == ["FILE app/Invoice.php +2 −0", "  delete :12 +1 −0", "  restore :30 +1 −0", "FILE app/Other.php +0 −0"])
        panel.setNoteText("soft delete: rows get deleted_at, never removed")
        panel.commitNote()
        check("panel: edited note is saved to the ledger file", ChangeLedger(root: root).sessions.first { $0.id == "old" }?.note == "soft delete: rows get deleted_at, never removed")
        check("panel: editing a note does not reorder the sessions", panel.rowDescriptions[0].contains("Refactor mailer"))
        let all = [ledger.sessions[0], ledger.sessions[1]]
        check("search: matches title, note, file and symbol names, case-insensitively",
              ChangeLedgerPanel.filter(all, query: "MAILER").map { $0.id } == ["new"] && ChangeLedgerPanel.filter(all, query: "deleted_at").map { $0.id } == ["old"]
              && ChangeLedgerPanel.filter(all, query: "restore").map { $0.id } == ["old"] && ChangeLedgerPanel.filter(all, query: "Invoice.php").map { $0.id } == ["old"]
              && ChangeLedgerPanel.filter(all, query: "  ").count == 2 && ChangeLedgerPanel.filter(all, query: "zzz").isEmpty)
        var opened: (URL, Int)?
        panel.openFile = { opened = ($0, $1) }
        _ = panel.selectSession(id: "old")
        panel.openSymbol(row: 1)
        check("panel: opening a symbol jumps to its file and line", opened?.0.path == "/tmp/proj-panel/app/Invoice.php" && opened?.1 == 12)
        panel.openSymbol(row: 0)
        check("panel: opening a file row opens it at line 1", opened?.1 == 1)
        let empty = ChangeLedgerPanel(ledger: ChangeLedger(root: URL(fileURLWithPath: "/tmp/proj-none")), root: URL(fileURLWithPath: "/tmp/proj-none"))
        empty.reload()
        check("panel: empty ledger explains how to start it", empty.rowDescriptions.isEmpty && empty.emptyText.contains("Accept"))

        // Note field in Claude Changes
        let store = ChangeReviewStore(root: dir)
        store.activeAgent = { (4, "Agent four") }
        var seen: String?
        store.onAccept = { _, _, note in seen = note }
        let f = dir.appendingPathComponent("n.txt")
        try? "new\n".write(to: f, atomically: true, encoding: .utf8)
        store.recordBridgeEdit(url: f, original: "old\n", new: "new\n")
        let cr = ChangeReviewPanel(store: store)
        cr.noteField.stringValue = "  it renames the thing  "
        cr.accept(cr.rows[1])
        check("claude changes: the note is attached to the accept and the field clears", seen == "it renames the thing" && cr.noteField.stringValue == "")
        let g = dir.appendingPathComponent("m.txt")
        try? "x\n".write(to: g, atomically: true, encoding: .utf8)
        store.recordBridgeEdit(url: g, original: "y\n", new: "x\n")
        cr.reload()
        cr.acceptAllPending()
        check("claude changes: accepting with an empty field records an empty note", seen == "")

        // Notes are never silently dropped
        let session = store.sessions[0]
        let done = session.entries[0]
        check("claude changes: precondition, entry already accepted", done.state == .accepted)
        seen = "untouched"
        cr.noteField.stringValue = "keep me"
        cr.accept(.file(session, done))
        check("claude changes: accepting something already accepted keeps the note and fires nothing", cr.noteField.stringValue == "keep me" && seen == "untouched")
        cr.acceptAllPending()
        check("claude changes: Accept All with nothing pending keeps the note", cr.noteField.stringValue == "keep me" && seen == "untouched")
        let h = dir.appendingPathComponent("h.txt")
        try? "hh\n".write(to: h, atomically: true, encoding: .utf8)
        store.recordBridgeEdit(url: h, original: "h\n", new: "hh\n")
        cr.reload()
        cr.noteFieldReturned()
        check("claude changes: Return in the note field with nothing selected accepts nothing", store.pendingFileCount == 1 && cr.noteField.stringValue == "keep me")

        // A typed ledger note survives closing the window
        if let wp = w.changeLedgerPanel {
            wp.ledger.record(id: "close-test", title: "close test", started: Date(), files: [], note: "before", now: Date())
            wp.reload()
            _ = wp.selectSession(id: "close-test")
            wp.setNoteText("typed just before quitting")
            w.commitPendingNotes()
            check("ledger panel: a typed note is saved by commitPendingNotes (window close / quit)",
                  ChangeLedger(root: w.root!).sessions.first { $0.id == "close-test" }?.note == "typed just before quitting")
            wp.ledger.remove(id: "close-test")
        } else { check("ledger panel: window has a ledger panel", false) }

        check("wiring: the Ledger tool window is registered", w.hasToolPanel("ledger") && w.changeLedgerPanel != nil)

        if let prefix = ProcessInfo.processInfo.environment["CE_LEDGER_SNAPSHOT"] {
            _ = panel.selectSession(id: "old")
            panel.snapshot(to: prefix + "-ledger.png")
        }
    }
}
