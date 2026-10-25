import AppKit

/// Headless checks for the native Python diagnostics (including a no-false-positive sweep over the real standard library) and a
/// small latency / memory report on real files.
enum SelfTestNativePyDiag {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check("pydiag: " + name, ok()) }

    private static func analyze(_ project: PyProject, _ url: URL, _ text: String, _ groups: Set<PyDiagGroup> = Set(PyDiagGroup.allCases)) -> [NPDiag] {
        project.queue.sync { PyDiag.analyze(project: project, url: url, text: text as NSString, groups: groups) }
    }

    static func run() {
        let root = SelfTestNativePy.fixtureRoot()
        SelfTestNativePy.buildFixture(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("main.py")
        let project = NativePy.project(for: main)
        project.queue.sync { project.resetEnv(); project.dropMemo() }
        func codes(_ text: String, _ url: URL? = nil, _ groups: Set<PyDiagGroup> = Set(PyDiagGroup.allCases)) -> [String] {
            analyze(project, url ?? main, text, groups).map(\.code)
        }

        // the fixture itself is clean (apart from dimmed unused imports)
        for rel in ["app/__init__.py", "app/models.py", "app/utils.py", "main.py"] {
            let u = root.appendingPathComponent(rel)
            let text = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
            let bad = analyze(project, u, text).filter { $0.severity <= 3 }
            if !bad.isEmpty { fputs("PYDEBUG fixture \(rel): \(bad.map { "\($0.message)@\($0.range.location)" })\n", stderr) }
            check("fixture \(rel) has no errors / warnings", bad.isEmpty)
        }

        // syntax
        check("syntax error: broken def", codes("def f(:\n    pass\n").contains("syntax"))
        check("syntax error: unclosed paren", codes("x = (1 +\n").contains("syntax"))
        check("syntax error stops other rules", Set(codes("import nothing_pkg\ndef f(:\n")) == ["syntax"])
        check("valid modern syntax is accepted", codes("""
        type Pair[T] = tuple[T, T]
        class Box[T]:
            def get(self) -> T: ...
        match (1, 2):
            case (a, b) if a < b:
                print(a, b)
            case _:
                pass
        async def f():
            async with g() as h:
                return [x async for x in h if (y := x)]
        def g(): ...
        print(f"{1!r:>{3}}", lambda q, *r, **s: q)
        """).filter { $0 == "syntax" }.isEmpty)

        // imports
        check("unresolved absolute import (venv known)", codes("import notinstalled_pkg\n").contains("unresolved-import"))
        check("unresolved from-import package", codes("from notinstalled_pkg.sub import thing\n").contains("unresolved-import"))
        check("import in try/except ImportError is silent", !codes("try:\n    import notinstalled_pkg\nexcept ImportError:\n    notinstalled_pkg = None\n").contains("unresolved-import"))
        check("stdlib + site-packages imports resolve", !codes("import os\nimport fancylib\nfrom fancylib.core import Engine\nimport sys\nimport posixpath\n").contains("unresolved-import"))
        check("project module imports resolve", !codes("from app.models import User\nimport app.utils\n").contains("unresolved-import"))
        check("missing name in a project module", codes("from app.models import Nope\n").contains("unresolved-from-import"))
        check("existing + submodule names are fine", !codes("from app.models import User, Base\nfrom app import utils, models\n").contains("unresolved-from-import"))
        check("missing name in third-party module is silent", !codes("from fancylib.core import NotThere\n").contains("unresolved-from-import"))
        let utils = root.appendingPathComponent("app/utils.py")
        check("unresolved relative import", codes("from .nothing import x\n", utils).contains("unresolved-import"))
        check("relative import of existing module", !codes("from .models import User\nfrom . import models\n", utils).contains("unresolved-import"))
        check("missing name via relative import", codes("from .models import Nope\n", utils).contains("unresolved-from-import"))
        check("missing submodule of a project package", codes("import app.nothing\n").contains("unresolved-import"))
        check("imports group off is silent", codes("import notinstalled_pkg\n", nil, [.syntax]).isEmpty)
        // no venv => the environment is a guess => no unresolved-import
        let loose = FileManager.default.temporaryDirectory.appendingPathComponent("ce-py-loose-\(getpid())")
        SelfTestNativePHP.put(loose, "solo.py", "import something_unknown\n")
        defer { try? FileManager.default.removeItem(at: loose) }
        let lp = NativePy.project(for: loose.appendingPathComponent("solo.py"))
        let lenv = lp.queue.sync { lp.env }
        if lenv.venv == nil {
            check("no venv: unresolved imports stay silent", analyze(lp, loose.appendingPathComponent("solo.py"), "import something_unknown\n").filter { $0.code == "unresolved-import" }.isEmpty)
        }

        // names
        check("undefined name", codes("print(foo_undefined)\n").contains("undefined-name"))
        check("undefined name in function", codes("def f(a):\n    return a + b_undefined\n").contains("undefined-name"))
        check("builtins, locals, later definitions are fine", !codes("""
        def f(a, *args, **kw):
            total = sum(x for x in args)
            for i, (j, k) in enumerate(kw.items()):
                total += i + j + k
            try:
                pass
            except (ValueError, KeyError) as err:
                print(err)
            with open('x') as fh, open('y') as (p, q):
                print(fh, p, q)
            return later(total, lambda z, w=1: z + w + __name__)
        def later(x, y): return x
        class C:
            attr = 1
            other = attr + 1
            def m(self): return __class__
        if (n := 3) > 2: print(n)
        print(__file__, NotImplemented, Ellipsis)
        """).contains("undefined-name"))
        check("star import disables the names rule", !codes("from os import *\nprint(foo_undefined)\n").contains("undefined-name"))
        check("exec disables the names rule", !codes("exec('v = 1')\nprint(v)\n").contains("undefined-name"))
        check("names group off is silent", !codes("print(foo_undefined)\n", nil, [.syntax]).contains("undefined-name"))
        check("attribute names are never checked", !codes("import os\nos.whatever.anything\n").contains("undefined-name"))
        check("keyword argument names are not names", !codes("def f(**k): ...\nf(zzz=1)\n").contains("undefined-name"))
        check("global declared names count as bound", !codes("def a():\n    global G\n    G = 1\ndef b():\n    return G\n").contains("undefined-name"))

        // unused imports
        let unused = analyze(project, main, "import json\nimport os\nfrom fancylib import Engine\nos.getcwd()\n")
        if AppEnv.value("CE_PYDEBUG") != nil { fputs("PYDEBUG unused: \(unused.map { "\($0.code):\($0.message):\($0.severity)" })\n", stderr) }
        check("unused imports are hints", unused.filter { $0.code == "unused-import" }.count == 2 && unused.allSatisfy { $0.severity == 4 })
        check("string annotation counts as use", analyze(project, main, "from fancylib import Engine\ndef f(e: 'Engine'): ...\n").filter { $0.code == "unused-import" }.isEmpty)
        check("noqa keeps the import", analyze(project, main, "import json  # noqa\n").filter { $0.code == "unused-import" }.isEmpty)
        check("__init__ re-exports are not reported", analyze(project, root.appendingPathComponent("app/__init__.py"), "from .models import User\n").isEmpty)
        check("unused group off is silent", analyze(project, main, "import json\n", [.names]).isEmpty)

        bounds(project, main)
        if let dir = AppEnv.value("CE_PYREAL") { sweepProject(dir) }
        realWorld()
        sweepSitePackages()
    }

    // MARK: Bounds (pathological input must neither crash on the small queue stack nor take long)

    private static func bounds(_ project: PyProject, _ main: URL) {
        let chain = "x = " + (0..<6000).map { "a\($0)" }.joined(separator: " + ") + "\n"
        var t0 = Date()
        let r1 = analyze(project, main, chain)
        check("bounds: 6000-term expression chain survives (\(Int(Date().timeIntervalSince(t0) * 1000)) ms)", r1.count <= PyDiag.maxResults && Date().timeIntervalSince(t0) < 5)
        let nest = "x = " + String(repeating: "(", count: 900) + "1" + String(repeating: ")", count: 900) + "\n"
        _ = analyze(project, main, nest)
        check("bounds: 900 nested parentheses survive", true)
        let calls = "v = " + String(repeating: "f(", count: 500) + "1" + String(repeating: ")", count: 500) + "\nv.attr\n"
        let hit = NativePy.lookup(url: main, text: calls as NSString, offset: (calls as NSString).range(of: "attr").location)
        check("bounds: 500 nested calls resolve to nothing without a crash", hit == nil)
        let broken = String(repeating: "def f( {\n", count: 400)
        t0 = Date()
        check("bounds: pathological syntax errors stay capped", analyze(project, main, broken).count <= 5)
        let many = (0..<500).map { "print(undefined_\($0))\n" }.joined()
        check("bounds: result count is capped", analyze(project, main, many).count <= PyDiag.maxResults)
        let big = String(repeating: "# padding padding padding padding padding padding\n", count: 40_000) + "x = (\n"
        check("bounds: buffers over the size cap are skipped", (big as NSString).length > NativePy.maxBufferChars && analyze(project, main, big).isEmpty)
        let methods = "class Big:\n" + (0..<3000).map { "    def m\($0)(self, a: int) -> int:\n        return a + \($0)\n" }.joined()
        t0 = Date()
        let mh = NativePy.lookup(url: main, text: (methods + "Big().m2999(1)\n") as NSString, offset: (methods as NSString).length + 9)
        check("bounds: 3000-method class resolves (\(Int(Date().timeIntervalSince(t0) * 1000)) ms)", mh?.kind == "method" && Date().timeIntervalSince(t0) < 3)
    }

    // MARK: Real files

    private static func pyFiles(in dir: String, limit: Int, maxSize: Int = 200_000, topLevelOnly: Bool = false) -> [String] {
        var out: [String] = []
        let skip: Set<String> = ["test", "tests", "lib2to3", "idlelib", "__pycache__", "site-packages", "lib-dynload", "turtledemo", "ensurepip", "pydoc_data"]
        guard let en = FileManager.default.enumerator(atPath: dir) else { return [] }
        for case let rel as String in en {
            let comps = rel.split(separator: "/").map(String.init)
            if comps.contains(where: { skip.contains($0) }) { continue }
            if topLevelOnly && comps.count > 1 { continue }
            guard rel.hasSuffix(".py"), let a = try? FileManager.default.attributesOfItem(atPath: dir + "/" + rel), (a[.size] as? Int ?? 0) <= maxSize else { continue }
            out.append(dir + "/" + rel)
            if out.count >= limit { break }
        }
        return out.sorted()
    }

    static func realWorld() {
        let loose = FileManager.default.temporaryDirectory.appendingPathComponent("ce-py-real-\(getpid())")
        SelfTestNativePHP.put(loose, "pyproject.toml", "")
        SelfTestNativePHP.put(loose, "probe.py", "import os\n")
        defer { try? FileManager.default.removeItem(at: loose) }
        let probe = loose.appendingPathComponent("probe.py")
        let project = NativePy.project(for: probe)
        let env = project.queue.sync { project.env }
        guard let stdlib = env.stdlib.first else { fputs("PYBENCH no system python found, real-world checks skipped\n", stderr); return }
        accuracy(project, stdlib)
        let files = pyFiles(in: stdlib, limit: 160)
        // no false positives: standard library files are valid and define every name they use
        var bad: [String] = []
        var total = 0
        for f in files {
            guard let text = try? String(contentsOfFile: f, encoding: .utf8) else { continue }
            let list = project.queue.sync { PyDiag.analyze(project: project, url: URL(fileURLWithPath: f), text: text as NSString, groups: [.syntax, .names]) }
            total += 1
            for d in list where d.severity <= 2 { bad.append("\((f as NSString).lastPathComponent): \(d.message) @\(d.range.location)") }
        }
        if !bad.isEmpty { fputs("PYDIAG false positives (\(bad.count)): \(bad.prefix(12))\n", stderr) }
        check("no syntax / undefined-name findings in \(total) stdlib files", bad.isEmpty && total > 30)

        // latency + memory on real code
        let base = NativePHPBench.footprintMB()
        let osPath = stdlib + "/os.py"
        let osText = (try? String(contentsOfFile: osPath, encoding: .utf8)) ?? ""
        let snippet = "import os\nimport shutil\nos.path.join('a')\nshutil.copyfile('a', 'b')\n"
        func ms<T>(_ body: () -> T) -> (T, Double) { let t = DispatchTime.now().uptimeNanoseconds; let r = body(); return (r, Double(DispatchTime.now().uptimeNanoseconds - t) / 1e6) }
        NativePy.trimMemory()
        let (h1, cold) = ms { NativePy.lookup(url: probe, text: snippet as NSString, offset: (snippet as NSString).range(of: "join").location) }
        check("real: os.path.join resolves into the stdlib", h1?.targets.first?.path.hasSuffix("posixpath.py") == true || h1?.targets.first?.path.hasSuffix("ntpath.py") == true)
        check("real: hover has the docstring", h1?.markdown.contains("Join two or more pathname components") == true)
        let (h2, cold2) = ms { NativePy.lookup(url: probe, text: snippet as NSString, offset: (snippet as NSString).range(of: "copyfile").location) }
        check("real: shutil.copyfile resolves", h2?.targets.first?.path.hasSuffix("shutil.py") == true)
        var warm: [Double] = []
        for _ in 0..<60 { warm.append(ms { NativePy.lookup(url: probe, text: snippet as NSString, offset: (snippet as NSString).range(of: "join").location) }.1) }
        warm.sort()
        let (_, osParse) = ms { NativePy.lookup(url: probe, text: osText as NSString, offset: 0) }
        let (_, edit) = ms { NativePy.lookup(url: probe, text: (osText + "\nx = 1\n") as NSString, offset: 0) }
        let after = NativePHPBench.footprintMB()
        let stats = PyCache.stats
        fputs(String(format: "PYBENCH cold-lookup=%.1fms second-file=%.1fms warm-p50=%.2fms warm-max=%.2fms os.py-live-parse=%.1fms reparse-after-edit=%.1fms cache=%d files/%.1fMB footprintDelta=%.1fMB\n",
                     cold, cold2, warm[warm.count / 2], warm.last ?? 0, osParse, edit, stats.files, Double(stats.bytes) / 1_048_576, after - base), stderr)
        check("real: warm lookup is fast", warm[warm.count / 2] < 10)
    }

    /// Go to definition on every identifier of real stdlib files: a hit must point at a declaration of that very name (or a module).
    static func accuracy(_ project: PyProject, _ stdlib: String) {
        var files = pyFiles(in: stdlib, limit: 400, maxSize: 90_000, topLevelOnly: true)
        files = Array(files.enumerated().filter { $0.offset % 6 == 0 }.map(\.element).prefix(40))
        guard let re = try? NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z_0-9]*\b"#) else { return }
        var total = 0, resolved = 0, mismatches: [String] = []
        let t0 = Date()
        var texts: [String: NSString] = [:]
        func textOf(_ p: String) -> NSString? {
            if let t = texts[p] { return t }
            guard let s = try? String(contentsOfFile: p, encoding: .utf8) else { return nil }
            texts[p] = s as NSString
            return s as NSString
        }
        for f in files {
            guard let ns = textOf(f) else { continue }
            let url = URL(fileURLWithPath: f)
            var seen = 0
            re.enumerateMatches(in: ns as String, range: NSRange(location: 0, length: ns.length)) { m, _, stop in
                guard let m else { return }
                seen += 1
                if seen > 1500 { stop.pointee = true; return }
                let name = ns.substring(with: m.range)
                if PyComplete.keywords.contains(name) { return }
                total += 1
                guard let hit = NativePy.lookup(url: url, text: ns, offset: m.range.location), let t = hit.targets.first else { return }
                resolved += 1
                if hit.kind == "module" { return }
                guard let tt = textOf(t.path), t.offset + name.utf16.count <= tt.length else { mismatches.append("\((f as NSString).lastPathComponent):\(name) -> bad target"); return }
                if tt.substring(with: NSRange(location: t.offset, length: name.utf16.count)) != name {
                    mismatches.append("\((f as NSString).lastPathComponent): \(name) -> \(tt.substring(with: NSRange(location: t.offset, length: min(12, tt.length - t.offset)))) in \((t.path as NSString).lastPathComponent)")
                }
            }
        }
        let ms = Date().timeIntervalSince(t0) * 1000
        if !mismatches.isEmpty { fputs("PYACC mismatches (\(mismatches.count)): \(mismatches.prefix(15))\n", stderr) }
        fputs(String(format: "PYACC %d identifiers in %d files: %d resolved (%.0f%%), %d mismatching, %.1f ms per lookup\n", total, files.count, resolved, Double(resolved) * 100 / Double(max(total, 1)), mismatches.count, ms / Double(max(total, 1))), stderr)
        check("accuracy: definitions point at declarations of the same name (\(mismatches.count) of \(resolved))", mismatches.count * 100 <= max(resolved, 1))
    }

    /// Developer tool: CE_PYREAL=/path/to/python/project prints what the diagnostics say about the project's own files.
    static func sweepProject(_ dir: String) {
        let probe = URL(fileURLWithPath: dir).appendingPathComponent("x.py")
        let project = NativePy.project(for: probe)
        let env = project.queue.sync { project.env }
        fputs("PYREAL root=\(project.root) venv=\(env.venv ?? "none") stdlib=\(env.stdlib.first ?? "none") site=\(env.site.count)\n", stderr)
        var counts: [String: Int] = [:]
        var n = 0
        let t0 = Date()
        for f in pyFiles(in: dir, limit: 400, maxSize: 300_000) where !f.contains("/.venv/") && !f.contains("/venv/") && !f.contains("/site-packages/") && !f.contains("/ag_ts_env/") {
            guard let text = try? String(contentsOfFile: f, encoding: .utf8) else { continue }
            n += 1
            let tf = Date()
            let list = project.queue.sync { PyDiag.analyze(project: project, url: URL(fileURLWithPath: f), text: text as NSString, groups: Set(PyDiagGroup.allCases)) }
            let took = Int(Date().timeIntervalSince(tf) * 1000)
            if took > 150 { fputs("PYREAL slow \(took) ms: \(f.replacingOccurrences(of: dir + "/", with: "")) (\((text as NSString).length) chars)\n", stderr) }
            for d in list {
                counts[d.code, default: 0] += 1
                if d.severity <= 2 { fputs("PYREAL \(f.replacingOccurrences(of: dir + "/", with: "")): \(d.message) @\(d.range.location)\n", stderr) }
            }
        }
        fputs("PYREAL \(n) files, \(counts) in \(Int(Date().timeIntervalSince(t0) * 1000)) ms\n", stderr)
    }

    /// Third-party code is much wilder than the stdlib: only report, assert the rate stays tiny.
    static func sweepSitePackages() {
        let loose = FileManager.default.temporaryDirectory.appendingPathComponent("ce-py-real-\(getpid())")
        SelfTestNativePHP.put(loose, "pyproject.toml", "")
        defer { try? FileManager.default.removeItem(at: loose) }
        let project = NativePy.project(for: loose.appendingPathComponent("probe.py"))
        let env = project.queue.sync { project.env }
        guard let site = env.site.first else { return }
        let files = Array(pyFiles(in: site, limit: 400, maxSize: 120_000).enumerated().filter { $0.offset % 2 == 0 }.map(\.element))
        var findings: [String] = []
        for f in files {
            guard let text = try? String(contentsOfFile: f, encoding: .utf8) else { continue }
            let list = project.queue.sync { PyDiag.analyze(project: project, url: URL(fileURLWithPath: f), text: text as NSString, groups: [.syntax, .names]) }
            for d in list where d.severity <= 2 { findings.append("\(f.replacingOccurrences(of: site + "/", with: "")): \(d.message)") }
        }
        if !findings.isEmpty { fputs("PYDIAG site-packages findings (\(findings.count) in \(files.count) files): \(findings.prefix(10))\n", stderr) }
        check("site-packages sweep: findings are rare (\(findings.count)/\(files.count))", Double(findings.count) <= Double(files.count) * 0.03)
    }

    // MARK: Editor integration (needs a project window)

    static func runUI() {
        guard let w = (NSApp.delegate as? AppDelegate)?.active else { return }
        let root = SelfTestNativePy.fixtureRoot().appendingPathComponent("ui")
        SelfTestNativePy.buildFixture(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let code = "from app.models import User\n\nclass Local:\n    def go(self):\n        return missing_thing\n\nu = User('a')\nu.greet(None)\nLocal().go()\n"
        let file = root.appendingPathComponent("script.py")
        try? code.write(to: file, atomically: true, encoding: .utf8)
        w.open(file)
        guard let tab = w.current, tab.url.standardizedFileURL == file.standardizedFileURL else { check("ui: python tab opened", false); return }
        check("ui: python tab gets a session (hover / Cmd-click UI) without any language server", LanguageServers.session(for: tab) != nil)
        check("ui: native handles the tab", NativeEngines.handles(tab.url))
        let ns = code as NSString
        // go to definition through the editor hook
        var opened: (URL, Int)?
        let saved = LaravelNavigator.openLocation
        LaravelNavigator.openLocation = { u, line, _ in opened = (u, line) }
        let off = ns.range(of: "greet").location
        let consumed = LanguageServers.beforeDefinition?(tab, off) ?? false
        LaravelNavigator.openLocation = saved
        check("ui: Cmd-B on u.greet is consumed and opens models.py", consumed && opened?.0.lastPathComponent == "models.py" && opened?.1 == 30)
        // find usages on the declaration (Cmd-click on a declaration shows usages)
        var presented: (String, [PickerItem])?
        NativePyUI.synchronous = true
        NativePyUI.presentHook = { presented = ($0, $1) }
        NativePyUI.messageHook = { m in if AppEnv.value("CE_PYDEBUG") != nil { fputs("PYDEBUG ui message: \(m)\n", stderr) }; presented = (m, []) }
        tab.textView.setSelectedRange(NSRange(location: ns.range(of: "go(").location, length: 0))
        check("ui: find usages starts for a Python symbol", NativePyUI.findUsages(tab: tab))
        let deadline = Date().addingTimeInterval(5)
        while presented == nil, Date() < deadline { CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.02, true) }
        NativePyUI.presentHook = nil
        if AppEnv.value("CE_PYDEBUG") != nil { fputs("PYDEBUG ui usages: \(presented?.0 ?? "nil") \(presented?.1.map { $0.title + " | " + $0.detail } ?? [])\n", stderr) }
        check("ui: usages list has the declaration and the call", (presented?.1.count ?? 0) == 2)
        // diagnostics controller
        guard let c = NativePyDiagController.controllers[ObjectIdentifier(tab)] else { check("ui: diagnostics controller attached", false); return }
        let project = NativePy.project(for: file)
        let list = project.queue.sync { PyDiag.analyze(project: project, url: file, text: code as NSString, groups: Set(PyDiagGroup.allCases)) }
        c.apply(list, text: tab.textView.string)
        check("ui: undefined name is drawn and listed", c.squiggleCount == 1 && NativeProblems.diagnostics(forPath: file.standardizedFileURL.path).contains { $0.code == "undefined-name" })
        check("ui: hover diagnostics available", NativePyDiagController.hoverDiagnostics(for: tab).count == 1)
        let was = c.passes
        c.apply(list, text: tab.textView.string + "x")
        check("ui: stale results are dropped", c.passes == was)
        w.close(file.standardizedFileURL.path)
        check("ui: closing the tab clears the problems", NativeProblems.diagnostics(forPath: file.standardizedFileURL.path).isEmpty)
    }
}
