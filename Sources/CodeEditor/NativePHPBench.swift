import Foundation

/// Developer aid: `CE_NATIVE_BENCH=<laravel project> [CE_NATIVE_BENCH_OUT=<json>] [CE_NATIVE_BENCH_FILES=40] [CE_NATIVE_BENCH_DIAG_FILES=150]`
/// samples member / class tokens from the project's PHP files, times native go-to-definition on each (cold pass, then a warm repeat),
/// writes the positions and answers as JSON (replayable against Intelephense with scripts/bench-intelephense.py), and also times
/// diagnostics, find usages (5 popular symbols) and signature help on the slowest symbols. Prints footprint and latency to stderr, then exits.
enum NativePHPBench {
    private static func vmInfo() -> task_vm_info_data_t {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return info
    }

    static func footprintMB() -> Double { Double(vmInfo().phys_footprint) / 1_048_576 }
    static func residentMB() -> Double { Double(vmInfo().resident_size) / 1_048_576 }

    private static func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? 0 : a[min(a.count - 1, Int(Double(a.count) * p))] }
    private static func f1(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func ms(_ since: Date) -> Double { Date().timeIntervalSince(since) * 1000 }

    private struct Row { var file: String; var offset: Int; var word: String; var wordEnd: Int; var detail = "" }

    private static func listFiles(_ path: String, dirs: [String]) -> [String] {
        var files: [String] = []
        for dir in dirs {
            guard let en = FileManager.default.enumerator(atPath: path + "/" + dir) else { continue }
            for case let rel as String in en where rel.hasSuffix(".php") && !rel.hasSuffix(".blade.php") { files.append(path + "/" + dir + "/" + rel) }
        }
        files.sort()
        return files
    }

    static func run(_ path: String) {
        let rootURL = URL(fileURLWithPath: path)
        let base = footprintMB()
        let t0 = Date()
        let fp = FastProject.shared(root: rootURL)
        VendorIndex.shared(for: rootURL).refreshIfNeeded(force: true)
        VendorIndex.shared(for: rootURL).waitUntilIdle()
        let warm = Date().timeIntervalSince(t0)
        let files = listFiles(path, dirs: ["app"])
        let maxFiles = Int(AppEnv.value("CE_NATIVE_BENCH_FILES") ?? "40") ?? 40
        let stride = max(1, files.count / maxFiles)
        let picked = Array(files.enumerated().filter { $0.offset % stride == 0 }.map(\.element).prefix(maxFiles))
        let re = try! NSRegularExpression(pattern: "(?:->|::|new\\s+)([A-Za-z_][A-Za-z0-9_]*)")
        var rows: [Row] = []
        for f in picked {
            guard let t = FastProject.read(f) else { continue }
            let found = re.matches(in: t as String, range: NSRange(location: 0, length: t.length))
            let step = max(1, found.count / 12)
            for (i, m) in found.enumerated() where i % step == 0 {
                let r = m.range(at: 1)
                rows.append(Row(file: f, offset: r.location + r.length / 2, word: t.substring(with: r), wordEnd: r.location + r.length))
            }
        }
        // first lookup that touches the built-in stubs (cold: index mapping, class parse), on a synthetic buffer
        do {
            let src = "<?php\nnamespace App;\nclass Zed {\n    public function go(): bool\n    {\n        $z = new \\ZipArchive();\n        return $z->open('x.zip') === true;\n    }\n}\n" as NSString
            let off = src.range(of: "open").location + 1
            let s0 = Date()
            let h = fp.queue.sync { NativePHP.resolver(fp: fp, url: URL(fileURLWithPath: path + "/app/Zed.php"), text: src).lookup(at: off) }
            fputs("NBENCH stubFirstMs=\(f1(ms(s0))) resolved=\(h?.targets.isEmpty == false)\n", stderr)
        }
        func lookupPass(record: Bool) -> (times: [Double], hits: Int, out: [[String: Any]], slow: [(Double, Row)]) {
            var times: [Double] = [], out: [[String: Any]] = [], slow: [(Double, Row)] = []
            var hits = 0
            var curFile = "", text: NSString?
            for row in rows {
                if row.file != curFile { curFile = row.file; text = FastProject.read(row.file) }
                guard let t = text else { continue }
                let before = NPStats.snapshot()
                let s0 = Date()
                let hit = fp.queue.sync { NativePHP.resolver(fp: fp, url: URL(fileURLWithPath: row.file), text: t).lookup(at: row.offset) }
                let took = ms(s0)
                let after = NPStats.snapshot()
                var r2 = row
                if took > 1.5 {
                    r2.detail = "read=\(f1(after.read - before.read))ms/\(after.reads - before.reads) parse=\(f1(after.parse - before.parse))ms/\(after.parses - before.parses) funcs=\(f1(after.funcs - before.funcs))ms doc=\(f1(after.doc - before.doc))ms"
                }
                times.append(took); slow.append((took, r2))
                if let h = hit, !h.targets.isEmpty { hits += 1 }
                if record {
                    let pos = NPLineStarts(t).position(of: row.offset)
                    out.append(["file": row.file, "offset": row.offset, "line": pos.line, "col": pos.col, "word": row.word, "ms": took,
                                "targets": (hit?.targets ?? []).prefix(3).map { "\($0.path):\($0.line)" }, "kind": hit?.kind ?? ""])
                }
            }
            return (times, hits, out, slow)
        }
        let cold = lookupPass(record: true)
        let firstMs = cold.times.first ?? 0
        let afterCold = footprintMB()
        let sorted = cold.times.sorted()
        fputs("NBENCH baseMB=\(Int(base)) afterMB=\(Int(afterCold)) warmSec=\(f1(warm)) lookups=\(sorted.count) resolved=\(cold.hits) p50ms=\(f1(pct(sorted, 0.5))) p95ms=\(f1(pct(sorted, 0.95))) p99ms=\(f1(pct(sorted, 0.99))) maxMs=\(f1(sorted.last ?? 0)) firstMs=\(f1(firstMs)) totalMs=\(f1(sorted.reduce(0, +)))\n", stderr)
        let slowest = cold.slow.sorted(by: { $0.0 > $1.0 })
        for (t, r) in slowest.prefix(15) {
            fputs("NBENCH slow \(f1(t)) ms \(r.word) @ \(r.file.dropFirst(path.count + 1)):\(r.offset) \(r.detail)\n", stderr)
        }
        if let n = AppEnv.value("CE_NATIVE_BENCH_LOOP").flatMap({ Int($0) }) {      // profiling aid: hammer the slowest lookups (run `sample` on the process)
            fputs("NBENCH loop start pid=\(getpid())\n", stderr)
            for _ in 0..<n {
                for (_, r) in slowest.prefix(8) {
                    guard let t = FastProject.read(r.file) else { continue }
                    _ = fp.queue.sync { NativePHP.resolver(fp: fp, url: URL(fileURLWithPath: r.file), text: t).lookup(at: r.offset) }
                }
            }
        }
        // warm repeat
        let w = lookupPass(record: false)
        let ws = w.times.sorted()
        fputs("NBENCH warm p50ms=\(f1(pct(ws, 0.5))) p95ms=\(f1(pct(ws, 0.95))) p99ms=\(f1(pct(ws, 0.99))) maxMs=\(f1(ws.last ?? 0)) totalMs=\(f1(ws.reduce(0, +))) footprintMB=\(Int(footprintMB()))\n", stderr)
        // signature help on the slowest symbols that are calls
        var sigTimes: [(Double, String)] = []
        for (_, r) in slowest.prefix(40) {
            guard let t = FastProject.read(r.file), r.wordEnd < t.length, t.character(at: r.wordEnd) == 40 else { continue }
            let s0 = Date()
            _ = fp.queue.sync { NativePHP.resolver(fp: fp, url: URL(fileURLWithPath: r.file), text: t).signatureHelp(at: r.wordEnd + 1) }
            sigTimes.append((ms(s0), r.word))
            if sigTimes.count >= 10 { break }
        }
        fputs("NBENCH sighelp n=\(sigTimes.count) max=\(f1(sigTimes.map(\.0).max() ?? 0)) \(sigTimes.sorted { $0.0 > $1.0 }.prefix(5).map { "\($0.1)=\(f1($0.0))" }.joined(separator: " "))\n", stderr)
        // parse profile: the cold cost of big vendor classes, split into read / lex / FTParser (10 rounds, per-round average)
        do {
            var paths: [String] = []
            let carbon = path + "/vendor/nesbot/carbon/src/Carbon"
            for sub in ["", "/Traits"] { paths += (FileManager.default.subpaths(atPath: carbon + sub) ?? []).filter { $0.hasSuffix(".php") && !$0.contains("/") }.map { carbon + sub + "/" + $0 } }
            let ill = path + "/vendor/laravel/framework/src/Illuminate"
            paths += ["/Database/Eloquent/Builder.php", "/Database/Eloquent/Model.php", "/Database/Query/Builder.php", "/Foundation/helpers.php", "/Support/Collection.php"].map { ill + $0 }
            var bytes = 0, tRead = 0.0, tLex = 0.0, tParse = 0.0, n = 0
            for f in paths {
                for round in 0..<10 {
                    let a = Date()
                    guard let t = FastProject.read(f) else { break }
                    let b = Date()
                    let lex = PHPLex(t)
                    let c = Date()
                    _ = FTParser.parse(t, lex: lex)
                    let d = Date()
                    if round > 0 { tRead += b.timeIntervalSince(a); tLex += c.timeIntervalSince(b); tParse += d.timeIntervalSince(c); n += 1; if round == 1 { bytes += t.length } }
                }
            }
            let rounds = max(1, n / max(1, paths.count))
            fputs("NBENCH parseprofile files=\(paths.count) chars=\(bytes) perRoundMs read=\(f1(tRead * 1000 / 9)) lex=\(f1(tLex * 1000 / 9)) ftparse=\(f1(tParse * 1000 / 9)) (rounds=\(rounds))\n", stderr)
        }
        let fpWarm = Int(footprintMB())
        // find usages of 5 popular symbols (2 classes, 2 methods, 1 function when available)
        var freq: [String: (n: Int, row: Row, kind: String)] = [:]
        for (i, row) in rows.enumerated() where i < cold.out.count {
            let kind = cold.out[i]["kind"] as? String ?? ""
            guard ["class", "method", "function"].contains(kind), !(cold.out[i]["targets"] as? [String] ?? []).isEmpty else { continue }
            let key = kind + ":" + row.word
            freq[key] = ((freq[key]?.n ?? 0) + 1, freq[key]?.row ?? row, kind)
        }
        var usageDump: [String: [String]] = [:]
        var chosen: [(String, Row)] = []
        for (kind, want) in [("class", 2), ("method", 2), ("function", 1)] {
            chosen += freq.filter { $0.value.kind == kind }.sorted { ($0.value.n, $0.key) > ($1.value.n, $1.key) }.prefix(want).map { ($0.key, $0.value.row) }
        }
        // more very common member names (first occurrence in the app's own files; skipped when the call is on an unresolvable receiver)
        let already = Set(chosen.map { $0.0 })
        for name in (AppEnv.value("CE_NATIVE_BENCH_USAGE_NAMES") ?? "first,save,find,create,count").split(separator: ",").map(String.init) where !already.contains("method:" + name) {
            var found = false
            for f in files where !found {
                guard let t = FastProject.read(f) else { continue }
                var from = 0
                while from < t.length {
                    let r = t.range(of: "->" + name + "(", options: [], range: NSRange(location: from, length: t.length - from))
                    if r.location == NSNotFound { break }
                    from = r.location + r.length
                    let off = r.location + 2 + name.count / 2
                    if case .symbol(let sy) = NPRefs.identify(url: URL(fileURLWithPath: f), text: t, offset: off, root: path), sy.kind == .method, !sy.declPath.isEmpty {
                        chosen.append(("method:" + name, Row(file: f, offset: off, word: name, wordEnd: r.location + 2 + name.count)))
                        found = true; break
                    }
                }
            }
        }
        for (key, row) in chosen {
            guard let t = FastProject.read(row.file) else { continue }
            let s0 = Date()
            let id = NPRefs.identify(url: URL(fileURLWithPath: row.file), text: t, offset: row.offset, root: path)
            let idMs = ms(s0)
            guard case .symbol(let sym) = id else { fputs("NBENCH usages \(key) no-symbol\n", stderr); continue }
            if AppEnv.value("CE_NATIVE_BENCH_PAUSE_KEY") == key { fputs("NBENCH pause pid=\(getpid())\n", stderr); usleep(1_500_000) }      // profiling aid: attach `sample` to a cold request
            let s1 = Date()
            let sc0 = (NPStats.scanReadNs, NPStats.scanLexNs, NPStats.scanParseNs, NPStats.scanResolveNs)
            let st0 = NPStats.snapshot()
            let res = NPRefs.collect(sym)
            let collectMs = ms(s1)
            let st1 = NPStats.snapshot()
            fputs("NBENCH usagesPathMs=\(f1(Double(NPStats.pathNs) / 1e6))\n", stderr)
            fputs("NBENCH usagesIO read=\(f1(st1.read - st0.read))ms/\(st1.reads - st0.reads) parse=\(f1(st1.parse - st0.parse))ms/\(st1.parses - st0.parses)\n", stderr)
            fputs("NBENCH usagesCand listAndPrefilterMs=\(f1(Double(NPStats.candTotalNs) / 1e6))\n", stderr)
            fputs("NBENCH usagesSplit read=\(f1(Double(NPStats.scanReadNs &- sc0.0) / 1e6)) lex=\(f1(Double(NPStats.scanLexNs &- sc0.1) / 1e6)) parse=\(f1(Double(NPStats.scanParseNs &- sc0.2) / 1e6)) resolve=\(f1(Double(NPStats.scanResolveNs &- sc0.3) / 1e6))\n", stderr)
            usageDump[key] = res.hits.map { "\($0.path):\($0.range.location):\($0.range.length):\($0.role.rawValue):\($0.editable)" }
            if let n = AppEnv.value("CE_NATIVE_BENCH_USAGE_LOOP").flatMap({ Int($0) }), key == "method:get" {     // profiling aid: `sample <pid>`
                fputs("NBENCH usageLoop pid=\(getpid())\n", stderr)
                for _ in 0..<n { _ = NPRefs.collect(sym) }
            }
            let w0 = Date(); _ = NPRefs.collect(sym); let warmMs = ms(w0)
            fputs("NBENCH usages \(key) identifyMs=\(f1(idMs)) collectMs=\(f1(collectMs)) warmMs=\(f1(warmMs)) candidates=\(res.candidates) hits=\(res.hits.count) resolved=\(res.resolvedCount)\n", stderr)
        }
        let fpUsages = Int(footprintMB())
        // diagnostics over a broader sample
        let diagMax = Int(AppEnv.value("CE_NATIVE_BENCH_DIAG_FILES") ?? "150") ?? 150
        let dfiles = listFiles(path, dirs: ["app", "routes", "database", "config", "Modules"])
        let dstride = max(1, dfiles.count / max(1, diagMax))
        var dtimes: [Double] = [], worstFile = ""
        var worst = 0.0
        for f in dfiles.enumerated().filter({ $0.offset % dstride == 0 }).map(\.element).prefix(diagMax) {
            guard let t = FastProject.read(f) else { continue }
            let s0 = Date()
            _ = fp.queue.sync { NativePHPDiag.analyze(url: URL(fileURLWithPath: f), text: t, fp: fp) }
            let took = ms(s0)
            dtimes.append(took)
            if took > worst { worst = took; worstFile = String(f.dropFirst(path.count + 1)) }
        }
        let ds = dtimes.sorted()
        fputs("NBENCH diag files=\(ds.count) p50ms=\(f1(pct(ds, 0.5))) p95ms=\(f1(pct(ds, 0.95))) worstMs=\(f1(worst)) totalMs=\(f1(ds.reduce(0, +))) worstFile=\(worstFile)\n", stderr)
        // diagnostics split by rule group (each run lexes again, so the sum exceeds the full pass)
        let groupFiles = dfiles.enumerated().filter { $0.offset % max(1, dfiles.count / 120) == 0 }.map(\.element).prefix(120)
        var groupTimes: [String] = []
        for g in NPDiagGroup.allCases {
            let s0 = Date()
            for f in groupFiles {
                guard let t = FastProject.read(f) else { continue }
                _ = fp.queue.sync { NativePHPDiag.analyze(url: URL(fileURLWithPath: f), text: t, fp: fp, groups: [g]) }
            }
            groupTimes.append("\(g)=\(f1(ms(s0)))")
        }
        fputs("NBENCH diagGroups files=\(groupFiles.count) ms: \(groupTimes.joined(separator: " "))\n", stderr)
        // sections the project-open warm-up builds (FastTier.warm), on a fresh FastProject: cold build time each, then the per-epoch re-validation
        do {
            let fp2 = FastProject(path: path)
            var parts: [String] = []
            fp2.queue.sync {
                fp2.beginRequest()
                func t(_ name: String, _ f: () -> Void) { let a = Date(); f(); parts.append("\(name)=\(f1(ms(a)))") }
                t("routes") { _ = fp2.routeNames() }
                t("views") { _ = fp2.viewNames() }
                t("config") { _ = fp2.configKeys() }
                t("schema") { _ = fp2.schema() }
                t("projectClasses") { _ = fp2.projectClasses() }
                fp2.markDirty(); fp2.beginRequest()
                t("revalidate:views") { _ = fp2.viewNames() }
                t("revalidate:projectClasses") { _ = fp2.projectClasses() }
            }
            fputs("NBENCH sectionsMs \(parts.joined(separator: " "))\n", stderr)
        }
        let vm = vmInfo()
        let cc = fp.queue.sync { (fp.cachedClassCount, fp.cachedClassBytes) }
        fputs("NBENCH ram baseMB=\(Int(base)) afterLookupMB=\(Int(afterCold)) afterWarmMB=\(fpWarm) afterUsagesMB=\(fpUsages) finalMB=\(Int(footprintMB())) residentMB=\(Int(Double(vm.resident_size) / 1_048_576)) growthMB=\(Int(footprintMB() - base)) classCache=\(cc.0)/\(cc.1 / 1024)KB npFiles=\(NPFiles.cachedCount) stubClasses=\(PHPStubs.cachedClassCount)\n", stderr)
        let finalMB = footprintMB()
        NativePHP.trimMemory()
        fp.queue.sync { }                          // let the queued cache drop finish
        malloc_zone_pressure_relief(nil, 0)
        fputs("NBENCH trim finalMB=\(Int(finalMB)) afterTrimMB=\(Int(footprintMB())) growthAfterTrimMB=\(Int(footprintMB() - base))\n", stderr)
        if AppEnv.value("CE_NATIVE_BENCH_HOLD") != nil { fputs("NBENCH hold pid=\(getpid())\n", stderr); sleep(90) }     // profiling aid: attach `heap` / `vmmap`
        if let out = AppEnv.value("CE_NATIVE_BENCH_OUT"),
           let data = try? JSONSerialization.data(withJSONObject: ["root": path, "rows": cold.out, "usages": usageDump], options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: out))
        }
    }
}
