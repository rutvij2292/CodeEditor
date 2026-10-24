import AppKit

/// Compiled regular expressions shared by the native PHP engine. Compiling an NSRegularExpression costs 20-100 us (more for long
/// patterns), which adds up when a request does it per class / per file. Bounded (64 entries, wiped when full) so pattern strings built
/// from user names cannot grow it.
enum NPRe {
    private static let lock = NSLock()
    private static var cache: [String: NSRegularExpression] = [:]

    static func make(pattern: String, options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        let key = "\(options.rawValue)|" + pattern
        lock.lock()
        if let r = cache[key] { lock.unlock(); return r }
        lock.unlock()
        guard let r = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        lock.lock()
        if cache.count >= 64 { cache.removeAll() }
        cache[key] = r
        lock.unlock()
        return r
    }

    static var cachedCount: Int { lock.lock(); defer { lock.unlock() }; return cache.count }
}

extension NativePHP {
    /// Drops every memoised parse and cached file text of the native engine and hands freed pages back to the system.
    /// Safe at any time (the next request simply re-reads what it needs). Called when the window is hidden, in power-saver
    /// mode and on memory pressure; never from a timer.
    static func trimMemory() {
        NPFiles.clear()
        NPText.dropTables()
        PHPStubs.dropParsed()
        dropLastParse()
        FastProject.trimAll()
        malloc_zone_pressure_relief(nil, 0)
    }

    private static var hooksInstalled = false
    private static var pressureSource: DispatchSourceMemoryPressure?

    /// Event driven trimming: system memory pressure, all windows hidden / app hidden, power saver switched on.
    static func installMemoryHooks() {
        guard !hooksInstalled else { return }
        hooksInstalled = true
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        src.setEventHandler { trimMemory() }
        src.resume()
        pressureSource = src
        let nc = NotificationCenter.default
        nc.addObserver(forName: PowerState.didChange, object: nil, queue: .main) { _ in
            if PowerState.shared.saver { DispatchQueue.global(qos: .utility).async { trimMemory() } }
        }
        nc.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main) { _ in
            DispatchQueue.global(qos: .utility).async { trimMemory() }
        }
        nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { _ in
            guard !AppEnv.headless else { return }
            let anyVisible = NSApp.windows.contains { $0.isVisible && $0.occlusionState.contains(.visible) && !$0.isMiniaturized }
            if !anyVisible { DispatchQueue.global(qos: .utility).async { trimMemory() } }
        }
    }
}

/// Cheap cumulative timers (nanoseconds) for the cold paths of the native engine; read by the benchmark and by tests.
/// Not synchronised on purpose: only used for diagnostics, a lost update is harmless.
enum NPStats {
    static var readNs: UInt64 = 0
    static var parseNs: UInt64 = 0
    static var funcIndexNs: UInt64 = 0
    static var docNs: UInt64 = 0
    static var scanReadNs: UInt64 = 0, scanLexNs: UInt64 = 0, scanParseNs: UInt64 = 0, scanResolveNs: UInt64 = 0
    static var candListNs: UInt64 = 0, candTotalNs: UInt64 = 0, candFiles = 0
    static var pathNs: UInt64 = 0
    static var reads = 0
    static var parses = 0

    @inline(__always) static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    static func snapshot() -> (read: Double, parse: Double, funcs: Double, doc: Double, reads: Int, parses: Int) {
        (Double(readNs) / 1e6, Double(parseNs) / 1e6, Double(funcIndexNs) / 1e6, Double(docNs) / 1e6, reads, parses)
    }
}
