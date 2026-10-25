import AppKit

/// Latency and footprint guards for the native CSS / HTML / Tailwind service. Thresholds are generous (debug build, loaded machine).
enum SelfTestNativeWebPerf {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("web perf: " + name, ok()) }
    private static func ms(_ since: Date) -> Double { Date().timeIntervalSince(since) * 1000 }

    static func run() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-selftest-webperf-\(getpid())").standardizedFileURL
        try? fm.removeItem(at: root)
        defer { try? fm.removeItem(at: root) }
        SelfTestNativeWeb.put(root, "package.json", #"{"devDependencies":{"tailwindcss":"^3.4.0"}}"#)
        SelfTestNativeWeb.put(root, "tailwind.config.js", SelfTestNativeWeb.v3Config)
        // 70 stylesheets (~30 KB each) and 300 templates
        for i in 0..<70 {
            var s = ":root { --c\(i)-a: #123; --c\(i)-b: 4px; }\n"
            for j in 0..<500 { s += ".f\(i)-c\(j) > .child-\(j):hover { color: red; margin: 0 auto; padding: .5rem; --x\(j): \(j)px }\n" }
            SelfTestNativeWeb.put(root, "resources/css/f\(i).css", s)
        }
        for i in 0..<300 {
            var s = "<div class=\"p-4 f\(i % 70)-c1\">\n"
            for j in 0..<40 { s += "  <span class=\"flex items-center f\(i % 70)-c\(j)\" id=\"n\(i)-\(j)\">{{ $a }}</span>\n" }
            SelfTestNativeWeb.put(root, "resources/views/v\(i).blade.php", s + "</div>\n")
        }
        let css = root.appendingPathComponent("resources/css/f0.css")
        let view = root.appendingPathComponent("resources/views/v0.blade.php")
        let before = NativePHPBench.footprintMB()

        var t = Date()
        let scratch = root.appendingPathComponent("resources/css/scratch.css")
        let cold = SelfTestNativeWeb.labels(scratch, ".x { color: var(--c5-§")
        let coldMs = ms(t)
        check("cold var() completion over 70 stylesheets (\(Int(coldMs)) ms)", cold.contains("--c5-a") && coldMs < 4000)
        t = Date()
        _ = SelfTestNativeWeb.labels(scratch, ".x { color: var(--c5-§")
        let warmVar = ms(t)
        check("warm var() completion (\(Int(warmVar)) ms)", warmVar < 250)

        t = Date()
        let tw = SelfTestNativeWeb.labels(view, "<div class=\"bg-§\">")
        let twCold = ms(t)
        check("cold tailwind class completion (\(Int(twCold)) ms)", !tw.isEmpty && twCold < 3000)
        t = Date()
        var count = 0
        for q in ["bg-r", "p-", "text-", "fl", "md:hov", "-m", "border-", "w-"] { count += SelfTestNativeWeb.labels(view, "<div class=\"\(q)§\">").count }
        let warm = ms(t) / 8
        check("warm tailwind completion (\(Int(warm)) ms avg, \(count / 8) items)", warm < 120 && count > 0)

        t = Date()
        for _ in 0..<20 { _ = SelfTestNativeWeb.hit(view, "<div class=\"md:hov§er:bg-red-500/50\">") }
        check("tailwind hover (\(Int(ms(t) / 20)) ms)", ms(t) / 20 < 25)

        t = Date()
        for _ in 0..<20 { _ = SelfTestNativeWeb.labels(css, ".x { col§ }") }
        check("css property completion (\(Int(ms(t) / 20)) ms)", ms(t) / 20 < 40)

        t = Date()
        let def = SelfTestNativeWeb.hit(css, ".f0-c§1 > .child-1:hover { color: red }")
        check("class usage search over 300 templates (\(Int(ms(t))) ms)", ms(t) < 4000 && def != nil)

        let used = NativePHPBench.footprintMB() - before
        check("footprint after a full cycle (\(String(format: "%.1f", used)) MB)", used < 60)
        NativeWeb.trimMemory()
        let p = NWProject.shared(root: root.path)
        check("index cache is capped", p.queue.sync { p.cachedIndexCount } <= NWProject.maxCSSIndexes)
        // lazy: opening a project / typing in a non-web file creates nothing, and answers that do not need the project never walk it
        let idle = fm.temporaryDirectory.appendingPathComponent("ce-selftest-webidle-\(getpid())").standardizedFileURL
        SelfTestNativeWeb.put(idle, "a.php", "<?php echo 1;\n")
        SelfTestNativeWeb.put(idle, "package.json", #"{"name":"idle"}"#)
        SelfTestNativeWeb.put(idle, "src/big.js", String(repeating: "const value = compute(1, 2) // comment\n", count: 20_000))
        defer { try? fm.removeItem(at: idle) }
        check("no state for projects that were never asked", NWProject.existing(root: idle.path) == nil)
        let js = idle.appendingPathComponent("src/big.js")
        let ip = NWProject.shared(root: idle.path)
        t = Date()
        for _ in 0..<20 { _ = SelfTestNativeWeb.labels(js, "const x = foo(§") }
        check("plain JS completion requests are cheap and never walk the project (\(Int(ms(t) / 20)) ms each)", ms(t) / 20 < 25 && !ip.queue.sync { ip.isListed })
        _ = SelfTestNativeWeb.labels(idle.appendingPathComponent("x.html"), "<di§")
        _ = SelfTestNativeWeb.labels(idle.appendingPathComponent("x.html"), "<div cl§")
        check("tag and attribute completion never walk the project", !ip.queue.sync { ip.isListed })
        _ = SelfTestNativeWeb.labels(idle.appendingPathComponent("x.html"), "<div class=\"§\">")
        check("class list completion does", ip.queue.sync { ip.isListed })
    }
}
