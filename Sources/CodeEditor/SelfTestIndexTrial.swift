import Foundation

/// CE_INDEX_TRIAL=<project root> CE_SELFTEST=1: what one saved file costs the project index, old way (full rescan + symbol rebuild)
/// against the hot-update way (applyChanges + one symbol re-parse), on a real project; then a correctness sweep on a throwaway tree.
extension SelfTest {
    static func indexTrial(root path: String) {
        // runs on a background thread (the main queue must stay free: the indexes deliver their results there)
        func wait(_ start: (@escaping () -> Void) -> Void) { let s = DispatchSemaphore(value: 0); start { s.signal() }; _ = s.wait(timeout: .now() + 120) }
        func ms(_ t0: CFAbsoluteTime) -> String { String(format: "%.1f ms", (CFAbsoluteTimeGetCurrent() - t0) * 1000) }
        let root = URL(fileURLWithPath: path)
        let idx = ProjectIndex(root: root)
        var t0 = CFAbsoluteTimeGetCurrent()
        wait { done in idx.refresh(force: true, completion: done) }
        fputs("TRIAL files: \(idx.files.count); full scan: \(ms(t0))\n", stderr)
        let sym = SymbolIndex(root: root, files: { idx.files })
        t0 = CFAbsoluteTimeGetCurrent()
        wait { done in sym.rebuild(completion: done) }
        fputs("TRIAL symbol rebuild (cold, parses everything): \(ms(t0)); entries \(sym.entries.count)\n", stderr)
        t0 = CFAbsoluteTimeGetCurrent()
        wait { done in sym.rebuild(completion: done) }
        let warm = ms(t0)
        t0 = CFAbsoluteTimeGetCurrent()
        wait { done in idx.refresh(force: true, completion: done) }
        fputs("TRIAL OLD per saved file: symbol rebuild (stat every file) \(warm) + full file scan \(ms(t0))\n", stderr)
        // NEW per saved file: one modified PHP file, then one that does not exist (as a delete would look)
        guard let php = idx.files.first(where: { $0.hasSuffix(".php") }) else { return }
        let abs = root.appendingPathComponent(php).path
        t0 = CFAbsoluteTimeGetCurrent()
        let d1 = idx.applyChanges([abs])
        let applyMs = ms(t0)
        t0 = CFAbsoluteTimeGetCurrent()
        wait { done in sym.update(files: d1?.touched ?? [], completion: done) }
        fputs("TRIAL NEW per saved file: applyChanges \(applyMs) (delta added \(d1?.added.count ?? -1) removed \(d1?.removed.count ?? -1)) + symbol update \(ms(t0))\n", stderr)
        t0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<20 { _ = idx.applyChanges([abs]) }
        fputs("TRIAL NEW warm applyChanges for one modified file: \(String(format: "%.2f ms", (CFAbsoluteTimeGetCurrent() - t0) * 1000 / 20))\n", stderr)
        check("trial: a modified file changes nothing in the list", d1 != nil && d1!.added.isEmpty && d1!.removed.isEmpty)

        // correctness on a throwaway tree: after every kind of change the hot-updated list must equal a fresh scan
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("ce-trial-\(getpid())")
        func write(_ rel: String, _ text: String = "<?php\n") {
            let u = tmp.appendingPathComponent(rel)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: u, atomically: true, encoding: .utf8)
        }
        for f in ["app/A.php", "app/Http/B.php", "app/Http/C.php", "resources/js/x.vue", "README.md"] { write(f) }
        let t = ProjectIndex(root: tmp)
        wait { done in t.refresh(force: true, completion: done) }
        func fresh() -> [String] {
            let f = ProjectIndex(root: tmp)
            wait { done in f.refresh(force: true, completion: done) }; return f.files
        }
        func same(_ label: String) {
            let a = t.files, b = fresh()
            check("trial: hot-updated list equals a fresh scan after \(label)", a == b)
            if a != b { fputs("TRIAL   hot \(a)\n   fresh \(b)\n", stderr) }
        }
        write("app/New.php"); _ = t.applyChanges([tmp.appendingPathComponent("app/New.php").path]); same("create")
        try? fm.removeItem(at: tmp.appendingPathComponent("app/A.php")); _ = t.applyChanges([tmp.appendingPathComponent("app/A.php").path]); same("delete")
        write("app/Models/User.php"); write("app/Models/Post.php")
        _ = t.applyChanges([tmp.appendingPathComponent("app/Models").path]); same("a new directory with files")
        try? fm.moveItem(at: tmp.appendingPathComponent("app/Models"), to: tmp.appendingPathComponent("app/Entities"))
        _ = t.applyChanges([tmp.appendingPathComponent("app/Models").path, tmp.appendingPathComponent("app/Entities").path]); same("renaming a directory")
        try? fm.removeItem(at: tmp.appendingPathComponent("app/Http"))
        _ = t.applyChanges([tmp.appendingPathComponent("app/Http").path]); same("deleting a directory")
        write("node_modules/p/i.js"); write("storage/logs/l.log")
        _ = t.applyChanges([tmp.appendingPathComponent("node_modules/p/i.js").path, tmp.appendingPathComponent("storage/logs/l.log").path]); same("changes in skipped directories")
        try? fm.removeItem(at: tmp)
    }
}
