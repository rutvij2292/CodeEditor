import Foundation

/// Builds and runs `vendor/bin/pest` (preferred) or `vendor/bin/phpunit` in a project root. The process runs off the main
/// thread at utility QoS, is cancellable, and its results come from a JUnit XML file (`--log-junit`), not from stdout.
final class TestRunner {
    struct Command: Equatable {
        var executable: String
        var arguments: [String]
        var cwd: String
        var isPest: Bool
    }

    struct Outcome {
        var exitCode: Int32
        var cancelled: Bool
        var results: [TestResult]
        var junitMissing: Bool
    }

    // MARK: command building

    /// `vendor/bin/pest` if present, else `vendor/bin/phpunit`.
    static func tool(in root: URL) -> (path: String, isPest: Bool)? {
        let fm = FileManager.default
        for (name, isPest) in [("pest", true), ("phpunit", false)] {
            let p = root.appendingPathComponent("vendor/bin/\(name)").path
            if fm.isExecutableFile(atPath: p) { return (p, isPest) }
        }
        return nil
    }

    static func absolute(_ path: String, root: URL) -> String {
        (path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)).standardizedFileURL.path
    }

    static func command(root: URL, request: TestRequest, junit: String) -> Command? {
        guard let tool = tool(in: root) else { return nil }
        var args = ["--colors=never", "--log-junit", junit]
        if let f = request.filter { args += ["--filter", f] }
        args += request.paths
        return Command(executable: tool.path, arguments: args, cwd: root.standardizedFileURL.path, isPest: tool.isPest)
    }

    /// Regex fragment matching a test by name: PHPUnit methods by `::name`, Pest descriptions with every
    /// non-alphanumeric character as a wildcard (Pest turns descriptions into method names with underscores).
    static func filterPattern(name: String, isMethod: Bool) -> String {
        if isMethod { return "::\(NSRegularExpression.escapedPattern(for: name))( |$)" }
        var out = ""
        var lastWild = false
        for ch in name {
            if ch.isLetter || ch.isNumber { out += NSRegularExpression.escapedPattern(for: String(ch)); lastWild = false }
            else if !lastWild { out += ".+"; lastWild = true }
        }
        return out
    }

    static func request(for test: DiscoveredTest, file: String) -> TestRequest {
        switch test.kind {
        case .method: return TestRequest(title: "\(test.className.map { $0 + "::" } ?? "")\(test.name)", paths: [file],
                                         filter: filterPattern(name: test.name, isMethod: true))
        case .pest: return TestRequest(title: test.name, paths: [file], filter: filterPattern(name: test.name, isMethod: false))
        case .class, .file: return TestRequest(title: (file as NSString).lastPathComponent, paths: [file])
        }
    }

    static func request(rerunning failed: [TestResult]) -> TestRequest? {
        guard !failed.isEmpty else { return nil }
        var parts: [String] = []
        for r in failed {
            var n = r.name
            if n.hasPrefix("__pest_evaluable_") { n.removeFirst("__pest_evaluable_".count) }
            if let range = n.range(of: " with data set") { n = String(n[..<range.lowerBound]) }
            let isMethod = n.hasPrefix("test") && !n.contains(" ")
            let p = filterPattern(name: n, isMethod: isMethod)
            if !parts.contains(p) { parts.append(p) }
        }
        return TestRequest(title: "\(parts.count) failed test\(parts.count == 1 ? "" : "s")", paths: [], filter: parts.joined(separator: "|"))
    }

    // MARK: running

    private var process: Process?
    private var cancelled = false
    private let lock = NSLock()
    private static let queue = DispatchQueue(label: "TestRunner", qos: .utility)

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return process != nil }

    /// Starts `command`; `onOutput` receives coalesced chunks and `completion` the outcome, both on the main thread.
    func start(_ command: Command, junit: String, onOutput: @escaping (String) -> Void, completion: @escaping (Outcome) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: command.executable)
        p.arguments = command.arguments
        p.currentDirectoryURL = URL(fileURLWithPath: command.cwd)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = FormatTools.searchPATH()
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        p.environment = env
        p.qualityOfService = .utility
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        // Output is buffered and flushed to the main thread at most every 100 ms (no timers while idle).
        let buffer = NSMutableData()
        let bufferLock = NSLock()
        var flushPending = false
        func flush() {
            bufferLock.lock()
            let data = buffer.copy() as! Data
            buffer.length = 0
            flushPending = false
            bufferLock.unlock()
            if !data.isEmpty { onOutput(String(decoding: data, as: UTF8.self)) }
        }
        pipe.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            if chunk.isEmpty { h.readabilityHandler = nil; return }
            bufferLock.lock()
            buffer.append(chunk)
            let schedule = !flushPending
            flushPending = true
            bufferLock.unlock()
            if schedule { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: flush) }
        }
        p.terminationHandler = { [weak self] proc in
            Self.queue.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                self?.lock.lock(); let stopped = self?.cancelled ?? false; self?.lock.unlock()
                // A cancelled shell may leave grandchildren holding the pipe open: do not wait for EOF then.
                let rest = stopped ? Data() : ((try? pipe.fileHandleForReading.readToEnd()) ?? Data())
                if !rest.isEmpty { bufferLock.lock(); buffer.append(rest); bufferLock.unlock() }
                let xml = try? Data(contentsOf: URL(fileURLWithPath: junit))
                try? FileManager.default.removeItem(atPath: junit)
                var results = xml.map { JUnitParser.parse($0) } ?? []
                for i in results.indices where !results[i].file.isEmpty { results[i].file = URL(fileURLWithPath: results[i].file).standardizedFileURL.path }
                self?.lock.lock()
                let wasCancelled = self?.cancelled ?? false
                self?.process = nil
                self?.lock.unlock()
                let outcome = Outcome(exitCode: proc.terminationStatus, cancelled: wasCancelled, results: results, junitMissing: xml == nil)
                DispatchQueue.main.async { flush(); completion(outcome) }
            }
        }
        lock.lock(); process = p; cancelled = false; lock.unlock()
        Self.queue.async { [weak self] in
            self?.lock.lock(); let early = self?.cancelled ?? false; self?.lock.unlock()
            if early {   // cancelled before launch
                self?.lock.lock(); self?.process = nil; self?.lock.unlock()
                DispatchQueue.main.async { completion(Outcome(exitCode: -1, cancelled: true, results: [], junitMissing: true)) }
                return
            }
            do { try p.run() } catch {
                self?.lock.lock(); self?.process = nil; self?.lock.unlock()
                DispatchQueue.main.async {
                    onOutput("Could not start \(command.executable): \(error.localizedDescription)\n")
                    completion(Outcome(exitCode: -1, cancelled: false, results: [], junitMissing: true))
                }
            }
        }
    }

    func cancel() {
        lock.lock()
        let p = process
        if p != nil { cancelled = true }
        lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }

    static func junitTempPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("kode-junit-\(UUID().uuidString).xml").path
    }
}
