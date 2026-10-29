import Foundation

/// A formatter binary resolved for one file.
struct FormatTool {
    enum Kind { case pint, phpCSFixer, prettier, nativeBlade }
    let kind: Kind
    let exe: URL
    let cwd: URL                     // directory the tool was found in (project root)
    var config: URL?                 // pint.json / .php-cs-fixer*.php
    var plugin: String?              // prettier plugin package (Blade)
    var viaPHP = false               // script lacks the exec bit: run as `php <exe>`
    var global = false
    var indent: IndentSettings?      // native Blade formatter only

    var name: String {
        switch kind {
        case .pint: return "Pint"
        case .phpCSFixer: return "PHP-CS-Fixer"
        case .prettier: return "Prettier"
        case .nativeBlade: return "Blade"
        }
    }
}

enum FormatTools {
    static let prettierExtensions: Set<String> = ["js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts", "vue", "html", "htm", "css", "scss",
                                                  "less", "json", "jsonc", "md", "markdown", "yaml", "yml", "graphql", "gql"]
    static let phpExtensions: Set<String> = ["php", "phtml"]

    static func isBlade(_ url: URL) -> Bool { url.lastPathComponent.lowercased().hasSuffix(".blade.php") }

    /// Nearest directory containing composer.json / package.json / .git, walking up from the file.
    static func projectRoot(for url: URL) -> URL? {
        let fm = FileManager.default
        for dir in ancestors(of: url) {
            for marker in ["composer.json", "package.json", ".git"] where fm.fileExists(atPath: dir.appendingPathComponent(marker).path) { return dir }
        }
        return nil
    }

    private static func ancestors(of url: URL) -> [URL] {
        var out: [URL] = []
        var dir = url.deletingLastPathComponent().standardizedFileURL
        for _ in 0..<40 {
            out.append(dir)
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return out
    }

    /// Precedence: PHP: Pint > PHP-CS-Fixer. Blade: Prettier+blade plugin, else the built-in formatter. Others: project Prettier > PATH Prettier.
    static func detect(for url: URL) -> FormatTool? {
        let fm = FileManager.default
        let ext = url.pathExtension.lowercased()
        let dirs = ancestors(of: url)
        if isBlade(url) {
            for d in dirs {
                let bin = d.appendingPathComponent("node_modules/.bin/prettier")
                guard fm.isExecutableFile(atPath: bin.path) else { continue }
                for plugin in ["@shufo/prettier-plugin-blade", "prettier-plugin-blade"]
                where fm.fileExists(atPath: d.appendingPathComponent("node_modules/\(plugin)").path) {
                    return FormatTool(kind: .prettier, exe: bin, cwd: d, plugin: plugin)
                }
            }
            return FormatTool(kind: .nativeBlade, exe: URL(fileURLWithPath: "/usr/bin/true"), cwd: projectRoot(for: url) ?? url.deletingLastPathComponent())
        }
        if phpExtensions.contains(ext) {
            for d in dirs {
                let pint = d.appendingPathComponent("vendor/bin/pint")
                if fm.fileExists(atPath: pint.path) {
                    let cfg = d.appendingPathComponent("pint.json")
                    return FormatTool(kind: .pint, exe: pint, cwd: d, config: fm.fileExists(atPath: cfg.path) ? cfg : nil,
                                      viaPHP: !fm.isExecutableFile(atPath: pint.path))
                }
                let fixer = d.appendingPathComponent("vendor/bin/php-cs-fixer")
                if fm.fileExists(atPath: fixer.path) {
                    let cfg = [".php-cs-fixer.php", ".php-cs-fixer.dist.php", ".php_cs", ".php_cs.dist"]
                        .map { d.appendingPathComponent($0) }.first { fm.fileExists(atPath: $0.path) }
                    return FormatTool(kind: .phpCSFixer, exe: fixer, cwd: d, config: cfg, viaPHP: !fm.isExecutableFile(atPath: fixer.path))
                }
            }
            return nil
        }
        guard prettierExtensions.contains(ext) else { return nil }
        for d in dirs {
            let bin = d.appendingPathComponent("node_modules/.bin/prettier")
            if fm.isExecutableFile(atPath: bin.path) { return FormatTool(kind: .prettier, exe: bin, cwd: d) }
        }
        if let g = which("prettier") {
            return FormatTool(kind: .prettier, exe: g, cwd: projectRoot(for: url) ?? url.deletingLastPathComponent(), global: true)
        }
        return nil
    }

    static func prettierVersion(_ tool: FormatTool) -> String? {
        var dir = tool.exe.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<4 {
            let u = dir.appendingPathComponent("package.json")
            if let d = try? Data(contentsOf: u), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               j["name"] as? String == "prettier", let v = j["version"] as? String { return v }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    // MARK: PATH

    private static let pathLock = NSLock()
    private static var cachedLoginPATH: String?
    private static var resolving = false

    /// Directories GUI apps do not inherit.
    static func extraDirs() -> [String] {
        let home = NSHomeDirectory()
        var dirs: [String] = []
        let nvm = home + "/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            dirs += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { "\(nvm)/\($0)/bin" }
        }
        dirs += [home + "/Library/Application Support/Herd/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        return dirs
    }

    private static func merge(_ lists: [[String]]) -> String {
        var seen = Set<String>(), out: [String] = []
        for l in lists { for d in l where !d.isEmpty && seen.insert(d).inserted { out.append(d) } }
        return out.joined(separator: ":")
    }

    private static func split(_ s: String?) -> [String] { (s ?? "").split(separator: ":").map(String.init) }

    /// Cached login-shell PATH merged with the extra dirs. Never blocks: falls back to the process PATH until resolved.
    static func searchPATH() -> String {
        pathLock.lock()
        let cached = cachedLoginPATH
        let start = cached == nil && !resolving
        if start { resolving = true }
        pathLock.unlock()
        if start { DispatchQueue.global(qos: .utility).async { _ = resolveLoginPATH() } }
        return merge([split(cached), split(ProcessInfo.processInfo.environment["PATH"]), extraDirs(),
                      ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]])
    }

    /// Blocking (<= 3 s); runs `$SHELL -ilc 'echo $PATH'` once and caches.
    @discardableResult
    static func resolveLoginPATH() -> String {
        pathLock.lock()
        if let c = cachedLoginPATH { pathLock.unlock(); return c }
        pathLock.unlock()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let marker = "__CEPATH__"
        let out = FormatProcess().runSync(exe: URL(fileURLWithPath: shell), args: ["-ilc", "echo \(marker)$PATH\(marker)"],
                                          cwd: URL(fileURLWithPath: NSHomeDirectory()), env: ProcessInfo.processInfo.environment,
                                          stdin: nil, timeout: 3)
        var path = ""
        let text = String(decoding: out.stdout, as: UTF8.self)
        if let a = text.range(of: marker), let b = text.range(of: marker, range: a.upperBound..<text.endIndex) {
            path = String(text[a.upperBound..<b.lowerBound])
        }
        pathLock.lock(); cachedLoginPATH = path; resolving = false; pathLock.unlock()
        return path
    }

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = merge([split(resolveLoginPATH()), split(env["PATH"]), extraDirs(), ["/usr/bin", "/bin"]])
        env["NO_COLOR"] = "1"
        env["FORCE_COLOR"] = "0"
        return env
    }

    static func which(_ name: String) -> URL? {
        for d in searchPATH().split(separator: ":") {
            let p = String(d) + "/" + name
            if FileManager.default.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        }
        return nil
    }
}
