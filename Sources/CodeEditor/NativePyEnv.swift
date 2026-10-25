import Foundation
import SwiftTreeSitter
import TreeSitterPython

/// Byte-capped cache of file outlines shared by every project (stdlib and site-packages files are shared between projects).
/// Entries are validated against the file's mtime + size on use; the least recently used are dropped when the cap is exceeded.
enum PyCache {
    static var capBytes = 8 << 20
    private static let lock = NSLock()
    private static var files: [String: PyFile] = [:]
    private static var bytes = 0
    private static var tick = 0

    static func get(_ path: String) -> PyFile? {
        lock.lock(); defer { lock.unlock() }
        guard let f = files[path] else { return nil }
        tick += 1; f.lastUse = tick
        return f
    }

    static func put(_ f: PyFile) {
        lock.lock(); defer { lock.unlock() }
        if let old = files[f.path] { bytes -= old.cost }
        tick += 1; f.lastUse = tick
        files[f.path] = f
        bytes += f.cost
        if bytes > capBytes {
            let order = files.values.sorted { $0.lastUse < $1.lastUse }
            for e in order {
                if bytes <= capBytes * 3 / 4 { break }
                if e === f { continue }
                files[e.path] = nil
                bytes -= e.cost
            }
        }
    }

    static func drop(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        if let f = files.removeValue(forKey: path) { bytes -= f.cost }
    }

    static func clear() { lock.lock(); files = [:]; bytes = 0; lock.unlock() }
    static var stats: (files: Int, bytes: Int) { lock.lock(); defer { lock.unlock() }; return (files.count, bytes) }
}

/// Interpreter environment of a project: where imports are found. Discovered from the file system only (no interpreter is run).
struct PyEnvInfo {
    var venv: String?
    var site: [String] = []
    var stdlib: [String] = []
    var editable: [String: String] = [:]     // top-level name -> package directory (editable installs)
    var extraPaths: [String] = []            // `.pth` directories
    var known: Bool { !stdlib.isEmpty }
    /// True when third-party packages can be expected to resolve (a venv or a system site-packages was found).
    var hasSite: Bool { !site.isEmpty }
}

enum PyFS {
    static func isDir(_ p: String) -> Bool { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: p, isDirectory: &d) && d.boolValue }
    static func isFile(_ p: String) -> Bool { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: p, isDirectory: &d) && !d.boolValue }
    static func list(_ p: String) -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: p)) ?? [] }
    static func read(_ p: String, max: Int = 2 << 20) -> String? {
        guard let d = FileManager.default.contents(atPath: p), d.count <= max else { return nil }
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1)
    }
    static func stat(_ p: String) -> (mtime: TimeInterval, size: Int)? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: p) else { return nil }
        return ((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0, (a[.size] as? NSNumber)?.intValue ?? 0)
    }
}

enum PyEnvDiscovery {
    private static let rootLock = NSLock()
    private static var rootCache: [String: String] = [:]
    private static let markers = ["pyproject.toml", "setup.py", "setup.cfg", "Pipfile", "requirements.txt", "manage.py", "tox.ini", "pytest.ini", ".git"]

    /// Project root of a Python file: the nearest ancestor with a project marker, else the file's own directory.
    static func projectRoot(for file: URL) -> String {
        let start = file.deletingLastPathComponent().standardizedFileURL.path
        rootLock.lock()
        if let c = rootCache[start] { rootLock.unlock(); return c }
        rootLock.unlock()
        var dir = start
        var result = start
        for _ in 0..<12 {
            if markers.contains(where: { FileManager.default.fileExists(atPath: dir + "/" + $0) }) { result = dir; break }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent.isEmpty || parent == "/" || parent == NSHomeDirectory() { break }
            dir = parent
        }
        rootLock.lock()
        if rootCache.count > 200 { rootCache.removeAll() }
        rootCache[start] = result
        rootLock.unlock()
        return result
    }

    static func resetRootCache() { rootLock.lock(); rootCache = [:]; rootLock.unlock() }

    private static func pyVersionDirs(_ lib: String) -> [String] {
        PyFS.list(lib).filter { $0.hasPrefix("python3") }.sorted { versionKey($0) > versionKey($1) }.map { lib + "/" + $0 }
    }

    private static func versionKey(_ s: String) -> Int {
        let digits = s.drop(while: { !$0.isNumber }).split(separator: ".")
        guard digits.count >= 2, let a = Int(digits[0]), let b = Int(digits[1]) else { return 0 }
        return a * 100 + b
    }

    private static func venvCandidates(root: String) -> [String] {
        var out: [String] = []
        let names = [".venv", "venv", "env", ".env", "virtualenv", ".virtualenv", "venv3"]
        var dir = root
        for _ in 0..<4 {
            for n in names where PyFS.isFile(dir + "/" + n + "/pyvenv.cfg") { out.append(dir + "/" + n) }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir || parent == "/" || parent == NSHomeDirectory() { break }
            dir = parent
        }
        // any direct child folder that is a virtualenv (custom names such as `ag_ts_env`)
        for e in PyFS.list(root) where !e.hasPrefix(".") && !names.contains(e) {
            if PyFS.isFile(root + "/" + e + "/pyvenv.cfg") { out.append(root + "/" + e) }
        }
        let env = ProcessInfo.processInfo.environment
        if let v = env["VIRTUAL_ENV"], PyFS.isDir(v) { out.append(v) }
        if let v = env["CONDA_PREFIX"], PyFS.isDir(v + "/lib") { out.append(v) }
        // poetry / pipenv keep their environments outside the project, named after it
        let base = (root as NSString).lastPathComponent
        let norm = base.replacingOccurrences(of: "[^A-Za-z0-9_.]+", with: "-", options: .regularExpression)
        for dirPath in [NSHomeDirectory() + "/Library/Caches/pypoetry/virtualenvs", NSHomeDirectory() + "/.cache/pypoetry/virtualenvs", NSHomeDirectory() + "/.local/share/virtualenvs"] {
            for e in PyFS.list(dirPath) where e.hasPrefix(norm + "-") || e.hasPrefix(base + "-") { out.append(dirPath + "/" + e) }
        }
        // pyenv local version
        if let v = PyFS.read(root + "/.python-version", max: 200)?.split(whereSeparator: \.isNewline).first {
            let p = NSHomeDirectory() + "/.pyenv/versions/" + v.trimmingCharacters(in: .whitespaces)
            if PyFS.isDir(p + "/lib") { out.append(p) }
        }
        return out
    }

    private static func isStdlib(_ dir: String) -> Bool { PyFS.isFile(dir + "/os.py") }

    private static let systemLock = NSLock()
    private static var systemCache: (stdlib: [String], site: [String])?

    private static func systemPython() -> (stdlib: [String], site: [String]) {
        systemLock.lock()
        if let c = systemCache { systemLock.unlock(); return c }
        systemLock.unlock()
        var libs: [String] = []
        let home = NSHomeDirectory()
        for base in ["/opt/homebrew/opt", "/usr/local/opt"] {
            for e in PyFS.list(base) where e.hasPrefix("python@3") {
                let v = e.dropFirst("python@".count)
                libs.append("\(base)/\(e)/Frameworks/Python.framework/Versions/\(v)/lib")
            }
        }
        for v in PyFS.list("/Library/Frameworks/Python.framework/Versions") { libs.append("/Library/Frameworks/Python.framework/Versions/\(v)/lib") }
        for p in ["/opt/anaconda3", home + "/anaconda3", home + "/miniconda3", "/opt/miniconda3", "/usr/local", "/usr"] { libs.append(p + "/lib") }
        for v in PyFS.list("/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions") {
            libs.append("/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/\(v)/lib")
        }
        var best: (key: Int, dir: String)?
        for lib in libs {
            for d in pyVersionDirs(lib) where isStdlib(d) {
                let k = versionKey((d as NSString).lastPathComponent)
                if best == nil || k > best!.key { best = (k, d) }
            }
        }
        var res: (stdlib: [String], site: [String]) = ([], [])
        if let b = best {
            res.stdlib = [b.dir]
            let name = (b.dir as NSString).lastPathComponent
            for s in [b.dir + "/site-packages", "/opt/homebrew/lib/\(name)/site-packages", "/usr/local/lib/\(name)/site-packages"] where PyFS.isDir(s) { res.site.append(s) }
        }
        systemLock.lock(); systemCache = res; systemLock.unlock()
        return res
    }

    static func discover(root: String) -> PyEnvInfo {
        var info = PyEnvInfo()
        var stdlibDirName: String?
        for v in venvCandidates(root: root) {
            guard PyFS.isDir(v + "/lib") || PyFS.isDir(v + "/lib64") else { continue }
            var sites: [String] = []
            for lib in [v + "/lib", v + "/lib64"] {
                for d in pyVersionDirs(lib) where PyFS.isDir(d + "/site-packages") { sites.append(d + "/site-packages"); stdlibDirName = stdlibDirName ?? (d as NSString).lastPathComponent }
            }
            if sites.isEmpty { continue }
            // Several environments next to each other (.venv + a custom one): packages of any of them resolve (silent beats wrong).
            if info.venv != nil { info.site += sites.filter { !info.site.contains($0) }; continue }
            info.venv = v
            info.site = sites
            // base interpreter from pyvenv.cfg (`home = /prefix/bin`)
            if let cfg = PyFS.read(v + "/pyvenv.cfg", max: 4000) {
                for line in cfg.split(whereSeparator: \.isNewline) {
                    let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2, parts[0] == "home" {
                        let prefix = (parts[1] as NSString).deletingLastPathComponent
                        for lib in [prefix + "/lib"] {
                            for d in pyVersionDirs(lib) where isStdlib(d) && (stdlibDirName == nil || (d as NSString).lastPathComponent == stdlibDirName) {
                                info.stdlib = [d]; break
                            }
                        }
                    }
                }
            }
        }
        if info.stdlib.isEmpty || info.site.isEmpty {
            let sys = systemPython()
            if info.stdlib.isEmpty { info.stdlib = sys.stdlib }
            if info.site.isEmpty { info.site = sys.site }
        }
        // editable installs and .pth directories
        for s in info.site {
            for f in PyFS.list(s) {
                if f.hasSuffix(".pth"), let text = PyFS.read(s + "/" + f, max: 20_000) {
                    for line in text.split(whereSeparator: \.isNewline) {
                        let l = line.trimmingCharacters(in: .whitespaces)
                        if l.isEmpty || l.hasPrefix("#") || l.hasPrefix("import") { continue }
                        let p = l.hasPrefix("/") ? l : s + "/" + l
                        if PyFS.isDir(p) { info.extraPaths.append(p) }
                    }
                } else if f.hasPrefix("__editable__"), f.hasSuffix(".py"), let text = PyFS.read(s + "/" + f, max: 200_000), let re = NPRe.make(pattern: #"'([A-Za-z0-9_]+)':\s*'(/[^']+)'"#) {
                    let ns = text as NSString
                    re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                        guard let m else { return }
                        info.editable[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
                    }
                }
            }
        }
        return info
    }
}

/// One Python project: a serial utility queue (like the PHP fast tier), a lazily created parser and the discovered environment.
final class PyProject {
    private static let registryLock = NSLock()
    private static var registry: [String: PyProject] = [:]

    static func shared(root: String) -> PyProject {
        registryLock.lock(); defer { registryLock.unlock() }
        if let p = registry[root] { return p }
        let p = PyProject(root: root)
        registry[root] = p
        return p
    }

    static func trimAll() {
        registryLock.lock(); let all = Array(registry.values); registryLock.unlock()
        for p in all { p.queue.async { p.dropMemo() } }
    }

    let root: String
    let queue: DispatchQueue
    private var parserStore: Parser?
    private var envStore: PyEnvInfo?
    // last parsed live buffer
    var liveKey = ""
    var liveFile: PyFile?
    var liveTree: MutableTree?

    init(root: String) {
        self.root = root
        queue = DispatchQueue(label: "kode.py." + (root as NSString).lastPathComponent, qos: .utility)
    }

    /// Only on `queue`.
    var parser: Parser? {
        if let p = parserStore { return p }
        let p = Parser()
        guard (try? p.setLanguage(Language(tree_sitter_python()))) != nil else { return nil }
        parserStore = p
        return p
    }

    private var envStamp = ""
    private var envChecked = Date.distantPast

    private func stamp(_ e: PyEnvInfo?) -> String {
        var parts: [String] = []
        func m(_ p: String) -> String { String(PyFS.stat(p)?.mtime ?? 0) }
        parts.append(m(root))
        if let e { for d in [e.venv].compactMap({ $0 }) + e.site { parts.append(m(d)) } }
        return parts.joined(separator: "|")
    }

    /// Only on `queue`. Re-discovered (at most every 3 s, on demand) when the project folder or the site-packages directories changed
    /// (a venv was created, packages installed); never by a timer.
    var env: PyEnvInfo {
        if let e = envStore {
            if Date().timeIntervalSince(envChecked) < 3 { return e }
            envChecked = Date()
            let s = stamp(e)
            if s == envStamp { return e }
            envStore = nil
        }
        let e = PyEnvDiscovery.discover(root: root)
        envStore = e
        envStamp = stamp(e)
        envChecked = Date()
        moduleNamesStore = nil; extensionNamesStore = nil
        return e
    }

    /// Only on `queue`: forget the environment (a venv was created / packages installed).
    func resetEnv() { envStore = nil }

    // lazily built name sets for the unresolved-import rule (only on `queue`)
    var moduleNamesStore: Set<String>?
    var extensionNamesStore: Set<String>?

    func dropMemo() { liveKey = ""; liveFile = nil; liveTree = nil; parserStore = nil; moduleNamesStore = nil; extensionNamesStore = nil }
}

/// Request-scoped view of a project: validated outlines of every file touched are pinned for the request, the live buffer
/// outline replaces the on-disk one for the open file. Only used on the project's queue.
final class PyCtx {
    let project: PyProject
    let livePath: String?
    var live: PyFile?
    private var pinned: [String: PyFile] = [:]
    private var missing: Set<String> = []
    private var existsMemo: [String: Bool] = [:]
    private var dirMemo: [String: Bool] = [:]
    private var site: [String] = []
    private var rootsMemo: [String: [String]] = [:]

    init(project: PyProject, livePath: String? = nil, live: PyFile? = nil) {
        self.project = project
        self.livePath = livePath
        self.live = live
    }

    var env: PyEnvInfo { project.env }

    // MARK: Files

    func file(_ path: String) -> PyFile? {
        if let l = live, l.path == path { return l }
        if let f = pinned[path] { return f }
        if missing.contains(path) { return nil }
        guard let st = PyFS.stat(path) else { missing.insert(path); return nil }
        if let c = PyCache.get(path), c.mtime == st.mtime, c.rawSize == st.size { pinned[path] = c; return c }
        guard st.size <= 2 << 20, let text = PyFS.read(path), let parser = project.parser,
              let tree = parser.parse(text), let rootNode = tree.rootNode else { missing.insert(path); return nil }
        let f = PyOutlineBuilder(path: path, ns: text as NSString, root: rootNode).file
        f.mtime = st.mtime
        f.rawSize = st.size
        PyCache.put(f)
        pinned[path] = f
        return f
    }

    func exists(_ p: String) -> Bool {
        if let v = existsMemo[p] { return v }
        let v = PyFS.isFile(p)
        existsMemo[p] = v
        return v
    }

    func isDir(_ p: String) -> Bool {
        if let v = dirMemo[p] { return v }
        let v = PyFS.isDir(p)
        dirMemo[p] = v
        return v
    }

    // MARK: Import roots and module location

    enum Loc { case file(String), dir(String) }

    /// Directories imports are resolved against for a file, in sys.path order: the top of the file's package, the project
    /// (and src/), the file's directory, the standard library, site-packages and `.pth` paths.
    func roots(for file: String) -> [String] {
        let dir = (file as NSString).deletingLastPathComponent
        if let r = rootsMemo[dir] { return r }
        var out: [String] = []
        func add(_ p: String) { if !p.isEmpty, !out.contains(p) { out.append(p) } }
        // top of the regular-package chain
        var top = dir
        while exists(top + "/__init__.py") || exists(top + "/__init__.pyi") {
            let parent = (top as NSString).deletingLastPathComponent
            if parent == top || parent == "/" { break }
            top = parent
        }
        add(top)
        add(project.root)
        for s in ["src", "lib", "python"] where isDir(project.root + "/" + s) { add(project.root + "/" + s) }
        add(dir)
        let e = env
        for s in e.stdlib { add(s) }
        for s in e.site { add(s) }
        for s in e.extraPaths { add(s) }
        rootsMemo[dir] = out
        return out
    }

    func locate(_ comps: [String], in root: String) -> Loc? {
        var dir = root
        for (i, c) in comps.enumerated() {
            let last = i == comps.count - 1
            let pkg = dir + "/" + c
            if last {
                if exists(pkg + "/__init__.py") { return .file(pkg + "/__init__.py") }
                if exists(dir + "/" + c + ".py") { return .file(dir + "/" + c + ".py") }
                if exists(pkg + "/__init__.pyi") { return .file(pkg + "/__init__.pyi") }
                if exists(dir + "/" + c + ".pyi") { return .file(dir + "/" + c + ".pyi") }
                if isDir(pkg) { return .dir(pkg) }
                return nil
            }
            guard isDir(pkg) else { return nil }
            dir = pkg
        }
        return nil
    }

    /// Resolves `import a.b.c` / `from .x import y` (module part) as seen from `file`.
    func resolveModule(_ name: String, level: Int, from file: String) -> Loc? {
        let comps = name.isEmpty ? [] : name.split(separator: ".").map(String.init)
        if level > 0 {
            var base = (file as NSString).deletingLastPathComponent
            for _ in 1..<level { base = (base as NSString).deletingLastPathComponent }
            if comps.isEmpty {
                if exists(base + "/__init__.py") { return .file(base + "/__init__.py") }
                if exists(base + "/__init__.pyi") { return .file(base + "/__init__.pyi") }
                return isDir(base) ? .dir(base) : nil
            }
            return locate(comps, in: base)
        }
        guard !comps.isEmpty else { return nil }
        if let m = env.editable[comps[0]] {
            let parent = (m as NSString).deletingLastPathComponent
            if (m as NSString).lastPathComponent == comps[0], let l = locate(comps, in: parent) { return l }
        }
        var firstDir: Loc?
        for r in roots(for: file) {
            guard let l = locate(comps, in: r) else { continue }
            if case .file = l { return l }
            if firstDir == nil { firstDir = l }
        }
        return firstDir
    }

    // MARK: Project facts for diagnostics

    func isProjectLocal(_ path: String) -> Bool {
        guard path.hasPrefix(project.root + "/"), !path.contains("/site-packages/") else { return false }
        if let v = env.venv, path.hasPrefix(v + "/") { return false }
        return true
    }

    /// Top-level module / package names that exist anywhere inside the project (depth <= 4): monorepos with several source roots
    /// are not reported as unresolved.
    func projectHasModule(_ name: String) -> Bool {
        if project.moduleNamesStore == nil {
            var names = Set<String>()
            var budget = 4000
            func scan(_ dir: String, _ depth: Int) {
                guard depth <= 4, budget > 0 else { return }
                for e in PyFS.list(dir) {
                    if e.hasPrefix(".") { continue }
                    let full = dir + "/" + e
                    if e.hasSuffix(".py") || e.hasSuffix(".pyi") { names.insert((e as NSString).deletingPathExtension); continue }
                    if PyRefs.skipDirs.contains(e) || PyFS.isFile(full + "/pyvenv.cfg") { continue }
                    if PyFS.isDir(full) { budget -= 1; names.insert(e); scan(full, depth + 1) }
                }
            }
            scan(project.root, 0)
            project.moduleNamesStore = names
        }
        return project.moduleNamesStore!.contains(name)
    }

    /// Compiled extension modules (`name.cpython-312-darwin.so`) of site-packages and the standard library.
    func extensionModuleExists(_ name: String, from file: String) -> Bool {
        if project.extensionNamesStore == nil {
            var names = Set<String>()
            var dirs = env.site + env.extraPaths
            for s in env.stdlib { dirs.append(s); dirs.append(s + "/lib-dynload") }
            for d in dirs {
                for e in PyFS.list(d) where e.hasSuffix(".so") || e.hasSuffix(".pyd") || e.hasSuffix(".dylib") {
                    if let dot = e.firstIndex(of: ".") { names.insert(String(e[..<dot])) }
                }
            }
            project.extensionNamesStore = names
        }
        return project.extensionNamesStore!.contains(name)
    }

    /// Submodule `name` of a package location (`pkg/name.py`, `pkg/name/__init__.py`, namespace directory).
    func submodule(of loc: Loc, named name: String) -> Loc? {
        let dir: String
        switch loc {
        case .file(let p):
            guard (p as NSString).lastPathComponent.hasPrefix("__init__.") else { return nil }
            dir = (p as NSString).deletingLastPathComponent
        case .dir(let d): dir = d
        }
        return locate([name], in: dir)
    }
}
