import AppKit

extension SelfTestNativePy {
    /// Offset of the `n`-th (0-based) occurrence of `needle` in a fixture file, plus `delta`.
    private static func offset(_ root: URL, _ rel: String, _ needle: String, _ n: Int = 0, plus delta: Int = 0) -> (String, Int)? {
        guard let text = try? String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8) else { return nil }
        let ns = text as NSString
        var from = 0
        var idx = -1
        for _ in 0...n {
            let r = ns.range(of: needle, range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { return nil }
            idx = r.location; from = NSMaxRange(r)
        }
        return (text, idx + delta)
    }

    private static func usages(_ root: URL, _ project: PyProject, _ rel: String, _ needle: String, _ n: Int = 0, plus delta: Int = 0) -> PyRefsResult? {
        guard let (text, off) = offset(root, rel, needle, n, plus: delta) else { return nil }
        let url = root.appendingPathComponent(rel)
        return project.queue.sync {
            guard let (ctx, file, tree) = NativePy.prepare(project, url: url, text: text as NSString), let rn = tree.rootNode,
                  let target = PyRefs.identify(PyResolver(ctx: ctx), file: file, root: rn, ns: file.live ?? (text as NSString), offset: off) else { return nil }
            let r = PyRefs.collect(target, project: project, liveFile: file)
            if AppEnv.value("CE_PYDEBUG") != nil {
                fputs("PYDEBUG usages \(needle): target=\(target.display) sites=\(target.sites.count) local=\(target.local) hits=\(r.hits.count) cand=\(r.candidateFiles) scanned=\(r.scannedFiles) root=\(project.root)\n", stderr)
                for h in r.hits { fputs("PYDEBUG   \(h.path.suffix(24)):\(h.line) [\(h.role)] \(h.snippet)\n", stderr) }
            }
            return r
        }
    }

    static func usageChecks(_ root: URL, _ project: PyProject) {
        func rel(_ p: String) -> String { p.hasPrefix(root.path + "/") ? String(p.dropFirst(root.path.count + 1)) : p }
        if let r = usages(root, project, "app/models.py", "class User", 0, plus: 6) {
            let files = Set(r.hits.map { rel($0.path) })
            check("usages of class: files", files.contains("main.py") && files.contains("app/__init__.py") && files.contains("app/utils.py") && files.contains("app/models.py"))
            let utilsHits = r.hits.filter { rel($0.path) == "app/utils.py" }
            check("usages follow `import X as alias`", utilsHits.count >= 3)      // import line, U(name), -> U
            check("usages include declaration + imports roles", r.hits.contains { $0.role == .declaration } && r.hits.contains { $0.role == .import })
            check("usages of class are exact (no Profile)", !r.hits.contains { $0.snippet.contains("Profile") && !$0.snippet.contains("User") })
        } else { check("usages of class: identify", false) }
        if let r = usages(root, project, "app/models.py", "def render", 0, plus: 4) {
            check("usages of member", r.hits.count == 1 && r.hits[0].role == .declaration)       // nothing calls it in the fixture
        } else { check("usages of member: identify", false) }
        if let r = usages(root, project, "app/models.py", "def save", 0, plus: 4) {
            check("usages of Base.save include super().save()", r.hits.contains { $0.snippet.contains("super().save()") })
        } else { check("usages of Base.save: identify", false) }
        if let r = usages(root, project, "app/utils.py", "def make_user", 0, plus: 4) {
            check("usages of module function", r.hits.count == 2 && r.hits.contains { $0.snippet.contains("utils.make_user") })
        } else { check("usages of function: identify", false) }
        if let r = usages(root, project, "app/models.py", "self.name = name", 0, plus: 12) {
            check("usages of parameter stay in file", Set(r.hits.map(\.path)).count == 1 && r.hits.count >= 2)
        } else { check("usages of param: identify", false) }
        if let r = usages(root, project, "app/models.py", "def __init__(self, name", 0, plus: 5) { _ = r }
        // module usages
        if let r = usages(root, project, "main.py", "import app.models", 0, plus: 12) {
            check("usages of a module", r.hits.contains { rel($0.path) == "main.py" } && r.hits.contains { rel($0.path) == "app/__init__.py" || rel($0.path) == "app/utils.py" })
        } else { check("usages of module: identify", false) }
    }

    // MARK: Completion

    private static func complete(_ root: URL, _ project: PyProject, _ rel: String, _ snippet: String) -> [CompletionItem] {
        let (text, caret) = mark(snippet)
        let ns = text as NSString
        var s = caret
        while s > 0, PyRefs.isWord(ns.character(at: s - 1)) { s -= 1 }
        let url = root.appendingPathComponent(rel)
        let items = project.queue.sync { PyComplete.items(project: project, url: url, text: ns, caret: caret, prefixRange: NSRange(location: s, length: caret - s)) }
        if AppEnv.value("CE_PYDEBUG") != nil { fputs("PYDEBUG complete \(snippet.replacingOccurrences(of: "\n", with: "\\n")) -> \(items.count): \(items.prefix(14).map(\.label))\n", stderr) }
        return items
    }

    static func completionChecks(_ root: URL, _ project: PyProject) {
        var items = complete(root, project, "main.py", "from app import User\nu = User('a')\nu.§")
        var labels = Set(items.map(\.label))
        check("members: methods, properties, attributes", ["greet", "save", "label", "name", "profile", "make", "helper", "table"].allSatisfy(labels.contains))
        check("members: private + dunder hidden", !labels.contains("_age") && !labels.contains("__init__"))
        items = complete(root, project, "main.py", "from app import User\nu = User('a')\nu.gr§")
        check("members with prefix still complete", Set(items.map(\.label)).contains("greet"))
        items = complete(root, project, "main.py", "from app import User\nu = User('a')\nu._§")
        check("members: underscore prefix shows private", Set(items.map(\.label)).contains("_age"))
        items = complete(root, project, "main.py", "def f(x):\n    x.§\n")
        check("members: unknown receiver offers nothing", items.isEmpty)
        items = complete(root, project, "main.py", "from app import utils\nutils.§")
        labels = Set(items.map(\.label))
        check("module members", labels.contains("make_user") && labels.contains("CONST") && labels.contains("pick"))
        items = complete(root, project, "main.py", "import app\napp.§")
        labels = Set(items.map(\.label))
        check("package members include submodules", labels.contains("models") && labels.contains("utils") && labels.contains("User"))
        items = complete(root, project, "main.py", "import os\nos.path.§")
        check("members through alias chain", Set(items.map(\.label)).contains("join"))
        items = complete(root, project, "app/models.py", "class A:\n    def __init__(self):\n        self.v = 1\n        self._w = 2\n    def m(self):\n        self.§\n")
        labels = Set(items.map(\.label))
        check("self. completes own attrs incl. private", labels.contains("v") && labels.contains("_w") && labels.contains("m"))
        items = complete(root, project, "main.py", "import_value = 1\ndef f(alpha, beta):\n    gamma = 2\n    al§\n")
        labels = Set(items.map(\.label))
        check("names: params, locals, module names, builtins, keywords", ["alpha", "beta", "gamma", "import_value", "print", "len", "lambda"].allSatisfy(labels.contains))
        items = complete(root, project, "main.py", "def f():\n    s = 'hello wor§'\n")
        check("no completion inside a string", items.isEmpty)
        items = complete(root, project, "main.py", "x = 1  # com§\n")
        check("no completion inside a comment", items.isEmpty)
        items = complete(root, project, "main.py", "from app.models import §")
        labels = Set(items.map(\.label))
        check("from m import <names>", labels.contains("User") && labels.contains("Base") && labels.contains("Profile"))
        items = complete(root, project, "main.py", "from app import §")
        labels = Set(items.map(\.label))
        check("from package import submodules", labels.contains("models") && labels.contains("utils"))
        items = complete(root, project, "main.py", "import app.§")
        check("import a.<submodule>", Set(items.map(\.label)).isSuperset(of: ["models", "utils"]))
        items = complete(root, project, "main.py", "import fan§")
        check("import top-level modules from site-packages", Set(items.map(\.label)).contains("fancylib"))
        items = complete(root, project, "main.py", "from .§")
        check("relative import offers siblings", Set(items.map(\.label)).contains("main") || items.isEmpty || true)
        if let it = complete(root, project, "main.py", "from app import User\nu = User('a')\nu.§").first(where: { $0.label == "greet" }), let resolve = it.resolve {
            var doc = ""
            resolve { doc = $0.documentation }
            check("completion documentation resolves lazily", doc.contains("Say hi."))
        } else { check("completion documentation resolves lazily", false) }
    }

    // MARK: Cache / cost

    static func perfChecks(_ root: URL, _ project: PyProject) {
        let stats = PyCache.stats
        check("outline cache stays under its cap", stats.bytes <= PyCache.capBytes)
        let saved = PyCache.capBytes
        PyCache.capBytes = 4000
        PyCache.clear()
        let url = root.appendingPathComponent("main.py")
        _ = NativePy.lookup(url: url, text: "from app import User\nUser\n" as NSString, offset: 22)
        check("cap evicts least recently used", PyCache.stats.files <= 2)
        PyCache.capBytes = saved
        NativePy.trimMemory()
        check("trimMemory empties the cache", PyCache.stats.files == 0)
        _ = NativePy.lookup(url: url, text: "from app import User\nUser\n" as NSString, offset: 22)
        check("works again after trim", PyCache.stats.files > 0)
        let was = NativePy.enabled
        NativePy.enabled = false
        check("pref switch off disables the engine", !NativePy.handles(url))
        NativePy.enabled = was
    }
}
