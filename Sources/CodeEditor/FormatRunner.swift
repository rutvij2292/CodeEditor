import Foundation

/// Runs one external formatter process safely: pipes drained concurrently, hard timeout, cancellable, process tree killed.
final class FormatProcess {
    struct Output {
        var status: Int32 = -1
        var stdout = Data()
        var stderr = Data()
        var timedOut = false
        var cancelled = false
        var truncated = false
        var launchError: String?
    }

    static let maxOutput = 20_000_000
    private let lock = NSLock()
    private var process: Process?
    private var cancelledFlag = false

    private final class Box {
        let lock = NSLock()
        var data = Data()
        var overflow = false
        func append(_ d: Data) {
            lock.lock(); defer { lock.unlock() }
            if data.count + d.count > FormatProcess.maxOutput { overflow = true } else { data.append(d) }
        }
        func snapshot() -> (Data, Bool) { lock.lock(); defer { lock.unlock() }; return (data, overflow) }
        func setFlag() { lock.lock(); overflow = true; lock.unlock() }
    }

    func cancel() {
        lock.lock()
        cancelledFlag = true
        let p = process
        lock.unlock()
        if let p, p.isRunning { Self.killTree(p.processIdentifier) }
    }

    static func killTree(_ pid: pid_t) {
        for child in children(of: pid) { killTree(child) }
        kill(pid, SIGKILL)
    }

    private static func children(of pid: pid_t) -> [pid_t] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-P", String(pid)]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { pid_t($0) }
    }

    /// Blocking; call from a background queue.
    func runSync(exe: URL, args: [String], cwd: URL, env: [String: String], stdin: Data?, timeout: TimeInterval) -> Output {
        signal(SIGPIPE, SIG_IGN)
        var result = Output()
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        p.qualityOfService = .utility
        p.currentDirectoryURL = cwd
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }

        lock.lock()
        if cancelledFlag { lock.unlock(); result.cancelled = true; return result }
        lock.unlock()
        do { try p.run() } catch {
            result.launchError = error.localizedDescription
            return result
        }
        lock.lock()
        process = p
        let wasCancelled = cancelledFlag
        lock.unlock()
        if wasCancelled { Self.killTree(p.processIdentifier) }

        let outBox = Box(), errBox = Box()
        let group = DispatchGroup()
        func drain(_ pipe: Pipe, _ box: Box) {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let h = pipe.fileHandleForReading
                while true {
                    let d = h.availableData
                    if d.isEmpty { break }
                    box.append(d)
                }
                group.leave()
            }
        }
        drain(outPipe, outBox)
        drain(errPipe, errBox)
        DispatchQueue.global(qos: .userInitiated).async {
            let w = inPipe.fileHandleForWriting
            if let stdin, !stdin.isEmpty { try? w.write(contentsOf: stdin) }
            try? w.close()
        }

        let timeoutFlag = Box()
        let pid = p.processIdentifier
        let timer = DispatchWorkItem { [weak p] in
            guard let p, p.isRunning else { return }
            timeoutFlag.setFlag()
            Self.killTree(pid)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        exited.wait()
        timer.cancel()

        lock.lock(); let cancelled = cancelledFlag; lock.unlock()
        let didTimeOut = timeoutFlag.snapshot().1
        let killed = cancelled || didTimeOut
        // A grandchild may keep the pipe open; do not wait for it forever.
        _ = group.wait(timeout: .now() + (killed ? 1 : 30))
        let (o, oOver) = outBox.snapshot()
        let (e, _) = errBox.snapshot()
        result.status = p.terminationStatus
        result.stdout = o
        result.stderr = e
        result.truncated = oOver
        result.timedOut = didTimeOut
        result.cancelled = cancelled
        return result
    }
}
