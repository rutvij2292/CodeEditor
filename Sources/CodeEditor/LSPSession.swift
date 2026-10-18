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
    private var diags: [String: [LSPDiagnostic]] = [:]
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

    func didOpen(in inst: LSPServerInstance) {
        guard let client = inst.client, !opened.contains(inst.key) else { return }
        opened.insert(inst.key)
        if inst.syncKind == 2 { resetShadow() }
        let ext = url.pathExtension.lowercased()
        client.notify("textDocument/didOpen", ["textDocument": [
            "uri": uri, "languageId": inst.config.languageId(forExtension: ext), "version": version, "text": text,
        ]])
    }

    func instanceRestarting(_ inst: LSPServerInstance) { opened.remove(inst.key); updateShadowNeed() }

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        scheduleSignatureCheck()
    }

    /// Sends any pending edit now (full-text sync; valid for servers declaring incremental sync too).
    func flushChanges() {
        flushWork?.cancel()
        guard hasUnsentChanges else { return }
        hasUnsentChanges = false
        version += 1
        let current = text as NSString
        // Incremental changes are only trusted while the mirror still equals the editor text (any edit that
        // bypassed the storage notification, a gap, or too many queued edits falls back to full sync).
        var incremental: [[String: Any]]?
        if let sh = shadow, !shadowStale, sh.matches(current) { incremental = pendingChanges }
        let fullChanges: [[String: Any]] = [["text": text]]
        for inst in instances where opened.contains(inst.key) {
            let useInc = inst.syncKind == 2 && incremental != nil
            let changes = useInc ? incremental! : fullChanges
            if useInc { incrementalSends += 1 } else { fullSends += 1 }
            LSPSession.didChangeObserver?(uri, changes)
            inst.client?.notify("textDocument/didChange", [
                "textDocument": ["uri": uri, "version": version], "contentChanges": changes,
            ] as [String: Any])
        }
        if shadow != nil, shadowStale || !(shadow?.matches(current) ?? false) { shadow = LSPShadow(current); shadowStale = false }
        pendingChanges.removeAll()
    }

    func didSave() {
        flushChanges()
        for inst in instances where opened.contains(inst.key) {
            inst.client?.notify("textDocument/didSave", ["textDocument": ["uri": uri]])
            inst.client?.notify("workspace/didChangeWatchedFiles", ["changes": [["uri": uri, "type": 2]]])
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
    var allDiagnostics: [LSPDiagnostic] { diags.values.flatMap { $0 } }

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
                                     message: (d["message"] as? String) ?? "", source: d["source"] as? String, code: code))
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
        allDiagnostics.filter { NSLocationInRange(offset, $0.range) }.sorted { $0.severity < $1.severity }
    }
}

/// Draws wavy underlines for the session's diagnostics; invisible to the mouse.
final class LSPDiagnosticOverlay: NSView {
    weak var session: LSPSession?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let session, let tv = session.textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let origin = tv.textContainerOrigin
        let length = tv.textStorage?.length ?? 0
        for d in session.allDiagnostics.sorted(by: { $0.severity > $1.severity }) {
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
