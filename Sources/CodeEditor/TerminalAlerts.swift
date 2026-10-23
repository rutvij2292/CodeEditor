import AppKit
import UserNotifications

/// What an agent tab is telling the user.
enum AgentAlertKind: String {
    case finished   // Claude Code `Stop` hook: the turn is over
    case waiting    // `Notification` hook / BEL: permission prompt or input needed

    var message: String { self == .finished ? "finished" : "is waiting for you" }
}

/// Pure parsing of the alert line a hook writes to the socket (`<tabID> <event>`), and of agent window titles.
enum AgentAlertProtocol {
    static func parse(_ line: String) -> (tab: Int, kind: AgentAlertKind)? {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 2, let id = Int(parts[0]), id > 0 else { return nil }
        switch parts[1].lowercased() {
        case "stop", "done", "finished": return (id, .finished)
        case "input", "notification", "notify", "waiting", "permission": return (id, .waiting)
        default: return nil
        }
    }

    enum TitleState { case working, idle, other }
    /// Claude Code prefixes its OSC window title with a braille spinner frame while working and "✳" when idle.
    static func titleState(_ title: String) -> TitleState {
        guard let u = title.unicodeScalars.first else { return .other }
        if (0x2800...0x28FF).contains(u.value) { return .working }
        if u.value == 0x2733 { return .idle }
        return .other
    }
}

/// Tiny unix-socket listener a Claude Code hook can write to (`nc -U`). Event-driven (DispatchSource), no timers or polling;
/// one process-wide instance started lazily when the first terminal shell is spawned. Nothing is allocated while the pref is off.
final class AgentAlertServer {
    static let shared = AgentAlertServer()
    /// Headless runs never listen unless a test opts in.
    static var allowHeadless = false

    private(set) var path: String?
    var onEvent: ((_ tab: Int, _ kind: AgentAlertKind) -> Void)?
    private var fd: Int32 = -1
    private var listener: DispatchSourceRead?

    private static func address(_ path: String) -> sockaddr_un? {
        var a = sockaddr_un()
        a.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: a.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &a.sun_path) { raw in for (i, b) in bytes.enumerated() { raw[i] = UInt8(bitPattern: b) } }
        return a
    }

    static func defaultPath() -> String {
        let p = (NSTemporaryDirectory() as NSString).appendingPathComponent("kode-alert-\(getpid()).sock")
        return p.utf8.count < 100 ? p : "/tmp/kode-alert-\(getpid()).sock"
    }

    /// Removes sockets left by Kode processes that no longer exist.
    private static func removeStale(in dir: String) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where name.hasPrefix("kode-alert-") && name.hasSuffix(".sock") {
            let pidText = name.dropFirst("kode-alert-".count).dropLast(".sock".count)
            if let pid = Int32(pidText), pid != getpid(), kill(pid, 0) != 0, errno == ESRCH {
                unlink((dir as NSString).appendingPathComponent(name))
            }
        }
    }

    @discardableResult
    func start(at requested: String? = nil) -> String? {
        if let path { return path }
        let p = requested ?? Self.defaultPath()
        Self.removeStale(in: (p as NSString).deletingLastPathComponent)
        guard var addr = Self.address(p) else { return nil }
        unlink(p)
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return nil }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(s, 8) == 0 else { close(s); unlink(p); return nil }
        chmod(p, 0o600)
        _ = fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK)
        fd = s; path = p
        let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: .main)
        src.setEventHandler { [weak self] in self?.accepted() }
        src.resume()
        listener = src
        return p
    }

    func stop() {
        listener?.cancel(); listener = nil
        if fd >= 0 { close(fd); fd = -1 }
        if let path { unlink(path) }
        path = nil
    }

    private func accepted() {
        let c = accept(fd, nil, nil)
        guard c >= 0 else { return }
        _ = fcntl(c, F_SETFL, fcntl(c, F_GETFL) | O_NONBLOCK)
        let src = DispatchSource.makeReadSource(fileDescriptor: c, queue: .main)
        var data = Data()
        var finished = false
        let finish = { [weak self] in
            guard !finished else { return }
            finished = true
            src.cancel()
            if let line = String(data: data, encoding: .utf8)?.split(separator: "\n").first,
               let (tab, kind) = AgentAlertProtocol.parse(String(line)) { self?.onEvent?(tab, kind) }
        }
        src.setEventHandler {
            var buf = [UInt8](repeating: 0, count: 256)
            let n = read(c, &buf, buf.count)
            if n > 0 { data.append(contentsOf: buf[0..<n]) }
            if n <= 0 || data.contains(10) || data.count >= 256 { finish() }
        }
        src.setCancelHandler { close(c) }
        src.resume()
        // A client that connects and never writes must not pin the descriptor.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if !finished { finished = true; src.cancel() } }
    }

    /// Client side (tests; the shell hook uses `nc -U`): writes one alert line.
    @discardableResult
    static func send(to path: String, line: String) -> Bool {
        guard var addr = address(path) else { return false }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return false }
        defer { close(s) }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { return false }
        let bytes = Array((line + "\n").utf8)
        return write(s, bytes, bytes.count) == bytes.count
    }
}

enum AgentAlerts {
    /// Env vars for a new shell: socket path + the tab id the hook echoes back. Empty when alerts are off or unavailable.
    static func environment(tabID: Int) -> [String: String] {
        guard Prefs.terminalAgentAlerts, !AppEnv.headless || AgentAlertServer.allowHeadless else { return [:] }
        let server = AgentAlertServer.shared
        if server.onEvent == nil { server.onEvent = { TerminalPanelController.deliverAlert(tab: $0, kind: $1) } }
        guard let path = server.start() else { return [:] }
        return ["KODE_ALERT_SOCK": path, "KODE_TAB_ID": String(tabID)]
    }
}

/// macOS user notifications for agent alerts. Permission is requested on the first alert, not at launch.
enum AgentNotifier {
    /// Tests replace this; `nil` uses the real notification centre (only for a packaged .app, never headless).
    static var sink: ((_ title: String, _ body: String) -> Void)?

    private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                    withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) { done([.banner]) }
    }
    private static let delegate = Delegate()

    static func post(title: String, body: String) {
        if let sink { sink(title, body); return }
        guard !AppEnv.headless, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let add = {
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        center.getNotificationSettings { s in
            switch s.authorizationStatus {
            case .notDetermined: center.requestAuthorization(options: [.alert, .sound]) { ok, _ in if ok { add() } }
            case .authorized, .provisional: add()
            default: break
            }
        }
    }
}
