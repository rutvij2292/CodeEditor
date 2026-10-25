import AppKit

/// Per-tab completion controller: auto-trigger, provider merging/ranking, popup keyboard handling, accept + snippets.
final class CompletionController: NSObject {
    typealias Ranked = CompletionRanker.Ranked

    struct SnippetSession {
        var stops: [(index: Int, range: NSRange)]
        var current: Int
    }

    private weak var tab: EditorTab?
    let textView: CodeTextView
    private let ext: String
    private let url: URL

    private var providers: [CompletionProvider] = []
    private var results: [(items: [CompletionItem], incomplete: Bool)?] = []
    private(set) var ranked: [Ranked] = []
    private(set) var selected = 0
    private(set) var isOpen = false
    private var generation = 0
    private var debounce: Timer?
    private var anchor = 0
    private var requestingNow = false
    private var deliveredDuringRequest = false
    private var pendingTyped = false
    private var pendingEdit: (NSRange, Int)?
    private var lastLength = 0
    private var lastCaret = 0
    private var applying = false
    private var lastRequestManual = false
    private var rankContext = CompletionRanker.Context.empty
    /// Ctrl-Shift-Space: the list is limited to candidates whose type fits the expected type (typeMatch > 0).
    private var smartMode = false
    private lazy var projectKey: String = CompletionHistory.shared.projectKey(for: url)
    private var resolved: [String: CompletionItem] = [:]
    private var resolving: Set<String> = []
    private(set) var session: SnippetSession?
    private var observers: [NSObjectProtocol] = []

    var candidateLabels: [String] { ranked.map { $0.item.label } }

    init(tab: EditorTab) {
        self.tab = tab
        textView = tab.textView
        ext = tab.url.pathExtension.lowercased()
        url = tab.url
        super.init()
        lastLength = textView.textStorage?.length ?? 0
        lastCaret = textView.selectedRange().location

        let prevKey = textView.keyInterceptor
        textView.keyInterceptor = { [weak self] e in (self?.handleKey(e) ?? false) || (prevKey?(e) ?? false) }
        let prevTrigger = textView.onTriggerCompletion
        textView.onTriggerCompletion = { [weak self] in
            if let self { self.trigger(manual: true) } else { prevTrigger?() }
        }
        let prevSmart = textView.onTriggerSmartCompletion
        textView.onTriggerSmartCompletion = { [weak self] in
            if let self { self.trigger(manual: true, smart: true) } else { prevSmart?() }
        }
        let prevResign = textView.onResignFirstResponder
        textView.onResignFirstResponder = { [weak self] in self?.close(); prevResign?() }

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSText.didChangeNotification, object: textView, queue: nil) { [weak self] _ in self?.textChanged() })
        observers.append(nc.addObserver(forName: NSTextView.didChangeSelectionNotification, object: textView, queue: nil) { [weak self] _ in self?.selectionChanged() })
        let prevWill = textView.onWillChange
        textView.onWillChange = { [weak self] r, n in self?.pendingEdit = (r, n); prevWill?(r, n) }
        observers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] n in
            if let self, (n.object as? NSWindow) === self.textView.window { self.close() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.close() })
    }

    func detach() {
        close()
        endSession()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    // MARK: - Triggering

    private var allTriggers: Set<String> {
        var s = Set<String>()
        for p in CompletionRegistry.providers(forExtension: ext) { for t in p.triggerCharacters { s.insert(t) } }
        return s
    }

    private func identRunLength(_ caret: Int) -> Int {
        let ns = textView.string as NSString
        return caret - CompletionLex.runStart(ns, min(caret, ns.length), CompletionLex.isIdent)
    }

    func trigger(manual: Bool, character: String? = nil, smart: Bool = false) {
        debounce?.invalidate()
        if manual { smartMode = smart; request(trigger: character, manual: true) }
        else {
            debounce = Timer.scheduledTimer(withTimeInterval: PowerState.shared.scaled(CompletionSystem.debounce), repeats: false) { [weak self] _ in
                self?.request(trigger: character, manual: false)
            }
        }
    }

    private func textChanged() {
        if let e = pendingEdit {
            pendingEdit = nil
            if !applying { storageEdited(NSRange(location: e.0.location, length: e.1), delta: e.1 - e.0.length) }
        }
        guard !applying else { return }
        let len = textView.textStorage?.length ?? 0
        let sel = textView.selectedRange()
        let caret = sel.location
        let typed = pendingTyped
        pendingTyped = false
        defer { lastLength = len; lastCaret = caret }
        guard textView.selectedRanges.count == 1, !textView.multiCaretActive, sel.length == 0 else { close(); return }
        let grew = len > lastLength
        let ns = textView.string as NSString
        if isOpen {
            guard caret >= anchor else { close(); return }
            if !grew { refilter(); return }
            guard typed, caret > 0, caret <= ns.length else { close(); return }
            let c = ns.character(at: caret - 1)
            let s = String(utf16CodeUnits: [c], count: 1)
            if allTriggers.contains(s) { let keepSmart = smartMode; close(); smartMode = keepSmart; trigger(manual: false, character: s) }
            else if CompletionLex.isIdent(c) || "-$@#".utf16.contains(c) {
                if results.contains(where: { $0?.incomplete == true }) { trigger(manual: false) }
                refilter()
            } else { close() }
            return
        }
        guard typed, grew, session == nil, caret > 0, caret <= ns.length else { return }
        let c = ns.character(at: caret - 1)
        let s = String(utf16CodeUnits: [c], count: 1)
        if allTriggers.contains(s) { trigger(manual: false, character: s) }
        else if CompletionLex.isIdent(c), identRunLength(caret) >= CompletionSystem.autoOpenMinChars { trigger(manual: false) }
    }

    private func selectionChanged() {
        guard !applying else { return }
        let sel = textView.selectedRange()
        if isOpen, sel.location != lastCaret || sel.length > 0 { close() }
        if let s = session, let first = s.stops.map(\.range.location).min(), let last = s.stops.map(\.range.upperBound).max(),
           sel.location < first || sel.upperBound > last { endSession() }
        lastCaret = sel.location
    }

    // MARK: - Keys

    @discardableResult
    func handleKey(_ e: NSEvent) -> Bool {
        guard e.type == .keyDown else { return false }
        let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command), ctrl = flags.contains(.control), shift = flags.contains(.shift)
        let code = e.keyCode
        // Ctrl-Space (or Ctrl-Option-Space, in case macOS reserves Ctrl-Space for input-source switching) opens suggestions now.
        if code == 49, ctrl, !cmd {
            trigger(manual: true, smart: shift)
            return true
        }
        if isOpen {
            switch code {
            case 126: move(-1); return true
            case 125: move(1); return true
            case 116: move(-CompletionListView.visibleRows, clamp: true); return true
            case 121: move(CompletionListView.visibleRows, clamp: true); return true
            case 36, 76: if !cmd { acceptSelected(); return true }
            case 48:
                if shift { close(); return false }
                if flags.isDisjoint(with: [.command, .control, .option]), expandTemplate(requireTopMatch: true) { return true }
                acceptSelected(); return true
            case 53: close(); return true
            case 123, 124, 115, 119: close(); return false
            case 45 where ctrl: move(1); return true
            case 35 where ctrl: move(-1); return true
            case 49 where cmd: return false
            default: break
            }
        } else {
            if code == 48, flags.isDisjoint(with: [.command, .control, .option, .shift]), expandTemplate(requireTopMatch: false) { return true }
            if session != nil {
                if code == 48, flags.isDisjoint(with: [.command, .control, .option]) { return shift ? previousStop() : nextStop() }
                if code == 53 { endSession(); return true }
            }
        }
        if !cmd, !ctrl, let ch = e.characters?.unicodeScalars.first, ch.value >= 32, ch.value != 127, !(0xF700...0xF8FF).contains(ch.value) {
            pendingTyped = true
            DispatchQueue.main.async { [weak self] in self?.pendingTyped = false }
        }
        return false
    }

    /// Tab after a complete live-template abbreviation (LiveTemplates.swift) expands it through the snippet machinery.
    /// With the popup open (`requireTopMatch`) only when the highlighted row is that very abbreviation.
    private func expandTemplate(requireTopMatch: Bool) -> Bool {
        let sel = textView.selectedRange()
        guard sel.length == 0, textView.selectedRanges.count == 1, !textView.multiCaretActive else { return false }
        let ns = textView.string as NSString
        let caret = min(sel.location, ns.length)
        let start = CompletionLex.runStart(ns, caret, CompletionLex.isIdent)
        guard caret > start, caret - start <= 40, caret >= ns.length || !CompletionLex.isIdent(ns.character(at: caret)) else { return false }
        let abbrev = ns.substring(with: NSRange(location: start, length: caret - start))
        guard LiveTemplates.shared.knows(abbrev: abbrev) else { return false }
        if start > 0, !LiveTemplateCompletion.mayExpand(after: ns.character(at: start - 1)) { return false }
        if requireTopMatch, !(ranked.indices.contains(selected) && ranked[selected].item.label.lowercased() == abbrev.lowercased()) { return false }
        let ctx = CompletionContext(text: textView.string, caret: caret, fileURL: url, fileExtension: ext, triggerCharacter: nil, isManual: true,
                                    prefixRange: NSRange(location: start, length: caret - start))
        if ext != "md", ext != "markdown", CompletionLex.state(ctx) != .code { return false }
        guard let t = LiveTemplates.shared.lookup(abbrev, scopes: LiveTemplates.scopes(for: ctx)) else { return false }
        close()
        insert(LiveTemplates.item(t, fileURL: url, range: NSRange(location: start, length: caret - start)))
        return true
    }

    private func move(_ delta: Int, clamp: Bool = false) {
        guard !ranked.isEmpty else { return }
        var n = selected + delta
        if clamp { n = max(0, min(ranked.count - 1, n)) }
        else if n < 0 { n = ranked.count - 1 } else if n >= ranked.count { n = 0 }
        selected = n
        CompletionPopup.shared.update(selected: n)
        selectionDidChange()
    }

    // MARK: - Request / merge

    private func request(trigger: String?, manual: Bool) { Perf.measure("completion.request") { requestImpl(trigger: trigger, manual: manual) } }

    private func requestImpl(trigger: String?, manual: Bool) {
        generation += 1
        let g = generation
        providers.forEach { $0.cancel() }
        CompletionLex.resetCache()
        let sel = textView.selectedRange()
        guard sel.length == 0, textView.selectedRanges.count == 1, !textView.multiCaretActive else { return }
        let text = textView.string
        let ns = text as NSString
        let caret = min(sel.location, ns.length)
        let start = CompletionLex.runStart(ns, caret, CompletionLex.isIdent)
        var ctx = CompletionContext(text: text, caret: caret, fileURL: url, fileExtension: ext, triggerCharacter: trigger,
                                    isManual: manual, prefixRange: NSRange(location: start, length: caret - start))
        ctx.smart = smartMode
        lastRequestManual = manual
        let pkey = projectKey
        rankContext = CompletionRanker.Context(docCounts: CompletionRanker.docCounts(ns, caret: caret),
                                               history: { CompletionHistory.shared.level($0, project: pkey) },
                                               popularity: CompletionPopularity.table(ext: ext, blade: url.lastPathComponent.hasSuffix(".blade.php")))
        providers = CompletionRegistry.providers(forExtension: ext)
        results = Array(repeating: nil, count: providers.count)
        resolved = [:]; resolving = []
        anchor = start
        requestingNow = true
        deliveredDuringRequest = false
        for (i, p) in providers.enumerated() {
            p.complete(ctx) { [weak self] items, incomplete in
                let apply: () -> Void = { self?.deliver(i, items, incomplete, g) }
                if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
            }
        }
        requestingNow = false
        if deliveredDuringRequest { present() }
    }

    private func deliver(_ index: Int, _ items: [CompletionItem], _ incomplete: Bool, _ g: Int) {
        guard g == generation, index < results.count else { return }
        results[index] = (items, incomplete)
        if requestingNow { deliveredDuringRequest = true } else { present() }
    }

    private func refilter() { present() }

    // MARK: - Ranking

    private func rank() -> [Ranked] {
        let o = CompletionRanker.rank(results: results, text: textView.string as NSString, caret: textView.selectedRange().location, anchor: anchor, context: rankContext)
        anchor = o.anchor
        if smartMode { return o.ranked.filter { $0.item.typeMatch > 0 } }
        return o.ranked
    }

    private func matches(_ label: String, _ query: String) -> [Int] {
        guard !query.isEmpty else { return [] }
        let l = Array(label.lowercased().utf16), q = Array(query.lowercased().utf16)
        guard l.count == label.utf16.count else { return [] }
        if l.starts(with: q) { return Array(0..<q.count) }
        var out: [Int] = []
        var qi = 0
        for (i, c) in l.enumerated() where qi < q.count && c == q[qi] { out.append(i); qi += 1 }
        return qi == q.count ? out : []
    }

    private func present() { Perf.measure("completion.present") { presentImpl() } }

    private func presentImpl() {
        let previous = ranked.indices.contains(selected) ? ranked[selected].item.label + ranked[selected].item.kind.rawValue : nil
        ranked = rank()
        if ranked.isEmpty { hidePopup(); return }
        if ranked.count == 1, ranked[0].query == ranked[0].item.label, !lastRequestManual { hidePopup(); return }
        selected = previous.flatMap { p in ranked.firstIndex { $0.item.label + $0.item.kind.rawValue == p } } ?? 0
        let rows = ranked.map { PopupRow(label: $0.item.label, detail: $0.item.detail, kind: $0.item.kind,
                                         deprecated: $0.item.deprecated, matches: matches($0.item.label, $0.query)) }
        let wasOpen = isOpen
        isOpen = true
        let anchorLoc = min(anchor, textView.selectedRange().location)
        let popup = CompletionPopup.shared
        popup.list.onClick = { [weak self] idx in self?.selected = idx; self?.acceptSelected() }
        popup.present(rows: rows, selected: selected, anchor: screenRect(at: anchorLoc), window: textView.window)
        if !wasOpen { lastCaret = textView.selectedRange().location }
        selectionDidChange()
    }

    private func key(_ item: CompletionItem) -> String { item.label + "\u{1}" + item.kind.rawValue + "\u{1}" + item.detail }

    private func currentItem(_ i: Int) -> CompletionItem {
        let it = ranked[i].item
        return resolved[key(it)].map { r in
            var m = it
            if !r.documentation.isEmpty { m.documentation = r.documentation }
            if !r.detail.isEmpty { m.detail = r.detail }
            if !r.additionalEdits.isEmpty { m.additionalEdits = r.additionalEdits }
            return m
        } ?? it
    }

    private func selectionDidChange() {
        guard ranked.indices.contains(selected) else { return }
        let it = currentItem(selected)
        CompletionPopup.shared.setDocumentation(it.documentation)
        let k = key(ranked[selected].item)
        if let r = ranked[selected].item.resolve, resolved[k] == nil, !resolving.contains(k) {
            resolving.insert(k)
            let g = generation
            r { [weak self] new in
                DispatchQueue.main.async {
                    guard let self, g == self.generation else { return }
                    self.resolved[k] = new
                    if self.isOpen, self.ranked.indices.contains(self.selected), self.key(self.ranked[self.selected].item) == k {
                        CompletionPopup.shared.setDocumentation(self.currentItem(self.selected).documentation)
                    }
                }
            }
        }
    }

    private func screenRect(at loc: Int) -> NSRect {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return .zero }
        let len = (textView.string as NSString).length
        let l = max(0, min(loc, len))
        var rect: NSRect
        if l >= len, !lm.extraLineFragmentRect.isEmpty {
            rect = lm.extraLineFragmentRect
        } else if len == 0 {
            rect = NSRect(x: 0, y: 0, width: 0, height: Theme.font.pointSize * 1.3)
        } else {
            let g = lm.glyphIndexForCharacter(at: min(l, len - 1))
            rect = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            let x = lm.location(forGlyphAt: l >= len ? max(0, lm.numberOfGlyphs - 1) : g).x
            var cx = rect.minX + x
            if l >= len { cx += lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc).width }
            rect.origin.x = cx
        }
        rect.origin.x += textView.textContainerOrigin.x
        rect.origin.y += textView.textContainerOrigin.y
        let inWindow = textView.convert(rect, to: nil)
        return textView.window?.convertToScreen(inWindow) ?? inWindow
    }

    // MARK: - Closing

    func close() {
        debounce?.invalidate()
        smartMode = false
        hidePopup()
        generation += 1
        providers.forEach { $0.cancel() }
    }

    private func hidePopup() {
        if isOpen { CompletionPopup.shared.hide() }
        isOpen = false
    }

    // MARK: - Accept

    func acceptSelected() {
        guard isOpen, ranked.indices.contains(selected) else { return }
        let item = currentItem(selected)
        close()
        if item.kind != .text { CompletionHistory.shared.record(item.label.trimmingCharacters(in: CharacterSet(charactersIn: "$@:-")), project: projectKey) }
        insert(item)
    }

    func insert(_ item: CompletionItem) {
        guard let storage = textView.textStorage else { return }
        let ns = textView.string as NSString
        let caret = min(textView.selectedRange().location, ns.length)
        var r = item.replaceRange ?? {
            let s = CompletionLex.runStart(ns, caret, CompletionLex.isIdent)
            return NSRange(location: s, length: caret - s)
        }()
        guard r.location <= caret, r.location >= 0 else { return }
        if r.upperBound < caret { r.length = caret - r.location }
        if r.upperBound > ns.length { r.length = ns.length - r.location }

        var text = item.insertText
        var isSnippet = item.isSnippet
        // the user already typed the parentheses (renaming a call in place): insert the name alone
        if item.insertText.hasPrefix(item.label + "("), r.upperBound < ns.length, ns.character(at: r.upperBound) == 40 { text = item.label; isSnippet = false }
        var stops: [(index: Int, range: NSRange)] = []
        if isSnippet {
            let ls = CompletionLex.lineStart(ns, r.location)
            var ws = ls
            while ws < r.location, ns.character(at: ws) == 32 || ns.character(at: ws) == 9 { ws += 1 }
            let indent = ns.substring(with: NSRange(location: ls, length: ws - ls))
            var raw = item.insertText
            raw = raw.replacingOccurrences(of: "\n", with: "\n" + indent).replacingOccurrences(of: "\t", with: textView.indentUnit)
            let parsed = SnippetParser.parse(raw)
            text = parsed.text
            stops = parsed.stops
        }
        var edits: [(range: NSRange, text: String)] = [(r, text)]
        for e in item.additionalEdits where e.range.upperBound <= ns.length {
            if e.range.upperBound <= r.location || e.range.location >= r.upperBound { edits.append(e) }
        }
        edits.sort { $0.range.location < $1.range.location }
        applying = true
        defer { applying = false }
        guard textView.shouldChangeText(inRanges: edits.map { NSValue(range: $0.range) }, replacementStrings: edits.map { $0.text }) else { return }
        textView.undoManager?.beginUndoGrouping()
        storage.beginEditing()
        for e in edits.reversed() {
            storage.replaceCharacters(in: e.range, with: NSAttributedString(string: e.text, attributes: textView.typingAttributes))
        }
        storage.endEditing()
        textView.didChangeText()
        textView.undoManager?.endUndoGrouping()
        var shift = 0
        for e in edits where e.range.location < r.location { shift += e.text.utf16.count - e.range.length }
        let base = r.location + shift
        let nonFinal = stops.filter { $0.index != 0 }
        if nonFinal.isEmpty {
            let end = base + (stops.last.map { $0.range.location } ?? text.utf16.count)
            textView.setSelectedRange(NSRange(location: end, length: 0))
            session = nil
        } else {
            let shifted = stops.map { (index: $0.index, range: NSRange(location: $0.range.location + base, length: $0.range.length)) }
            session = SnippetSession(stops: shifted, current: 0)
            textView.setSelectedRange(shifted[0].range)
        }
        textView.scrollRangeToVisible(textView.selectedRange())
        lastLength = storage.length
        lastCaret = textView.selectedRange().location
        // items ending in `:` / `.`-like continuations (e.g. tailwind variants) chain into the next popup
        if item.kind == .keyword, item.insertText.hasSuffix(":"), !item.isSnippet {
            DispatchQueue.main.async { [weak self] in self?.applying = false; self?.trigger(manual: true) }
        }
    }

    // MARK: - Snippet tab stops

    private func storageEdited(_ edited: NSRange, delta: Int) {
        guard !applying, var s = session else { return }
        let oldEnd = edited.location + (edited.length - delta)
        var keep: [(index: Int, range: NSRange)] = []
        var newCurrent = s.current
        for (k, stop) in s.stops.enumerated() {
            var r = stop.range
            if k == s.current, edited.location >= r.location, oldEnd <= r.upperBound { r.length += delta }
            else if oldEnd <= r.location { r.location += delta }
            else if edited.location >= r.upperBound { }
            else if edited.location >= r.location, oldEnd <= r.upperBound { r.length += delta }
            else { if k <= s.current { newCurrent -= 1 }; continue }
            keep.append((stop.index, r))
        }
        s.stops = keep
        s.current = max(0, min(newCurrent, keep.count - 1))
        session = keep.isEmpty ? nil : s
    }

    private func goToStop(_ k: Int) {
        guard var s = session, s.stops.indices.contains(k) else { endSession(); return }
        s.current = k
        let stop = s.stops[k]
        applying = true
        textView.setSelectedRange(stop.range)
        applying = false
        lastCaret = textView.selectedRange().location
        textView.scrollRangeToVisible(stop.range)
        session = stop.index == 0 ? nil : s
    }

    private func nextStop() -> Bool {
        guard let s = session else { return false }
        goToStop(min(s.current + 1, s.stops.count - 1))
        return true
    }

    private func previousStop() -> Bool {
        guard let s = session else { return false }
        goToStop(max(0, s.current - 1))
        return true
    }

    func endSession() { session = nil }
}
