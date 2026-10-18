import Foundation
import Darwin

/// Error from a JSON-RPC request.
struct LSPError: Error {
    let code: Int
    let message: String
    static let timeout = LSPError(code: -32001, message: "request timed out")
    static let notRunning = LSPError(code: -32002, message: "server not running")
}

enum LSPLog {
    static let enabled = ProcessInfo.processInfo.environment["CE_LSP_LOG"] != nil
    static func log(_ s: @autoclosure () -> String) {
        if enabled { FileHandle.standardError.write(Data(("[lsp] " + s() + "\n").utf8)) }
    }
}

/// Process-tree helpers (RSS of a server and its children, kill of the tree).
enum LSPProcessInfo {
    static func children(of pid: Int32) -> [Int32] {
        var buf = [Int32](repeating: 0, count: 256)
        let n = proc_listchildpids(pid, &buf, Int32(buf.count * MemoryLayout<Int32>.size))
        return n > 0 ? Array(buf.prefix(Int(n))) : []
    }
    static func tree(of pid: Int32) -> [Int32] { [pid] + children(of: pid).flatMap { tree(of: $0) } }
    static func residentBytes(of pid: Int32) -> UInt64 {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return 0 }
        return info.pti_resident_size
    }
    /// Resident memory of the process and all its descendants.
    static func treeResidentBytes(of pid: Int32) -> UInt64 { tree(of: pid).reduce(0) { $0 + residentBytes(of: $1) } }
}

/// JSON-RPC 2.0 over stdio with Content-Length framing. All state lives on `queue`; callbacks run on the
/// queue named per call (main by default).
final class LSPClient {
    typealias Result = Swift.Result<Any?, LSPError>
    /// Return from `onServerRequest` to answer MethodNotFound.
    static let unhandled = NSObject()

    private struct Pending { let completion: (Result) -> Void; let queue: DispatchQueue; var timeout: DispatchWorkItem? }

    let queue = DispatchQueue(label: "codeeditor.lsp.client")
    private let writeQueue = DispatchQueue(label: "codeeditor.lsp.write")
    private var process: Process?
    private var stdin: FileHandle?
    private var buffer = Data()
    private var pending: [Int: Pending] = [:]
    private let idLock = NSLock()
    private var lastID = 0
    private var shuttingDown = false

    private(set) var pid: Int32 = 0
    var isRunning: Bool { process?.isRunning ?? false }

    /// Notifications from the server (main thread).
    var onNotification: ((String, Any?) -> Void)?
    /// Server->client requests (called on `queue`); return the result, or `LSPClient.unhandled`.
    var onServerRequest: ((String, Any?) -> Any?)?
    /// Process exit (main thread): (status, wasRequested).
    var onExit: ((Int32, Bool) -> Void)?

    // MARK: Launch

    func start(executable: String, arguments: [String], environment: [String: String], cwd: URL?) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.environment = environment
        if let cwd { p.currentDirectoryURL = cwd }
        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        stdin = inPipe.fileHandleForWriting
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.queue.async { self?.ingest(d) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData   // drain so the server never blocks on a full stderr pipe
            if d.isEmpty { h.readabilityHandler = nil; return }
            if LSPLog.enabled { LSPLog.log("stderr: " + String(decoding: d.suffix(700), as: UTF8.self)) }
        }
        p.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.queue.async {
                let requested = self.shuttingDown
                self.failAll(.notRunning)
                DispatchQueue.main.async { self.onExit?(proc.terminationStatus, requested) }
            }
        }
        try p.run()
        process = p
        pid = p.processIdentifier
        signal(SIGPIPE, SIG_IGN)
    }

    // MARK: Sending

    func nextID() -> Int { idLock.lock(); defer { idLock.unlock() }; lastID += 1; return lastID }

    /// Sends a request; returns its id (for `cancel`). The completion is delivered on `on`.
    @discardableResult
    func request(_ method: String, _ params: Any?, timeout: TimeInterval = 10, on: DispatchQueue = .main,
                 _ completion: @escaping (Result) -> Void) -> Int {
        let id = nextID()
        queue.async { [self] in
            guard isRunning else { on.async { completion(.failure(.notRunning)) }; return }
            var entry = Pending(completion: completion, queue: on, timeout: nil)
            let work = DispatchWorkItem { [weak self] in
                guard let self, let e = self.pending.removeValue(forKey: id) else { return }
                self.send(["jsonrpc": "2.0", "method": "$/cancelRequest", "params": ["id": id]])
                e.queue.async { e.completion(.failure(.timeout)) }
            }
            entry.timeout = work
            pending[id] = entry
            queue.asyncAfter(deadline: .now() + timeout, execute: work)
            send(["jsonrpc": "2.0", "id": id, "method": method, "params": params ?? NSNull()])
        }
        return id
    }

    /// Drops the pending completion and tells the server to stop working on it.
    func cancel(_ id: Int) {
        queue.async { [self] in
            guard let e = pending.removeValue(forKey: id) else { return }
            e.timeout?.cancel()
            send(["jsonrpc": "2.0", "method": "$/cancelRequest", "params": ["id": id]])
        }
    }

    func notify(_ method: String, _ params: Any? = nil) {
        queue.async { [self] in
            guard isRunning else { return }
            var msg: [String: Any] = ["jsonrpc": "2.0", "method": method]
            if let params { msg["params"] = params }
            send(msg)
        }
    }

    private func send(_ message: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: message) else { return }
        var frame = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        frame.append(body)
        let handle = stdin
        writeQueue.async { try? handle?.write(contentsOf: frame) }
    }

    // MARK: Receiving

    private static let separator = Data("\r\n\r\n".utf8)

    private func ingest(_ data: Data) {
        buffer.append(data)
        while true {
            guard let sep = buffer.range(of: Self.separator) else {
                if buffer.count > 65_536 { buffer.removeAll() }   // garbage without a header
                return
            }
            let header = String(decoding: buffer[buffer.startIndex..<sep.lowerBound], as: UTF8.self)
            var length: Int?
            for line in header.split(separator: "\r\n") where line.lowercased().hasPrefix("content-length:") {
                length = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces))
            }
            guard let length, length >= 0 else { buffer.removeSubrange(buffer.startIndex..<sep.upperBound); continue }
            let bodyStart = sep.upperBound
            guard buffer.count - bodyStart >= length else { return }   // wait for the rest
            let body = Data(buffer[bodyStart..<(bodyStart + length)])
            buffer.removeSubrange(buffer.startIndex..<(bodyStart + length))
            if let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] { dispatch(obj) }
        }
    }

    private func dispatch(_ msg: [String: Any]) {
        let id = msg["id"]
        if let method = msg["method"] as? String {
            let params = msg["params"]
            if let id {
                let result = onServerRequest?(method, params) ?? LSPClient.unhandled
                if result as AnyObject === LSPClient.unhandled {
                    send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "method not found"]])
                } else {
                    send(["jsonrpc": "2.0", "id": id, "result": result is NSNull ? NSNull() : result])
                }
            } else {
                DispatchQueue.main.async { [weak self] in self?.onNotification?(method, params) }
            }
            return
        }
        guard let numID = (id as? NSNumber)?.intValue, let entry = pending.removeValue(forKey: numID) else { return }
        entry.timeout?.cancel()
        if let err = msg["error"] as? [String: Any] {
            let e = LSPError(code: (err["code"] as? Int) ?? -1, message: (err["message"] as? String) ?? "error")
            entry.queue.async { entry.completion(.failure(e)) }
        } else {
            let result = msg["result"]
            entry.queue.async { entry.completion(.success(result is NSNull ? nil : result)) }
        }
    }

    private func failAll(_ error: LSPError) {
        let all = pending
        pending.removeAll()
        for (_, e) in all { e.timeout?.cancel(); e.queue.async { e.completion(.failure(error)) } }
    }

    // MARK: Shutdown

    /// shutdown request, exit notification, then terminate and finally SIGKILL (whole tree) if still alive.
    func shutdown() {
        // Closures capture self strongly on purpose: the client must outlive its owner until the process is gone.
        queue.async { [self] in
            guard !shuttingDown else { return }
            shuttingDown = true
            guard isRunning else { return }
            let pid = self.pid
            request("shutdown", nil, timeout: 2, on: queue) { _ in
                self.notify("exit")
            }
            queue.asyncAfter(deadline: .now() + 3) {
                guard let p = self.process, p.isRunning else { return }
                p.terminate()
                self.queue.asyncAfter(deadline: .now() + 1.5) {
                    if p.isRunning { LSPProcessInfo.tree(of: pid).reversed().forEach { Darwin.kill($0, SIGKILL) } }
                }
            }
        }
    }

    /// Immediate kill of the server tree (app quit).
    func kill() {
        shuttingDown = true
        let p = pid
        guard p > 0, isRunning else { return }
        let tree = LSPProcessInfo.tree(of: p)
        tree.reversed().forEach { Darwin.kill($0, SIGKILL) }
    }
}

// MARK: - UTF-16 position conversion

/// Line table over a snapshot of the text; LSP positions are (line, UTF-16 column) = NSString offsets.
struct LSPLineTable {
    private(set) var starts: [Int] = [0]
    let length: Int

    init(_ text: NSString) {
        length = text.length
        var chunk = [unichar](repeating: 0, count: 4096)
        var pos = 0
        while pos < length {
            let n = min(4096, length - pos)
            text.getCharacters(&chunk, range: NSRange(location: pos, length: n))
            for i in 0..<n where chunk[i] == 10 { starts.append(pos + i + 1) }
            pos += n
        }
    }

    func offset(line: Int, character: Int) -> Int {
        guard line >= 0 else { return 0 }
        if line >= starts.count { return length }
        let lineStart = starts[line]
        let lineEnd = line + 1 < starts.count ? starts[line + 1] - 1 : length   // before the newline
        return max(lineStart, min(lineStart + max(0, character), max(lineStart, lineEnd)))
    }

    func position(of offset: Int) -> (line: Int, character: Int) {
        let o = max(0, min(offset, length))
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= o { lo = mid } else { hi = mid - 1 }
        }
        return (lo, o - starts[lo])
    }

    func lspPosition(_ offset: Int) -> [String: Int] {
        let p = position(of: offset)
        return ["line": p.line, "character": p.character]
    }

    func range(fromLSP r: [String: Any]) -> NSRange? {
        guard let s = r["start"] as? [String: Any], let e = r["end"] as? [String: Any],
              let sl = (s["line"] as? NSNumber)?.intValue, let sc = (s["character"] as? NSNumber)?.intValue,
              let el = (e["line"] as? NSNumber)?.intValue, let ec = (e["character"] as? NSNumber)?.intValue
        else { return nil }
        let a = offset(line: sl, character: sc), b = offset(line: el, character: ec)
        return NSRange(location: a, length: max(0, b - a))
    }
}
