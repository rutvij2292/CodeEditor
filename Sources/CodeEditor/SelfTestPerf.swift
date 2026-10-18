import AppKit
import QuartzCore

/// Performance regression guards (CE_SELFTEST). Budgets are generous multiples of what the release build measures (see
/// Bench.swift / `CE_BENCH=1`) so a reintroduced whole-document pass on the main thread, a polling timer or a forced
/// full layout fails the suite, while a noisy CI machine does not. Debug builds get a 5x allowance.
enum SelfTestPerf {
    #if DEBUG
    static let slack = 5.0
    #else
    static let slack = 1.0
    #endif

    private static func phpSource(lines: Int) -> String {
        var s = "<?php\n\nnamespace App;\n\nclass Big\n{\n"
        var i = 0
        while i * 12 < lines {
            s += "    public function m\(i)(array $a, int $n = 3): array\n    {\n        $x = collect($a)->map(fn ($v) => strtoupper((string) $v));\n"
                + "        if (count($x) > $n) {\n            $x = $x->take($n);\n        }\n        foreach ($x as $k => $v) {\n            $this->log[] = \"$k:$v\";\n        }\n"
                + "        return $x->all();\n    }\n\n"
            i += 1
        }
        return s + "}\n"
    }

    static func run(app: AppDelegate) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ce-perf-\(getpid())")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        func ms(_ t: Double) -> Double { t * 1000 }

        // 1. Open a 5k-line PHP file: non-contiguous layout keeps this far below a full layout (~190 ms release before).
        let big = dir.appendingPathComponent("big.php")
        try? phpSource(lines: 5000).write(to: big, atomically: true, encoding: .utf8)
        let t0 = CACurrentMediaTime()
        let tab = EditorTab(url: big)
        let layoutOnOpen = tab?.textView.layoutManager?.allowsNonContiguousLayout ?? false
        if let tab {
            tab.view.frame = NSRect(x: 0, y: 0, width: 940, height: 750)
            tab.view.layoutSubtreeIfNeeded()
            if let rep = tab.view.bitmapImageRepForCachingDisplay(in: tab.view.bounds) { tab.view.cacheDisplay(in: tab.view.bounds, to: rep) }
        }
        let openMs = ms(CACurrentMediaTime() - t0)
        SelfTest.check("perf: layout is non-contiguous", layoutOnOpen)
        SelfTest.check("perf: opening a 5k-line file takes < \(Int(120 * slack)) ms (was \(String(format: "%.0f", openMs)))", openMs < 120 * slack)

        // 2. Keystrokes: insertText must not scan the whole document synchronously.
        if let tab {
            let tv = tab.textView
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length / 2, length: 0))
            var xs: [Double] = []
            for i in 0..<60 {
                let t = CACurrentMediaTime()
                if i % 2 == 0 { tv.insertText("x", replacementRange: tv.selectedRange()) } else { tv.deleteBackward(nil) }
                xs.append(ms(CACurrentMediaTime() - t))
            }
            xs.sort()
            let p95 = xs[Int(Double(xs.count) * 0.95)]
            SelfTest.check("perf: keystroke insert p95 < \(Int(15 * slack)) ms on 5k lines (was \(String(format: "%.1f", p95)))", p95 < 15 * slack)
        }

        // 3. Go to File on a synthetic 100k-file index.
        let index = ProjectIndex(root: dir)
        var fake: [String] = []
        let words = ["Controller", "Service", "Model", "User", "Order", "Invoice", "Report", "Handler", "Provider", "Request"]
        for i in 0..<100_000 { fake.append("app/\(words[i % 10])s/Mod\(i % 97)/\(words[(i / 10) % 10])\(words[(i / 7) % 10])\(i).php") }
        index.setFilesForBenchmark(fake)
        _ = index.search("ctrl", limit: 200)     // warm
        var worst = 0.0
        for q in ["UserC", "o", "usrctl", "InvoiceR"] {
            let t = CACurrentMediaTime()
            let hits = index.search(q, limit: 200)
            worst = max(worst, ms(CACurrentMediaTime() - t))
            if q == "UserC" { SelfTest.check("perf: 100k-file search finds results", !hits.isEmpty) }
        }
        SelfTest.check("perf: Go to File search on 100k files < \(Int(60 * slack)) ms (was \(String(format: "%.0f", worst)))", worst < 60 * slack)

        // 4. A minified single-line file degrades gracefully (soft wrap on, features off, no multi-second layout).
        let min = dir.appendingPathComponent("min.js")
        try? String(repeating: "var a=function(b){return b+1};", count: 4000).write(to: min, atomically: true, encoding: .utf8)
        let t4 = CACurrentMediaTime()
        let longTab = EditorTab(url: min)
        let longMs = ms(CACurrentMediaTime() - t4)
        SelfTest.check("perf: very long lines switch to the large-file feature set", longTab?.longLines == true && longTab?.isLargeFile == true)
        SelfTest.check("perf: opening a 120 KB single-line file < \(Int(800 * slack)) ms (was \(String(format: "%.0f", longMs)))", longMs < 800 * slack)

        // 5. Power saver stretches debounces and pauses the optional live features.
        let power = PowerState.shared
        power.simulated = true
        SelfTest.check("perf: power saver scales debounce 2.5x", abs(power.scaled(0.1) - 0.25) < 1e-9)
        SelfTest.check("perf: power saver pauses live git diff and inline blame", !PowerState.liveGitDiff && !PowerState.liveBlame)
        SelfTest.check("perf: power saver halves workers", power.maxWorkers <= max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
        power.simulated = false
        SelfTest.check("perf: power saver off restores timings", abs(power.scaled(0.1) - 0.1) < 1e-9 && PowerState.liveGitDiff)
        power.simulated = nil

        // 6. Idle: with an open editor nothing may keep waking the run loop (no polling timers).
        var wakeups = 0
        let obs = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue, true, 0) { _, _ in wakeups += 1 }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))     // let debounced work from the edits above drain
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.0))
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), obs, .commonModes)
        SelfTest.check("perf: idle editor causes < 40 run-loop wakeups in 2 s (was \(wakeups))", wakeups < 40)

        // 7. Every repeating timer in the sources sets a tolerance (lint; only runs where the sources are available).
        timerLint()
        _ = tab; _ = longTab
    }

    /// Repeating `Timer`s without `tolerance` prevent timer coalescing (extra wakeups, extra energy).
    private static func timerLint() {
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "swift" }), !files.isEmpty else {
            SelfTest.check("perf: timer lint (sources not available, skipped)", true)
            return
        }
        var offenders: [String] = []
        for file in files where !["SelfTestPerf.swift", "Bench.swift", "BenchEnergy.swift"].contains(file.lastPathComponent) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = text.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.contains("repeats: true") && (line.contains("scheduledTimer(") || line.contains("Timer(timeInterval:")) {
                let window = lines[i..<min(lines.count, i + 12)].joined(separator: "\n")
                if !window.contains("tolerance") { offenders.append("\(file.lastPathComponent):\(i + 1)") }
            }
        }
        SelfTest.check("perf: every repeating timer sets a tolerance" + (offenders.isEmpty ? "" : " (missing: \(offenders.joined(separator: ", ")))"), offenders.isEmpty)
    }
}
