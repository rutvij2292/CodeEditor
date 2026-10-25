import Foundation
import SwiftTreeSitter

/// Developer aid: `CE_NJS_BENCH=<js project> [CE_NJS_OUT=<json>] [CE_NJS_FILES=60] [CE_NJS_PER_FILE=14]` samples identifier / member tokens from the
/// project's JS / TS / Vue files, times native go to definition (cold, then warm), writes positions + answers as JSON (replayable against the
/// TypeScript server with scripts/bench-tsserver.py), and also times hover, diagnostics and find usages. Prints footprint and latency to stderr.
enum NativeJSBench {
    private static func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? 0 : a[min(a.count - 1, Int(Double(a.count) * p))] }
    private static func f1(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func ms(_ since: Date) -> Double { Date().timeIntervalSince(since) * 1000 }

    private struct Row { var file: String; var offset: Int; var word: String; var kind: String }

    static func run(_ path: String) {
        let root = (path as NSString).standardizingPath
        let nFiles = Int(AppEnv.value("CE_NJS_FILES") ?? "") ?? 60
        let perFile = Int(AppEnv.value("CE_NJS_PER_FILE") ?? "") ?? 14
        let base = NativePHPBench.footprintMB()
        var trunc = false
        var files = NJSRefs.filesForBench(root, truncated: &trunc)
        let total = files.count
        if files.count > nFiles { let step = Double(files.count) / Double(nFiles); files = (0..<nFiles).map { files[Int(Double($0) * step)] } }
        fputs("BENCH project \(root): \(total) source files, sampling \(files.count)\n", stderr)

        // sample tokens
        let t0 = Date()
        var rows: [Row] = []
        var texts: [String: String] = [:]
        for f in files {
            guard let text = FastProject.read(f), let doc = NJSDoc(path: f, text: text) else { continue }
            let imports = Set(doc.summary.order.filter { $0.kind == .import }.map(\.name))
            var cands: [Row] = []
            var stack: [Node] = [doc.root]
            while let n = stack.popLast() {
                let k = n.kind
                if k == "identifier" || k == "type_identifier" {
                    let nm = n.text(text)
                    if imports.contains(nm), let p = n.parent, p.kind != "import_specifier", p.kind != "import_clause", p.kind != "namespace_import", p.kind != "export_specifier" {
                        cands.append(Row(file: f, offset: n.start, word: nm, kind: "import-usage"))
                    }
                } else if k == "property_identifier", let p = n.parent, p.kind == "member_expression", let pr = p.field("property"), pr == n {
                    cands.append(Row(file: f, offset: n.start, word: n.text(text), kind: "member"))
                }
                if n.namedChildCount > 0 { stack.append(contentsOf: n.kids) }
            }
            cands.sort { $0.offset < $1.offset }
            if cands.count > perFile { let step = Double(cands.count) / Double(perFile); cands = (0..<perFile).map { cands[Int(Double($0) * step)] } }
            rows += cands
            if f.hasSuffix(".vue") { texts[f] = doc.isVue ? NJSDoc.maskVue(text).0 as String : text as String }
            if rows.count >= 1500 { break }
        }
        fputs("BENCH sampled \(rows.count) tokens in \(f1(ms(t0))) ms\n", stderr)
        NativeJS.trimMemory()
        let afterSample = NativePHPBench.footprintMB()

        // cold pass (per file: first token pays parse + resolution), then warm repeat
        let proj = NJSProject.shared(root: root)
        var cold: [Double] = [], warm: [Double] = []
        var answers: [[String: Any]] = []
        var answered = 0
        var lastFile = ""
        var lastText: NSString?
        for r in rows {
            if r.file != lastFile { lastFile = r.file; lastText = FastProject.read(r.file) }
            guard let text = lastText else { continue }
            let t = Date()
            let hit = NativeJS.lookup(url: URL(fileURLWithPath: r.file), text: text, offset: r.offset + 1, root: root)
            let el = ms(t)
            cold.append(el)
            if hit != nil { answered += 1 }
            let table = NPLineStarts(text)
            let pos = table.position(of: r.offset)
            answers.append(["file": r.file, "offset": r.offset, "line": pos.line - 1, "character": pos.col - 1, "word": r.word, "kind": r.kind,
                            "native": (hit?.targets ?? []).map { ["path": $0.path, "line": $0.line, "column": $0.column] }, "ms": el])
        }
        let afterCold = NativePHPBench.footprintMB()
        for r in rows {
            if r.file != lastFile { lastFile = r.file; lastText = FastProject.read(r.file) }
            guard let text = lastText else { continue }
            let t = Date()
            _ = NativeJS.lookup(url: URL(fileURLWithPath: r.file), text: text, offset: r.offset + 1, root: root)
            warm.append(ms(t))
        }
        cold.sort(); warm.sort()
        fputs("BENCH go-to-definition: answered \(answered)/\(rows.count) (\(rows.isEmpty ? 0 : answered * 100 / rows.count)%)\n", stderr)
        fputs("BENCH latency cold p50=\(f1(pct(cold, 0.5))) p95=\(f1(pct(cold, 0.95))) max=\(f1(cold.last ?? 0)) ms | warm-repeat p50=\(f1(pct(warm, 0.5))) p95=\(f1(pct(warm, 0.95))) ms\n", stderr)
        fputs("BENCH summaries cached=\(proj.cachedSummaries) cost~\(proj.cachedCost / 1024) KB\n", stderr)

        // hover
        var hov: [Double] = []
        var hovered = 0
        for (i, r) in rows.enumerated() where i % 3 == 0 {
            guard let text = FastProject.read(r.file) else { continue }
            let t = Date()
            if let h = NativeJS.lookup(url: URL(fileURLWithPath: r.file), text: text, offset: r.offset + 1, root: root), !h.markdown.isEmpty { hovered += 1 }
            hov.append(ms(t))
        }
        hov.sort()
        fputs("BENCH hover: \(hovered)/\(hov.count) with text, p50=\(f1(pct(hov, 0.5))) p95=\(f1(pct(hov, 0.95))) ms\n", stderr)

        // diagnostics
        var dtimes: [Double] = [], dn = 0, missing: [String] = []
        for f in files {
            guard let text = FastProject.read(f) else { continue }
            let t = Date()
            let list = NativeJSDiag.analyze(url: URL(fileURLWithPath: f), text: text)
            dtimes.append(ms(t))
            for d in list where d.code == "module-not-found" { dn += 1; missing.append("\((f as NSString).lastPathComponent): \(text.substring(with: d.range))") }
        }
        dtimes.sort()
        fputs("BENCH diagnostics: \(files.count) files, p50=\(f1(pct(dtimes, 0.5))) p95=\(f1(pct(dtimes, 0.95))) max=\(f1(dtimes.last ?? 0)) ms; module-not-found=\(dn) \(missing.prefix(8))\n", stderr)

        // find usages on the most imported top-level names
        var usageTimes: [Double] = []
        var usageOut: [String: Any] = [:]
        var picks: [(String, Int)] = []
        for r in rows where r.kind == "import-usage" && !picks.contains(where: { $0.0 == r.word }) { picks.append((r.file, r.offset)); if picks.count >= 5 { break } }
        for (f, off) in picks {
            guard let text = FastProject.read(f) else { continue }
            let t = Date()
            var doc: NJSDoc?
            let sym: NJSRefSymbol? = proj.queue.sync {
                guard let env = NativeJS.env(url: URL(fileURLWithPath: f), text: text, root: root) else { return nil }
                doc = env.doc
                return NJSRefs.identify(env: env, offset: off + 1)
            }
            guard let s = sym else { continue }
            let r = NJSRefs.collect(s, liveDoc: doc, liveTexts: [:])
            let el = ms(t)
            usageTimes.append(el)
            let tb = NPLineStarts(text).position(of: off)
            usageOut[s.name] = ["file": f, "line": tb.line - 1, "character": tb.col - 1, "ms": el,
                                "hits": r.hits.filter { $0.role != .unresolved }.map { ["path": $0.path, "line": $0.line - 1] }]
            fputs("BENCH usages \(s.name): \(r.resolvedCount) hits (\(r.hits.count - r.resolvedCount) possible) in \(r.candidates) candidate files / \(r.filesScanned) parsed, \(f1(el)) ms\n", stderr)
        }
        if AppEnv.value("CE_NJS_LEAK") != nil {
            for round in 1...4 {
                for r in rows { autoreleasepool { if let text = FastProject.read(r.file) { _ = NativeJS.lookup(url: URL(fileURLWithPath: r.file), text: text, offset: r.offset + 1, root: root) } } }
                var st = malloc_statistics_t(); malloc_zone_statistics(nil, &st)
                fputs("BENCH malloc in use before trim \(f1(Double(st.size_in_use) / 1_048_576)) MB, allocated \(f1(Double(st.size_allocated) / 1_048_576)) MB\n", stderr)
                let before = NativePHPBench.footprintMB()
                NativeJS.trimMemory()
                malloc_zone_statistics(nil, &st)
                fputs("BENCH malloc in use after trim \(f1(Double(st.size_in_use) / 1_048_576)) MB, allocated \(f1(Double(st.size_allocated) / 1_048_576)) MB\n", stderr)
                fputs("BENCH leak round \(round): \(f1(before)) MB -> after trim \(f1(NativePHPBench.footprintMB())) MB\n", stderr)
            }
        }
        let afterAll = NativePHPBench.footprintMB()
        fputs("BENCH footprint MB: start=\(f1(base)) afterSampling=\(f1(afterSample)) afterLookups=\(f1(afterCold)) afterAll=\(f1(afterAll)) (resident=\(f1(NativePHPBench.residentMB())))\n", stderr)
        NativeJS.trimMemory()
        fputs("BENCH footprint after trimMemory: \(f1(NativePHPBench.footprintMB())) MB\n", stderr)

        if let out = AppEnv.value("CE_NJS_OUT") {
            let obj: [String: Any] = ["root": root, "rows": answers, "texts": texts, "usages": usageOut]
            if let d = try? JSONSerialization.data(withJSONObject: obj) { try? d.write(to: URL(fileURLWithPath: out)) }
            fputs("BENCH wrote \(out)\n", stderr)
        }
    }
}

extension NJSRefs {
    static func filesForBench(_ root: String, truncated: inout Bool) -> [String] { files(root, cancel: nil, truncated: &truncated) }
}
