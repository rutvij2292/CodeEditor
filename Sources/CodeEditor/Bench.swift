import AppKit
import QuartzCore

/// CE_BENCH=1: headless latency benchmark. Prints a table to stderr and writes JSON to CE_BENCH_OUT.
/// CE_BENCH_ONLY=open,key,scroll,jump,tabs,resize,tree,picker,find,completion (comma list) limits scenarios;
/// CE_BENCH_SIZES=1k,5k,20k,min,json limits file kinds.
enum Bench {
    static func run(app: AppDelegate) {
        guard AppEnv.value("CE_BENCH") != nil else { return }
        if BenchEnergy.runIfRequested(app: app) { return }
        setenv("GIT_OPTIONAL_LOCKS", "0", 1)
        // Not a main-queue block: nested run loops do not drain libdispatch's main queue from inside one.
        let runner = BenchRunner(app: app)
        let t = Timer(timeInterval: 0.3, repeats: false) { _ in runner.runAll() }
        RunLoop.main.add(t, forMode: .common)
    }
}

struct BenchStats {
    var p50 = 0.0, p95 = 0.0, max = 0.0, mean = 0.0, n = 0
    init(_ xs: [Double]) {
        guard !xs.isEmpty else { return }
        let s = xs.sorted()
        n = s.count
        p50 = s[s.count / 2]
        p95 = s[min(s.count - 1, Int(Double(s.count) * 0.95))]
        max = s.last!
        mean = s.reduce(0, +) / Double(s.count)
    }
}

/// Main-thread busy time (runloop wake to sleep) plus a 5 ms timer measuring runloop gaps.
final class BenchMeter {
    private(set) var busy = 0.0
    private var wake = 0.0
    private var observer: CFRunLoopObserver?
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    var maxGap = 0.0, over50 = 0, over16 = 0

    init() {
        observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [unowned self] _, act in
            if act == .afterWaiting { wake = CACurrentMediaTime() } else if wake > 0 { busy += CACurrentMediaTime() - wake; wake = 0 }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        let t = Timer(timeInterval: 0.005, repeats: true) { [unowned self] _ in
            let n = CACurrentMediaTime(), gap = n - last - 0.005
            last = n
            if gap > maxGap { maxGap = gap }
            if gap > 0.05 { over50 += 1 }
            if gap > 0.016 { over16 += 1 }
        }
        t.tolerance = 0
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func resetStalls() { maxGap = 0; over50 = 0; over16 = 0; last = CACurrentMediaTime() }
    func resetBusy() { busy = 0; wake = 0 }
}

final class BenchRunner {
    let app: AppDelegate
    let meter = BenchMeter()
    var rows: [[String: Any]] = []
    var window: ProjectWindow!
    var dir: URL!
    let only: Set<String>
    let sizes: Set<String>
    var largeDir: URL!

    init(app: AppDelegate) {
        self.app = app
        only = Set((AppEnv.value("CE_BENCH_ONLY") ?? "").split(separator: ",").map(String.init))
        sizes = Set((AppEnv.value("CE_BENCH_SIZES") ?? "").split(separator: ",").map(String.init))
    }

    func want(_ s: String) -> Bool { only.isEmpty || only.contains(s) }
    func wantSize(_ s: String) -> Bool { sizes.isEmpty || sizes.contains(s) }
    @inline(__always) func now() -> Double { CACurrentMediaTime() }
    func ms(_ s: Double) -> Double { s * 1000 }

    func pump(_ s: Double) { RunLoop.main.run(until: Date(timeIntervalSinceNow: s)) }

    func record(_ scenario: String, _ file: String, _ xs: [Double], extra: [String: Double] = [:], unit: String = "ms") {
        let st = BenchStats(xs)
        var row: [String: Any] = ["scenario": scenario, "file": file, "p50": st.p50, "p95": st.p95, "max": st.max, "mean": st.mean, "n": st.n,
                                  "maxGapMs": ms(meter.maxGap), "stalls50": meter.over50, "stalls16": meter.over16]
        for (k, v) in extra { row[k] = v }
        rows.append(row)
        let pad = { (s: String, n: Int) in s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
        fputs("\(pad(scenario, 22)) \(pad(file, 12)) p50 \(String(format: "%8.2f", st.p50)) p95 \(String(format: "%8.2f", st.p95)) max \(String(format: "%8.2f", st.max)) \(unit)  n=\(st.n)  gap \(String(format: "%.0f", ms(meter.maxGap)))ms stalls>50: \(meter.over50)\(extra.isEmpty ? "" : "  \(extra.sorted { $0.key < $1.key }.map { "\($0.key)=\(String(format: "%.2f", $0.value))" }.joined(separator: " "))")\n", stderr)
        meter.resetStalls()
    }

    // MARK: corpus

    func php(lines: Int) -> String {
        var s = "<?php\n\nnamespace App\\Services;\n\nuse Illuminate\\Support\\Collection;\n\nclass Generated\n{\n    protected array $log = [];\n\n"
        var i = 0
        while s.utf8.count > 0, i * 20 < lines - 12 {
            s += """
                /**
                 * Handle item \(i).
                 *
                 * @param  array<string, mixed>  $data
                 * @return array<int, string>
                 */
                public function handle\(i)(array $data, int $limit = 10): array
                {
                    $items = collect($data)->filter(fn ($v) => !empty($v))->map(function ($v, $k) {
                        return strtoupper((string) $v) . "-{$k}";
                    })->values()->all();

                    if (count($items) > $limit) {
                        $items = array_slice($items, 0, $limit);
                    }
                    foreach ($items as $index => $item) {
                        $this->log['\(i)'][] = sprintf('%d:%s', $index, $item);
                    }
                    return $items;
                }


            """
            i += 1
        }
        return s + "}\n"
    }

    func buildCorpus() {
        let fm = FileManager.default
        dir = fm.temporaryDirectory.appendingPathComponent("ce-bench-\(getpid())")
        try? fm.createDirectory(at: dir.appendingPathComponent("app"), withIntermediateDirectories: true)
        func put(_ rel: String, _ text: String) {
            let u = dir.appendingPathComponent(rel)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: u, atomically: false, encoding: .utf8)
        }
        put("composer.json", "{\"name\":\"bench/app\"}\n")
        put("app/php1k.php", php(lines: 1000))
        put("app/php5k.php", php(lines: 5000))
        put("app/php20k.php", php(lines: 20000))
        var js = "!function(){"
        var k = 0
        while js.utf8.count < 2_000_000 { js += "var a\(k)=function(b,c){return b+c*\(k)};if(a\(k)(1,2)>3){console.log(\"x\(k)\")}"; k += 1 }
        put("app/min.js", js + "}();")
        var json = "[\n"
        for i in 0..<5000 { json += "  {\n    \"id\": \(i),\n    \"name\": \"item \(i)\",\n    \"tags\": [\"a\", \"b\"]\n  }\(i < 4999 ? "," : "")\n" }
        put("app/data20k.json", json + "]\n")
        let ws = "/Users/rutvijkothari/Interwork/vrtac-apps/vendor/phpoffice/phpspreadsheet/src/PhpSpreadsheet/Worksheet/Worksheet.php"
        if let t = try? String(contentsOfFile: ws, encoding: .utf8) { put("app/Worksheet.php", t) }
        // ten mixed files for tab switching, from the real project (read only)
        let real = URL(fileURLWithPath: "/Users/rutvijkothari/Interwork/vrtac-apps/app")
        var cands: [(URL, Int)] = []
        if let en = fm.enumerator(at: real, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let u as URL in en where u.pathExtension == "php" {
                let sz = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if sz > 4000, sz < 120_000 { cands.append((u, sz)) }
            }
        }
        for (i, c) in cands.sorted(by: { $0.1 > $1.1 }).prefix(10).enumerated() {
            if let t = try? String(contentsOf: c.0, encoding: .utf8) { put("tabs/t\(i).php", t) }
        }
        // 2000 files in one folder for the tree
        for i in 0..<2000 { put("many/file\(i).txt", "x\n") }
        func git(_ args: [String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = args
            p.currentDirectoryURL = dir
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        }
        git(["init", "-q"]); git(["add", "-A"])
        git(["-c", "user.name=b", "-c", "user.email=b@b", "commit", "-qm", "init"])
    }

    // MARK: drawing helpers

    func draw(_ v: NSView) {
        v.layoutSubtreeIfNeeded()
        v.displayIfNeeded()
    }

    var hosts: [ObjectIdentifier: NSView] = [:]
    var reps: [ObjectIdentifier: NSBitmapImageRep] = [:]

    /// Moves the editor pane out of the (never shown) window into a window-less host: Core Animation then has nothing to
    /// commit, so timings measure the editor's own layout/draw/feature work and not an off-screen window server context.
    func detach(_ tab: EditorTab) {
        let id = ObjectIdentifier(tab)
        guard hosts[id] == nil, let v = tab.view else { return }
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 940, height: 750))
        v.removeFromSuperview()
        v.translatesAutoresizingMaskIntoConstraints = true
        v.frame = host.bounds
        v.autoresizingMask = [.width, .height]
        host.addSubview(v)
        host.layoutSubtreeIfNeeded()
        hosts[id] = host
    }

    /// Draws what one frame draws: the text view's visible rect and the gutter (no off-screen document area).
    func drawFull(_ tab: EditorTab) {
        detach(tab)
        let id = ObjectIdentifier(tab)
        let v = tab.view!
        v.layoutSubtreeIfNeeded()
        let tv = tab.textView
        let rect = tv.visibleRect
        guard rect.width > 0, rect.height > 0 else { return }
        if repsText[id]?.size != rect.size { repsText[id] = tv.bitmapImageRepForCachingDisplay(in: rect) }
        if let rep = repsText[id] { tv.cacheDisplay(in: rect, to: rep) }
        if let g = (v.subviews.first as? EditorContainer)?.gutter {
            if reps[id] == nil { reps[id] = g.bitmapImageRepForCachingDisplay(in: g.bounds) }
            if let rep = reps[id] { g.cacheDisplay(in: g.bounds, to: rep) }
        }
    }
    var repsText: [ObjectIdentifier: NSBitmapImageRep] = [:]

    /// One scroll frame as AppKit draws it with copiesOnScroll: only the newly exposed strip of the text view, plus the
    /// whole gutter (it is a separate view that redraws on every bounds change).
    func drawScrollFrame(_ tab: EditorTab, strip: CGFloat) {
        detach(tab)
        let id = ObjectIdentifier(tab)
        let v = tab.view!
        v.layoutSubtreeIfNeeded()
        let tv = tab.textView
        let vis = tv.visibleRect
        let rect = NSRect(x: vis.minX, y: vis.maxY - strip, width: vis.width, height: strip)
        if rect.width > 0 {
            if repsText[id]?.size != rect.size { repsText[id] = tv.bitmapImageRepForCachingDisplay(in: rect) }
            if let rep = repsText[id] { tv.cacheDisplay(in: rect, to: rep) }
        }
        if let g = (v.subviews.first as? EditorContainer)?.gutter {
            if reps[id] == nil { reps[id] = g.bitmapImageRepForCachingDisplay(in: g.bounds) }
            if let rep = reps[id] { g.cacheDisplay(in: g.bounds, to: rep) }
        }
    }

    func highlighted(_ tab: EditorTab) -> Bool {
        let lm = tab.textView.layoutManager!
        let len = tab.textView.textStorage?.length ?? 0
        var i = 0
        let step = 1
        while i < min(len, 3000) {
            if lm.temporaryAttribute(.foregroundColor, atCharacterIndex: i, effectiveRange: nil) != nil { return true }
            i += step
        }
        return false
    }

    // MARK: scenarios

    func runAll() {
        let t0 = now()
        buildCorpus()
        fputs("corpus built in \(String(format: "%.1f", now() - t0))s at \(dir.path)\n", stderr)
        window = app.openProject(dir)
        pump(1.5)
        window.window.setContentSize(NSSize(width: 1200, height: 800))
        window.window.contentView?.layoutSubtreeIfNeeded()
        let files: [(String, String)] = [("1k", "app/php1k.php"), ("5k", "app/php5k.php"), ("20k", "app/php20k.php"),
                                         ("worksheet", "app/Worksheet.php"), ("min", "app/min.js"), ("json", "app/data20k.json")]
        for (label, rel) in files where wantSize(label) {
            let url = dir.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            fputs("--- \(label)\n", stderr)
            let tab = openScenario(label, url)
            if let tab {
                if want("key") { keystrokes(label, tab) }
                if want("scroll"), label != "1k" { scroll(label, tab) }
                if want("jump"), label == "20k" || label == "5k" { jump(label, tab) }
            }
            window.close(url.standardizedFileURL.path)
            pump(0.3)
        }
        if want("completion") { completion() }
        if want("tabs") { tabSwitch() }
        if want("resize") { resize() }
        if want("tree") { tree() }
        if want("picker") { picker() }
        if want("find") { find() }
        if let out = AppEnv.value("CE_BENCH_OUT") { writeJSON(out) }
        LanguageServers.stopAll()
        pump(0.2)
        try? FileManager.default.removeItem(at: dir)
        fputs("BENCH DONE\n", stderr)
        exit(0)
    }

    func openScenario(_ label: String, _ url: URL) -> EditorTab? {
        guard want("open") || want("key") || want("scroll") || want("jump") else { return nil }
        var tabSync: [Double] = [], paint: [Double] = [], hl: [Double] = []
        var kept: EditorTab?
        let reps = (label == "min" || label == "20k") ? 3 : 5
        for r in 0..<reps {
            meter.resetStalls()
            let id = url.standardizedFileURL.path
            let t0 = now()
            window.open(url)
            let t1 = now()
            guard let tab = window.editors[id] else { continue }
            drawFull(tab)
            let t2 = now()
            var firstHL = highlighted(tab) ? t2 : 0
            while firstHL == 0, now() - t0 < 5 {
                pump(0.002)
                if highlighted(tab) { firstHL = now() }
            }
            tabSync.append(ms(t1 - t0)); paint.append(ms(t2 - t0)); hl.append(ms((firstHL > 0 ? firstHL : now()) - t0))
            if r == reps - 1 { kept = tab } else { window.close(id); pump(0.25) }
        }
        pump(0.4)
        let perf = Perf.drain()
        var ex: [String: Double] = [:]
        for (k, v) in perf { ex["perf." + k] = v.total * 1000 / Double(reps) }
        record("open.sync", label, tabSync)
        record("open.firstPaint", label, paint, extra: ex)
        record("open.firstHighlight", label, hl)
        kept?.textView.window?.makeFirstResponder(kept?.textView)
        return kept
    }

    let keyCount = Int(AppEnv.value("CE_BENCH_KEYS") ?? "") ?? 200

    func keystrokes(_ label: String, _ tab: EditorTab) {
        let keyCount = label == "min" ? min(self.keyCount, 40) : self.keyCount
        let tv = tab.textView
        let ns = tv.string as NSString
        let mid = ns.length / 2
        let start = ns.lineRange(for: NSRange(location: mid, length: 0)).location
        tv.setSelectedRange(NSRange(location: min(start + 8, ns.length), length: 0))
        tv.scrollRangeToVisible(tv.selectedRange())
        pump(0.5); drawFull(tab)
        if AppEnv.value("CE_BENCH_LAYERS") != nil { var out: [String] = []; LayerTuning.dump(tab.view, into: &out); fputs(out.joined(separator: "\n") + "\n", stderr) }
        if want("micro") {
            var a: [Double] = [], b: [Double] = []
            for _ in 0..<50 {
                let t0 = now(); let s = tv.string; _ = s.utf8.count; a.append(ms(now() - t0))
                let t1 = now(); let m = tv.textStorage!.mutableString; _ = m.length; b.append(ms(now() - t1))
            }
            record("micro.tv.string", label, a); record("micro.mutableString", label, b)
        }
        var sync: [Double] = [], total: [Double] = []
        _ = Perf.drain()
        meter.resetStalls()
        let words = ["x", "a", "$", "-", "t", "(", " ", "e"]
        for i in 0..<keyCount {
            let typing = i % 2 == 0
            meter.resetBusy()
            let t0 = now()
            if typing { tv.insertText(words[(i / 2) % words.count], replacementRange: tv.selectedRange()) } else { tv.deleteBackward(nil) }
            let t1 = now()
            drawFull(tab)
            let t2 = now()
            let busy0 = meter.busy
            pump(0.12)
            sync.append(ms(t1 - t0))
            total.append(ms((t2 - t0) + (meter.busy - busy0)))
        }
        var ex: [String: Double] = [:]
        for (k, v) in Perf.drain() { ex["perf." + k] = v.total * 1000 / Double(keyCount) }
        record("key.insertText", label, sync)
        record("key.total", label, total, extra: ex)
        // restore via undo noise is irrelevant; the tab is closed afterwards
    }

    func scroll(_ label: String, _ tab: EditorTab) {
        let sv = tab.scrollView
        sv.contentView.scroll(to: .zero)
        sv.reflectScrolledClipView(sv.contentView)
        pump(0.3); drawFull(tab)
        var frames: [Double] = []
        meter.resetStalls()
        _ = Perf.drain()
        let maxY = max(0, (sv.documentView?.frame.height ?? 0) - sv.contentView.bounds.height)
        let nFrames = 120 * (Int(AppEnv.value("CE_BENCH_SCROLLREPS") ?? "") ?? 1)
        for i in 0..<nFrames {
            let y = min(maxY, Double(i % 120) * 45 + 300)
            let t0 = now()
            sv.contentView.scroll(to: NSPoint(x: 0, y: y))
            sv.reflectScrolledClipView(sv.contentView)
            drawScrollFrame(tab, strip: 45)
            let t1 = now()
            pump(0.001)
            frames.append(ms(t1 - t0))
        }
        var ex: [String: Double] = [:]
        for (k, v) in Perf.drain() { ex["perf." + k] = v.total * 1000 / Double(nFrames) }
        record("scroll.frame", label, frames, extra: ex)
    }

    func jump(_ label: String, _ tab: EditorTab) {
        var xs: [Double] = []
        let lines = (tab.textView.string as NSString).length / 40
        for k in 0..<(Int(AppEnv.value("CE_BENCH_JUMPS") ?? "") ?? 5) {
            tab.textView.goToLine(1)
            pump(0.2)
            meter.resetBusy()
            let target = max(10, lines * (k % 2 == 0 ? 9 : 6) / 10)
            let t0 = now()
            tab.textView.goToLine(target)
            drawFull(tab)
            let b0 = meter.busy
            pump(0.15)
            xs.append(ms(now() - t0 - 0.15 + (meter.busy - b0)))
        }
        record("jump.toLine", label, xs)
    }

    func completion() {
        let url = dir.appendingPathComponent("app/php5k.php")
        window.open(url)
        guard let tab = window.editors[url.standardizedFileURL.path] else { return }
        pump(0.6)
        let tv = tab.textView
        var xs: [Double] = []
        for _ in 0..<10 {
            let ns = tv.string as NSString
            tv.setSelectedRange(NSRange(location: ns.length / 2, length: 0))
            tv.insertText("coll", replacementRange: tv.selectedRange())
            pump(0.05)
            meter.resetBusy()
            let t0 = now()
            tv.triggerCompletion(nil)
            let t1 = now()
            let b0 = meter.busy
            pump(0.15)
            xs.append(ms(t1 - t0) + ms(meter.busy - b0))
            CompletionSystem.controller(for: tab)?.close()
            for _ in 0..<4 { tv.deleteBackward(nil) }
            pump(0.1)
        }
        record("completion.open", "5k", xs)
        window.close(url.standardizedFileURL.path)
    }

    func tabSwitch() {
        var urls = (0..<10).map { dir.appendingPathComponent("tabs/t\($0).php") }.filter { FileManager.default.fileExists(atPath: $0.path) }
        urls.append(dir.appendingPathComponent("app/php5k.php"))
        for u in urls { window.open(u); pump(0.05) }
        pump(0.8)
        var xs: [Double] = []
        meter.resetStalls()
        for i in 0..<40 {
            let u = urls[(i * 3) % urls.count]
            let t0 = now()
            window.tabs.select(u.standardizedFileURL.path)
            window.window.contentView?.layoutSubtreeIfNeeded()
            if let t = window.current { drawFull(t) }
            let t1 = now()
            let b0 = meter.busy
            pump(0.05)
            xs.append(ms(t1 - t0) + ms(meter.busy - b0))
        }
        record("tab.switch", "\(urls.count) tabs", xs)
        window.closeAllTabs()
        pump(0.3)
    }

    func resize() {
        let u = dir.appendingPathComponent("app/php5k.php")
        window.open(u); pump(0.6)
        var xs: [Double] = []
        meter.resetStalls()
        for i in 0..<40 {
            let x = CGFloat(220 + (i % 20) * 12 + (i < 20 ? 0 : 0))
            let t0 = now()
            window.mainSplit.splitView.setPosition(x, ofDividerAt: 0)
            window.window.contentView?.layoutSubtreeIfNeeded()
            window.window.contentView?.displayIfNeeded()
            if let t = window.current { drawFull(t) }
            xs.append(ms(now() - t0))
            pump(0.002)
        }
        record("resize.split", "5k", xs)
        var ys: [Double] = []
        for i in 0..<30 {
            let t0 = now()
            window.window.setContentSize(NSSize(width: 1000 + (i % 15) * 20, height: 700 + (i % 10) * 10))
            window.window.contentView?.layoutSubtreeIfNeeded()
            if let t = window.current { drawFull(t) }
            ys.append(ms(now() - t0))
            pump(0.002)
        }
        record("resize.window", "5k", ys)
        window.closeAllTabs()
    }

    func tree() {
        guard let manyNode = (0..<window.tree.outline.numberOfRows).compactMap({ window.tree.outline.item(atRow: $0) as? FileNode })
            .first(where: { $0.url.lastPathComponent == "many" }) else { fputs("tree: no many folder\n", stderr); return }
        var xs: [Double] = []
        for _ in 0..<3 {
            window.tree.outline.collapseItem(manyNode); pump(0.1)
            let t0 = now()
            window.tree.outline.expandItem(manyNode)
            window.tree.scrollView.layoutSubtreeIfNeeded()
            window.tree.scrollView.displayIfNeeded()
            if let rep = window.tree.scrollView.bitmapImageRepForCachingDisplay(in: window.tree.scrollView.bounds) {
                window.tree.scrollView.cacheDisplay(in: window.tree.scrollView.bounds, to: rep)
            }
            xs.append(ms(now() - t0))
        }
        record("tree.expand2k", "many/", xs)
        var zs: [Double] = []
        for _ in 0..<3 {
            let n = FileNode(url: manyNode.url)
            let t = now(); _ = n.children.count; zs.append(ms(now() - t))
        }
        record("tree.listFolder2k", "many/", zs)
        var ys: [Double] = []
        for round in 0..<3 {
            var paths: [String] = []
            for i in 0..<300 {
                let p = dir.appendingPathComponent("many/burst\(round)_\(i).txt")
                try? "y".write(to: p, atomically: false, encoding: .utf8); paths.append(p.path)
            }
            meter.resetBusy()
            let t0 = now()
            window.filesChanged(paths)
            pump(max(0.5, window.coalesceInterval + 0.5))
            ys.append(ms(meter.busy))
            _ = t0
        }
        record("tree.fsBurstBusy", "300 files", ys)
        let t0 = now()
        window.tree.refresh()
        record("tree.refresh", "2.3k rows", [ms(now() - t0)])
    }

    func picker() {
        // Real project (read only): ~1.9k files; plus a synthetic 100k index.
        let realRoot = URL(fileURLWithPath: "/Users/rutvijkothari/Interwork/vrtac-apps")
        let real = ProjectIndex(root: realRoot)
        var done = false
        real.refresh(force: true) { done = true }
        while !done { pump(0.05) }
        runPicker("goto.keystroke", "\(real.files.count) files", real)
        var fake: [String] = []
        let words = ["Controller", "Service", "Model", "User", "Order", "Invoice", "Report", "Handler", "Provider", "Request"]
        for i in 0..<100_000 { fake.append("app/\(words[i % 10])s/Mod\(i % 97)/\(words[(i / 10) % 10])\(words[(i / 7) % 10])\(i).php") }
        let big = ProjectIndex(root: dir)
        big.setFilesForBenchmark(fake)
        runPicker("goto.keystroke", "100k files", big)
    }

    func runPicker(_ name: String, _ label: String, _ index: ProjectIndex) {
        let root = index.root
        QuickPicker.present(over: window.window, placeholder: "Go to file…", items: [], provider: { q in
            if q.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
            return index.search(q, limit: 200).map { hit in
                let rel = hit.path
                let url = URL(fileURLWithPath: rel, relativeTo: root).standardizedFileURL
                return PickerItem(title: url.lastPathComponent, detail: (rel as NSString).deletingLastPathComponent,
                                  symbol: FileIcon.symbol(forExtension: url.pathExtension), key: rel) {}
            }
        })
        var xs: [Double] = []
        for query in ["ctrl", "ctrlu", "UserC", "UserCon", "usrctl", "o", "or", "ord", "Invo", "InvoiceR"] {
            let t0 = now()
            QuickPicker.type(query)
            xs.append(ms(now() - t0))
            pump(0.01)
        }
        record(name, label, xs)
        QuickPicker.dismiss()
    }

    func find() {
        let realRoot = URL(fileURLWithPath: "/Users/rutvijkothari/Interwork/vrtac-apps")
        let idx = ProjectIndex(root: realRoot)
        var done = false
        idx.refresh(force: true) { done = true }
        while !done { pump(0.05) }
        let files = idx.files
        let engine = FindEngine(root: realRoot, files: { files })
        var results: [Double] = []
        meter.resetStalls()
        for q in ["function", "Illuminate", "zzzqqq"] {
            meter.resetBusy()
            var finished = false
            let t0 = now()
            _ = engine.search(FindOptions(query: q), batch: { _ in }, done: { _ in finished = true })
            while !finished, now() - t0 < 30 { pump(0.005) }
            results.append(ms(now() - t0))
            fputs("  find '\(q)': wall \(String(format: "%.0f", ms(now() - t0)))ms, main busy \(String(format: "%.0f", ms(meter.busy)))ms\n", stderr)
        }
        record("find.inFiles", "\(files.count) files", results)
    }

    func writeJSON(_ path: String) {
        let data = try? JSONSerialization.data(withJSONObject: ["rows": rows], options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: URL(fileURLWithPath: path))
    }
}
