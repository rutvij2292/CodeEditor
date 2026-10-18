import Foundation

// MARK: - Model

struct ArtisanArgument: Equatable {
    let name: String
    let isRequired: Bool
    let isArray: Bool
    let detail: String
}

struct ArtisanOption: Equatable {
    let name: String        // "--force"
    let shortcut: String    // "-f" or ""
    let acceptsValue: Bool
    let detail: String
}

struct ArtisanCommand: Equatable {
    let name: String
    let summary: String
    let arguments: [ArtisanArgument]
    let options: [ArtisanOption]

    var requiredArguments: [ArtisanArgument] { arguments.filter(\.isRequired) }
    /// `<name> [<email>]` style hint shown while typing arguments.
    var argumentHint: String {
        arguments.map { a in
            let n = "<\(a.name)>" + (a.isArray ? "..." : "")
            return a.isRequired ? n : "[\(n)]"
        }.joined(separator: " ")
    }
}

struct ArtisanRoute: Equatable {
    let method: String      // "GET|HEAD"
    let uri: String
    let name: String
    let action: String      // "App\Http\Controllers\UserController@show", "Closure", or an invokable class

    /// "GET|HEAD" -> "GET" (HEAD is implied), everything else verbatim.
    var displayMethod: String {
        let parts = method.split(separator: "|").map(String.init)
        let trimmed = parts.filter { $0 != "HEAD" }
        return (trimmed.isEmpty ? parts : trimmed).joined(separator: "|")
    }
}

enum ArtisanError: Error, Equatable {
    case noPHP
    case notLaravel
    case failed(String)

    var message: String {
        switch self {
        case .noPHP: return "php was not found (looked in Herd, Homebrew, /usr/local/bin and PATH)"
        case .notLaravel: return "No artisan file in this project"
        case .failed(let s): return s
        }
    }
}

// MARK: - Process + parsing

enum Artisan {
    /// Tests / headless renders point this (or CE_PHP) at a fake php script.
    static var phpOverride: String?

    /// Same candidate list as the artisan route index (Herd first), then every PATH directory.
    static func findPHP() -> String? {
        let fm = FileManager.default
        if let o = phpOverride ?? AppEnv.value("CE_PHP"), fm.isExecutableFile(atPath: o) { return o }
        var candidates = [NSHomeDirectory() + "/Library/Application Support/Herd/bin/php", "/opt/homebrew/bin/php", "/usr/local/bin/php", "/usr/bin/php"]
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/php" }
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// The command word to type in the user's shell: plain `php` when its directory is on PATH, else the quoted absolute path.
    static func shellPHP(_ php: String) -> String {
        let dir = (php as NSString).deletingLastPathComponent
        let onPath = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").contains { String($0) == dir }
        return onPath ? "php" : shellQuote(php)
    }

    static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// `php artisan <name> <args>`; `cd` is prepended when the terminal's directory is not the Laravel root.
    static func commandLine(php: String, command: String, args: String, cdTo: String? = nil) -> String {
        var line = shellPHP(php) + " artisan " + command
        let a = args.trimmingCharacters(in: .whitespaces)
        if !a.isEmpty { line += " " + a }
        if let cdTo { line = "cd " + shellQuote(cdTo) + " && " + line }
        return line
    }

    struct Output { var status: Int32; var stdout: String; var stderr: String; var timedOut: Bool }

    /// Blocking: call off the main thread.
    static func execute(php: String, arguments: [String], cwd: URL, timeout: TimeInterval = 30) -> Output? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: php)
        proc.arguments = arguments
        proc.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        proc.environment = env
        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        proc.standardInput = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter(); DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let timedOut = group.wait(timeout: .now() + timeout) == .timedOut
        if timedOut { proc.terminate(); return Output(status: -1, stdout: "", stderr: "", timedOut: true) }
        proc.waitUntilExit()
        return Output(status: proc.terminationStatus, stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData, as: UTF8.self), timedOut: false)
    }

    /// JSON value from output that may carry PHP warnings / notices before or after the document.
    private static func jsonValue(_ data: Data, open: UInt8, close: UInt8) -> Any? {
        guard let start = data.firstIndex(of: open) else { return nil }
        if let v = try? JSONSerialization.jsonObject(with: data[start...]) { return v }
        guard let end = data.lastIndex(of: close), end > start else { return nil }
        return try? JSONSerialization.jsonObject(with: data[start...end])
    }

    private static let globalOptions: Set<String> = ["--help", "--quiet", "--verbose", "--version", "--ansi", "--no-ansi",
                                                     "--no-interaction", "--env"]
    private static let skippedCommands: Set<String> = ["help", "list", "_complete", "completion"]

    /// `php artisan list --format=json`.
    static func parseCommands(_ data: Data) -> [ArtisanCommand]? {
        guard let obj = jsonValue(data, open: UInt8(ascii: "{"), close: UInt8(ascii: "}")) as? [String: Any],
              let list = obj["commands"] as? [[String: Any]] else { return nil }
        var out: [ArtisanCommand] = []
        for c in list {
            guard let name = c["name"] as? String, !skippedCommands.contains(name), (c["hidden"] as? Bool) != true else { continue }
            let def = c["definition"] as? [String: Any] ?? [:]
            let usage = (c["usage"] as? [String])?.first ?? ""
            var args: [ArtisanArgument] = []
            for (_, v) in def["arguments"] as? [String: Any] ?? [:] {
                guard let a = v as? [String: Any], let n = a["name"] as? String else { continue }
                args.append(ArtisanArgument(name: n, isRequired: (a["is_required"] as? Bool) ?? false,
                                            isArray: (a["is_array"] as? Bool) ?? false, detail: (a["description"] as? String) ?? ""))
            }
            // JSON objects lose key order: recover the declared order from the usage string.
            func pos(_ a: ArtisanArgument) -> Int {
                let r = (usage as NSString).range(of: "<\(a.name)>")
                return r.location == NSNotFound ? Int.max : r.location
            }
            args.sort { pos($0) != pos($1) ? pos($0) < pos($1) : $0.name < $1.name }
            var opts: [ArtisanOption] = []
            for (key, v) in def["options"] as? [String: Any] ?? [:] {
                guard let o = v as? [String: Any] else { continue }
                let n = (o["name"] as? String) ?? key
                if globalOptions.contains(n) { continue }
                let sc = ((o["shortcut"] as? String) ?? "").split(separator: "|").first.map(String.init) ?? ""
                opts.append(ArtisanOption(name: n, shortcut: sc, acceptsValue: (o["accept_value"] as? Bool) ?? false,
                                          detail: (o["description"] as? String) ?? ""))
            }
            opts.sort { $0.name < $1.name }
            out.append(ArtisanCommand(name: name, summary: (c["description"] as? String) ?? "", arguments: args, options: opts))
        }
        return out.sorted { $0.name < $1.name }
    }

    /// `php artisan route:list --json`.
    static func parseRoutes(_ data: Data) -> [ArtisanRoute]? {
        guard let arr = jsonValue(data, open: UInt8(ascii: "["), close: UInt8(ascii: "]")) as? [[String: Any]] else { return nil }
        return arr.compactMap { r in
            guard let uri = r["uri"] as? String else { return nil }
            return ArtisanRoute(method: (r["method"] as? String) ?? "", uri: uri.hasPrefix("/") ? uri : "/" + uri,
                                name: (r["name"] as? String) ?? "", action: (r["action"] as? String) ?? "")
        }
    }

    /// Files named by `INFO  Model [/abs/or/relative/path.php] created successfully.` lines (in output order).
    static func parseCreated(_ output: String, root: URL) -> [URL] {
        let clean = output.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        guard let re = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\s+created successfully"#) else { return [] }
        var seen = Set<String>(), urls: [URL] = []
        let ns = clean as NSString
        for m in re.matches(in: clean, range: NSRange(location: 0, length: ns.length)) {
            let p = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let url = p.hasPrefix("/") ? URL(fileURLWithPath: p) : root.appendingPathComponent(p)
            if seen.insert(url.standardizedFileURL.path).inserted { urls.append(url) }
        }
        return urls
    }
}

// MARK: - Per-project cache

/// Command and route tables per Laravel project. Entries are stamped with the mtimes of everything that can change
/// them (routes/, bootstrap/app.php, composer.json/lock, app/Console/Commands), so the existing FS watcher's events
/// (which bump those mtimes) invalidate them with no timers.
final class ArtisanCatalog {
    static let shared = ArtisanCatalog()
    private var entries: [String: (stamp: Int64, value: Any)] = [:]
    private var pending: [String: [(Result<Any, ArtisanError>) -> Void]] = [:]

    static func stamp(_ p: LaravelProject) -> Int64 {
        var paths = LaravelRouteIndex.routeFiles(p)
        paths += [p.abs("routes"), p.abs("composer.json"), p.abs("composer.lock"), p.abs("app/Console/Commands"), p.abs("app/Console/Kernel.php")]
        return p.stamp(paths)
    }

    func cached(_ key: String, _ p: LaravelProject) -> Any? {
        guard let e = entries[p.path + "|" + key], e.stamp == Self.stamp(p) else { return nil }
        return e.value
    }

    func store(_ key: String, _ p: LaravelProject, stamp: Int64, _ value: Any) {
        entries[p.path + "|" + key] = (stamp, value)
    }

    /// Synchronous fetch (background threads / tests). Never caches.
    static func fetch<T>(_ p: LaravelProject, args: [String], parse: (Data) -> T?) -> Result<T, ArtisanError> {
        guard LaravelFS.isFile(p.abs("artisan")) else { return .failure(.notLaravel) }
        guard let php = Artisan.findPHP() else { return .failure(.noPHP) }
        guard let out = Artisan.execute(php: php, arguments: ["artisan"] + args, cwd: p.root) else { return .failure(.noPHP) }
        if out.timedOut { return .failure(.failed("php artisan \(args.first ?? "") timed out")) }
        if let v = parse(Data(out.stdout.utf8)) { return .success(v) }
        let msg = (out.stderr.isEmpty ? out.stdout : out.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return .failure(.failed(msg.isEmpty ? "php artisan \(args.first ?? "") failed (exit \(out.status))" : String(msg.prefix(400))))
    }

    private func load<T>(_ key: String, _ p: LaravelProject, args: [String], parse: @escaping (Data) -> T?,
                         completion: @escaping (Result<T, ArtisanError>) -> Void) {
        if let hit = cached(key, p) as? T { completion(.success(hit)); return }
        let k = p.path + "|" + key
        let wrapped: (Result<Any, ArtisanError>) -> Void = { r in
            switch r {
            case .success(let v): if let t = v as? T { completion(.success(t)) }
            case .failure(let e): completion(.failure(e))
            }
        }
        if pending[k] != nil { pending[k]!.append(wrapped); return }
        pending[k] = [wrapped]
        let stamp = Self.stamp(p)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.fetch(p, args: args, parse: parse)
            DispatchQueue.main.async {
                if case .success(let v) = result { self.store(key, p, stamp: stamp, v) }
                let waiting = self.pending.removeValue(forKey: k) ?? []
                for w in waiting { w(result.map { $0 as Any }) }
            }
        }
    }

    func commands(_ p: LaravelProject, completion: @escaping (Result<[ArtisanCommand], ArtisanError>) -> Void) {
        load("commands", p, args: ["list", "--format=json"], parse: Artisan.parseCommands, completion: completion)
    }

    func routes(_ p: LaravelProject, completion: @escaping (Result<[ArtisanRoute], ArtisanError>) -> Void) {
        load("routes", p, args: ["route:list", "--json"], parse: Artisan.parseRoutes, completion: completion)
    }
}
