import Foundation

/// Developer aid: `CE_WEB_BENCH=<project root> [CE_WEB_BENCH_OUT=<json>] [CE_WEB_BENCH_FILES=30] CE_SELFTEST=1 .build/debug/CodeEditor`
/// samples CSS / markup positions from a real project, times the native completion / hover / definition on each (cold pass, then a warm
/// repeat), writes positions and answers as JSON (replayed against the external servers by scripts/bench-web-servers.py) and prints the
/// footprint. Read-only on the project. Exits when done.
enum NativeWebBench {
    private struct Row {
        var kind: String             // css-prop, css-value, css-hover, css-var, html-tag, html-attr, html-value, class-hover, class-complete, html-def
        var file: String
        var offset: Int
        var prefix: String = ""
        var line = 0, character = 0
    }

    private static func ms(_ since: Date) -> Double { Date().timeIntervalSince(since) * 1000 }
    private static func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? 0 : a[min(a.count - 1, Int(Double(a.count) * p))] }
    private static func f1(_ v: Double) -> String { String(format: "%.1f", v) }

    private static func lspPosition(_ t: NSString, _ off: Int) -> (Int, Int) {
        let p = NPLineStarts(t).position(of: off)
        return (p.line - 1, p.col - 1)
    }

    static func run(_ path: String) {
        let root = URL(fileURLWithPath: path).standardizedFileURL
        let maxFiles = Int(AppEnv.value("CE_WEB_BENCH_FILES") ?? "30") ?? 30
        if AppEnv.value("CE_WEB_BENCH_ALL") != nil { NWTailwindService.maxItems = 100_000 }      // parity runs compare whole result sets
        let base = NativePHPBench.footprintMB()
        let t0 = Date()
        let p = NWProject.shared(root: root.path)
        let css = p.queue.sync { Array(p.allCSSFiles.filter { !$0.contains("/public/") || $0.contains("/resources/") }) }
        let markup = p.queue.sync { Array(p.allMarkupFiles.filter { $0.hasSuffix(".html") || $0.hasSuffix(".blade.php") || $0.hasSuffix(".vue") || $0.hasSuffix(".jsx") || $0.hasSuffix(".tsx") }) }
        let listMs = ms(t0)
        func pick(_ a: [String], _ n: Int) -> [String] { let s = max(1, a.count / max(1, n)); return Array(a.enumerated().filter { $0.offset % s == 0 }.map(\.element).prefix(n)) }
        var rows: [Row] = []
        let propRe = try! NSRegularExpression(pattern: "^\\s*([a-z-]{4,}):\\s*([^;{}]*);", options: [.anchorsMatchLines])
        let varRe = try! NSRegularExpression(pattern: "var\\((--[A-Za-z0-9_-]+)")
        let tagRe = try! NSRegularExpression(pattern: "<([a-z][a-z0-9-]{3,})(\\s|>)")
        let attrRe = try! NSRegularExpression(pattern: "\\s([a-z][a-z-]{3,})=\"")
        let classRe = try! NSRegularExpression(pattern: "\\bclass(?:Name)?=\"([^\"{}<>]{3,200})\"")
        for f in pick(css, maxFiles / 2) where !f.hasSuffix(".min.css") {
            guard let t = FastProject.readRaw(f), t.length < 400_000 else { continue }
            let ms_ = propRe.matches(in: t as String, range: NSRange(location: 0, length: t.length))
            let step = max(1, ms_.count / 8)
            for (i, m) in ms_.enumerated() where i % step == 0 {
                let name = m.range(at: 1), value = m.range(at: 2)
                rows.append(Row(kind: "css-prop", file: f, offset: name.location + 3, prefix: t.substring(with: NSRange(location: name.location, length: 3))))
                rows.append(Row(kind: "css-hover", file: f, offset: name.location + name.length / 2))
                if value.length > 0 { rows.append(Row(kind: "css-value", file: f, offset: value.location, prefix: "")) }
            }
            let vs = varRe.matches(in: t as String, range: NSRange(location: 0, length: t.length))
            for (i, m) in vs.enumerated() where i % max(1, vs.count / 4) == 0 { rows.append(Row(kind: "css-var", file: f, offset: m.range(at: 1).location + 4)) }
        }
        for f in pick(markup, maxFiles) {
            guard let t = FastProject.readRaw(f), t.length < 300_000 else { continue }
            let tags = tagRe.matches(in: t as String, range: NSRange(location: 0, length: t.length))
            for (i, m) in tags.enumerated() where i % max(1, tags.count / 3) == 0 {
                let r = m.range(at: 1)
                rows.append(Row(kind: "html-tag", file: f, offset: r.location + 2, prefix: String(t.substring(with: r).prefix(2))))
                rows.append(Row(kind: "html-hover", file: f, offset: r.location + 1))
            }
            let attrs = attrRe.matches(in: t as String, range: NSRange(location: 0, length: t.length))
            for (i, m) in attrs.enumerated() where i % max(1, attrs.count / 3) == 0 {
                let r = m.range(at: 1)
                rows.append(Row(kind: "html-attr", file: f, offset: r.location + 2, prefix: String(t.substring(with: r).prefix(2))))
                rows.append(Row(kind: "attr-hover", file: f, offset: r.location + 1))
            }
            let cls = classRe.matches(in: t as String, range: NSRange(location: 0, length: t.length))
            for (i, m) in cls.enumerated() where i % max(1, cls.count / 4) == 0 {
                let r = m.range(at: 1)
                let list = t.substring(with: r) as NSString
                let words = list.components(separatedBy: " ").filter { $0.count >= 4 }
                guard let w = words.first else { continue }
                let wr = list.range(of: w)
                let start = r.location + wr.location
                rows.append(Row(kind: "class-hover", file: f, offset: start + 2))
                rows.append(Row(kind: "class-complete", file: f, offset: start + 3, prefix: String(w.prefix(3))))
            }
        }
        for i in rows.indices {
            guard let t = FastProject.readRaw(rows[i].file) else { continue }
            let (l, c) = lspPosition(t, rows[i].offset)
            rows[i].line = l; rows[i].character = c
        }
        let rootPath = root.path
        func ctxFor(_ row: Row, _ t: NSString) -> CompletionContext {
            let url = URL(fileURLWithPath: row.file)
            return CompletionContext(text: t as String, caret: row.offset, fileURL: url, fileExtension: url.pathExtension, triggerCharacter: nil, isManual: true,
                                     prefixRange: NSRange(location: max(0, row.offset - row.prefix.utf16.count), length: row.prefix.utf16.count))
        }
        func pass(record: Bool) -> (times: [String: [Double]], out: [[String: Any]]) {
            var times: [String: [Double]] = [:], out: [[String: Any]] = []
            var curFile = "", text: NSString?
            for row in rows {
                if row.file != curFile { curFile = row.file; text = FastProject.readRaw(row.file) }
                guard let t = text else { continue }
                let s0 = Date()
                var entry: [String: Any] = ["kind": row.kind, "file": row.file, "line": row.line, "character": row.character, "offset": row.offset, "prefix": row.prefix]
                switch row.kind {
                case "css-prop", "css-value", "html-tag", "html-attr", "class-complete":
                    let items = NativeWeb.items(for: ctxFor(row, t))
                    // the same filter an editor applies: subsequence of the typed prefix
                    let q = Array(row.prefix.lowercased().utf8)
                    let labels = items.map(\.label).filter { CompletionLex.subsequence(q, in: $0) }
                    entry["labels"] = Array(labels.prefix(100_000))
                case "css-hover", "css-var", "html-hover", "attr-hover", "class-hover":
                    let h = NativeWeb.lookup(url: URL(fileURLWithPath: row.file), text: t, offset: row.offset, usages: false)
                    entry["hover"] = h?.markdown ?? ""
                    entry["targets"] = (h?.targets ?? []).prefix(4).map { "\($0.path):\($0.line)" }
                    if row.kind == "css-var" || row.kind == "class-hover" {
                        let d = NativeWeb.lookup(url: URL(fileURLWithPath: row.file), text: t, offset: row.offset, usages: true)
                        entry["definition"] = (d?.targets ?? []).prefix(6).map { "\($0.path):\($0.line)" }
                    }
                default: break
                }
                let took = ms(s0)
                times[row.kind, default: []].append(took)
                if record { entry["ms"] = took; out.append(entry) }
            }
            return (times, out)
        }
        let cold = pass(record: true)
        let afterCold = NativePHPBench.footprintMB()
        func report(_ label: String, _ times: [String: [Double]]) {
            for (k, v) in times.sorted(by: { $0.key < $1.key }) {
                let s = v.sorted()
                fputs("WBENCH \(label) \(k) n=\(s.count) p50=\(f1(pct(s, 0.5))) p95=\(f1(pct(s, 0.95))) max=\(f1(s.last ?? 0)) total=\(f1(s.reduce(0, +)))ms\n", stderr)
            }
        }
        fputs("WBENCH root=\(rootPath) css=\(css.count) markup=\(markup.count) rows=\(rows.count) listMs=\(f1(listMs)) baseMB=\(f1(base)) afterColdMB=\(f1(afterCold))\n", stderr)
        report("cold", cold.times)
        let warm = pass(record: false)
        report("warm", warm.times)
        let tw = p.queue.sync { p.tailwind(near: root.path) }
        fputs("WBENCH tailwind=\(tw.map { "v\($0.version) colors=\($0.colors.count) bytes=\($0.approxBytes) buildMs=\(f1(Double(p.tailwindBuildNs) / 1e6)) unresolved=\($0.unresolved) incomplete=\($0.incomplete)" } ?? "none") indexes=\(p.queue.sync { p.cachedIndexCount }) footprintMB=\(f1(NativePHPBench.footprintMB())) residentMB=\(f1(NativePHPBench.residentMB()))\n", stderr)
        // structure diagnostics over every plain stylesheet of the project (all must be clean in a working project)
        var diagFiles = 0, diagIssues = 0
        let dStart = Date()
        for f in css where NWCssDiag.handles(URL(fileURLWithPath: f)) {
            guard let t = FastProject.readRaw(f) else { continue }
            diagFiles += 1
            let issues = NWCssDiag.analyze(NWBuf(t))
            diagIssues += issues.count
            for i in issues.prefix(2) { fputs("WBENCH diag \(f.dropFirst(rootPath.count)) @\(i.offset): \(i.message)\n", stderr) }
        }
        fputs("WBENCH diag files=\(diagFiles) issues=\(diagIssues) totalMs=\(f1(ms(dStart)))\n", stderr)
        NativeWeb.trimMemory()
        Thread.sleep(forTimeInterval: 0.3)
        fputs("WBENCH afterTrimFootprintMB=\(f1(NativePHPBench.footprintMB()))\n", stderr)
        if let out = AppEnv.value("CE_WEB_BENCH_OUT") {
            let doc: [String: Any] = ["root": rootPath, "rows": cold.out, "footprintMB": afterCold - base]
            if let d = try? JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted]) { try? d.write(to: URL(fileURLWithPath: out)) }
        }
    }
}
