import Foundation

/// Optional second opinion for syntax errors: the tree-sitter PHP grammar lags behind PHP in places (`(string) match (...)`,
/// `($f)()` inside ternaries, `"$a->class"` ...). When a `php` binary is installed, `php -l` confirms or vetoes a tree-sitter
/// finding, so a grammar limitation never shows up as a red error. Nothing runs unless tree-sitter already found an error.
/// Without a PHP binary the tree-sitter result stands. A single short-lived process, never kept alive, 4 s hard limit.
enum NPDiagPHPLint {
    static let enabledKey = "php.diag.confirmWithPHP"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Tests: force "no php available" or a specific binary.
    static var overridePath: String??

    private static let lock = NSLock()
    private static var resolved: String??
    private static var last: (hash: Int, length: Int, ok: Bool)?

    static var phpPath: String? {
        if let o = overridePath { return o }
        lock.lock(); defer { lock.unlock() }
        if let r = resolved { return r }
        var candidates = [NSHomeDirectory() + "/Library/Application Support/Herd/bin/php", "/opt/homebrew/bin/php", "/usr/local/bin/php", "/usr/bin/php"]
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/php" }
        let found = candidates.first { FileManager.default.isExecutableFile(atPath: $0) && ($0 != "/usr/bin/php" || probe($0)) }
        resolved = .some(found)
        return found
    }

    /// macOS ships a /usr/bin/php stub on some systems that only prints an error; make sure it runs.
    private static func probe(_ path: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["-r", "echo 1;"]
        let out = Pipe()
        p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) == "1"
    }

    /// true: PHP accepts the text; false: PHP reports a parse error; nil: unknown (no binary, timeout, failure).
    static func accepts(_ text: NSString) -> Bool? {
        guard enabled, let php = phpPath else { return nil }
        let hash = (text as String).hashValue
        lock.lock()
        if let l = last, l.hash == hash, l.length == text.length { lock.unlock(); return l.ok }
        lock.unlock()
        // A temp file (not a pipe): a child that exits early must never raise SIGPIPE in the editor.
        let tmp = NSTemporaryDirectory() + "kode-lint-\(getpid())-\(UInt32.random(in: 0...UInt32.max)).php"
        guard (try? (text as String).write(toFile: tmp, atomically: false, encoding: .utf8)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: php)
        p.arguments = ["-n", "-l", "-d", "display_errors=0", "-d", "log_errors=0", tmp]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }
        if done.wait(timeout: .now() + 4) == .timedOut { p.terminate(); return nil }
        let ok: Bool
        switch p.terminationStatus {
        case 0: ok = true
        case 255: ok = false
        default: return nil
        }
        lock.lock(); last = (hash, text.length, ok); lock.unlock()
        return ok
    }
}
