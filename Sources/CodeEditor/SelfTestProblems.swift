import AppKit

/// CE_SELFTEST: Problems panel — grouping, Claude evaluation parsing/cache, project scan, tabs and detail pane.
enum SelfTestProblems {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("problems: " + name, ok()) }

    static func diag(_ sev: Int = 2, _ msg: String, line: Int = 1, source: String? = nil, code: String? = nil) -> FileProblems.Diagnostic {
        FileProblems.Diagnostic(severity: sev, message: msg, line: line, column: 1, endLine: line, endColumn: 2, source: source, code: code)
    }

    static func run(w: ProjectWindow) {
        runGrouping()
        runEvaluator()
        runScanner()
        runPanel()
        runApplyFix(w: w)
    }

    static func runGrouping() {
        let a = FileProblems(url: URL(fileURLWithPath: "/p/a.php"), diagnostics: [
            diag(2, "Unused import X", source: "PHP", code: "unused-import"),
            diag(1, "Undefined variable $x", line: 4, source: "intelephense", code: "P1008"),
            diag(2, "Unused import Y", line: 2, source: "PHP", code: "unused-import")])
        let b = FileProblems(url: URL(fileURLWithPath: "/p/b.js"), diagnostics: [
            diag(2, "Something odd happened here in this file for sure", source: nil, code: nil),
            diag(1, "Unexpected token", source: "JS", code: "syntax")])
        let g = ProblemGrouping.group([a, b])
        check("grouping: categories sorted", g.map { $0.category } == ["General", "JavaScript", "PHP"])
        let php = g.first { $0.category == "PHP" }
        check("grouping: PHP inspections sorted by name", php?.inspections.map { $0.name } == ["P1008", "unused-import"])
        check("grouping: items counted", php?.inspections.first { $0.name == "unused-import" }?.items.count == 2)
        check("grouping: general uses first 40 chars of message", g.first { $0.category == "General" }?.inspections.first?.name == String("Something odd happened here in this file for sure".prefix(40)))
        check("grouping: intelephense maps to PHP, JS to JavaScript", ProblemGrouping.category(for: diag(1, "x", source: "intelephense")) == "PHP" && ProblemGrouping.category(for: diag(1, "x", source: "JS")) == "JavaScript")
    }

    static func ref(_ id: Int, text: String? = "a\nb\nc\nd") -> ProblemRef {
        ProblemRef(id: id, url: URL(fileURLWithPath: "/p/app/A.php"), relPath: "app/A.php", d: diag(2, "Unused import X\(id)", line: 2, source: "PHP", code: "unused-import"), fileText: text)
    }

    static func runEvaluator() {
        let json = #"[{"id":1,"verdict":"real","difficulty":"easy","explanation":"Remove it","oldText":"use X;","newText":""},{"id":2,"verdict":"false_positive","difficulty":"hard","explanation":"Used by magic"}]"#
        let a = ProblemEvaluator.parse(json, ids: [1, 2])
        check("parse: bare array", a.count == 2 && a[1]?.verdict == .real && a[1]?.difficulty == .easy && a[1]?.oldText == "use X;" && a[1]?.newText == "" && a[2]?.verdict == .falsePositive && a[2]?.oldText == nil)
        let fenced = "Sure!\n```json\n" + json + "\n```\nHope that helps [1]."
        check("parse: fenced with prose", ProblemEvaluator.parse(fenced, ids: [1, 2]).count == 2)
        check("parse: missing id and unknown id", ProblemEvaluator.parse(json, ids: [1, 3]).keys.sorted() == [1])
        check("parse: invalid enum drops entry", ProblemEvaluator.parse(#"[{"id":1,"verdict":"maybe","difficulty":"easy","explanation":"x"}]"#, ids: [1]).isEmpty)
        check("parse: garbage", ProblemEvaluator.parse("I cannot help", ids: [1]).isEmpty && ProblemEvaluator.parse("[not json]", ids: [1]).isEmpty)
        let p = ProblemEvaluator.prompt([ref(1), ref(2)])
        check("prompt: ids, location, message, snippet, JSON-only", p.contains("Problem 1") && p.contains("Problem 2"))
        check("prompt: carries path:line and message", p.contains("app/A.php:2") && p.contains("Unused import X2") && p.contains("```") && p.lowercased().contains("only"))
        var failed = ""
        ProblemEvaluator.evaluate((1...21).map { ref($0) }) { r in if case .failure(let f) = r { failed = f.message } }
        check("evaluate: over 20 problems fails mentioning 20", failed.contains("20"))
        check("fingerprint: stable, changes with line text", ProblemEvaluator.fingerprint(ref(1)) == ProblemEvaluator.fingerprint(ref(1)) && ProblemEvaluator.fingerprint(ref(1)) != ProblemEvaluator.fingerprint(ref(1, text: "a\nCHANGED\nc")))
        let cache = ProblemAnswerCache()
        let ans = ProblemAnswer(verdict: .real, difficulty: .easy, explanation: "e", oldText: nil, newText: nil)
        for i in 0...200 { cache.set("/p/f\(i).php|k", ans) }
        check("cache: capped at 200, oldest evicted", cache.count == 200 && cache.get("/p/f0.php|k") == nil && cache.get("/p/f200.php|k") == ans)
        cache.invalidate(path: "/p/f5.php")
        check("cache: invalidate(path:) drops that file's entries only", cache.get("/p/f5.php|k") == nil && cache.get("/p/f6.php|k") == ans)
    }

    /// Runs `scan` with callbacks on a private queue and waits for it (no dependence on the main run loop).
    static func finish(_ scan: ProjectScan) -> (results: [FileProblems], cancelled: Bool)? {
        let sem = DispatchSemaphore(value: 0)
        var out: (results: [FileProblems], cancelled: Bool)?
        scan.callbackQueue = DispatchQueue(label: "kode.selftest.scan")
        scan.onFinish = { r, c in out = (r, c); sem.signal() }
        scan.start()
        return sem.wait(timeout: .now() + 30) == .success ? out : nil
    }

    static func runScanner() {
        let skip = ProjectProblemScanner.shouldSkip
        check("scan skip: vendor, nested vendor, node_modules, build output, caches",
              skip("vendor", true) && skip("src/vendor", true) && skip("node_modules/a", false) && skip("public/build", true) && skip("public/build/x.js", false)
              && skip("bootstrap/cache", true) && skip("storage", true) && skip(".git", true) && skip("dist/a.js", false))
        check("scan skip: minified and map files", skip("a.min.js", false) && skip("css/a.min.css", false) && skip("a.js.map", false))
        check("scan keep: ordinary source", !skip("public/index.php", false) && !skip("bootstrap/app.php", false) && !skip("app/Build.php", false) && !skip("app/Http/C.php", false))

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("kode-scan-\(UUID().uuidString)")
        func put(_ rel: String, _ text: String) {
            let u = dir.appendingPathComponent(rel)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: u, atomically: true, encoding: .utf8)
        }
        defer { try? fm.removeItem(at: dir) }
        put("a.php", "<?php function {")
        put("ok.php", "<?php\nfunction f() { return 1; }\n")
        put("vendor/v.php", "<?php function {")
        put("node_modules/n.php", "<?php function {")
        put("public/build/b.php", "<?php function {")
        let scan = ProjectScan(root: dir)
        let r1 = finish(scan)
        let res = r1?.results, cancelled = r1?.cancelled ?? true
        check("scan: only the non-skipped file with a problem is reported", res?.map { $0.url.lastPathComponent } == ["a.php"] && cancelled == false)
        check("scan: problem has position and source", res?.first?.diagnostics.first.map { $0.line == 1 && $0.source == "PHP" } == true)

        // 5,000,001-byte file is skipped
        let big = dir.appendingPathComponent("big.php")
        try? Data(count: 5_000_001).write(to: big)
        check("scan: file over 5,000,000 bytes is skipped", ProjectScan.analyzeFile(url: big, root: dir) == nil)
        try? Data([0, 1, 2, 0, 255]).write(to: dir.appendingPathComponent("bin.php"))
        check("scan: binary file is skipped", ProjectScan.analyzeFile(url: dir.appendingPathComponent("bin.php"), root: dir) == nil)

        // Cap and cancel via the analyzer hook
        for i in 0..<8 { put("many/f\(i).php", "x") }
        ProjectProblemScanner.analyzerOverride = { url, _ in url.path.contains("/many/") ? (0..<1000).map { diag(2, "m\($0)", line: 1) } : [] }
        let capped = finish(ProjectScan(root: dir.appendingPathComponent("many")))?.results
        check("scan: at most 5,000 problems kept", capped.map { $0.reduce(0) { $0 + $1.diagnostics.count } } == 5000)

        var calls = 0
        let s3 = ProjectScan(root: dir.appendingPathComponent("many"))
        ProjectProblemScanner.analyzerOverride = { _, _ in calls += 1; s3.cancel(); return [] }
        let done2 = finish(s3)?.cancelled
        check("scan: cancel stops after the current file", done2 == true && calls == 1)
        ProjectProblemScanner.analyzerOverride = nil
    }

    static func runPanel() {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("kode-pp-\(UUID().uuidString)")
        let a = dir.appendingPathComponent("a.php"), b = dir.appendingPathComponent("b.php")
        let text = (1...8).map { "line \($0)" }.joined(separator: "\n")
        let fa = FileProblems(url: a, diagnostics: [
            diag(2, "Unused import X", line: 1, source: "PHP", code: "unused-import"),
            diag(2, "Unused import Y", line: 2, source: "PHP", code: "unused-import"),
            diag(1, "Undefined variable $x", line: 4, source: "intelephense", code: "P1008")])
        let fb = FileProblems(url: b, diagnostics: [diag(2, "Other thing", line: 3, source: "JS", code: "no-unused")])
        let p = ProblemsPanelController(root: dir) { _, _, _ in }
        p.problemsProvider = { [fa, fb] }
        p.currentFileProvider = { a }
        p.textProvider = { _ in text }

        p.select(tab: .file)
        var rows = p.rowDescriptions
        check("tabs: File lists only the current file", rows.count == 4 && rows[0].hasPrefix("FILE a.php") && !rows.contains { $0.contains("Other thing") })

        p.select(tab: .inspections)
        rows = p.rowDescriptions
        check("tabs: Inspections groups category, then inspection, current file only",
              rows.first == "GROUP PHP (3)" && rows.contains("GROUP P1008 (1)") && rows.contains("GROUP unused-import (2)") && !rows.contains { $0.contains("Other thing") })

        p.select(tab: .project)
        check("tabs: Project Errors is idle until scanned", p.rowDescriptions.isEmpty && p.emptyText.contains("Scan"))
        p.setProjectResults([fa, fb])
        rows = p.rowDescriptions
        check("tabs: Project Errors lists scan results of every file", p.projectResultCount == 2 && rows.contains { $0.hasPrefix("FILE a.php") } && rows.contains { $0.hasPrefix("FILE b.php") })
        p.select(tab: .file)
        check("tabs: leaving Project Errors drops its results", p.projectResultCount == 0)

        check("detail: selecting a problem shows its message", p.selectRow(containing: "Undefined variable") && p.detail.messageText.contains("Undefined variable $x"))

        p.select(tab: .inspections)
        var calls = 0, lastCount = 0
        p.evaluateOverride = { refs, done in
            calls += 1; lastCount = refs.count
            var m: [Int: ProblemAnswer] = [:]
            for r in refs {
                let first = r.d.message.hasPrefix("Undefined")
                m[r.id] = ProblemAnswer(verdict: .real, difficulty: first ? .easy : .hard, explanation: "expl " + r.d.message, oldText: first ? "line 4" : nil, newText: first ? "" : nil)
            }
            done(.success(m))
        }
        check("evaluate: selecting the category row", p.selectRow(containing: "GROUP PHP"))
        p.evaluateSelection()
        check("evaluate: a group of 3 is ONE call", calls == 1 && lastCount == 3)
        var ok = true
        for m in ["Unused import X", "Unused import Y", "Undefined variable $x"] {
            ok = ok && p.selectRow(containing: m) && p.detail.explanationText == "expl " + m
        }
        check("evaluate: each problem shows its own answer", ok)

        var applied: (String, String)?, handed = 0
        p.applyFix = { _, o, n in applied = (o, n); return true }
        p.handOff = { _, _ in handed += 1 }
        _ = p.selectRow(containing: "Undefined variable")
        check("apply: easy answer with a fix shows Apply, not Hand to agent", p.detail.applyVisible && !p.detail.handOffVisible)
        p.detail.performApply()
        check("apply: calls applyFix once with old/new text", applied?.0 == "line 4" && applied?.1 == "")
        _ = p.selectRow(containing: "Unused import X")
        check("apply: hard answer shows Hand to agent, not Apply", !p.detail.applyVisible && p.detail.handOffVisible)
        p.detail.performHandOff()
        check("apply: Hand to agent calls handOff once", handed == 1)

        if let png = ProcessInfo.processInfo.environment["CE_PROBLEMS_SNAPSHOT"] {      // headless render for eyeballing the layout
            _ = p.selectRow(containing: "Undefined variable")
            p.snapshot(to: png + "-inspections.png")
            p.select(tab: .file)
            _ = p.selectRow(containing: "Unused import Y")
            p.snapshot(to: png + "-file.png")
            p.select(tab: .inspections)
        }

        // More than 20 problems: one call of 20, the rest reported
        let many = FileProblems(url: a, diagnostics: (1...25).map { diag(2, "m\($0)", line: min($0, 8), source: "PHP", code: "c\($0)") })
        p.problemsProvider = { [many] }
        p.select(tab: .file)
        calls = 0
        _ = p.selectRow(containing: "FILE a.php")
        p.evaluateSelection()
        check("evaluate: 25 problems send 20 and report the rest", calls == 1 && lastCount == 20 && p.statusText.contains("5 more"))
    }

    static func runApplyFix(w: ProjectWindow) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("kode-fix-\(UUID().uuidString)")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let u = dir.appendingPathComponent("f.php")
        try? "use A;\nuse B;\nuse B2;\n".write(to: u, atomically: true, encoding: .utf8)
        check("applyFix: unique text is replaced on disk", w.applyProblemFix(url: u, old: "use A;\n", new: "") && (try? String(contentsOf: u, encoding: .utf8)) == "use B;\nuse B2;\n")
        check("applyFix: text found twice is refused and the file is untouched", !w.applyProblemFix(url: u, old: "use B", new: "X") && (try? String(contentsOf: u, encoding: .utf8)) == "use B;\nuse B2;\n")
        check("applyFix: missing text is refused", !w.applyProblemFix(url: u, old: "nope", new: "X") && !w.applyProblemFix(url: u, old: "", new: "X"))
    }
}
