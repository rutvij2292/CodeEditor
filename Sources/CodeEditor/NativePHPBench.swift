import Foundation

/// Developer aid: `CE_NATIVE_BENCH=<laravel project> [CE_NATIVE_BENCH_OUT=<json>] [CE_NATIVE_BENCH_FILES=40]` samples member / class tokens
/// from the project's PHP files, times native go-to-definition on each and writes the positions and answers as JSON, so the same
/// positions can be replayed against Intelephense (scripts/bench-intelephense.py). Prints footprint and latency to stderr, then exits.
enum NativePHPBench {
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static func run(_ path: String) {
        let rootURL = URL(fileURLWithPath: path)
        let base = footprintMB()
        let t0 = Date()
        let fp = FastProject.shared(root: rootURL)
        VendorIndex.shared(for: rootURL).refreshIfNeeded(force: true)
        VendorIndex.shared(for: rootURL).waitUntilIdle()
        let warm = Date().timeIntervalSince(t0)
        var files: [String] = []
        for dir in ["app"] {
            guard let en = FileManager.default.enumerator(atPath: path + "/" + dir) else { continue }
            for case let rel as String in en where rel.hasSuffix(".php") && !rel.hasSuffix(".blade.php") { files.append(path + "/" + dir + "/" + rel) }
        }
        files.sort()
        let maxFiles = Int(AppEnv.value("CE_NATIVE_BENCH_FILES") ?? "40") ?? 40
        let stride = max(1, files.count / maxFiles)
        let picked = Array(files.enumerated().filter { $0.offset % stride == 0 }.map(\.element).prefix(maxFiles))
        let re = try! NSRegularExpression(pattern: "(?:->|::|new\\s+)([A-Za-z_][A-Za-z0-9_]*)")
        var rows: [[String: Any]] = []
        var times: [Double] = []
        var hits = 0
        for f in picked {
            guard let t = FastProject.read(f) else { continue }
            let ms = re.matches(in: t as String, range: NSRange(location: 0, length: t.length))
            let step = max(1, ms.count / 12)
            for (i, m) in ms.enumerated() where i % step == 0 {
                let r = m.range(at: 1)
                let off = r.location + r.length / 2
                let s0 = Date()
                let hit = fp.queue.sync { NativePHP.resolver(fp: fp, url: URL(fileURLWithPath: f), text: t).lookup(at: off) }
                let took = Date().timeIntervalSince(s0) * 1000
                times.append(took)
                if let h = hit, !h.targets.isEmpty { hits += 1 }
                let table = NPLineStarts(t)
                let pos = table.position(of: off)
                rows.append(["file": f, "offset": off, "line": pos.line, "col": pos.col, "word": t.substring(with: r), "ms": took,
                             "targets": (hit?.targets ?? []).prefix(3).map { "\($0.path):\($0.line)" }, "kind": hit?.kind ?? ""])
            }
        }
        times.sort()
        func pct(_ p: Double) -> Double { times.isEmpty ? 0 : times[min(times.count - 1, Int(Double(times.count) * p))] }
        fputs("NBENCH baseMB=\(Int(base)) afterMB=\(Int(footprintMB())) warmSec=\(String(format: "%.1f", warm)) lookups=\(times.count) resolved=\(hits) p50ms=\(String(format: "%.1f", pct(0.5))) p95ms=\(String(format: "%.1f", pct(0.95))) maxMs=\(String(format: "%.1f", times.last ?? 0))\n", stderr)
        if let out = AppEnv.value("CE_NATIVE_BENCH_OUT"),
           let data = try? JSONSerialization.data(withJSONObject: ["root": path, "rows": rows], options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: out))
        }
    }
}
