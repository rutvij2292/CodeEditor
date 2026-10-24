import AppKit

/// Regression and performance guards for the native PHP engine's hot paths (docblock query parsing, PHP-tag table, helper-function
/// byte scanner, byte-capped class cache, leak guard, memory trim). Thresholds are deliberately generous (debug build, loaded machine).
enum SelfTestNativePHPPerf {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("perf: " + name, ok()) }

    private static func ms(_ since: Date) -> Double { Date().timeIntervalSince(since) * 1000 }

    // MARK: Docblock query parsing

    private static func bigDoc(methods: Int) -> String {
        var s = "/**\n * Big class summary line one\n * continues here.\n *\n * @property string $label Display label\n * @property-read int $count\n * @see \\App\\Other\\Thing\n * @mixin \\App\\Mixed\\Helper\n * @template T of \\Foo\\Bar\n * @deprecated use something else\n"
        for i in 0..<methods {
            s += " * @method static \\Carbon\\Carbon make\(i)(string $v = null, int ...$rest) Make number \(i) \u{00e9}\u{4e2d}\n"
        }
        s += " * @method string wrapped(array $a,\n *     int $b) a continuation line\n"
        s += " * @return string\n */"
        return s
    }

    private static func docParity() {
        let raw = bigDoc(methods: 600)
        check("big docblock exceeds the lazy threshold", raw.utf8.count > NPDoc.bigDocBytes)
        let full = NPDoc.parse(raw, start: 120)
        for name in ["make0", "make299", "make599", "wrapped", "nothere"] {
            let q = NPDoc.parse(raw, start: 120, query: .method(name))
            let a = full.methods.first { $0.name == name }, b = q.methods.first { $0.name == name }
            check("query @method \(name) equals the full parse", a?.name == b?.name && a?.line == b?.line && a?.loc == b?.loc)
        }
        for name in ["label", "count", "nothere"] {
            let q = NPDoc.parse(raw, start: 120, query: .prop(name))
            let a = full.props.first { $0.name == name }, b = q.props.first { $0.name == name }
            check("query @property \(name) equals the full parse", a?.name == b?.name && a?.type == b?.type && a?.loc == b?.loc && a?.readOnly == b?.readOnly)
        }
        let s = NPDoc.parse(raw, start: 120, query: .sees)
        check("query @see/@mixin equals the full parse", s.sees == full.sees && s.sees.count == 2)
        let c = NPDoc.parse(raw, start: 120, query: .classInfo)
        check("class info query keeps summary, deprecation, return and templates",
              c.summary == full.summary && c.deprecated == full.deprecated && c.ret?.type == full.ret?.type && c.raw.contains("@template T of") && !c.raw.isEmpty)
        check("class info query does not build the @method list", c.methods.isEmpty)
        let small = "/**\n * Small.\n * @return int\n */"
        check("small docblocks are parsed whole", NPDoc.parse(small, query: .sees).ret?.type == "int")
        let t0 = Date()
        let huge = bigDoc(methods: 6000)
        for _ in 0..<5 { _ = NPDoc.parse(huge, start: 0, query: .method("make5999")) }
        check("query parse of a 6000 line docblock is fast (\(Int(ms(t0) / 5)) ms each)", ms(t0) / 5 < 150)
    }

    // MARK: PHP tag table (inPHP)

    private static func inPHPReference(_ ns: NSString, _ offset: Int) -> Bool {
        func last(_ s: String, before: Int) -> Int {
            guard before > 0 else { return -1 }
            let r = ns.range(of: s, options: [.backwards, .literal], range: NSRange(location: 0, length: min(before, ns.length)))
            return r.location == NSNotFound ? -1 : r.location
        }
        let o = last("<?", before: offset + 2), c = last("?>", before: offset)
        if o >= 0 { return o > c }
        return ns.range(of: "<?", options: .literal).location == NSNotFound
    }

    private static func tagTable(_ root: URL, _ fp: FastProject) {
        let samples = ["<?php\necho 1;\n", "<h1>x</h1>\n<?php echo $a; ?>\n<p>y</p>\n<?= $b ?>\n<footer/>", "plain text without tags", "<?php if ($a): ?>\n  html\n<?php endif; ?>",
                       "<??>?><?<?php ?>", "", "<", "<?", "?>", "a<?b?>c<?d"]
        var ok = true
        for (si, text) in samples.enumerated() {
            let ns = text as NSString
            let url = root.appendingPathComponent("app/Tag\(si).php")
            for off in 0...ns.length {
                let r = NativePHP.resolver(fp: fp, url: url, text: ns)
                if r.inPHP(off) != inPHPReference(ns, off) { ok = false; fputs("inPHP mismatch sample \(si) offset \(off)\n", stderr) }
            }
        }
        check("PHP tag table gives the same answers as the backwards substring search", ok)
        // chunk boundaries: a tag pair straddling the 4096 boundary
        let pad = String(repeating: "x", count: 4095)
        let straddle = ("<?php " + pad + "?>tail<?php" as NSString)
        var ok2 = true
        for off in stride(from: 4085, through: min(straddle.length, 4120), by: 1) {
            let r = NativePHP.resolver(fp: fp, url: root.appendingPathComponent("app/Tag99.php"), text: straddle)
            if r.inPHP(off) != inPHPReference(straddle, off) { ok2 = false }
        }
        check("PHP tag table handles tags across chunk boundaries", ok2)
    }

    // MARK: Helper function byte scanner

    private static func funcScan() {
        let src = """
        <?php
        namespace Foo;
        const ALPHA = 1;
        define('BETA', 2);
        if (! function_exists('route')) {
            /** doc */
            function route($name) { return 1; }
        }
        function &refd() { return $x; }
        class K { public function method() {} public static function sm() {} private  function  pm() {} function bare() {} }
        function   spaced   ( $a ) {}
        $f = function ($x) { return $x; };
        const OMEGA
            = 3;
        """
        guard let data = src.data(using: .utf8), let r = NPFuncIndex.scanBytes(data) else { check("byte scanner accepts ASCII", false); return }
        let names = r.functions.map(\.name)
        check("byte scanner finds helper functions", names.contains("route") && names.contains("refd") && names.contains("spaced"))
        check("byte scanner skips methods with modifiers", !names.contains("method") && !names.contains("sm") && !names.contains("pm"))
        check("byte scanner keeps modifier-less nested function", names.contains("bare"))
        check("byte scanner finds constants", r.constants.map(\.name).sorted() == ["ALPHA", "BETA", "OMEGA"])
        let ns = src as NSString
        if let route = r.functions.first(where: { $0.name == "route" }) {
            check("byte scanner offsets point at the name / declaration", ns.substring(with: NSRange(location: route.loc, length: 5)) == "route" && ns.substring(from: route.declStart + 1).hasPrefix("function route"))
        } else { check("route offsets", false) }
        check("non-ASCII files fall back to the regex path", NPFuncIndex.scanBytes("<?php // \u{00e9}\nfunction a() {}".data(using: .utf8)!) == nil)
    }

    // MARK: Class cache, leak guard, trim

    private static func caches(_ root: URL, _ fp: FastProject) {
        for i in 0..<450 {
            SelfTestNativePHP.put(root, "app/Gen/G\(i).php", "<?php\nnamespace App\\Gen;\nclass G\(i) {\n    public function m\(i)(int $a): int { return $a; }\n}\n")
        }
        fp.queue.sync {
            for i in 0..<450 { _ = fp.classInfo(path: root.path + "/app/Gen/G\(i).php") }
        }
        let (count, bytes) = fp.queue.sync { (fp.cachedClassCount, fp.cachedClassBytes) }
        check("class cache stays within its entry cap (\(count))", count <= FastProject.maxClasses && count > 100)
        check("class cache stays within its byte cap (\(bytes) bytes)", bytes <= FastProject.maxClassBytes)
        let before = NPStats.parses
        fp.queue.sync { _ = fp.classInfo(path: root.path + "/app/Gen/G449.php") }
        check("most recently used class is still cached (no re-parse)", NPStats.parses == before)
        // a class that is clearly big is accounted for
        var big = "<?php\nnamespace App\\Gen;\nclass Big {\n"
        for i in 0..<2000 { big += "    public function method\(i)(array $a, string $b = 'x'): ?string { return null; }\n" }
        SelfTestNativePHP.put(root, "app/Gen/Big.php", big + "}\n")
        let sz = fp.queue.sync { fp.classInfo(path: root.path + "/app/Gen/Big.php")?.approxBytes } ?? 0
        check("approxBytes grows with the member count (\(sz))", sz > 100_000)

        // leak guard
        let fix = "<?php\nnamespace App\\Gen;\nuse App\\Gen\\G1;\nclass Leak {\n    public function go(G1 $g) {\n        $x = 1;\n        return $g->m1($x) + $undefinedVar;\n    }\n}\n"
        let url = root.appendingPathComponent("app/Gen/Leak.php")
        SelfTestNativePHP.put(root, "app/Gen/Leak.php", fix)
        let base = NPDiagContext.liveCount
        fp.queue.sync { for _ in 0..<30 { _ = NativePHPDiag.analyze(url: url, text: fix as NSString, fp: fp) } }
        check("diagnostics contexts are freed after each analysis (live \(NPDiagContext.liveCount - base))", NPDiagContext.liveCount - base == 0)

        // trim
        let t = NativePHP.lookup(url: url, text: fix as NSString, offset: (fix as NSString).range(of: "m1").location + 1, root: root.path)
        check("lookup before trim resolves", t?.targets.isEmpty == false)
        NativePHP.trimMemory()
        let drained = DispatchSemaphore(value: 0)
        fp.queue.async { drained.signal() }
        _ = drained.wait(timeout: .now() + 5)
        check("trim empties the file text cache and the class cache", NPFiles.cachedCount == 0 && fp.queue.sync { fp.cachedClassCount } == 0)
        let t2 = NativePHP.lookup(url: url, text: fix as NSString, offset: (fix as NSString).range(of: "m1").location + 1, root: root.path)
        check("lookup after trim gives the same answer", t2?.targets.first?.path == t?.targets.first?.path && t2?.targets.first?.line == t?.targets.first?.line)
    }

    // MARK: Lookups against a Carbon-like class

    private static func bigClass(_ root: URL, _ fp: FastProject) {
        var doc = "/**\n * Carbon-like facade\n *\n"
        for i in 0..<3000 { doc += " * @method static string helper\(i)(int $a) Helper \(i)\n" }
        doc += " */\n"
        SelfTestNativePHP.put(root, "vendor/laravel/framework/src/Illuminate/Support/Big.php", "<?php\nnamespace Illuminate\\Support;\n" + doc + "class Big {\n    public static function real(): string { return ''; }\n}\n")
        let src = "<?php\nnamespace App;\nuse Illuminate\\Support\\Big;\nclass UsesBig {\n    public function go() {\n        Big::helper2999(1);\n        Big::real();\n    }\n}\n"
        let url = root.appendingPathComponent("app/UsesBig.php")
        SelfTestNativePHP.put(root, "app/UsesBig.php", src)
        let ns = src as NSString
        // vendor psr-4 map in the fixture covers Illuminate\\
        let off = ns.range(of: "helper2999").location + 3
        _ = NativePHP.lookup(url: url, text: ns, offset: off, root: root.path)           // cold
        let t0 = Date()
        var hit: NPHit?
        for _ in 0..<5 { hit = NativePHP.lookup(url: url, text: ns, offset: off, root: root.path) }
        let per = ms(t0) / 5
        check("@method lookup on a 3000 line docblock resolves (kind \(hit?.kind ?? "-"))", hit?.kind == "docMethod" && hit?.markdown.contains("helper2999") == true)
        check("@method lookup on a 3000 line docblock is fast (\(Int(per)) ms warm)", per < 250)
        let real = NativePHP.lookup(url: url, text: ns, offset: ns.range(of: "real").location + 1, root: root.path)
        check("real method next to a huge docblock resolves", real?.kind == "method")
    }

    // MARK: Cold-path / find-usages speedups

    private static func speedups(_ root: URL, _ fp: FastProject) {
        // fast directory walk == generic FindEngine walk (same set, same spelling)
        let fast = Set(NPRefs.phpFiles(root: root.path, includeVendor: true)), ref = Set(NPRefs.phpFilesViaEngine(root: root.path, includeVendor: true))
        check("fast php file walk equals the FindEngine walk (\(fast.count) files)", fast == ref && fast.count > 5)
        let filtered = NPRefs.phpFiles(root: root.path, includeVendor: false, filter: { $0.hasSuffix("G1.php") })
        check("walk filter keeps only matching files", filtered.count == 1)
        // byte prefilter equals the old substring semantics on a few tokens
        let ns = "<?php $x = [Foo::class, 'Get_User'];\n$y = 'unrelated';\n$z = \"caf\u{00e9} get\";" as NSString
        let lex = PHPLex(ns)
        var buf = [unichar](repeating: 0, count: 1024)
        let needles = NPRefs.asciiNeedles(["get_user"])!.needles
        var verdicts: [Bool] = []
        for i in 0..<lex.count where lex.toks[i].kind == .string { verdicts.append(NPRefs.stringMayContain(ns, lex.toks[i], needles, &buf)) }
        check("string prefilter: match, no match, non-ASCII never rejected", verdicts == [true, false, true])
        // lazy hierarchy: same order as the eager depth-first walk, and stops early
        SelfTestNativePHP.put(root, "app/Gen2/T1.php", "<?php\nnamespace App\\Gen2;\ntrait T1 { public function fromT1() {} }\n")
        SelfTestNativePHP.put(root, "app/Gen2/T2.php", "<?php\nnamespace App\\Gen2;\ntrait T2 { use T3; public function fromT2() {} }\n")
        SelfTestNativePHP.put(root, "app/Gen2/T3.php", "<?php\nnamespace App\\Gen2;\ntrait T3 { public function fromT3() {} }\n")
        SelfTestNativePHP.put(root, "app/Gen2/Base.php", "<?php\nnamespace App\\Gen2;\nclass Base { public function fromBase() {} }\n")
        SelfTestNativePHP.put(root, "app/Gen2/Child.php", "<?php\nnamespace App\\Gen2;\nclass Child extends Base { use T1, T2; public function own() {} }\n")
        let evText = "<?php\n" as NSString
        let ev = FTEval(fp: fp, text: evText, lex: PHPLex(evText), cur: nil)
        let order = fp.queue.sync { () -> [String] in
            let h = ev.hierarchy("App\\Gen2\\Child")
            let firstOnly = h.first?.fqn
            return [firstOnly ?? "", h.done ? "done" : "partial"] + h.all.map(\.fqn)
        }
        check("lazy hierarchy: first class alone leaves the walk partial", order.prefix(2) == ["App\\Gen2\\Child", "partial"])
        check("lazy hierarchy order == depth first: class, traits (with their traits), parent (\(order.dropFirst(2)))",
              Array(order.dropFirst(2)) == ["App\\Gen2\\Child", "App\\Gen2\\T1", "App\\Gen2\\T2", "App\\Gen2\\T3", "App\\Gen2\\Base"])
        let found = fp.queue.sync { ev.findMethod("App\\Gen2\\Child", "fromT3")?.0.fqn }
        check("findMethod walks through nested traits", found == "App\\Gen2\\T3")
        // class cache: a changed file is picked up after the next validation (epoch), even though per-call stats are gone
        let invPath = root.path + "/app/Gen2/Inv.php"
        SelfTestNativePHP.put(root, "app/Gen2/Inv.php", "<?php\nnamespace App\\Gen2;\nclass Inv { public function m1() {} }\n")
        fp.queue.sync { fp.markDirty(); fp.beginRequest() }
        let a = fp.queue.sync { fp.classInfo(path: invPath)?.methods.map(\.name) }
        SelfTestNativePHP.put(root, "app/Gen2/Inv.php", "<?php\nnamespace App\\Gen2;\nclass Inv { public function m1() {} public function m2Longer() {} }\n")
        fp.queue.sync { fp.markDirty(); fp.beginRequest() }
        let b = fp.queue.sync { fp.classInfo(path: invPath)?.methods.map(\.name) }
        check("class cache sees a changed file after revalidation", a == ["m1"] && b == ["m1", "m2Longer"])
        // find usages: shared memo + parallel prepare give the same hits as a plain per-file scan
        SelfTestNativePHP.put(root, "app/Gen2/Use.php", "<?php\nnamespace App\\Gen2;\nclass Use1 { public function go(Child $c, Base $b) { $c->fromBase(); $b->fromBase(); $c->own(); return [Child::class, 'own']; } }\n")
        let off = (try? String(contentsOfFile: root.path + "/app/Gen2/Base.php", encoding: .utf8)).map { ($0 as NSString).range(of: "fromBase").location + 1 } ?? 0
        let baseText = FastProject.read(root.path + "/app/Gen2/Base.php")!
        if case .symbol(let sym) = NPRefs.identify(url: URL(fileURLWithPath: root.path + "/app/Gen2/Base.php"), text: baseText, offset: off, root: root.path) {
            let res = NPRefs.collect(sym)
            let rel = NPRelations(fp: fp)
            let plain = NPRefs.candidates(root: root.path, needles: [sym.name], includeVendor: false, extra: [], cancel: nil).flatMap { p in
                fp.queue.sync { fp.beginRequest(); return NPRefs.scanFile(sym, path: p, fp: fp, rel: rel).hits }
            }
            let key: (NPRefHit) -> String = { "\($0.path):\($0.range.location):\($0.role.rawValue)" }
            check("collect (parallel prepare, shared memo) == plain per-file scan (\(res.hits.count) hits)",
                  res.hits.map(key).sorted() == plain.map(key).sorted() && res.hits.count >= 3)
        } else { check("identify fromBase", false) }
    }

    static func run() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ce-nativeperf-\(getpid())")
        try? fm.removeItem(at: root)
        SelfTestNativePHP.buildFixture(root)
        defer { try? fm.removeItem(at: root) }
        NPFiles.clear()
        let fp = FastProject.shared(root: root)
        docParity()
        tagTable(root, fp)
        funcScan()
        bigClass(root, fp)
        caches(root, fp)
        speedups(root, fp)
        NPFiles.clear()
    }
}
