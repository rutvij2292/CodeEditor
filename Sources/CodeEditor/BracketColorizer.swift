import AppKit

/// Rainbow bracket colouring + matching-bracket highlight.
///
/// Design: the layout manager's delegate is consulted *at draw time* for the temporary attributes of every
/// run (`shouldUseTemporaryAttributes`). For bracket characters we return the syntax run's attributes with a
/// different foreground (and optionally background), so we survive `Highlighter.apply()` untouched and
/// scrolling costs nothing (a binary search per visible bracket). The bracket table itself is rebuilt on a
/// background queue (tree-sitter incremental reparse -> string/comment spans -> linear scan) and kept in
/// sync on the main thread between rebuilds by shifting offsets.
final class BracketColorizer: NSObject, NSMenuItemValidation {
    static let shared = BracketColorizer()
    static let defaultsKey = "bracketPairColorization"

    private var states: [ObjectIdentifier: TabBracketState] = [:]
    private(set) static var enabled = true

    static func start() {
        let d = UserDefaults.standard
        d.register(defaults: [defaultsKey: true])
        enabled = AppEnv.headless ? true : d.bool(forKey: defaultsKey)
        EditorEvents.onOpen { tab in if !tab.isLargeFile { shared.attach(tab) } }
        EditorEvents.onClose { tab in shared.detach(tab) }
        NotificationCenter.default.addObserver(shared, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
    }

    func attach(_ tab: EditorTab) {
        let id = ObjectIdentifier(tab.textView)
        guard states[id] == nil else { return }
        states[id] = TabBracketState(tab: tab)
    }

    func detach(_ tab: EditorTab) {
        states.removeValue(forKey: ObjectIdentifier(tab.textView))?.tearDown()
    }

    func state(for textView: NSTextView) -> TabBracketState? { states[ObjectIdentifier(textView)] }

    @objc private func themeChanged() { redrawAll() }

    private func redrawAll() { states.values.forEach { $0.redraw() } }

    // MARK: Menu actions (targets are set explicitly, so no responder-chain plumbing is needed)

    @objc func toggleBracketColorization(_ sender: Any?) {
        Self.enabled.toggle()
        if !AppEnv.headless { UserDefaults.standard.set(Self.enabled, forKey: Self.defaultsKey) }
        redrawAll()
    }

    @objc func moveCaretToMatchingBrace(_ sender: Any?) {
        guard let tv = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        state(for: tv)?.moveCaretToMatching()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleBracketColorization(_:)) { item.state = Self.enabled ? .on : .off }
        if item.action == #selector(moveCaretToMatchingBrace(_:)) { return NSApp.keyWindow?.firstResponder is NSTextView }
        return true
    }

    // MARK: Palette (5-colour cycle, tuned per appearance)

    private static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    static let darkCycle = [c(0.98, 0.80, 0.25), c(0.86, 0.50, 0.92), c(0.38, 0.68, 1.0), c(0.42, 0.86, 0.55), c(0.96, 0.58, 0.36)]
    static let lightCycle = [c(0.70, 0.50, 0.0), c(0.66, 0.22, 0.74), c(0.10, 0.40, 0.86), c(0.08, 0.56, 0.28), c(0.84, 0.36, 0.08)]
    static let darkUnmatched = c(1.0, 0.38, 0.38), lightUnmatched = c(0.85, 0.08, 0.08)

    static func color(depth: Int, unmatched: Bool, dark: Bool) -> NSColor {
        if unmatched { return dark ? darkUnmatched : lightUnmatched }
        let cycle = dark ? darkCycle : lightCycle
        return cycle[depth % cycle.count]
    }
}

/// Per-tab state. Also the layout manager's delegate (forwarding everything else to the previous delegate).
final class TabBracketState: NSObject, NSLayoutManagerDelegate {
    private weak var tab: EditorTab?
    private weak var textView: NSTextView?
    private weak var layout: NSLayoutManager?
    private weak var forwardee: NSLayoutManagerDelegate?
    private let ext: String

    private(set) var model = BracketModel()
    private var activePair: (UInt32, UInt32)?
    private var observers: [NSObjectProtocol] = []

    // Rescan pipeline
    private let queue = DispatchQueue(label: "bracket.scan", qos: .userInitiated)
    private let lock = NSLock()
    private struct Job { var text: [UInt16]; var acc: EditAcc?; var fresh: Bool; var id: Int; var logCount: Int }
    private var slot: Job?                       // guarded by lock
    private var scanner: TreeScanner?            // queue-only
    private var scannerMade = false              // queue-only
    private var nextJob = 0, latestJob = 0
    private var editLog: [(Int, Int, Int)] = []
    private var pendingAcc: EditAcc?
    private var firstJob = true
    private var debounce: DispatchWorkItem?
    /// Test hook: called on main after a rescan result has been installed.
    var onModelUpdated: (() -> Void)?

    init(tab: EditorTab) {
        self.tab = tab
        textView = tab.textView
        layout = tab.textView.layoutManager
        ext = tab.url.pathExtension
        super.init()
        if let lm = layout {
            if let existing = lm.delegate, existing !== self { forwardee = existing }
            lm.delegate = self
        }
        let nc = NotificationCenter.default
        if let storage = tab.textView.textStorage {
            observers.append(nc.addObserver(forName: NSTextStorage.didProcessEditingNotification, object: storage, queue: nil) { [weak self] _ in
                self?.storageEdited()
            })
        }
        observers.append(nc.addObserver(forName: NSTextView.didChangeSelectionNotification, object: tab.textView, queue: nil) { [weak self] _ in
            self?.updatePair()
        })
        scheduleScan(delay: 0)
    }

    func tearDown() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        debounce?.cancel()
        if let lm = layout, lm.delegate === self { lm.delegate = forwardee }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    // MARK: Delegate forwarding

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (forwardee as AnyObject?)?.responds(to: aSelector) == true
    }
    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let f = forwardee as AnyObject?, f.responds(to: aSelector) { return f }
        return super.forwardingTarget(for: aSelector)
    }

    // MARK: Draw-time attribute substitution

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldUseTemporaryAttributes attrs: [NSAttributedString.Key: Any] = [:],
                       forDrawingToScreen toScreen: Bool, atCharacterIndex charIndex: Int,
                       effectiveRange effectiveCharRange: NSRangePointer?) -> [NSAttributedString.Key: Any]? {
        guard BracketColorizer.enabled, model.count > 0 else { return attrs }
        let end = effectiveCharRange.map { NSMaxRange($0.pointee) } ?? charIndex + 1
        let i = model.lowerBound(charIndex)
        guard i < model.count else { return attrs }
        let p = Int(model.pos[i])
        if p == charIndex {
            effectiveCharRange?.pointee = NSRange(location: p, length: 1)
            return decorated(attrs, index: i)
        }
        if p < end { effectiveCharRange?.pointee = NSRange(location: charIndex, length: p - charIndex) }
        return attrs
    }

    func decorated(_ attrs: [NSAttributedString.Key: Any], index i: Int) -> [NSAttributedString.Key: Any] {
        var a = attrs
        let dark = Theme.isDark
        let unmatched = model.isUnmatched(i)
        let color = BracketColorizer.color(depth: Int(model.depth[i]), unmatched: unmatched, dark: dark)
        a[.foregroundColor] = color
        if unmatched {
            a[.backgroundColor] = BracketColorizer.color(depth: 0, unmatched: true, dark: dark).withAlphaComponent(dark ? 0.25 : 0.16)
        } else if let pair = activePair, pair.0 == model.pos[i] || pair.1 == model.pos[i] {
            a[.backgroundColor] = color.withAlphaComponent(dark ? 0.32 : 0.24)
        }
        return a
    }

    // MARK: Edits and rescans

    private func storageEdited() {
        guard let storage = textView?.textStorage, storage.editedMask.contains(.editedCharacters) else { return }
        let r = storage.editedRange, delta = storage.changeInLength
        let oldLen = r.length - delta
        model.applyEdit(location: r.location, oldLength: oldLen, newLength: r.length)
        editLog.append((r.location, oldLen, r.length))
        if pendingAcc == nil { pendingAcc = EditAcc(location: r.location, oldLength: oldLen, newLength: r.length) }
        else { pendingAcc!.merge(location: r.location, oldLength: oldLen, newLength: r.length) }
        scheduleScan(delay: r.length + oldLen > 20_000 ? 0.15 : 0.06)
    }

    private func scheduleScan(delay: TimeInterval) {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.snapshotAndScan() }
        debounce = work
        if delay == 0 { DispatchQueue.main.async(execute: work) }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    }

    private func snapshotAndScan() {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        var units = [UInt16](repeating: 0, count: ns.length)
        units.withUnsafeMutableBufferPointer { ns.getCharacters($0.baseAddress!, range: NSRange(location: 0, length: ns.length)) }
        nextJob += 1; latestJob = nextJob
        let job = Job(text: units, acc: pendingAcc, fresh: firstJob, id: nextJob, logCount: editLog.count)
        pendingAcc = nil
        firstJob = false
        lock.lock()
        if var s = slot {
            // Merge with the not-yet-started job: compose the edits, keep the newest text.
            var acc = s.acc
            if let later = job.acc { if acc == nil { acc = later } else { acc!.merge(later) } }
            s = Job(text: job.text, acc: acc, fresh: s.fresh || job.fresh, id: job.id, logCount: job.logCount)
            slot = s
        } else { slot = job }
        lock.unlock()
        queue.async { [weak self] in self?.runPending() }
    }

    private func runPending() {
        lock.lock(); let job = slot; slot = nil; lock.unlock()
        guard let job else { return }
        if !scannerMade { scanner = TreeScanner(extension: ext); scannerMade = true }
        let spans = scanner?.update(text: job.text, edit: job.fresh ? nil : job.acc)
        let model = BracketScanner.build(job.text, spans: spans, spec: .forExtension(ext))
        DispatchQueue.main.async { [weak self] in self?.install(model, job: job) }
    }

    private func install(_ fresh: BracketModel, job: Job) {
        var m = fresh
        for (loc, o, n) in editLog[min(job.logCount, editLog.count)...] { m.applyEdit(location: loc, oldLength: o, newLength: n) }
        if job.id == latestJob { editLog.removeAll() }
        model = m
        updatePair(force: true)
        redraw()
        onModelUpdated?()
    }

    func redraw() {
        guard let tv = textView else { return }
        tv.setNeedsDisplay(tv.visibleRect)
    }

    // MARK: Matching

    private func updatePair(force: Bool = false) {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        var new: (UInt32, UInt32)?
        if sel.length == 0, BracketColorizer.enabled, let p = model.pair(atCaret: sel.location) {
            new = (model.pos[p.open], model.pos[p.close])
        }
        if !force, new?.0 == activePair?.0, new?.1 == activePair?.1 { return }
        let old = activePair
        activePair = new
        for pos in [old?.0, old?.1, new?.0, new?.1].compactMap({ $0 }) {
            layout?.invalidateDisplay(forCharacterRange: NSRange(location: Int(pos), length: 1))
        }
    }

    /// Currently highlighted pair offsets (for tests).
    var highlightedPair: (Int, Int)? { activePair.map { (Int($0.0), Int($0.1)) } }

    func moveCaretToMatching() {
        guard let tv = textView else { return }
        let caret = tv.selectedRange().location
        var target: Int?
        if let p = model.pair(atCaret: caret) {
            target = model.isCloser(p.touching) ? Int(model.pos[p.open]) : Int(model.pos[p.close]) + 1
        } else if let o = model.enclosingOpener(before: caret), let c = model.partner(of: o) {
            target = Int(model.pos[c]) + 1
        }
        guard let t = target else { NSSound.beep(); return }
        tv.setSelectedRange(NSRange(location: t, length: 0))
        tv.scrollRangeToVisible(NSRange(location: t, length: 0))
    }
}
