import AppKit

/// Opt-in real-tool check: `CE_PRETTIER_REAL=<dir> CE_SELFTEST=1`, where <dir> has `node_modules/.bin/prettier`.
/// Runs the real `Formatter.format` path (detect, execute, safety check, apply) against a real Prettier install.
enum SelfTestPrettierReal {
    private static let messy: [(name: String, text: String, expect: (String) -> Bool)] = [
        ("app.js", "const a = {b:1,\"c\":[1,2,3]}\nfunction f( x ){return \"hi\"+x;}\n", { $0.contains("const a = { b: 1, c: [1, 2, 3] }") && $0.contains("'hi'") && !$0.contains(";") }),
        ("util.ts", "export const n:number=1;\ninterface A{a:string}\n", { $0.contains("export const n: number = 1") && $0.contains("interface A {") }),
        ("style.css", "a{color:red;margin:0 }\n.b{display:flex}\n", { $0.contains("a {\n  color: red;") }),
        ("data.json", "{\"a\":1,\"b\":[1,2]}\n", { $0.contains("\"a\": 1") }),
        ("page.html", "<div   class=\"a\"   id=b><p>hi</p>\n\n\n\n<span>x</span></div>\n", { $0.contains("<div class=\"a\" id=\"b\">") }),
        ("Comp.vue", "<template><div>{{msg}}</div></template>\n<script>\nexport default {data(){return {msg:\"x\"}}}\n</script>\n", { $0.contains("data() {") && $0.contains("'x'") }),
        ("notes.md", "# T\n\n* a\n* b\n", { $0.contains("- a") }),
    ]

    static func run(w: ProjectWindow, then done: @escaping () -> Void) {
        guard let path = AppEnv.value("CE_PRETTIER_REAL") else { done(); return }
        let dir = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: dir.appendingPathComponent("node_modules/.bin/prettier").path) else {
            SelfTest.check("prettier-real: node_modules/.bin/prettier exists in CE_PRETTIER_REAL", false); done(); return
        }
        try? #"{ "singleQuote": true, "semi": false, "tabWidth": 2 }"#.write(to: dir.appendingPathComponent(".prettierrc"), atomically: true, encoding: .utf8)
        try? "ignored.js\n".write(to: dir.appendingPathComponent(".prettierignore"), atomically: true, encoding: .utf8)
        for f in messy { try? f.text.write(to: dir.appendingPathComponent(f.name), atomically: true, encoding: .utf8) }
        try? "const   x = {a:1}\n".write(to: dir.appendingPathComponent("ignored.js"), atomically: true, encoding: .utf8)
        try? "const = ;;\n".write(to: dir.appendingPathComponent("broken.js"), atomically: true, encoding: .utf8)
        try? "const ok = 1\n".write(to: dir.appendingPathComponent("clean.js"), atomically: true, encoding: .utf8)
        try? "const a = {b:1}\r\nconst c = [1,2]\r\n".write(to: dir.appendingPathComponent("crlf.js"), atomically: true, encoding: .utf8)

        func format(_ name: String, selection: ((String) -> NSRange)? = nil, _ next: @escaping (EditorTab, Formatter.Result, TimeInterval) -> Void) {
            w.open(dir.appendingPathComponent(name))
            guard let tab = w.current else { SelfTest.check("prettier-real: \(name) opens", false); done(); return }
            let t0 = Date()
            let cb: (Formatter.Result) -> Void = { r in next(tab, r, Date().timeIntervalSince(t0)) }
            if let selection { tab.textView.setSelectedRange(selection(tab.textView.string)); Formatter.formatSelection(tab, completion: cb) }
            else { Formatter.format(tab, completion: cb) }
        }
        func isFormatted(_ r: Formatter.Result) -> Bool { if case .formatted(let t) = r { return t == "Prettier" }; return false }
        func describe(_ r: Formatter.Result) -> String {
            switch r { case .formatted(let t): return "formatted(\(t))"; case .unchanged(let t): return "unchanged(\(t))"
            case .unavailable(let m): return "unavailable(\(m))"; case .failed(let t, let m): return "failed(\(t): \(m))" }
        }

        var queue = Array(messy)
        var latencies: [TimeInterval] = []
        func nextMessy() {
            guard !queue.isEmpty else { edgeCases(); return }
            let f = queue.removeFirst()
            format(f.name) { tab, r, dt in
                latencies.append(dt)
                let out = tab.textView.string
                SelfTest.check("prettier-real: \(f.name) formats via project Prettier [\(describe(r))]", isFormatted(r) && f.expect(out))
                nextMessy()
            }
        }
        func edgeCases() {
            format("clean.js") { _, r, _ in
                if case .unchanged = r { SelfTest.check("prettier-real: already formatted file is unchanged", true) } else { SelfTest.check("prettier-real: already formatted file is unchanged [\(describe(r))]", false) }
                format("ignored.js") { tab, r, _ in
                    SelfTest.check("prettier-real: .prettierignore'd file is left alone [\(describe(r))]", tab.textView.string == "const   x = {a:1}\n")
                    format("broken.js") { tab, r, _ in
                        if case .failed(_, let m) = r { SelfTest.check("prettier-real: syntax error reports a failure and keeps the buffer [\(m.prefix(60))]", tab.textView.string == "const = ;;\n") }
                        else { SelfTest.check("prettier-real: syntax error reports a failure [\(describe(r))]", false) }
                        format("crlf.js") { tab, r, _ in
                            SelfTest.check("prettier-real: CRLF file formats [\(describe(r))]", isFormatted(r) && tab.textView.string.contains("{ b: 1 }"))
                            try? "const a = {b:1}\nconst c = {d:2}\n".write(to: dir.appendingPathComponent("range.js"), atomically: true, encoding: .utf8)
                            format("range.js", selection: { s in (s as NSString).range(of: "const c = {d:2}") }) { tab, r, _ in
                                let out = tab.textView.string
                                SelfTest.check("prettier-real: selection formatting touches only the selection [\(describe(r))]", out.contains("const c = { d: 2 }") && out.contains("const a = {b:1}"))
                                finish()
                            }
                        }
                    }
                }
            }
        }
        func finish() {
            let sorted = latencies.sorted()
            fputs(String(format: "prettier-real: latency per format (ms): median %.0f, max %.0f over %d files\n", (sorted.isEmpty ? 0 : sorted[sorted.count / 2]) * 1000, (sorted.last ?? 0) * 1000, sorted.count), stderr)
            if let tool = FormatTools.detect(for: dir.appendingPathComponent("app.js")), let v = FormatTools.prettierVersion(tool) { fputs("prettier-real: Prettier \(v), global=\(tool.global)\n", stderr) }
            done()
        }
        nextMessy()
    }
}
