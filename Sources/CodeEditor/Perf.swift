import AppKit
import os

/// Cheap performance instrumentation. `CE_PERF=1` turns on os_signpost intervals (Instruments > os_signpost, subsystem
/// "CodeEditor", category "perf") around the main-thread tasks below; `CE_BENCH=1` also collects per-task totals in process.
/// When both are off `Perf.measure` is one boolean test.
enum Perf {
    static let enabled = AppEnv.value("CE_PERF") != nil || AppEnv.value("CE_BENCH") != nil
    private static let signposter = OSSignposter(subsystem: "CodeEditor", category: "perf")
    private static let collect = AppEnv.value("CE_BENCH") != nil
    private static var totals: [String: (count: Int, total: Double, max: Double)] = [:]

    @inline(__always)
    static func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
        guard enabled else { return body() }
        let state = signposter.beginInterval(name)
        let t0 = collect ? CFAbsoluteTimeGetCurrent() : 0
        defer {
            signposter.endInterval(name, state)
            if collect { record("\(name)", CFAbsoluteTimeGetCurrent() - t0) }
        }
        return body()
    }

    private static func record(_ name: String, _ dt: Double) {
        var e = totals[name] ?? (0, 0, 0)
        e.count += 1; e.total += dt; e.max = max(e.max, dt)
        totals[name] = e
    }

    /// Per-task (count, total seconds, max seconds) since the last call.
    static func drain() -> [String: (count: Int, total: Double, max: Double)] {
        defer { totals = [:] }
        return totals
    }
}

/// Core Animation backing-store tuning for the editor's big layers. On HDR/wide-gamut displays AppKit may back layers with
/// 16-bit float stores (4x the memory traffic of RGBA8, and a full-store copy on every dirty-rect update). Code editor
/// content is plain sRGB, so request 8-bit stores explicitly. `CE_LAYER=off` disables (A/B benchmarking).
enum LayerTuning {
    static let enabled = AppEnv.value("CE_LAYER") != "off"
    static let nonContiguous = AppEnv.value("CE_CONTIG") == nil
    static let backgroundLayout: Bool? = AppEnv.value("CE_BGLAYOUT").map { $0 == "1" }
    static func apply(_ views: [NSView]) {
        guard enabled else { return }
        for v in views {
            v.wantsLayer = true
            v.layer?.contentsFormat = .RGBA8Uint
        }
    }

    /// Human-readable dump (benchmark diagnostics).
    static func dump(_ root: NSView, depth: Int = 0, into out: inout [String]) {
        let l = root.layer
        out.append(String(repeating: "  ", count: depth) + "\(type(of: root)) layer=\(l.map { "\(type(of: $0)) \(Int($0.bounds.width))x\(Int($0.bounds.height)) fmt=\($0.contentsFormat.rawValue) opaque=\($0.isOpaque)" } ?? "none")")
        if depth < 6 { for s in root.subviews { dump(s, depth: depth + 1, into: &out) } }
    }
}
