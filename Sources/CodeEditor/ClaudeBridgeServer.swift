import Foundation
import Network
import Security

/// Loopback-only WebSocket server speaking the transport Claude Code's IDE integration expects
/// (see docs/claude-code-bridge.md): subprotocol "mcp", header `X-Claude-Code-Ide-Authorization: <token>`,
/// one JSON-RPC message per text frame.
///
/// Networking runs on a private serial queue (so `start()` can block briefly even when called from a main-queue block);
/// the `on...` callbacks are delivered on the main queue.
final class ClaudeBridgeServer {
    static let authHeader = "x-claude-code-ide-authorization"
    static let subprotocol = "mcp"
    /// Largest accepted frame / message (the CLI's biggest legitimate payload is one file's proposed contents).
    static let maxMessageBytes = 16 * 1024 * 1024
    static let maxConnections = 16

    let authToken: String
    private(set) var port: UInt16 = 0
    private let queue = DispatchQueue(label: "kode.claude-bridge")
    private var listener: NWListener?
    private var connections: [Int: NWConnection] = [:]      // queue-confined
    private var nextID = 1                                  // queue-confined
    private let counterLock = NSLock()
    private var rejected = 0
    /// Handshake requests rejected because the token was missing / wrong (for tests and diagnostics).
    var rejectedHandshakes: Int { counterLock.lock(); defer { counterLock.unlock() }; return rejected }

    /// A text message arrived from connection `id`.
    var onMessage: ((Int, String) -> Void)?
    /// A WebSocket connection finished its (authenticated) handshake.
    var onConnect: ((Int) -> Void)?
    var onDisconnect: ((Int) -> Void)?

    init(authToken: String = ClaudeBridgeServer.makeToken()) { self.authToken = authToken }

    /// 128 random bits from the system CSPRNG, formatted as a UUID (what the IDE extensions use too).
    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess { return UUID().uuidString.lowercased() }
        bytes[6] = (bytes[6] & 0x0f) | 0x40; bytes[8] = (bytes[8] & 0x3f) | 0x80
        let h = bytes.map { String(format: "%02x", $0) }.joined()
        func s(_ a: Int, _ b: Int) -> String { String(h.dropFirst(a).prefix(b - a)) }
        return "\(s(0, 8))-\(s(8, 12))-\(s(12, 16))-\(s(16, 20))-\(s(20, 32))"
    }

    /// Constant-time comparison so the token cannot be probed byte by byte.
    static func tokensEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = x.count ^ y.count
        for i in 0..<max(x.count, y.count) { diff |= Int(i < x.count ? x[i] : 0) ^ Int(i < y.count ? y[i] : 0) }
        return diff == 0
    }

    /// Starts listening on 127.0.0.1 with an OS-chosen port. Returns false when the listener could not start.
    @discardableResult
    func start(timeout: TimeInterval = 3) -> Bool {
        guard listener == nil else { return port != 0 }
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        ws.maximumMessageSize = Self.maxMessageBytes
        ws.setClientRequestHandler(queue) { [weak self] subprotocols, headers in
            guard let self else { return NWProtocolWebSocket.Response(status: .reject, subprotocol: nil) }
            let token = headers.first { $0.name.lowercased() == Self.authHeader }?.value
            guard let token, Self.tokensEqual(token, self.authToken) else {
                self.counterLock.lock(); self.rejected += 1; self.counterLock.unlock()
                return NWProtocolWebSocket.Response(status: .reject, subprotocol: nil)
            }
            return NWProtocolWebSocket.Response(status: .accept, subprotocol: subprotocols.contains(Self.subprotocol) ? Self.subprotocol : nil)
        }
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        params.acceptLocalOnly = true
        guard let l = try? NWListener(using: params) else { return false }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        l.stateUpdateHandler = { state in
            switch state {
            case .ready: ok = true; sem.signal()
            case .failed, .cancelled: sem.signal()
            default: break
            }
        }
        l.start(queue: queue)
        guard sem.wait(timeout: .now() + timeout) == .success, ok, let p = l.port?.rawValue else { l.cancel(); return false }
        l.stateUpdateHandler = nil
        listener = l
        port = p
        return true
    }

    func stop() {
        let l = listener
        listener = nil
        port = 0
        queue.async { [weak self] in
            guard let self else { return }
            l?.cancel()
            let all = self.connections
            self.connections = [:]
            for (id, c) in all { c.cancel(); DispatchQueue.main.async { self.onDisconnect?(id) } }
        }
    }

    func send(_ text: String, to id: Int) {
        queue.async { [weak self] in
            guard let c = self?.connections[id] else { return }
            let meta = NWProtocolWebSocket.Metadata(opcode: .text)
            let ctx = NWConnection.ContentContext(identifier: "mcp", metadata: [meta])
            c.send(content: Data(text.utf8), contentContext: ctx, isComplete: true, completion: .idempotent)
        }
    }

    func broadcast(_ text: String, to ids: [Int]) { for id in ids { send(text, to: id) } }

    func disconnect(_ id: Int) {
        queue.async { [weak self] in self?.drop(id) }
    }

    // MARK: Connections (queue-confined)

    private func drop(_ id: Int) {
        guard let c = connections.removeValue(forKey: id) else { return }
        c.cancel()
        DispatchQueue.main.async { [weak self] in self?.onDisconnect?(id) }
    }

    private func accept(_ c: NWConnection) {
        guard connections.count < Self.maxConnections else { c.cancel(); return }
        let id = nextID; nextID += 1
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c else { return }
            switch state {
            case .ready:
                self.connections[id] = c
                DispatchQueue.main.async { self.onConnect?(id) }
                self.receive(id, c)
            case .failed, .cancelled:
                self.drop(id)
            default: break
            }
        }
        c.start(queue: queue)
    }

    private func receive(_ id: Int, _ c: NWConnection) {
        c.receiveMessage { [weak self, weak c] data, context, _, error in
            guard let self, let c, self.connections[id] === c else { return }
            if let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata {
                if meta.opcode == .close { self.drop(id); return }
                if meta.opcode == .text, let data, data.count <= Self.maxMessageBytes, let text = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async { self.onMessage?(id, text) }
                }
            }
            if error != nil { self.drop(id); return }
            self.receive(id, c)
        }
    }
}
