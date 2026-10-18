import Foundation

// MARK: - Path / URL link parsing (pure)

struct TerminalPathLink: Equatable {
    var path: String
    var line: Int?
    var column: Int?
}

enum TerminalLinks {
    private static let parenRE = try! NSRegularExpression(pattern: #"^(.+?)\((\d+)(?:\s*,\s*(\d+))?\)$"#)
    private static let colonRE = try! NSRegularExpression(pattern: #"^(.+?):(\d+)(?::(\d+))?$"#)

    private static func cap(_ r: NSTextCheckingResult, _ i: Int, _ s: String) -> String? {
        let nr = r.range(at: i)
        guard nr.location != NSNotFound, let rr = Range(nr, in: s) else { return nil }
        return String(s[rr])
    }

    /// Parses `path`, `path:42`, `path:42:7`, `path(42)`, `path(42,7)`, `file:///x`, quoted/bracketed and
    /// Windows-style (`C:\a\b.php:3`) text. Returns nil for web URLs and strings that do not look like paths.
    static func parse(_ raw: String) -> TerminalPathLink? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = s.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") || lower.hasPrefix("ftp://") { return nil }
        let leading = CharacterSet(charactersIn: "\"'`<[({")
        while let f = s.unicodeScalars.first, leading.contains(f) { s.removeFirst() }
        let trailing = CharacterSet(charactersIn: ".,;:'\"`>]}")
        func trimTrailing() { while let l = s.unicodeScalars.last, trailing.contains(l) { s.removeLast() } }
        trimTrailing()
        if s.hasSuffix(")") && !s.contains("(") { s.removeLast(); trimTrailing() }
        if lower.hasPrefix("file:") {
            if let u = URL(string: s), u.isFileURL { s = u.path } else { s = String(s.dropFirst(s.hasPrefix("file://") ? 7 : 5)) }
        }
        guard !s.isEmpty else { return nil }
        var path = s, line: Int? = nil, col: Int? = nil
        let ns = NSRange(s.startIndex..., in: s)
        if let m = parenRE.firstMatch(in: s, range: ns), let p = cap(m, 1, s) {
            path = p; line = cap(m, 2, s).flatMap(Int.init); col = cap(m, 3, s).flatMap(Int.init)
        } else if let m = colonRE.firstMatch(in: s, range: ns), let p = cap(m, 1, s), p.count > 1 || !p.first!.isLetter {
            path = p; line = cap(m, 2, s).flatMap(Int.init); col = cap(m, 3, s).flatMap(Int.init)
        }
        // Must look like a path: a separator, or a dotted file name.
        let name = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
        guard path.contains("/") || path.contains("\\") || (name.contains(".") && !name.hasPrefix(".") && !name.hasSuffix(".")) else { return nil }
        return TerminalPathLink(path: path, line: line, column: col)
    }

    static func isWindowsPath(_ p: String) -> Bool {
        let u = Array(p.unicodeScalars)
        return u.count >= 3 && CharacterSet.letters.contains(u[0]) && u[1] == ":" && (u[2] == "\\" || u[2] == "/")
    }

    /// Resolves against the project root; nil if the file does not exist (or is a directory).
    static func resolve(_ link: TerminalPathLink, root: URL) -> URL? {
        if isWindowsPath(link.path) { return nil }
        var p = link.path
        if p.hasPrefix("~") { p = (p as NSString).expandingTildeInPath }
        let url = p.hasPrefix("/") ? URL(fileURLWithPath: p) : root.appendingPathComponent(p)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return nil }
        return url.standardizedFileURL
    }
}

// MARK: - Environment / PATH capture

enum TerminalEnvironment {
    static let pathDefaultsKey = "terminal.loginPath"

    /// Child environment: parent env minus CE_* test variables, with terminal essentials.
    static func build(base: [String: String], path: String, extra: [String: String] = [:]) -> [String] {
        var env = base.filter { !$0.key.hasPrefix("CE_") }
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = "en_US.UTF-8"
        env["CODEEDITOR"] = "1"
        env["TERM_PROGRAM"] = "CodeEditor"
        env["PATH"] = path
        for (k, v) in extra { env[k] = v }
        return env.map { "\($0.key)=\($0.value)" }.sorted()
    }

    /// `Prefs.terminalShell` when it is an executable, else `$SHELL`, else zsh. Used for new tabs and restarts.
    static var resolvedShell: String {
        let pref = Prefs.terminalShell.trimmingCharacters(in: .whitespaces)
        if !pref.isEmpty, FileManager.default.isExecutableFile(atPath: pref) { return pref }
        return userShell
    }

    static var userShell: String {
        if let s = ProcessInfo.processInfo.environment["SHELL"], FileManager.default.isExecutableFile(atPath: s) { return s }
        return "/bin/zsh"
    }

    /// Runs `$SHELL -ilc 'echo $PATH'` (blocking, call off the main thread). nil on failure / timeout.
    static func captureLoginPath(shell: String = userShell, timeout: TimeInterval = 5) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-ilc", "echo __CEP__${PATH}__CEP__"]
        p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("CE_") }
        p.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        p.standardInput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        let lock = NSLock(); var data = Data()
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            lock.lock(); data.append(d); lock.unlock()
        }
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            _ = done.wait(timeout: .now() + 1)
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        usleep(50_000)
        pipe.fileHandleForReading.readabilityHandler = nil
        lock.lock(); let out = String(decoding: data, as: UTF8.self); lock.unlock()
        let parts = out.components(separatedBy: "__CEP__")
        guard parts.count >= 3, !parts[1].isEmpty else { return nil }
        return parts[1]
    }

    static var fallbackPath: String {
        let base = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extra = ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin",
                     NSHomeDirectory() + "/.claude/local", NSHomeDirectory() + "/Library/Application Support/Herd/bin"]
        var parts = base.split(separator: ":").map(String.init)
        for e in extra where !parts.contains(e) { parts.append(e) }
        return parts.joined(separator: ":")
    }

    private static var refreshing = false

    /// Cached login PATH (UserDefaults) or a sane fallback; kicks off a background refresh (once per launch).
    static func effectivePath() -> String {
        let cached = UserDefaults.standard.string(forKey: pathDefaultsKey)
        if !refreshing && !AppEnv.headless {
            refreshing = true
            DispatchQueue.global(qos: .utility).async {
                if let p = captureLoginPath() { UserDefaults.standard.set(p, forKey: pathDefaultsKey) }
            }
        }
        return cached ?? fallbackPath
    }

    /// First executable named `name` on the effective PATH (plus common install dirs).
    static func which(_ name: String, path: String? = nil) -> String? {
        let p = path ?? effectivePath()
        for dir in p.split(separator: ":") {
            let f = String(dir) + "/" + name
            if FileManager.default.isExecutableFile(atPath: f) { return f }
        }
        return nil
    }
}

// MARK: - Run menu detection

struct TerminalRunItem: Equatable {
    var group: String
    var title: String
    var command: String
}

enum TerminalRunCommands {
    private struct Stamp: Equatable { var artisan: Bool; var composer: Date?; var package: Date? }
    private static var cache: [String: (Stamp, [TerminalRunItem])] = [:]

    private static func mtime(_ u: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date
    }

    static func packageManager(root: URL) -> String {
        let fm = FileManager.default
        func has(_ n: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(n).path) }
        if has("bun.lockb") || has("bun.lock") { return "bun" }
        if has("pnpm-lock.yaml") { return "pnpm" }
        if has("yarn.lock") { return "yarn" }
        return "npm"
    }

    private static func scripts(_ url: URL) -> [String] {
        guard let d = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let s = obj["scripts"] as? [String: Any] else { return [] }
        return s.keys.sorted()
    }

    /// Cached per root; re-parses only when artisan/composer.json/package.json changed.
    static func detect(root: URL) -> [TerminalRunItem] {
        let artisan = root.appendingPathComponent("artisan"), composer = root.appendingPathComponent("composer.json")
        let package = root.appendingPathComponent("package.json")
        let stamp = Stamp(artisan: FileManager.default.fileExists(atPath: artisan.path), composer: mtime(composer), package: mtime(package))
        if let c = cache[root.path], c.0 == stamp { return c.1 }
        var items: [TerminalRunItem] = []
        if stamp.artisan {
            for c in ["serve", "test", "migrate", "tinker", "queue:work", "route:list"] {
                items.append(.init(group: "Artisan", title: "php artisan \(c)", command: "php artisan \(c)"))
            }
        }
        if stamp.composer != nil {
            let fixed = ["install", "update", "dump-autoload", "test"]
            for c in fixed { items.append(.init(group: "Composer", title: "composer \(c)", command: "composer \(c)")) }
            for s in scripts(composer) where !fixed.contains(s) {
                items.append(.init(group: "Composer", title: "composer run \(s)", command: "composer run \(s)"))
            }
        }
        if stamp.package != nil {
            let pm = packageManager(root: root)
            for s in scripts(package) { items.append(.init(group: pm, title: "\(pm) run \(s)", command: "\(pm) run \(s)")) }
        }
        items.append(.init(group: "PHP", title: "php -v", command: "php -v"))
        cache[root.path] = (stamp, items)
        return items
    }

    /// AI agent launchers as run items (see `TerminalAgents`).
    static func agentItems(path: String? = nil, custom: String? = nil, legacy: String? = nil) -> [TerminalRunItem] {
        TerminalAgents.all(path: path, custom: custom, legacy: legacy).map { .init(group: "AI", title: $0.title, command: $0.command) }
    }
}
