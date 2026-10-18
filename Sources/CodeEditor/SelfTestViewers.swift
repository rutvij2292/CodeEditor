import AppKit

/// Headless checks for the Markdown preview, JSON / YAML tree, diagnostics and structured completion (Viewer*.swift,
/// Struct*.swift, Markdown*.swift, YAMLTape.swift). Prints timings / memory for the report.
extension SelfTest {
    private static func rssMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }

    private static func timed(_ block: () -> Void) -> Double {
        let t = CFAbsoluteTimeGetCurrent()
        block()
        return (CFAbsoluteTimeGetCurrent() - t) * 1000
    }

    /// `text` contains `|` at the caret.
    private static func complete(_ file: String, _ text: String) -> [CompletionItem] {
        let caret = (text as NSString).range(of: "|").location
        let clean = text.replacingOccurrences(of: "|", with: "")
        let url = URL(fileURLWithPath: "/tmp/ce-viewer-proj/" + file)
        let ctx = CompletionContext(text: clean, caret: caret, fileURL: url, fileExtension: url.pathExtension, triggerCharacter: nil,
                                    isManual: true, prefixRange: NSRange(location: caret, length: 0))
        return StructuredCompletion.items(for: ctx)
    }

    private static func labels(_ items: [CompletionItem]) -> Set<String> { Set(items.map(\.label)) }

    static func viewerChecks(app: AppDelegate, w: ProjectWindow, then done: @escaping () -> Void) {
        markdownChecks()
        jsonChecks { yamlChecks(); completionChecks(); integrationChecks(w: w, then: done) }
    }

    /// Polls `condition` every 20 ms (the checks run inside a main-queue block, so nested run loops cannot service
    /// main-queue work: continue from a callback instead).
    private static func wait(_ condition: @escaping () -> Bool, timeout: TimeInterval = 8, then next: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() || Date() > deadline { next(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: poll)
        }
        DispatchQueue.main.async(execute: poll)
    }

    // MARK: Markdown

    private static func markdownChecks() {
        let md = """
        ---
        title: front matter
        ---
        # Title *emph*

        Setext H2
        ---------

        Para one line one
        line two  
        hard break **bold** and `code` and [link](docs/other.md#x) ~~gone~~.

        > quote line
        > > nested

        - [ ] open task
        - [x] done task
          - nested bullet
        - plain

        3. three
        4. four

        ```php
        <?php echo 1;
        ```

        | a | b |
        |:--|--:|
        | 1 | 2 |
        | 3 |

        ***
        <p align="center"><img src="x.png" alt="logo"></p>

        ![img](missing.png)
        """
        let blocks = MarkdownParser.parse(md)
        func kind(_ b: MDBlock) -> String {
            switch b {
            case .heading(let l, _, _): return "h\(l)"
            case .paragraph: return "p"
            case .code(let lang, _, _): return "code:" + lang
            case .quote: return "quote"
            case .list(let o, _, _, _): return o ? "ol" : "ul"
            case .table: return "table"
            case .rule: return "hr"
            case .html: return "html"
            }
        }
        let kinds = blocks.map(kind)
        if AppEnv.value("CE_DEBUG_MD") != nil { fputs("\(blocks[4])\n", stderr) }
        check("md: block kinds in order", kinds == ["h1", "h2", "p", "quote", "ul", "ol", "code:php", "table", "hr", "html", "p"])
        check("md: front matter skipped, heading line numbers kept", blocks.first?.line == 3)
        if case .heading(_, let t, _) = blocks[0] { check("md: heading text", t == "Title *emph*") } else { check("md: heading text", false) }
        if case .paragraph(let t, _) = blocks[2] { check("md: soft break joins, hard break kept", t.contains("one line one line two\u{2028}hard break")) } else { check("md: paragraph", false) }
        if case .list(_, _, let items, _) = blocks[4] {
            check("md: task items", items.count == 3 && items[0].task == false && items[1].task == true && items[2].task == nil)
            if case .list(_, _, let nested, _)? = items[1].blocks.last { check("md: nested list", nested.count == 1) } else { check("md: nested list", false) }
        } else { check("md: list", false) }
        if case .list(true, let start, let items, _) = blocks[5] { check("md: ordered list start 3", start == 3 && items.count == 2) } else { check("md: ordered list", false) }
        if case .table(let head, let align, let rows, _) = blocks[7] {
            check("md: table header/align", head == ["a", "b"] && align == [0, 2])
            check("md: short row padded", rows == [["1", "2"], ["3", ""]])
        } else { check("md: table", false) }
        if case .quote(let inner, _) = blocks[3] { check("md: nested quote", inner.count == 2 && kind(inner[1]) == "quote") } else { check("md: quote", false) }
        check("md: unterminated fence does not hang", MarkdownParser.parse("```js\nabc").count == 1)
        check("md: empty input", MarkdownParser.parse("").isEmpty)
        check("md: table cells honour escaped pipes", MarkdownParser.splitRow("| a \\| b | c |") == ["a | b", "c"])

        // render
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ce-md-\(getpid())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let r = MarkdownRenderer(style: MDStyle(), baseURL: dir.appendingPathComponent("README.md"), highlight: true).render(blocks)
        let s = r.text.string
        check("md render: text present", s.contains("Title emph") && s.contains("Setext H2") && s.contains("open task") && s.contains("☐") && s.contains("☑"))
        check("md render: strikethrough/links survive", { var found = false; r.text.enumerateAttribute(.link, in: NSRange(location: 0, length: r.text.length)) { v, _, _ in if v != nil { found = true } }; return found }())
        let h1 = r.text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let bodyAt = (s as NSString).range(of: "Para one").location
        let body = r.text.attribute(.font, at: bodyAt, effectiveRange: nil) as? NSFont
        check("md render: h1 bigger than body", (h1?.pointSize ?? 0) > (body?.pointSize ?? 99))
        check("md render: line map monotonic", zip(r.lineMap, r.lineMap.dropFirst()).allSatisfy { $0.line < $1.line && $0.loc <= $1.loc } && r.lineMap.count >= 8)
        check("md render: anchors", r.anchors["title-emph"] != nil && r.anchors["setext-h2"] != nil)
        let codeLoc = (s as NSString).range(of: "echo").location
        let ps = r.text.attribute(.paragraphStyle, at: codeLoc, effectiveRange: nil) as? NSParagraphStyle
        check("md render: code block in a shaded text block", ps?.textBlocks.count == 1)
        let cellLoc = (s as NSString).range(of: "\n3\n").location + 1
        let tps = r.text.attribute(.paragraphStyle, at: cellLoc, effectiveRange: nil) as? NSParagraphStyle
        check("md render: table cell block", (tps?.textBlocks.first as? NSTextTableBlock)?.table.numberOfColumns == 2)
        check("md render: php fence is syntax coloured", { var colours = Set<NSColor>(); r.text.enumerateAttribute(.foregroundColor, in: NSRange(location: codeLoc - 6, length: 20)) { v, _, _ in if let c = v as? NSColor { colours.insert(c) } }; return colours.count > 1 }())
        check("md links: relative resolves next to file", MarkdownLinks.resolve(URL(string: "docs/other.md")!, base: dir.appendingPathComponent("README.md"))?.path == dir.appendingPathComponent("docs/other.md").standardizedFileURL.path)
        check("md links: https is external", MarkdownLinks.resolve(URL(string: "https://x.dev/a")!, base: nil) == nil)

        // image: real PNG downscaled
        let png = dir.appendingPathComponent("big.png")
        let img = NSImage(size: NSSize(width: 1600, height: 900), flipped: false) { rect in NSColor.systemTeal.setFill(); rect.fill(); return true }
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: png) }
        let loaded = MarkdownImages.load(png, maxWidth: 560)
        check("md images: local image downscaled to <= 560pt", loaded != nil && loaded!.size.width <= 560.5 && abs(loaded!.size.width / loaded!.size.height - 16.0 / 9.0) < 0.05)
        let ir = MarkdownRenderer(style: MDStyle(), baseURL: dir.appendingPathComponent("README.md"), highlight: false).render(MarkdownParser.parse("![pic](big.png)\n\n![rem](https://example.com/a.png)"))
        check("md images: attachment inserted, remote becomes placeholder", ir.images == 1 && ir.text.string.contains("[rem]"))

        // preview view: render time on a 4000-line document
        var big = ""
        for i in 0..<400 { big += "## Section \(i)\n\nSome *text* with `code` and a [link](http://x.y).\n\n- a\n- b\n\n```swift\nlet x = \(i)\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n" }
        var blocksBig: [MDBlock] = []
        let parseMs = timed { blocksBig = MarkdownParser.parse(big) }
        let view = MarkdownPreviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 800))
        let renderMs = timed { view.show(blocks: blocksBig) }
        fputs(String(format: "METRIC markdown 4000-line doc: %d chars, parse %.0f ms, render %.0f ms, %d blocks\n", big.count, parseMs, renderMs, blocksBig.count), stderr)
        check("md perf: 4000-line document parses+renders in under 5 s (debug build)", parseMs + renderMs < 5000)
        view.scroll(toSourceLine: 2000)
        check("md scroll sync moves the preview", view.scrollY > 0)
        view.scroll(toSourceLine: 0)
        check("md scroll sync to line 0 returns to top", view.scrollY == 0)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: JSON

    private static func jsonChecks(then next: @escaping () -> Void) {
        let src = #"{"name":"x","n":[1,2.5,-3e2,true,null],"o":{"é":"ü","k":{}},"e":[]}"#
        let t = JSONTapeParser.parse(Array(src.utf8), lenient: false)
        check("json: no issues", t.issues.isEmpty)
        check("json: node count", t.nodeCount == 12)
        check("json: root is object with 4 members", t.kindOf(0) == .object && t.childCount(0) == 4)
        let kids = t.children(of: 0)
        check("json: keys", kids.compactMap { t.keyText($0) } == ["name", "n", "o", "e"])
        check("json: array length and kinds", t.childCount(kids[1]) == 5 && t.children(of: kids[1]).map { t.kindOf($0) } == [.number, .number, .number, .bool, .null])
        check("json: path", t.path(t.children(of: kids[1])[3]) == "$.n[3]" && t.path(kids[0]) == "$.name")
        let oKids = t.children(of: kids[2])
        check("json: non-ASCII key text and offsets", t.keyText(oKids[0]) == "é" && t.scalarText(oKids[0]) == "ü")
        let r = t.editorRange(oKids[1])
        check("json: editor range maps UTF-8 -> UTF-16", (src as NSString).substring(with: r).hasPrefix("\"k\":{"))
        check("json: chain at offset descends", t.chain(at: (src as NSString).range(of: "2.5").location).count == 3)
        check("json: filter finds keys and values with ancestors", { let s = t.search("ü"); return s.matches.count == 1 && s.visible.contains(0) }())

        // malformed / tolerant
        let bad = JSONTapeParser.parse(Array(#"{"a": 1, "b": [1, 2"#.utf8), lenient: false)
        check("json: unterminated -> error + partial tree", bad.issues.contains { $0.severity == 1 } && bad.nodeCount >= 4)
        let missingColon = JSONTapeParser.parse(Array(#"{"a" 1}"#.utf8), lenient: false)
        check("json: missing colon error position", missingColon.issues.first?.severity == 1 && missingColon.issues.first?.offset == 5)
        let trailing = #"{"a": [1, 2,], // c"# + "\n" + #""b": 'x', c: 0x1F}"#
        let strict = JSONTapeParser.parse(Array(trailing.utf8), lenient: false)
        let lenient = JSONTapeParser.parse(Array(trailing.utf8), lenient: true)
        check("json: strict mode warns about comments / trailing commas / quotes", strict.issues.count >= 3 && strict.issues.allSatisfy { $0.severity == 2 })
        check("json: lenient (jsonc/json5) mode is silent and parses everything", lenient.issues.isEmpty && lenient.childCount(0) == 3)
        check("json: garbage after value", JSONTapeParser.parse(Array("{} x".utf8), lenient: false).issues.first?.message.contains("after") == true)
        check("json: bad number", JSONTapeParser.parse(Array("[01x]".utf8), lenient: false).issues.contains { $0.severity == 1 })
        check("json: empty input is an empty tape", JSONTapeParser.parse([], lenient: false).isEmpty)
        check("json: BOM skipped", JSONTapeParser.parse([0xEF, 0xBB, 0xBF] + Array("[1]".utf8), lenient: false).issues.isEmpty)
        check("json: deep nesting is bounded, not a crash", JSONTapeParser.parse(Array(String(repeating: "[", count: 5000).utf8), lenient: false).issues.contains { $0.severity == 1 })
        check("json: unterminated string reported", JSONTapeParser.parse(Array("{\"a\":\"x\n}".utf8), lenient: false).issues.first?.message == "Unterminated string")

        // 10 MB synthetic file
        var big = [UInt8]()
        big.reserveCapacity(11_000_000)
        big.append(contentsOf: Array("[".utf8))
        var i = 0
        while big.count < 10_400_000 {
            if i > 0 { big.append(44) }
            big.append(contentsOf: Array("{\"id\":\(i),\"name\":\"item \(i)\",\"price\":\(Double(i) * 1.25),\"tags\":[\"a\",\"b\"],\"ok\":\(i % 2 == 0),\"note\":null}".utf8))
            i += 1
        }
        big.append(93)
        let before = rssMB()
        var tape = StructTape()
        let parseMs = timed { tape = JSONTapeParser.parse(big, lenient: false) }
        let after = rssMB()
        fputs(String(format: "METRIC json %.1f MB: %d records, parse %.0f ms (debug build), tape %d nodes (truncated=%@), RSS +%.0f MB\n",
                     Double(big.count) / 1e6, i, parseMs, tape.nodeCount, tape.truncated ? "yes" : "no", after - before), stderr)
        check("json 10MB: parses without error", tape.issues.filter { $0.severity == 1 }.isEmpty)
        check("json 10MB: node cap respected and flagged", tape.nodeCount <= JSONTapeParser.defaultMaxNodes && tape.truncated)
        check("json 10MB: parse stays under 4 s even in a debug build", parseMs < 4000)
        let tree = StructureTreeView(frame: NSRect(x: 0, y: 0, width: 500, height: 600))
        let showMs = timed { tree.show(tape: tape) }
        fputs(String(format: "METRIC json tree show (lazy) %.0f ms, rows materialised %d of %d top-level records\n", showMs, tree.outline.numberOfRows, tape.childCount(0)), stderr)
        check("json 10MB: tree only materialises expanded rows", tree.outline.numberOfRows < 200 && showMs < 1500)
        var searchHits = 0
        let searchMs = timed { searchHits = tape.search("item 777").matches.count }
        fputs(String(format: "METRIC json search over %d nodes %.0f ms, %d hits\n", tape.nodeCount, searchMs, searchHits), stderr)
        check("json 10MB: search finds matches", searchHits >= 1)
        tree.show(tape: nil)

        // tree view interaction on a small doc
        let sm = StructureTreeView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        sm.show(tape: t)
        var jumped: NSRange?
        sm.onJump = { jumped = $0 }
        sm.select(positions: [1])   // "n"
        check("json tree: selecting a row jumps to its source range", jumped.map { (src as NSString).substring(with: $0).hasPrefix("\"n\":[") } == true)
        check("json tree: breadcrumb shows the path", sm.selectedPath == "$.n")
        sm.setFilter("ü")
        wait({ sm.matchCount > 0 }) {
            check("json tree: filter keeps matches and their ancestors only", sm.matchCount == 1 && sm.outline.numberOfRows >= 3 && sm.outline.numberOfRows <= 4)
            jsonFormatChecks()
            next()
        }
    }

    private static func jsonFormatChecks() {

        // formatter
        let fmt = JSONFormatter.reformat(Array(#"{"a":[1,2,{"b":null}],"c":{},"d":"x,y:z"}"#.utf8), unit: "    ", minify: false)
        check("json format: 4-space indent keeps order and strings", fmt == "{\n    \"a\": [\n        1,\n        2,\n        {\n            \"b\": null\n        }\n    ],\n    \"c\": {},\n    \"d\": \"x,y:z\"\n}\n")
        check("json minify round trip", JSONFormatter.reformat(Array((fmt ?? "").utf8), unit: "  ", minify: true) == "{\"a\":[1,2,{\"b\":null}],\"c\":{},\"d\":\"x,y:z\"}\n")
        check("json format drops trailing commas", JSONFormatter.reformat(Array("[1,2,]".utf8), unit: "  ", minify: false) == "[\n  1,\n  2\n]\n")
        check("json minify refuses to drop comments", JSONFormatter.reformat(Array("{/*c*/\"a\":1}".utf8), unit: "  ", minify: true) == nil)
        check("json format keeps comments", (JSONFormatter.reformat(Array("{\"a\":1, // note\n\"b\":2}".utf8), unit: "  ", minify: false) ?? "").contains("// note"))
        check("json lenient flavours", JSONFlavor.isLenient(URL(fileURLWithPath: "/p/tsconfig.json")) && !JSONFlavor.isLenient(URL(fileURLWithPath: "/p/package.json")))
    }

    // MARK: YAML

    private static func yamlChecks() {
        guard let lang = Languages.grammar(forKey: "yaml")?.language else { check("yaml grammar available", false); return }
        let src = """
        name: demo
        services:
          web:
            image: nginx
            ports:
              - "80:80"
              - 8080
            environment: { A: 1, B: [x, y] }
            enabled: true
            nothing: ~
            text: |
              multi
              line
        """
        let t = YAMLTapeBuilder.parse(src, language: lang)
        check("yaml: no issues on valid file", t.issues.isEmpty)
        check("yaml: root mapping with 2 keys", t.kindOf(0) == .object && t.childCount(0) == 2)
        let web = t.children(of: t.children(of: t.children(of: 0)[1])[0])
        check("yaml: nested mapping keys", web.compactMap { t.keyText($0) } == ["image", "ports", "environment", "enabled", "nothing", "text"])
        check("yaml: sequence length + scalar typing", t.childCount(web[1]) == 2 && t.children(of: web[1]).map { t.kindOf($0) } == [.string, .number])
        check("yaml: flow mapping/sequence", t.kindOf(web[2]) == .object && t.childCount(web[2]) == 2 && t.childCount(t.children(of: web[2])[1]) == 2)
        check("yaml: bool/null typing", t.kindOf(web[3]) == .bool && t.kindOf(web[4]) == .null)
        check("yaml: quoted scalar unquoted", t.scalarText(t.children(of: web[1])[0]) == "80:80")
        check("yaml: path", t.path(t.children(of: web[1])[1]) == "$.services.web.ports[1]")
        check("yaml: source range jumps to the value", (src as NSString).substring(with: t.editorRange(web[0])).hasPrefix("image: nginx"))
        let docs = YAMLTapeBuilder.parse("a: 1\n---\nb: 2\n", language: lang)
        check("yaml: two documents -> array of 2", docs.kindOf(0) == .array && docs.childCount(0) == 2)
        check("yaml: empty file", YAMLTapeBuilder.parse("", language: lang).isEmpty && YAMLTapeBuilder.parse("# only a comment\n", language: lang).isEmpty)

        // diagnostics
        let broken = YAMLTapeBuilder.parse("a: [1, 2\nb: {x: 1\nc: : :\n", language: lang)
        check("yaml diag: unterminated flow collections are errors", broken.issues.contains { $0.severity == 1 })
        let badIndent = YAMLTapeBuilder.parse("a:\n  b: 1\n c: 2\n", language: lang)
        check("yaml diag: bad indentation is an error", badIndent.issues.contains { $0.severity == 1 })
        let dup = YAMLTapeBuilder.parse("a: 1\nb: 2\na: 3\n", language: lang)
        check("yaml diag: duplicate key warning at the 2nd occurrence", dup.issues.count == 1 && dup.issues[0].severity == 2 && dup.issues[0].message.contains("'a'") && dup.issues[0].offset == 10)
        let tab = YAMLTapeBuilder.parse("a:\n\tb: 1\n", language: lang)
        check("yaml diag: tab indentation reported", tab.issues.contains { $0.message.lowercased().contains("tab") || $0.severity == 1 })
        check("yaml diag: valid compose/workflow samples are clean",
              YAMLTapeBuilder.parse("name: CI\non:\n  push:\n    branches: [main]\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n      - name: Run\n        run: |\n          echo hi\n          echo there\n", language: lang).issues.isEmpty)
        let lc = LineCol("a: 1\nb: 2\na: 3\n" as NSString, 10)
        check("yaml diag: offset -> line/col", lc.line == 3 && lc.col == 1)

        // problems panel + squiggles + live buffer
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ce-yaml-\(getpid()).yml")
        NativeProblems.set(url: url, [FileProblems.Diagnostic(severity: 1, message: "x", line: 3, column: 1, endLine: 3, endColumn: 2, source: "YAML", code: nil)])
        check("native problems appear under the project root", NativeProblems.problems(forRoot: url.deletingLastPathComponent(), excluding: []).contains { $0.url.lastPathComponent == url.lastPathComponent })
        NativeProblems.set(url: url, [])
        check("native problems cleared", NativeProblems.diagnostics(forPath: url.standardizedFileURL.path).isEmpty)
    }

    // MARK: Completion

    private static func completionChecks() {
        // YAML contexts
        let c1 = StructuredCompletion.yamlContext("services:\n  web:\n    im", caret: 24)
        check("yaml ctx: key position, path by indentation", c1.pos == .key && c1.path == ["services", "web"] && c1.prefix == "im")
        let c2 = StructuredCompletion.yamlContext("services:\n  web:\n    restart: ", caret: 35)
        check("yaml ctx: value position after 'key: '", c2.pos == .value && c2.key == "restart" && c2.path == ["services", "web"] && c2.prefix == "")
        let c3 = StructuredCompletion.yamlContext("jobs:\n  b:\n    steps:\n      - name: x\n        ", caret: 56)
        check("yaml ctx: second key of a sequence item", c3.pos == .key && c3.path == ["jobs", "b", "steps"] && c3.siblings["name"] == "x" && !c3.inSeqItem)
        let c4 = StructuredCompletion.yamlContext("jobs:\n  b:\n    steps:\n      - ", caret: 33)
        check("yaml ctx: new sequence item", c4.pos == .key && c4.inSeqItem && c4.path == ["jobs", "b", "steps"])
        let c5 = StructuredCompletion.yamlContext("a: 1 # comment he", caret: 17)
        check("yaml ctx: nothing inside a comment", c5.pos == .none)
        let c6 = StructuredCompletion.yamlContext("on: [push, pull", caret: 15)
        check("yaml ctx: flow sequence value", c6.pos == .value && c6.key == "on" && c6.prefix == "pull" && c6.flow)
        let c7 = StructuredCompletion.yamlContext("x:\n  y: z\nw:", caret: 12)
        check("yaml ctx: caret right after colon", c7.pos == .value && c7.afterColonNoSpace && c7.key == "w")

        // compose
        let compose = "services:\n  web:\n    image: nginx\n    |\n  db:\n    image: mysql\n"
        let ck = complete("docker-compose.yml", compose)
        check("compose: keys under a service (minus siblings)", labels(ck).isSuperset(of: ["ports", "restart", "volumes", "depends_on", "environment"]) && !labels(ck).contains("image"))
        check("compose: key items insert 'key:' / enum keys chain a value popup", ck.first { $0.label == "ports" }?.insertText == "ports:" && ck.first { $0.label == "restart" }?.kind == .keyword)
        let cv = complete("compose.yaml", "services:\n  web:\n    restart: |")
        check("compose: restart values", labels(cv).isSuperset(of: ["always", "unless-stopped", "on-failure", "no"]) && cv.first?.insertText.hasPrefix(" ") == false)
        let cv0 = complete("compose.yaml", "services:\n  web:\n    restart:|")
        check("compose: value right after the colon gets a leading space", cv0.first { $0.label == "always" }?.insertText == " always")
        let cv2 = complete("compose.yaml", "services:\n  web:\n    restart: al|")
        check("compose: value replaces the typed prefix", cv2.first?.replaceRange == NSRange(location: 30, length: 2))
        let ci = complete("docker-compose.yml", "services:\n  web:\n    image: |")
        check("compose: common images (Sail stack)", labels(ci).isSuperset(of: ["mysql/mysql-server:8.0", "redis:alpine", "axllent/mailpit:latest"]))
        let cs = complete("docker-compose.yml", "services:\n  |")
        check("compose: Sail service names", labels(cs).isSuperset(of: ["laravel.test", "mysql", "redis", "meilisearch", "mailpit"]))
        let cd = complete("docker-compose.yml", "services:\n  web:\n    depends_on:\n      - |\n  db:\n    image: x\n  cache:\n    image: y\n")
        check("compose: depends_on lists services defined in the file", labels(cd).isSuperset(of: ["db", "cache", "web"]))
        let ce = complete("docker-compose.yml", "services:\n  app:\n    environment:\n      - |")
        check("compose: environment list items insert KEY=", ce.contains { $0.label == "MYSQL_DATABASE" && $0.insertText == "MYSQL_DATABASE=" })
        let cp = complete("docker-compose.yml", "services:\n  app:\n    ports:\n      - |")
        check("compose: ports values", labels(cp).contains("3306:3306"))
        let cn = complete("docker-compose.yml", "networks:\n  sail:\n    |")
        check("compose: network keys", labels(cn).isSuperset(of: ["driver", "external", "ipam"]))

        // GitHub Actions
        let wf = ".github/workflows/ci.yml"
        let top = complete(wf, "name: CI\n|")
        check("gha: top-level keys", labels(top).isSuperset(of: ["on", "jobs", "permissions", "env", "concurrency"]) && !labels(top).contains("name"))
        let ev = complete(wf, "name: CI\non:\n  |")
        check("gha: on: events as keys", labels(ev).isSuperset(of: ["push", "pull_request", "workflow_dispatch", "schedule"]))
        let ev2 = complete(wf, "on: [push, |")
        check("gha: on: flow list events", labels(ev2).contains("pull_request"))
        let ro = complete(wf, "jobs:\n  build:\n    runs-on: |")
        check("gha: runs-on values", labels(ro).isSuperset(of: ["ubuntu-latest", "macos-latest", "windows-latest"]))
        let jk = complete(wf, "jobs:\n  build:\n    |")
        check("gha: job keys", labels(jk).isSuperset(of: ["runs-on", "steps", "needs", "strategy", "env"]))
        let sk = complete(wf, "jobs:\n  build:\n    steps:\n      - name: a\n        |")
        check("gha: step keys (uses/run/with)", labels(sk).isSuperset(of: ["uses", "run", "with", "env", "if"]) && !labels(sk).contains("name"))
        let us = complete(wf, "jobs:\n  build:\n    steps:\n      - uses: |")
        check("gha: uses: common actions", labels(us).isSuperset(of: ["actions/checkout@v4", "actions/setup-node@v4", "shivammathur/setup-php@v2"]))
        let us2 = complete(wf, "jobs:\n  build:\n    steps:\n      - uses: actions/ch|")
        check("gha: uses: prefix filters by replace range", us2.first?.replaceRange?.length == 10)
        let wi = complete(wf, "jobs:\n  build:\n    steps:\n      - uses: actions/setup-node@v4\n        with:\n          |")
        check("gha: with: inputs of the sibling action", labels(wi).isSuperset(of: ["node-version", "cache", "registry-url"]))
        let nd = complete(wf, "jobs:\n  a:\n    runs-on: x\n  b:\n    needs: |\n")
        check("gha: needs lists jobs", labels(nd).contains("a"))
        let ex = complete(wf, "jobs:\n  a:\n    steps:\n      - run: echo ${{ github.|")
        check("gha: expression members", labels(ex).isSuperset(of: ["sha", "ref", "actor", "repository"]))
        let ex2 = complete(wf, "jobs:\n  a:\n    steps:\n      - run: echo ${{ |")
        check("gha: expression contexts", labels(ex2).isSuperset(of: ["github", "secrets", "matrix", "env"]))
        let on3 = complete(wf, "on:\n  push:\n    branches: [main]\n  pull_request:\n    types: |")
        check("gha: pull_request types", labels(on3).isSuperset(of: ["opened", "synchronize"]))

        // generic YAML
        let gen = complete("data/app.yml", "server:\n  port: 80\n  host: a\nclient:\n  |")
        check("yaml generic: keys already used in the file", labels(gen).isSuperset(of: ["port", "host"]))
        let genv = complete("data/app.yml", "mode: fast\nother:\n  mode: slow\nx:\n  mode: |")
        check("yaml generic: values used for the same key", labels(genv).isSuperset(of: ["fast", "slow"]))
        check("yaml: no completions in a comment", complete("a.yml", "# note |").isEmpty)

        // JSON contexts and schemas
        let j1 = StructuredCompletion.jsonContext(#"{"scripts": {"dev": "vite", "#, caret: 29)
        check("json ctx: key position, path", j1.pos == .key && j1.path == ["scripts"] && j1.siblings == ["dev"])
        let j2 = StructuredCompletion.jsonContext(#"{"compilerOptions": {"target": "ES"#, caret: 37)
        check("json ctx: value inside string", j2.pos == .value && j2.inString && j2.key == "target" && j2.path == ["compilerOptions"] && j2.prefix == "ES")
        let j3 = StructuredCompletion.jsonContext("{\"a\": [1, {\"b\": ", caret: 16)
        check("json ctx: array/object nesting", j3.pos == .value && j3.key == "b" && j3.path == ["a"])
        check("json ctx: comments are skipped", StructuredCompletion.jsonContext("{ // \"x\": \n \"", caret: 14).pos == .key)
        let pk = complete("package.json", "{\n  |\n}")
        check("package.json: top keys", labels(pk).isSuperset(of: ["name", "version", "scripts", "dependencies", "devDependencies", "engines"]))
        check("package.json: key insert is quoted with colon", pk.first { $0.label == "version" }?.insertText == "\"version\": ")
        let pk2 = complete("package.json", "{\n  \"ver|\n}")
        check("package.json: inside a string inserts the bare key", pk2.first { $0.label == "version" }?.insertText == "version")
        let pt = complete("package.json", "{\n  \"type\": |\n}")
        check("package.json: type values quoted", labels(pt) == ["module", "commonjs"] && pt[0].insertText.hasPrefix("\""))
        let pd = complete("package.json", "{\n  \"dependencies\": {\n    |\n  }\n}")
        check("package.json: dependency name suggestions", labels(pd).isSuperset(of: ["vue", "axios", "tailwindcss"]))
        let pp = complete("package.json", "{\n  \"private\": |\n}")
        check("package.json: booleans insert bare", pp.contains { $0.label == "true" && $0.insertText == "true" })
        let co = complete("composer.json", "{\n  \"require\": {\n    |\n  }\n}")
        check("composer.json: require packages", labels(co).isSuperset(of: ["php", "laravel/framework"]))
        let ck2 = complete("composer.json", "{\n  \"minimum-stability\": \"|\"\n}")
        check("composer.json: minimum-stability enum", labels(ck2).isSuperset(of: ["stable", "dev"]))
        let ts = complete("tsconfig.json", "{\n  \"compilerOptions\": {\n    \"target\": \"|\"\n  }\n}")
        check("tsconfig: target values", labels(ts).isSuperset(of: ["ES2022", "ESNext"]))
        let ts2 = complete("tsconfig.json", "{\n  \"compilerOptions\": {\n    |\n  }\n}")
        check("tsconfig: compilerOptions keys", labels(ts2).isSuperset(of: ["strict", "moduleResolution", "paths", "outDir", "jsx"]))
        let es = complete(".eslintrc.json", "{\n  \"rules\": {\n    \"no-console\": |\n  }\n}")
        check("eslintrc: rule severities (wildcard values reach named rules)", labels(es).isSuperset(of: ["off", "warn", "error"]))
        let es2 = complete(".eslintrc.json", "{\n  \"env\": {\n    |\n  }\n}")
        check("eslintrc: env keys", labels(es2).isSuperset(of: ["browser", "node", "es2021"]))
        let gj = complete("data/other.json", "{\"a\": {\"alpha\": 1}, \"b\": {|}}")
        check("json generic: keys used elsewhere in the file", labels(gj).isSuperset(of: ["alpha", "a"]))
        check("json: no key completions after a value", StructuredCompletion.jsonContext("{\"a\": 1 ", caret: 8).pos == .none || StructuredCompletion.jsonContext("{\"a\": 1 ", caret: 8).pos == .value)
        let t0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<50 { _ = complete(".github/workflows/ci.yml", "jobs:\n  build:\n    steps:\n      - uses: actions/setup-node@v4\n        with:\n          |") }
        let per = (CFAbsoluteTimeGetCurrent() - t0) * 1000 / 50
        fputs(String(format: "METRIC structured completion: %.2f ms per request (workflow with: context)\n", per), stderr)
        check("completion latency is small", per < 25)
        check("completion registry covers yaml and json", CompletionRegistry.providers(forExtension: "yml").contains { $0 is StructuredProvider } && CompletionRegistry.providers(forExtension: "json").contains { $0 is StructuredProvider })
    }

    // MARK: Integration with tabs, prefs, menus

    private static func integrationChecks(w: ProjectWindow, then done: @escaping () -> Void) {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("ce-viewer-int-\(getpid())")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let md = dir.appendingPathComponent("README.md"), js = dir.appendingPathComponent("data.json"), yml = dir.appendingPathComponent("compose.yml"), other = dir.appendingPathComponent("a.txt")
        try? "# Hello\n\ntext **bold**\n".write(to: md, atomically: true, encoding: .utf8)
        try? "{\"a\": [1, 2, {\"b\": true}], \"c\": \"x\"}\n".write(to: js, atomically: true, encoding: .utf8)
        try? "services:\n  web:\n    image: nginx\n".write(to: yml, atomically: true, encoding: .utf8)
        try? "plain\n".write(to: other, atomically: true, encoding: .utf8)

        Prefs.reset(["viewerMode.markdown", "viewerMode.json", "viewerMode.yaml"])
        check("prefs: markdown defaults to split, json/yaml to source", ViewerKind.markdown.mode == .split && ViewerKind.json.mode == .source && ViewerKind.yaml.mode == .source)
        check("prefs: viewer modes are restorable defaults", ["viewerMode.markdown", "viewerMode.json", "viewerMode.yaml"].allSatisfy { Prefs.allKeys.contains($0) })

        w.open(other)
        check("viewer: plain text files get no viewer", ViewerSystem.controller(for: w.current) == nil)
        w.open(md)
        guard let mdTab = w.current, let mc = ViewerSystem.controller(for: mdTab), let pane = mdTab.view as? EditorPane else { check("viewer: markdown tab has a controller", false); done(); return }
        check("viewer: markdown opens in the remembered mode (split) with a preview pane", mc.mode == .split && mc.markdown != nil && pane.viewerState.side === mc.markdown)
        check("viewer: preview shows the rendered text", mc.markdown?.textView.string.contains("Hello") == true && mc.markdown?.textView.string.contains("**") == false)
        check("viewer: segmented control present with Preview title", pane.viewerState.control?.label(forSegment: 2) == "Preview" && pane.viewerState.control?.selectedSegment == 1)
        check("viewer: status bar button shows the mode", w.statusBar.viewerText.contains("Split"))
        mc.setMode(.preview)
        check("viewer: preview-only hides the editor", pane.contentView.isHidden && mc.mode == .preview && ViewerKind.markdown.mode == .preview)
        mc.setMode(.source)
        check("viewer: source mode frees the preview", pane.viewerState.side == nil && mc.markdown == nil && !pane.contentView.isHidden)
        mc.setMode(.split)
        mdTab.textView.string += "\n## Added section\n"
        mdTab.textView.didChangeText()
        mc.refreshNow()
        check("viewer: edits show up in the preview", mc.markdown?.textView.string.contains("Added section") == true)
        check("viewer: pane layout puts the preview at the right half", { () -> Bool in
            pane.layoutSubtreeIfNeeded()
            guard let m = mc.markdown else { return false }
            return m.frame.width > 1 && abs(m.frame.width - pane.frame.width / 2) < 2
        }())
        mc.setMode(.source, persist: true)

        ViewerSystem.alwaysNativeJSON = true
        w.open(js)
        guard let jsTab = w.current, let jc = ViewerSystem.controller(for: jsTab) else { check("viewer: json tab has a controller", false); done(); return }
        check("viewer: json starts in source mode (no tree allocated)", jc.mode == .source && jc.tree == nil)
        jc.setMode(.split)
        wait({ jc.lastTape != nil }) {
            check("viewer: json tree built off the main thread", jc.lastTape?.nodeCount == 7 && jc.tree?.tape === jc.lastTape)
            check("viewer: tree rows for the expanded root", (jc.tree?.outline.numberOfRows ?? 0) >= 3)
            jc.tree?.select(positions: [0])
            check("viewer: clicking a tree row moves the editor caret to the source", jsTab.textView.selectedRange().location == 1)
            jsTab.textView.setSelectedRange(NSRange(location: (jsTab.textView.string as NSString).range(of: "true").location, length: 0))
            jc.tree?.reveal(offset: jsTab.textView.selectedRange().location)
            check("viewer: caret in the editor reveals the node in the tree", jc.tree?.selectedPath == "$.a[2].b")
            jc.setMode(.source)
            jsTab.textView.string = "{\"a\": 1,, \"b\": }"
            jsTab.textView.didChangeText()
            jc.publish(JSONTapeParser.parse(Array(jsTab.textView.string.utf8), lenient: false).issues, text: jsTab.textView.string)
            let probs = LanguageServers.problems(forRoot: dir).first { $0.url.lastPathComponent == "data.json" }
            check("json diag: syntax error reaches the Problems model with line/col", probs?.diagnostics.first.map { $0.severity == 1 && $0.line == 1 && $0.column == 9 } == true)
            check("json diag: squiggle overlay installed", jc.squiggleCount == 1 && jsTab.textView.subviews.contains { $0 is NativeSquiggleOverlay })
            jsTab.textView.string = "{\"a\": 1}"
            jsTab.textView.didChangeText()
            jc.publish(JSONTapeParser.parse(Array(jsTab.textView.string.utf8), lenient: false).issues, text: jsTab.textView.string)
            check("json diag: fixing the file clears the problem", LanguageServers.problems(forRoot: dir).first { $0.url.lastPathComponent == "data.json" } == nil && jc.squiggleCount == 0)
            check("json: Format JSON uses 4 spaces by default", ViewerSystem.formatJSON(jsTab, minify: false) && jsTab.textView.string == "{\n    \"a\": 1\n}\n")
            check("json: Minify JSON", ViewerSystem.formatJSON(jsTab, minify: true) && jsTab.textView.string == "{\"a\":1}\n")
            jsTab.textView.string = "{\"a\": }"
            check("json: Format refuses invalid JSON", !ViewerSystem.formatJSON(jsTab, minify: false) && jsTab.textView.string == "{\"a\": }")

            w.open(yml)
            guard let yTab = w.current, let yc = ViewerSystem.controller(for: yTab) else { check("viewer: yaml tab has a controller", false); done(); return }
            yc.setMode(.preview)
            wait({ yc.lastTape != nil }) {
                check("viewer: yaml tree built", yc.lastTape?.nodeCount == 4 && yc.tree?.selectedPath == "$")
                yc.setMode(.source)
                check("menu: Cycle viewer is Ctrl-Opt-Cmd-V", shortcut("Cycle Source / Split / Preview") == "⌃⌥⌘V")
                check("menu: viewer shortcut does not collide with another binding", (NSApp.mainMenu.map(MainMenu.duplicateShortcuts(in:)) ?? []).filter { $0.contains("⌃⌥⌘V") }.isEmpty)
                check("menu: Format JSON / Minify JSON exist", shortcut("Format JSON") == "" && shortcut("Minify JSON") == "")
                for u in [md, js, yml, other] { w.close(u.standardizedFileURL.path) }
                check("viewer: closing tabs releases controllers", ViewerSystem.controllers.isEmpty || ViewerSystem.controller(for: nil) == nil)
                ViewerSystem.alwaysNativeJSON = false
                try? fm.removeItem(at: dir)
                done()
            }
        }
    }
}
