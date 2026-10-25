import Foundation
import SwiftTreeSitter

/// Developer aid: `CE_NJS_BENCH=<js project> [CE_NJS_OUT=<json>] [CE_NJS_FILES=60] [CE_NJS_PER_FILE=14]` samples identifier / member tokens from the
/// project's JS / TS / Vue files, times native go to definition (cold, then warm), writes positions + answers as JSON (replayable against the
/// TypeScript server with scripts/bench-tsserver.py), and also times hover, diagnostics and find usages. Prints footprint and latency to stderr.
enum NativeJSBench {
    private static func inUseMB() -> Double { var st = malloc_statistics_t(); malloc_zone_statistics(nil, &st); return Double(st.size_in_use) / 1_048_576 }
    private static func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? 0 : a[min(a.count - 1, Int(Double(a.count) * p))] }
    private static func f1(_ v: Double) -> String { String(format: "%.1f", v) }
    private static func ms(_ since: Date) -> Double { Date().timeIntervalSince(since) * 1000 }

    private struct Row { var file: String; var offset: Int; var word: String; var kind: String }

    static func run(_ path: String) {
        let root = (path as NSString).standardizingPath
        let nFiles = Int(AppEnv.value("CE_NJS_FILES") ?? "") ?? 60
        let perFile = Int(AppEnv.value("CE_NJS_PER_FILE") ?? "") ?? 14
        let base = NativePHPBench.footprintMB()
        let baseInUse = inUseMB()
        var trunc = false
        var files = NJSRefs.filesForBench(root, truncated: &trunc)
        let total = files.count
        if files.count > nFiles { let step = Double(files.count) / Double(nFiles); files = (0..<nFiles).map { files[Int(Double($0) * step)] } }
        fputs("BENCH project \(root): \(total) source files, sampling \(files.count)\n", stderr)

        // sample tokens
        let t0 = Date()
        var rows: [Row] = []
        var callSites: [Row] = []
        var texts: [String: String] = [:]
        var enough = false
        for f in files where !enough { autoreleasepool {
            guard let text = FastProject.read(f), let doc = NJSDoc(path: f, text: text) else { return }
            defer { withExtendedLifetime(doc) {} }      // nodes below must not outlive the document's tree zone
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
                if (k == "call_expression" || k == "new_expression"), let a = n.field("arguments"), a.kind == "arguments", callSites.count < 4000 {
                    callSites.append(Row(file: f, offset: a.start + 1, word: "", kind: k))
                }
                if n.namedChildCount > 0 { stack.append(contentsOf: n.kids) }
            }
            cands.sort { $0.offset < $1.offset }
            if cands.count > perFile { let step = Double(cands.count) / Double(perFile); cands = (0..<perFile).map { cands[Int(Double($0) * step)] } }
            rows += cands
            if f.hasSuffix(".vue") { texts[f] = doc.isVue ? NJSDoc.maskVue(text).0 as String : text as String }
            if rows.count >= 1500 { enough = true }
        } }
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
            let hit = autoreleasepool { NativeJS.lookup(url: URL(fileURLWithPath: r.file), text: text, offset: r.offset + 1, root: root) }
            let el = ms(t)
            cold.append(el)
            if hit != nil { answered += 1 }
            let table = NPLineStarts(text)
            let pos = table.position(of: r.offset)
            answers.append(["file": r.file, "offset": r.offset, "line": pos.line - 1, "character": pos.col - 1, "word": r.word, "kind": r.kind,
                            "native": (hit?.targets ?? []).map { ["path": $0.path, "line": $0.line, "column": $0.column] }, "ms": el])
        }
        let afterCold = NativePHPBench.footprintMB()
        let inUseCold = inUseMB()
        for r in rows {
            if r.file != lastFile { lastFile = r.file; lastText = FastProject.read(r.file) }
            guard let text = lastText else { continue }
            let t = Date()
            autoreleasepool { _ = NativeJS.lookup(url: URL(fileURLWithPath: r.file), text: text, offset: r.offset + 1, root: root) }
            warm.append(ms(t))
        }
        cold.sort(); warm.sort()
        fputs("BENCH go-to-definition: answered \(answered)/\(rows.count) (\(rows.isEmpty ? 0 : answered * 100 / rows.count)%)\n", stderr)
        fputs("BENCH latency cold p50=\(f1(pct(cold, 0.5))) p95=\(f1(pct(cold, 0.95))) max=\(f1(cold.last ?? 0)) ms | warm-repeat p50=\(f1(pct(warm, 0.5))) p95=\(f1(pct(warm, 0.95))) ms\n", stderr)
        fputs("BENCH summaries cached=\(proj.cachedSummaries) cost~\(proj.cachedCost / 1024) KB\n", stderr)

        // hover
        var hov: [Double] = []
        var hovered = 0
        for (i, r) in rows.enumerated() where i % 3 == 0 { autoreleasepool {
            guard let text = FastProject.read(r.file) else { return }
            let t = Date()
            if let h = NativeJS.lookup(url: URL(fileURLWithPath: r.file), text: text, offset: r.offset + 1, root: root), !h.markdown.isEmpty { hovered += 1 }
            hov.append(ms(t))
        } }
        hov.sort()
        fputs("BENCH hover: \(hovered)/\(hov.count) with text, p50=\(f1(pct(hov, 0.5))) p95=\(f1(pct(hov, 0.95))) ms\n", stderr)

        // diagnostics
        var dtimes: [Double] = [], dn = 0, missing: [String] = []
        for f in files { autoreleasepool {
            guard let text = FastProject.read(f) else { return }
            let t = Date()
            let list = NativeJSDiag.analyze(url: URL(fileURLWithPath: f), text: text)
            dtimes.append(ms(t))
            for d in list where d.code == "module-not-found" { dn += 1; missing.append("\((f as NSString).lastPathComponent): \(text.substring(with: d.range))") }
        } }
        dtimes.sort()
        fputs("BENCH diagnostics: \(files.count) files, p50=\(f1(pct(dtimes, 0.5))) p95=\(f1(pct(dtimes, 0.95))) max=\(f1(dtimes.last ?? 0)) ms; module-not-found=\(dn) \(missing.prefix(8))\n", stderr)

        // CE_NJS_PREWARM=1: what the project-open warm-up costs (it runs at utility QoS in the background in the app)
        if AppEnv.value("CE_NJS_PREWARM") != nil {
            let t = Date()
            var trunc = false
            let list = NJSRefs.files(root, cancel: nil, truncated: &trunc)
            _ = proj.graph.ensureBuilt(files: list, live: [:], modules: proj.modules, stateKey: NJSRefs.listingDigest(list, [:]))
            fputs("BENCH project-open warm-up (listing + import graph, \(list.count) files): \(f1(ms(t))) ms, scan misses \(proj.graph.misses)\n", stderr)
        }
        // find usages on the most imported top-level names
        var usageTimes: [Double] = []
        var usageOut: [String: Any] = [:]
        var picks: [(String, Int)] = []
        for r in rows where r.kind == "import-usage" && !picks.contains(where: { $0.0 == r.word }) { picks.append((r.file, r.offset)); if picks.count >= 5 { break } }
        for (f, off) in picks { autoreleasepool {
            guard let text = FastProject.read(f) else { return }
            NJSRefs.tList = 0; NJSRefs.tGraph = 0; NJSRefs.tParse = 0; NJSRefs.tWalk = 0
            let t = Date()
            var doc: NJSDoc?
            let sym: NJSRefSymbol? = proj.queue.sync {
                guard let env = NativeJS.env(url: URL(fileURLWithPath: f), text: text, root: root) else { return nil }
                doc = env.doc
                return NJSRefs.identify(env: env, offset: off + 1)
            }
            guard let s = sym else { return }
            let r = NJSRefs.collect(s, liveDoc: doc, liveTexts: [:])
            let el = ms(t)
            fputs("BENCH   phases: list \(f1(Double(NJSRefs.tList) / 1e6)) graph \(f1(Double(NJSRefs.tGraph) / 1e6)) parse \(f1(Double(NJSRefs.tParse) / 1e6)) walk+resolve \(f1(Double(NJSRefs.tWalk) / 1e6)) ms\n", stderr)
            let gd = proj.graph.dbg; fputs("BENCH   graph: project scan \(f1(gd.projectMs)) ms, externals in \(f1(gd.extMs)) ms, bfs \(f1(gd.bfsMs)) ms, entries \(gd.entries), cache misses \(proj.graph.misses)\n", stderr)
            let t2 = Date(); _ = NJSRefs.collect(s, liveDoc: doc, liveTexts: [:]); let repeatMs = ms(t2)
            let t3 = Date(); NJSRefs.dropMemos(); _ = NJSRefs.collect(s, liveDoc: doc, liveTexts: [:]); let warmNoMemo = ms(t3)
            usageTimes.append(el)
            let tb = NPLineStarts(text).position(of: off)
            usageOut[s.name] = ["file": f, "line": tb.line - 1, "character": tb.col - 1, "ms": el,
                                "hits": r.hits.filter { $0.role != .unresolved }.map { ["path": $0.path, "line": $0.line - 1] }]
            fputs("BENCH usages \(s.name): \(r.resolvedCount) hits (\(r.hits.count - r.resolvedCount) possible) in \(r.candidates) candidate files / \(r.filesScanned) parsed, first \(f1(el)) ms, repeat(memo) \(f1(repeatMs)) ms, warm no-memo \(f1(warmNoMemo)) ms\n", stderr)
        } }
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
        fputs("BENCH heap in use MB: start=\(f1(baseInUse)) afterLookups=\(f1(inUseCold)) afterAll=\(f1(inUseMB()))\n", stderr)
        fputs("BENCH footprint MB: start=\(f1(base)) afterSampling=\(f1(afterSample)) afterLookups=\(f1(afterCold)) afterAll=\(f1(afterAll)) (resident=\(f1(NativePHPBench.residentMB())))\n", stderr)
        NativeJS.trimMemory()
        if let hold = AppEnv.value("CE_NJS_HOLD").flatMap(Double.init) { fputs("BENCH holding pid \(getpid())\n", stderr); Thread.sleep(forTimeInterval: hold) }
        fputs("BENCH footprint after trimMemory: \(f1(NativePHPBench.footprintMB())) MB\n", stderr)

        // signature help: a spread of call sites, native label / active parameter
        var sigOut: [[String: Any]] = []
        var sigTimes: [Double] = []
        let sigStep = max(1, callSites.count / 300)
        for (i, r) in callSites.enumerated() where i % sigStep == 0 { autoreleasepool {
            guard let text = FastProject.read(r.file), r.offset <= text.length else { return }
            let t = Date()
            let out = NativeJS.signatureHelp(url: URL(fileURLWithPath: r.file), text: text, caret: r.offset)
            sigTimes.append(ms(t))
            let pos = NPLineStarts(text).position(of: r.offset)
            var rec: [String: Any] = ["file": r.file, "line": pos.line - 1, "character": pos.col - 1]
            switch out {
            case .help(let payload):
                let sigs = (payload["signatures"] as? [[String: Any]]) ?? []
                rec["result"] = "help"; rec["labels"] = sigs.map { ($0["label"] as? String) ?? "" }
                rec["active"] = payload["activeSignature"] ?? 0; rec["param"] = payload["activeParameter"] ?? 0
            case .notInCall: rec["result"] = "none"
            case .unknown: rec["result"] = "unknown"
            }
            sigOut.append(rec)
        } }
        sigTimes.sort()
        let sigHelp = sigOut.filter { ($0["result"] as? String) == "help" }.count
        fputs("BENCH signature help: \(sigHelp)/\(sigOut.count) call sites answered natively, p50=\(f1(pct(sigTimes, 0.5))) p95=\(f1(pct(sigTimes, 0.95))) ms\n", stderr)

        // rename: the edit set native would apply for a sample of resolved symbols (nothing is written)
        var renameOut: [[String: Any]] = []
        var renameTimes: [Double] = []
        let renameCandidates = answers.filter { ($0["native"] as? [[String: Any]])?.isEmpty == false && ($0["kind"] as? String) == "import-usage" }
        let rStep = max(1, renameCandidates.count / 20)
        for (i, a) in renameCandidates.enumerated() where i % rStep == 0 && renameOut.count < 20 { autoreleasepool {
            guard let f = a["file"] as? String, let off = a["offset"] as? Int, let text = FastProject.read(f) else { return }
            let url = URL(fileURLWithPath: f)
            let proj = NJSProject.shared(root: root)
            var doc: NJSDoc?
            var sym: NJSRefSymbol?
            var why: String?
            proj.queue.sync {
                guard let env = NativeJS.env(url: url, text: text, root: root), let sy = NJSRefs.identify(env: env, offset: off + 1) else { return }
                doc = env.doc; sym = sy; why = NJSRename.refusal(sy, env: env)
            }
            guard let sy = sym else { return }
            let t = Date()
            var rec: [String: Any] = ["file": f, "line": (a["line"] as? Int) ?? 0, "character": (a["character"] as? Int) ?? 0, "name": sy.name]
            if let why { rec["refused"] = why } else {
                let plan = NJSRename.plan(sy, newName: "NjsRenamed", liveDoc: doc, liveTexts: [:])
                renameTimes.append(ms(t))
                if let c = plan.conflict { rec["refused"] = c } else {
                    var edits: [[String: Any]] = []
                    for (path, es) in plan.edits {
                        guard let t = FastProject.read(path) else { continue }
                        let table = NPLineStarts(t)
                        for e in es { let p = table.position(of: e.range.location); edits.append(["path": path, "line": p.line - 1, "character": p.col - 1]) }
                    }
                    rec["edits"] = edits
                }
            }
            renameOut.append(rec)
        } }
        renameTimes.sort()
        fputs("BENCH rename: \(renameOut.filter { $0["edits"] != nil }.count)/\(renameOut.count) sampled symbols planned natively (rest refused), p50=\(f1(pct(renameTimes, 0.5))) p95=\(f1(pct(renameTimes, 0.95))) ms\n", stderr)

        if let out = AppEnv.value("CE_NJS_OUT") {
            let obj: [String: Any] = ["root": root, "rows": answers, "texts": texts, "usages": usageOut, "sigs": sigOut, "renames": renameOut]
            if let d = try? JSONSerialization.data(withJSONObject: obj) { try? d.write(to: URL(fileURLWithPath: out)) }
            fputs("BENCH wrote \(out)\n", stderr)
        }
    }
}

extension NJSRefs {
    static func filesForBench(_ root: String, truncated: inout Bool) -> [String] { files(root, cancel: nil, truncated: &truncated) }
}
