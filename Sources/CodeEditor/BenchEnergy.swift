import AppKit

/// CE_BENCH_ENERGY=<state>: parks the headless app in one steady state so an external `top -pid <pid> -l 3 -stats
/// pid,command,cpu,idlew,power` (idle wakeups + energy-impact proxy) can sample it. States: idle, typing, scroll, terminal-idle,
/// terminal-stream, fsburst. Prints "ENERGY READY <pid>" once the state is running and exits after CE_BENCH_ENERGY_SECONDS (45).
enum BenchEnergy {
    static func runIfRequested(app: AppDelegate) -> Bool {
        guard let state = AppEnv.value("CE_BENCH_ENERGY") else { return false }
        setenv("GIT_OPTIONAL_LOCKS", "0", 1)
        let t = Timer(timeInterval: 0.3, repeats: false) { _ in Runner(app: app, state: state).start() }
        RunLoop.main.add(t, forMode: .common)
        return true
    }

    private final class Runner {
        let app: AppDelegate
        let state: String
        let bench: BenchRunner
        var timers: [Timer] = []
        init(app: AppDelegate, state: String) { self.app = app; self.state = state; bench = BenchRunner(app: app) }

        func start() {
            bench.buildCorpus()
            let w = app.openProject(bench.dir)
            bench.window = w
            bench.pump(1.0)
            for rel in ["app/php5k.php", "tabs/t0.php", "tabs/t1.php"] { w.open(bench.dir.appendingPathComponent(rel)) }
            bench.pump(2.0)
            guard let tab = w.current else { fputs("no tab\n", stderr); exit(1) }
            tab.textView.setSelectedRange(NSRange(location: 2000, length: 0))
            let seconds = Double(AppEnv.value("CE_BENCH_ENERGY_SECONDS") ?? "") ?? 45
            switch state {
            case "typing":
                var n = 0
                add(0.2) { _ in
                    if n % 2 == 0 { tab.textView.insertText("x", replacementRange: tab.textView.selectedRange()) } else { tab.textView.deleteBackward(nil) }
                    n += 1
                    self.bench.drawFull(tab)
                }
            case "scroll":
                var y = 0.0
                add(1.0 / 60) { _ in
                    y += 40
                    let max = Swift.max(0, (tab.scrollView.documentView?.frame.height ?? 0) - tab.scrollView.contentView.bounds.height)
                    if y > max { y = 0 }
                    tab.scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
                    tab.scrollView.reflectScrolledClipView(tab.scrollView.contentView)
                    self.bench.drawScrollFrame(tab, strip: 40)
                }
            case "terminal-idle", "terminal-stream":
                w.showTerminalPanel(focus: false)
                bench.pump(1.5)
                if state == "terminal-stream" { w.terminalPanel?.send("yes 'streaming output line for the energy benchmark' | head -n 3000000\n") }
            case "fsburst":
                var round = 0
                add(2.0) { _ in
                    round += 1
                    var paths: [String] = []
                    for i in 0..<300 {
                        let p = self.bench.dir.appendingPathComponent("many/e\(round)_\(i).txt")
                        try? "y".write(to: p, atomically: false, encoding: .utf8)
                        paths.append(p.path)
                    }
                    w.filesChanged(paths)
                }
            default: break    // idle
            }
            fputs("ENERGY READY \(getpid()) \(state)\n", stderr)
            let end = Timer(timeInterval: seconds, repeats: false) { _ in
                LanguageServers.stopAll()
                try? FileManager.default.removeItem(at: self.bench.dir)
                exit(0)
            }
            RunLoop.main.add(end, forMode: .common)
        }

        func add(_ interval: TimeInterval, _ block: @escaping (Timer) -> Void) {
            let t = Timer(timeInterval: interval, repeats: true, block: block)
            RunLoop.main.add(t, forMode: .common)
            timers.append(t)
        }
    }
}
