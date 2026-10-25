import AppKit

struct LSPDiagnostic {
    var range: NSRange
    let severity: Int            // 1 error, 2 warning, 3 info, 4 hint
    let message: String
    let source: String?
    let code: String?
}

/// Per-open-tab glue: document sync with every server attached to the file, diagnostics display, and the
/// hover / signature / definition UI (see LSPUI.swift).
final class LSPSession: NSResponder {
    weak var tab: EditorTab?
    let url: URL
    unowned let manager: LanguageServerManager
    var instances: [LSPServerInstance] = []
    private(set) var version = 1
    private var opened: Set<String> = []
    private var flushWork: DispatchWorkItem?
    private var hasUnsentChanges = false
    private var diags: [String: [LSPDiagnostic]] = [:] { didSet { diagCache = nil; diagSortedCache = nil } }
    private var diagCache: [LSPDiagnostic]?
    private var diagSortedCache: [LSPDiagnostic]?
    private var applyScheduled = false
    private var observers: [NSObjectProtocol] = []

    // Incremental sync (see LSPSync.swift). `shadow` exists only while some attached server wants incremental changes.
    var shadow: LSPShadow?
    private var pendingChanges: [[String: Any]] = []
    private var shadowStale = false
    /// Test hook: every didChange payload (uri, contentChanges) right before it is sent.
    static var didChangeObserver: ((String, [[String: Any]]) -> Void)?
    private(set) var incrementalSends = 0, fullSends = 0
    private static let maxPendingChanges = 64

    // UI state (LSPUI.swift)
    var hoverToken = 0
    var hoverTimer: Timer?
    var hoverAnchor: NSRange?
    var linkRange: NSRange?
    var linkToken = 0
    var linkPending: NSRange?          // word whose definition check is in flight (moves inside it must not restart the check)
    var linkRequests = 0  // test hook: definition checks started
    var signatureWork: DispatchWorkItem?
    var trackingArea: NSTrackingArea?
    var overlay: LSPDiagnosticOverlay?

    var uri: String { url.standardizedFileURL.absoluteString }
    var textView: CodeTextView? { tab?.textView }
    var text: String { tab?.textView.string ?? "" }

    init(tab: EditorTab, manager: LanguageServerManager) {
        self.tab = tab
        self.url = tab.url
        self.manager = manager
        super.init()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(textChanged(_:)), name: NSText.didChangeNotification, object: tab.textView)
        if let storage = tab.textView.textStorage {
            nc.addObserver(self, selector: #selector(storageEdited(_:)),
                           name: NSTextStorage.didProcessEditingNotification, object: storage)
        }
        nc.addObserver(self, selector: #selector(selectionChanged(_:)),
                       name: NSTextView.didChangeSelectionNotification, object: tab.textView)
        nc.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: Sync

    func instance(_ serverId: String) -> LSPServerInstance? { instances.first { $0.config.id == serverId } }

    /// First initialised server of this file that advertises `capability` (e.g. "hoverProvider").
    func instance(supporting capability: String) -> LSPServerInstance? {
        instances.first { $0.supports(capability) && opened.contains($0.key) }
    }

    /// All initialised servers of this file that advertise `capability`, in priority order.
    func instances(supporting capability: String) -> [LSPServerInstance] {
        instances.filter { $0.supports(capability) && opened.contains($0.key) }
    }

    /// Asks the supporting servers in order until one gives a non-empty answer (e.g. a Vue file: Volar for template
    /// positions, the TypeScript server for script positions). The last server's answer (or the first error) is
    /// delivered when nobody has anything.
    func requestChain(_ capability: String, _ method: String, _ params: [String: Any], timeout: TimeInterval,
                      accept: @escaping (Any?) -> Bool = { LSPSession.nonEmpty($0) },
                      completion: @escaping (LSPClient.Result, LSPServerInstance?) -> Void) {
        let candidates = instances(supporting: capability)
        func step(_ i: Int, _ firstError: LSPError?) {
            guard i < candidates.count, let client = candidates[i].client else {
                completion(firstError.map { .failure($0) } ?? .failure(.notRunning), candidates.last); return
            }
            let last = i == candidates.count - 1
            client.request(method, params, timeout: timeout) { result in
                switch result {
                case .success(let v):
                    if last || accept(v) { completion(result, candidates[i]) } else { step(i + 1, firstError) }
                case .failure(let e):
                    if last { completion(firstError.map { .failure($0) } ?? result, candidates[i]) } else { step(i + 1, firstError ?? e) }
                }
            }
        }
        step(0, nil)
    }

    static func nonEmpty(_ v: Any?) -> Bool {
        guard let v, !(v is NSNull) else { return false }
        if let a = v as? [Any] { return !a.isEmpty }
        if let d = v as? [String: Any] { return !d.isEmpty }
        return true
    }

    func didOpen(in inst: LSPServerInstance) {
        guard let client = inst.client, !opened.contains(inst.key) else { return }
        opened.insert(inst.key)
        if inst.syncKind == 2 { resetShadow() }
        client.notify("textDocument/didOpen", ["textDocument": [
            "uri": uri, "languageId": inst.config.languageId(for: url), "version": version, "text": text,
        ]])
        requestDiagnostics(from: inst, delay: 0.05)
    }

    func instanceRestarting(_ inst: LSPServerInstance) {
        opened.remove(inst.key)
        pullWork[inst.key]?.cancel(); pullWork[inst.key] = nil
        updateShadowNeed()
    }

    /// Drops every server attachment (servers stopped or re-evaluated); `attach` rebuilds them.
    func resetAttachments() {
        for inst in instances where opened.contains(inst.key) { inst.client?.notify("textDocument/didClose", ["textDocument": ["uri": uri]]) }
        opened.removeAll()
        instances.removeAll()
        pullWork.values.forEach { $0.cancel() }
        pullWork.removeAll()
        shadow = nil
        pendingChanges.removeAll()
        diags.removeAll()
        manager.clearDiagnostics(forPath: url.standardizedFileURL.path)
        scheduleApply()
    }

    // MARK: Pull diagnostics (servers such as native TypeScript only answer `textDocument/diagnostic`)

    private var pullWork: [String: DispatchWorkItem] = [:]

    func requestDiagnostics(from inst: LSPServerInstance, delay: TimeInterval = 0.3) {
        guard inst.usesPullDiagnostics, opened.contains(inst.key), inst.supports("diagnosticProvider") else { return }
        pullWork[inst.key]?.cancel()
        let work = DispatchWorkItem { [weak self, weak inst] in self?.pullNow(inst) }
        pullWork[inst.key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func pullNow(_ inst: LSPServerInstance?) {
        guard let inst, let client = inst.client, opened.contains(inst.key) else { return }
        flushChanges()
        let sent = version
        client.request("textDocument/diagnostic", ["textDocument": ["uri": uri]], timeout: 60) { [weak self, weak inst] result in
            guard let self, let inst, self.opened.contains(inst.key), case .success(let v) = result,
                  let d = v as? [String: Any] else { return }
            if sent != self.version { return }       // edited meanwhile; the edit queued a fresh pull
            if (d["kind"] as? String) == "unchanged" { inst.endWarmup(); return }
            self.setDiagnostics((d["items"] as? [[String: Any]]) ?? [], serverId: inst.config.id, version: nil)
            inst.endWarmup()
        }
    }

    private func resetShadow() {
        pendingChanges.removeAll()
        shadowStale = false
        shadow = LSPShadow((textView?.string ?? "") as NSString)
    }

    private func updateShadowNeed() {
        if !instances.contains(where: { opened.contains($0.key) && $0.syncKind == 2 }) { shadow = nil; pendingChanges.removeAll() }
    }

    @objc private func textChanged(_ n: Notification) {
        hasUnsentChanges = true
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushChanges() }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PowerState.shared.scaled(0.12), execute: work)
        scheduleSignatureCheck()
    }

    private var flushCount = 0
    private var lastEditLocation = 0

    /// Whether the mirror still equals the buffer. A full compare of a 700 KB file on every flush cost ~5 ms, so big files
    /// compare lengths plus the text around the last edit, and everything every 16th flush.
    private func shadowMatches(_ sh: LSPShadow, _ current: NSString) -> Bool {
        guard sh.length == current.length else { return false }
        flushCount += 1
        if sh.length < 20_000 || flushCount % 16 == 0 { return sh.matches(current) }
        let from = max(0, min(lastEditLocation, sh.length) - 300)
        let r = NSRange(location: from, length: min(600, sh.length - from))
        return sh.text.substring(with: r) == current.substring(with: r)
    }

    /// Sends any pending edit now (full-text sync; valid for servers declaring incremental sync too).
    func flushChanges() { Perf.measure("lsp.flush") { flushChangesImpl() } }

    private func flushChangesImpl() {
        flushWork?.cancel()
        guard hasUnsentChanges else { return }
        hasUnsentChanges = false
        version += 1
        // The live storage string (no copy): `text` bridges a full copy of the buffer on every call.
        let current: NSString = tab?.textView.textStorage?.mutableString ?? ("" as NSString)
        // Incremental changes are only trusted while the mirror still equals the editor text (any edit that
        // bypassed the storage notification, a gap, or too many queued edits falls back to full sync).
        var incremental: [[String: Any]]?
        if let sh = shadow, !shadowStale, shadowMatches(sh, current) { incremental = pendingChanges }
        var fullCache: [[String: Any]]?
        func fullChanges() -> [[String: Any]] {
            if let fullCache { return fullCache }
            let c: [[String: Any]] = [["text": text]]
            fullCache = c
            return c
        }
        for inst in instances where opened.contains(inst.key) {
            let useInc = inst.syncKind == 2 && incremental != nil
            let changes = useInc ? incremental! : fullChanges()
            if useInc { incrementalSends += 1 } else { fullSends += 1 }
            LSPSession.didChangeObserver?(uri, changes)
            inst.client?.notify("textDocument/didChange", [
                "textDocument": ["uri": uri, "version": version], "contentChanges": changes,
            ] as [String: Any])
        }
        if let sh = shadow, shadowStale || !shadowMatches(sh, current) { shadow = LSPShadow(current); shadowStale = false }
        pendingChanges.removeAll()
        for inst in instances where inst.usesPullDiagnostics && opened.contains(inst.key) {
            requestDiagnostics(from: inst)
            // Other open files of the project may now have (or lose) errors, e.g. after changing an exported type.
            for other in inst.sessions.values where other !== self { other.requestDiagnostics(from: inst, delay: 1.0) }
        }
    }

    func didSave() {
        flushChanges()
        for inst in instances where opened.contains(inst.key) {
            inst.client?.notify("textDocument/didSave", ["textDocument": ["uri": uri]])
            inst.client?.notify("workspace/didChangeWatchedFiles", ["changes": [["uri": uri, "type": 2]]])
            requestDiagnostics(from: inst, delay: 0.1)
        }
    }

    func close() {
        flushWork?.cancel()
        hoverTimer?.invalidate()
        signatureWork?.cancel()
        LSPPopups.hideAll(for: self)
        for inst in instances where opened.contains(inst.key) {
            inst.client?.notify("textDocument/didClose", ["textDocument": ["uri": uri]])
        }
        opened.removeAll()
        if let tv = textView, let area = trackingArea { tv.removeTrackingArea(area) }
        clearUnderlines()
        diags.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Diagnostics

    func diagnostics(for serverId: String) -> [LSPDiagnostic] { diags[serverId] ?? [] }
    /// Diagnostics of every server, identical ones (same range, severity and text from different servers) merged.
    var allDiagnostics: [LSPDiagnostic] {
        if let diagCache { return diagCache }
        var seen = Set<String>()
        var out: [LSPDiagnostic] = []
        for key in diags.keys.sorted() {
            for d in diags[key] ?? [] where seen.insert("\(d.range.location):\(d.range.length):\(d.severity):\(d.message)").inserted {
                out.append(d)
            }
        }
        diagCache = out
        return out
    }

    /// `allDiagnostics` ordered most severe first, cached (the overlay draws on every frame).
    var sortedDiagnostics: [LSPDiagnostic] {
        if let diagSortedCache { return diagSortedCache }
        let sorted = allDiagnostics.sorted { $0.severity > $1.severity }
        diagSortedCache = sorted
        return sorted
    }

    func setDiagnostics(_ raw: [[String: Any]], serverId: String, version published: Int?) {
        LSPLog.log("diagnostics \(url.lastPathComponent) published v\(published.map(String.init) ?? "-") ours v\(version) n=\(raw.count)")
        if let published, published < version { return }   // computed for text we have already edited past
        let ns = text as NSString
        let table = LSPLineTable(ns)
        var out: [LSPDiagnostic] = []
        for d in raw {
            guard let r = d["range"] as? [String: Any], var range = table.range(fromLSP: r) else { continue }
            if range.length == 0 {
                if range.location < ns.length { range.length = 1 }
                else if range.location > 0 { range = NSRange(location: range.location - 1, length: 1) }
            }
            var code: String?
            if let c = d["code"] as? String { code = c } else if let c = d["code"] as? NSNumber { code = c.stringValue }
            out.append(LSPDiagnostic(range: range, severity: (d["severity"] as? NSNumber)?.intValue ?? 1,
                                     message: (d["message"] as? String) ?? "",
                                     source: (d["source"] as? String) ?? instance(serverId)?.config.name, code: code))
        }
        diags[serverId] = out
        manager.recordDiagnostics(for: self, serverId: serverId)
        scheduleApply()
    }

    @objc private func storageEdited(_ n: Notification) {
        guard let storage = n.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
        let edited = storage.editedRange, delta = storage.changeInLength
        trackEdit(storage, edited: edited, delta: delta)
        guard !diags.isEmpty else { return }
        let oldEnd = edited.location + edited.length - delta
        for (k, list) in diags {
            diags[k] = list.map { d in
                var d = d
                let s = d.range.location, e = NSMaxRange(d.range)
                if e <= edited.location { return d }
                if s >= oldEnd { d.range.location = s + delta; return d }
                let newEnd = max(s, e + delta)
                d.range = NSRange(location: min(s, edited.location), length: max(0, newEnd - min(s, edited.location)))
                return d
            }
        }
        scheduleApply()
    }

    /// Records the edit into the shadow (computing the LSP range from the pre-edit mirror).
    private func trackEdit(_ storage: NSTextStorage, edited: NSRange, delta: Int) {
        lastEditLocation = edited.location
        guard shadow != nil, !shadowStale else { return }
        let oldRange = NSRange(location: edited.location, length: edited.length - delta)
        guard oldRange.length >= 0, NSMaxRange(edited) <= storage.length,
              pendingChanges.count < Self.maxPendingChanges else { shadowStale = true; pendingChanges.removeAll(); return }
        let inserted = (storage.string as NSString).substring(with: edited) as NSString
        if let change = shadow?.replace(oldRange, with: inserted) { pendingChanges.append(change) }
        else { shadowStale = true; pendingChanges.removeAll() }
    }

    private func scheduleApply() {
        guard !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.applyScheduled = false
            self?.applyUnderlines()
        }
    }

    @objc private func themeChanged() { applyUnderlines() }

    static func color(forSeverity s: Int) -> NSColor {
        switch s {
        case 1: return .systemRed
        case 2: return .systemOrange
        case 3: return .systemBlue
        default: return .systemGray
        }
    }

    /// Squiggles are drawn by a transparent overlay subview of the text view (TextKit 1 temporary underline
    /// attributes only support straight/dotted lines), so the Highlighter's attributes are never touched.
    func applyUnderlines() {
        guard let tv = textView else { return }
        if overlay == nil || overlay?.superview !== tv {
            let o = LSPDiagnosticOverlay(frame: tv.bounds)
            o.autoresizingMask = [.width, .height]
            o.session = self
            tv.addSubview(o)
            overlay = o
        }
        overlay?.needsDisplay = true
    }

    private func clearUnderlines() { overlay?.removeFromSuperview(); overlay = nil }

    func diagnostics(at offset: Int) -> [LSPDiagnostic] {
        (allDiagnostics + NativeEngines.hoverDiagnostics(for: tab)).filter { NSLocationInRange(offset, $0.range) }.sorted { $0.severity < $1.severity }
    }
}

/// Draws wavy underlines for the session's diagnostics; invisible to the mouse.
final class LSPDiagnosticOverlay: NSView {
    weak var session: LSPSession?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let session, let tv = session.textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let all = session.sortedDiagnostics
        guard !all.isEmpty else { return }
        let origin = tv.textContainerOrigin
        let length = tv.textStorage?.length ?? 0
        // Only diagnostics intersecting the dirty rect cost anything: asking the layout manager for rects of every
        // diagnostic of a big file on every draw used to dominate scroll/typing frames.
        var local = dirtyRect.insetBy(dx: -4, dy: -4)
        local.origin.x -= origin.x; local.origin.y -= origin.y
        let visibleGlyphs = lm.glyphRange(forBoundingRect: local, in: tc)
        let visible = lm.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        for d in all {
            guard NSMaxRange(d.range) >= visible.location, d.range.location <= NSMaxRange(visible) else { continue }
            let cr = NSIntersectionRange(d.range, NSRange(location: 0, length: length))
            guard cr.length > 0 else { continue }
            let gr = lm.glyphRange(forCharacterRange: cr, actualCharacterRange: nil)
            LSPSession.color(forSeverity: d.severity).setStroke()
            lm.enumerateEnclosingRects(forGlyphRange: gr, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                       in: tc) { rect, _ in
                let r = rect.offsetBy(dx: origin.x, dy: origin.y)
                guard r.intersects(dirtyRect.insetBy(dx: -4, dy: -4)) else { return }
                let y = r.maxY - 1.5
                let path = NSBezierPath()
                path.lineWidth = 1.1
                var x = r.minX
                var up = true
                path.move(to: NSPoint(x: x, y: y))
                while x < r.maxX {
                    x = min(x + 2, r.maxX)
                    path.line(to: NSPoint(x: x, y: up ? y - 1.6 : y))
                    up.toggle()
                }
                path.stroke()
            }
        }
    }
}
