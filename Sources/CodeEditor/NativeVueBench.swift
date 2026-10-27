import Foundation

/// Developer aid: `CE_VUE_BENCH=<project> [CE_VUE_OUT=<json>] [CE_VUE_FILES=400] CE_SELFTEST=1 .build/debug/CodeEditor` samples component tags, their
/// props / events / slots and template expression identifiers from the project's `.vue` files, times native lookups (cold, then warm), reports the
/// resolved percentage per category and the footprint, and writes positions + answers as JSON (replayable with scripts/bench-vue-server.py).
enum NativeVueBench {
    private static func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? 0 : a[min(a.count - 1, Int(Double(a.count) * p))] }
    private static func f1(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func ms(_ since: Date) -> Double { Date().timeIntervalSince(since) * 1000 }

    private struct Row { var file: String; var offset: Int; var word: String; var kind: String; var detail: String }

    static func run(_ path: String) {
        let root = (path as NSString).standardizingPath
        let maxFiles = Int(AppEnv.value("CE_VUE_FILES") ?? "") ?? 400
        let base = NativePHPBench.footprintMB()
        let p = NVProject.shared(root: root)
        if let spec = AppEnv.value("CE_VUE_RESOLVE") {            // dev aid: CE_VUE_RESOLVE="primevue/select" prints how module resolution answers from the project root
            fputs("RESOLVE \(spec) -> \(p.resolve(spec, from: root + "/resources/js/x.vue") ?? "nil")\n", stderr)
            return
        }
        if let spec = AppEnv.value("CE_VUE_COMPLETE") {            // dev aid: CE_VUE_COMPLETE="<file>|<text inserted after the line containing 'modal'>" prints the attribute completions there
            let parts = spec.components(separatedBy: "|")
            guard parts.count == 2, let text = FastProject.readRaw(parts[0]) else { fputs("COMPLETE: bad spec\n", stderr); return }
            let ns = text as NSString
            let m = ns.range(of: "\n", options: [], range: NSRange(location: ns.range(of: "<template>").location, length: ns.length - ns.range(of: "<template>").location)).location
            let ins = "\n" + parts[1]
            let withText = ns.replacingCharacters(in: NSRange(location: ns.range(of: "\n", range: NSRange(location: ns.range(of: "    <Dialog").location, length: 200)).location, length: 0), with: ins) as NSString
            _ = m
            let caret = ns.range(of: "\n", range: NSRange(location: ns.range(of: "    <Dialog").location, length: 200)).location + ins.utf16.count
            let ctx = CompletionContext(text: withText as String, caret: caret, fileURL: URL(fileURLWithPath: parts[0]), fileExtension: "vue", triggerCharacter: nil, isManual: true, prefixRange: NSRange(location: caret - parts[1].trimmingCharacters(in: .whitespaces).utf16.count, length: parts[1].trimmingCharacters(in: .whitespaces).utf16.count))
            let items = p.queue.sync { NVComplete.items(p, ctx) }
            fputs("COMPLETE \(items.count) items: " + items.prefix(40).map(\.label).joined(separator: ", ") + "\n", stderr)
            return
        }
        let tWalk = Date()
        var files = p.queue.sync { p.vueFiles }
        let walkMs = ms(tWalk)
        let total = files.count
        if files.count > maxFiles { let step = Double(files.count) / Double(maxFiles); files = (0..<maxFiles).map { files[Int(Double($0) * step)] } }
        fputs("BENCH project \(root): \(total) .vue files (walk \(f1(walkMs)) ms), sampling \(files.count)\n", stderr)

        var rows: [Row] = []
        let t0 = Date()
        for f in files { autoreleasepool {
            guard let text = FastProject.readRaw(f), let doc = NVDoc(p, file: f, text: text) else { return }
            for e in doc.tpl.elems where NVProject.isComponentTag(e.name) {
                rows.append(Row(file: f, offset: e.nameRange.location + 1, word: e.name, kind: "tag", detail: ""))
                for a in e.attrs {
                    switch NVService.classify(a.name) {
                    case .prop: if !a.name.hasPrefix("data-"), !a.name.hasPrefix("aria-") { rows.append(Row(file: f, offset: a.nameRange.location + 1, word: a.name, kind: "prop", detail: e.name)) }
                    case .event: rows.append(Row(file: f, offset: a.nameRange.location + 1, word: a.name, kind: "event", detail: e.name))
                    case .model: rows.append(Row(file: f, offset: a.nameRange.location + 1, word: a.name, kind: "model", detail: e.name))
                    case .slot: rows.append(Row(file: f, offset: a.nameRange.location + 1, word: a.name, kind: "slot", detail: e.name))
                    default: break
                    }
                }
            }
            // expression identifiers (interpolations and bound attributes)
            var exprs: [(NSRange, Int)] = doc.tpl.interps.map { ($0.range, $0.parent) }
            for (i, e) in doc.tpl.elems.enumerated() { for a in e.attrs where NVService.isBoundExpression(a.name) && !a.name.hasPrefix("v-for") { if let v = a.value { exprs.append((v, i)) } } }
            var n = 0
            for (r, _) in exprs where n < 40 {
                let ex = VSExpr(doc.text, r)
                for i in 0..<ex.tk.count {
                    let t = ex.tk[i]
                    guard t.kind == .ident, !ex.isMember(i), !ex.isObjectKey(i), !NVService.keywords.contains(t.text), ex.arrowParams[t.text] == nil else { continue }
                    rows.append(Row(file: f, offset: t.s + 1, word: t.text, kind: "expr", detail: ""))
                    n += 1
                    break
                }
            }
        } }
        fputs("BENCH sampled \(rows.count) sites in \(f1(ms(t0))) ms\n", stderr)
        NativeVue.trimMemory()
        let afterSample = NativePHPBench.footprintMB()

        var cold: [Double] = [], warm: [Double] = []
        var answers: [[String: Any]] = []
        var byKind: [String: (n: Int, hit: Int, lib: Int)] = [:]
        var unresolvedTags: [String: Int] = [:]
        var unresolvedAttrs: [String: Int] = [:]
        var lastFile = ""
        var lastText: NSString?
        for r in rows {
            if r.file != lastFile { lastFile = r.file; lastText = FastProject.readRaw(r.file) }
            guard let text = lastText else { continue }
            let t = Date()
            let hit = autoreleasepool { NativeVue.lookup(url: URL(fileURLWithPath: r.file), text: text, offset: r.offset, root: root) }
            let el = ms(t)
            cold.append(el)
            var b = byKind[r.kind] ?? (0, 0, 0)
            b.n += 1
            if let h = hit, !h.targets.isEmpty { b.hit += 1; if h.targets[0].path.contains("/node_modules/") { b.lib += 1 } }
            else if r.kind == "tag" { unresolvedTags[r.word, default: 0] += 1 }
            else if r.kind == "prop" || r.kind == "event" || r.kind == "model" { unresolvedAttrs[r.detail + " " + r.word, default: 0] += 1 }
            byKind[r.kind] = b
            let pos = NPLineStarts(text).position(of: r.offset)
            answers.append(["file": r.file, "offset": r.offset, "line": pos.line - 1, "character": pos.col - 1, "word": r.word, "kind": r.kind, "detail": r.detail,
                            "native": (hit?.targets ?? []).map { ["path": $0.path, "line": $0.line, "column": $0.column] }, "ms": el])
        }
        let afterCold = NativePHPBench.footprintMB()
        for r in rows {
            if r.file != lastFile { lastFile = r.file; lastText = FastProject.readRaw(r.file) }
            guard let text = lastText else { continue }
            let t = Date()
            autoreleasepool { _ = NativeVue.lookup(url: URL(fileURLWithPath: r.file), text: text, offset: r.offset, root: root) }
            warm.append(ms(t))
        }
        cold.sort(); warm.sort()
        for k in ["tag", "prop", "event", "model", "slot", "expr"] {
            guard let b = byKind[k] else { continue }
            fputs("BENCH \(k): resolved \(b.hit)/\(b.n) (\(b.n == 0 ? 0 : b.hit * 100 / b.n)%), of which in node_modules \(b.lib)\n", stderr)
        }
        fputs("BENCH latency cold p50=\(f1(pct(cold, 0.5))) p95=\(f1(pct(cold, 0.95))) max=\(f1(cold.last ?? 0)) ms | warm-repeat p50=\(f1(pct(warm, 0.5))) p95=\(f1(pct(warm, 0.95))) ms\n", stderr)
        fputs("BENCH summaries cached=\(p.cachedSummaries) cost~\(p.cachedCost / 1024) KB\n", stderr)
        fputs("BENCH unresolved tags (top): \(unresolvedTags.sorted { $0.value > $1.value }.prefix(14).map { "\($0.key)x\($0.value)" })\n", stderr)
        fputs("BENCH unresolved attrs (top): \(unresolvedAttrs.sorted { $0.value > $1.value }.prefix(10).map { "\($0.key)x\($0.value)" })\n", stderr)

        // usages of the most used components
        var tagCounts: [String: (String, Int)] = [:]
        for a in answers where (a["kind"] as? String) == "tag" {
            if let t = (a["native"] as? [[String: Any]])?.first, let path = t["path"] as? String { tagCounts[path, default: (a["word"] as! String, 0)].1 += 1 }
        }
        var usageMs: [Double] = []
        for (path, (name, _)) in tagCounts.sorted(by: { $0.value.1 > $1.value.1 }).prefix(4) {
            let t = Date()
            NVProject.statBuilds = 0; NVProject.statBuildNs = 0; NVProject.statPaths = [:]
            let hits = NVRefs.collect(p, target: NVUsageTarget(path: path, display: name), liveTexts: [:], cancel: nil).filter { $0.role == .usage }
            let el = ms(t)
            usageMs.append(el)
            fputs("BENCH   most rebuilt: \(NVProject.statPaths.sorted { $0.value > $1.value }.prefix(3).map { "\(($0.key as NSString).lastPathComponent)x\($0.value)" })\n", stderr)
            fputs("BENCH   summary builds \(NVProject.statBuilds) in \(f1(Double(NVProject.statBuildNs) / 1e6)) ms\n", stderr)
            fputs("BENCH usages of <\(name)> (\((path as NSString).lastPathComponent)): \(hits.count) in \(Set(hits.map(\.path)).count) files, \(f1(el)) ms\n", stderr)
        }
        // completion latency
        var compMs: [Double] = []
        for f in files.prefix(40) { autoreleasepool {
            guard let text = FastProject.readRaw(f), let r = text.range(of: "<template>") as NSRange?, r.location != NSNotFound else { return }
            let src = text as String
            let caret = r.location + r.length + 3
            let withTag = (src as NSString).replacingCharacters(in: NSRange(location: caret, length: 0), with: "<But")
            let ctx = CompletionContext(text: withTag, caret: caret + 4, fileURL: URL(fileURLWithPath: f), fileExtension: "vue", triggerCharacter: nil, isManual: true, prefixRange: NSRange(location: caret + 1, length: 3))
            let t = Date()
            let items = p.queue.sync { NVComplete.items(p, ctx) }
            compMs.append(ms(t))
            _ = items
        } }
        compMs.sort()
        fputs("BENCH tag completion: p50=\(f1(pct(compMs, 0.5))) p95=\(f1(pct(compMs, 0.95))) max=\(f1(compMs.last ?? 0)) ms (\(compMs.count) files)\n", stderr)
        let end = NativePHPBench.footprintMB()
        fputs("BENCH footprint: baseline \(f1(base)) MB, after sampling \(f1(afterSample)), after cold pass \(f1(afterCold)) (+\(f1(afterCold - afterSample))), at end \(f1(end)) MB\n", stderr)
        NativeVue.trimMemory()
        usleep(300_000)
        fputs("BENCH footprint after trim: \(f1(NativePHPBench.footprintMB())) MB\n", stderr)

        if let out = AppEnv.value("CE_VUE_OUT"), let data = try? JSONSerialization.data(withJSONObject: ["root": root, "rows": answers], options: []) {
            try? data.write(to: URL(fileURLWithPath: out))
            fputs("BENCH wrote \(answers.count) answers to \(out)\n", stderr)
        }
    }
}
