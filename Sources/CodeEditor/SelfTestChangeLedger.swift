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

        a.remove(id: "n4")
        check("remove persists", ChangeLedger(root: root).sessions.contains { $0.id == "n4" } == false)
    }
}
