import AppKit

// Floating prompt composer for the active Claude agent terminal tab (Cmd-Shift-Return). A multi-line box with `@file` and
// `/command` completion, Up / Down history on an empty box, image paste (saved to a temp file, path inserted), Cmd-Return to send
// and Esc to close keeping the draft. Created on open, released on close; no timers, no background work while idle.

struct ClaudeComposerHost {
    var root: URL
    /// Fuzzy file search (project-relative paths, best first); an empty query lists open files.
    var searchFiles: (String) -> [String]
    var slashEntries: () -> [SlashEntry]
    /// Sends the prompt (bracketed paste + Return) to the Claude tab. False when there is no agent tab.
    var send: (String) -> Bool
    /// Starts Claude Code in a new terminal tab and sends the prompt once it has had time to boot.
    var startAgentAndSend: (String) -> Void
}

private final class ComposerPanel: NSPanel {
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

private final class ComposerTextView: NSTextView {
    var onKey: ((NSEvent) -> Bool)?
    var onPasteImage: ((NSImage) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if pb.string(forType: .string) == nil, let img = NSImage(pasteboard: pb), onPasteImage?(img) == true { return }
        super.paste(sender)
    }
}

private final class ComposerContent: NSView {
    var onLayout: (() -> Void)?
    override func layout() { super.layout(); onLayout?() }
}

final class ClaudeComposer: NSObject, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var current: ClaudeComposer?
    static var isOpen: Bool { current != nil }
    static var shared: ClaudeComposer? { current }
    static let maxSuggestions = 8
    static func dismiss() { current?.close(refocus: true) }

    /// Opens the composer over `window`. `prefill` is appended to an existing draft (after a blank line).
    @discardableResult
    static func present(over window: NSWindow, host: ClaudeComposerHost, prefill: String?) -> ClaudeComposer {
        if let c = current, !c.closed, c.parent === window {
            c.append(prefill)
            c.panel.makeFirstResponder(c.text)
            return c
        }
        dismiss()
        let c = ClaudeComposer(parent: window, host: host)
        current = c
        c.show(prefill: prefill)
        return c
    }

    static func snapshot(to path: String) {
        guard let v = current?.panel.contentView else { return }
        Verification.render(v, to: path)
    }

    private weak var parent: NSWindow?
    private let host: ClaudeComposerHost
    private let panel: ComposerPanel
    private let content = ComposerContent()
    private let scroll = NSScrollView()
    private let text = ComposerTextView()
    private let listScroll = NSScrollView()
    private let table = NSTableView()
    private let hint = NSTextField(labelWithString: "")
    private let sendButton = NSButton(title: "Send  ⌘↩", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Close", target: nil, action: nil)
    private var closed = false
    private var history = HistoryCursor()
    private var slashCache: [SlashEntry]?
    private(set) var token: ComposerToken?
    private(set) var suggestions: [(insert: String, title: String, detail: String)] = []
    private var tokenToken = 0
    private var editing = false

    private init(parent: NSWindow, host: ClaudeComposerHost) {
        self.parent = parent
        self.host = host
        panel = ComposerPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 300),
                              styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: true)
        super.init()
        panel.title = "Claude Prompt"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 420, height: 220)
        panel.onEscape = { [weak self] in self?.escape() }
        DialogMemory.remember(panel, as: "ClaudeComposer")
        build()
    }

    // MARK: build

    private func build() {
        panel.contentView = content
        text.isRichText = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.allowsUndo = true
        text.font = .systemFont(ofSize: 14)
        text.textContainerInset = NSSize(width: 6, height: 6)
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.delegate = self
        text.onKey = { [weak self] in self?.handleKey($0) ?? false }
        text.onPasteImage = { [weak self] in self?.pasteImage($0) ?? false }
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("s"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        listScroll.documentView = table
        listScroll.hasVerticalScroller = true
        listScroll.autohidesScrollers = true
        listScroll.isHidden = true

        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.stringValue = "@ file   / command   ↑↓ history   ⌘V image   Esc keeps draft"
        hint.lineBreakMode = .byTruncatingTail
        sendButton.bezelStyle = .rounded
        sendButton.target = self; sendButton.action = #selector(sendClicked)
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self; cancelButton.action = #selector(closeClicked)
        for v in [scroll, listScroll, hint, sendButton, cancelButton] as [NSView] { content.addSubview(v) }
        content.onLayout = { [weak self] in self?.layoutAll() }
        applyTheme()
    }

    private func applyTheme() {
        text.backgroundColor = Theme.background
        text.textColor = Theme.foreground
        text.insertionPointColor = Theme.foreground
        table.backgroundColor = Theme.background
        scroll.backgroundColor = Theme.background
    }

    private func layoutAll() {
        let w = content.bounds.width, h = content.bounds.height
        let bar: CGFloat = 40
        let listH: CGFloat = listScroll.isHidden ? 0 : CGFloat(min(suggestions.count, Self.maxSuggestions)) * 24 + 6
        sendButton.sizeToFit(); cancelButton.sizeToFit()
        let sw = sendButton.frame.width + 10, cw = cancelButton.frame.width + 10
        sendButton.frame = NSRect(x: w - sw - 10, y: 8, width: sw, height: 24)
        cancelButton.frame = NSRect(x: sendButton.frame.minX - cw - 6, y: 8, width: cw, height: 24)
        hint.frame = NSRect(x: 10, y: 12, width: max(0, cancelButton.frame.minX - 18), height: 16)
        listScroll.frame = NSRect(x: 0, y: bar, width: w, height: listH)
        scroll.frame = NSRect(x: 0, y: bar + listH, width: w, height: max(0, h - bar - listH))
    }

    // MARK: show / close

    private func show(prefill: String?) {
        guard let parent else { return }
        text.string = PromptHistory.draft
        append(prefill)
        text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
        let pf = parent.frame
        panel.setFrameOrigin(NSPoint(x: pf.midX - panel.frame.width / 2, y: pf.maxY - panel.frame.height - 90))
        parent.addChildWindow(panel, ordered: .above)
        if !AppEnv.headless { panel.makeKeyAndOrderFront(nil) }
        panel.makeFirstResponder(text)
        content.needsLayout = true
        refreshSuggestions()
    }

    private func append(_ prefill: String?) {
        guard let prefill, !prefill.isEmpty else { return }
        let cur = text.string
        if cur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text.string = prefill }
        else { text.string = cur + (cur.hasSuffix("\n") ? "\n" : "\n\n") + prefill }
        text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0))
        text.scrollRangeToVisible(text.selectedRange())
    }

    private func close(refocus: Bool) {
        guard !closed else { return }
        closed = true
        PromptHistory.draft = text.string
        if Self.current === self { Self.current = nil }
        let parent = self.parent
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if (refocus || parent?.isKeyWindow == false), !AppEnv.headless { parent?.makeKey() }
        text.delegate = nil; table.dataSource = nil; table.delegate = nil
        text.onKey = nil; text.onPasteImage = nil; content.onLayout = nil
        text.string = ""
        suggestions = []; slashCache = nil
        table.reloadData()
    }

    @objc private func closeClicked() { close(refocus: true) }
    @objc private func sendClicked() { send() }
    @objc private func rowClicked() { if table.clickedRow >= 0 { table.selectRowIndexes([table.clickedRow], byExtendingSelection: false); acceptSuggestion() } }

    /// Esc: closes the suggestion list first, then the popup (the draft is kept).
    func escape() {
        if !suggestions.isEmpty { hideSuggestions(); return }
        close(refocus: true)
    }

    // MARK: send

    var string: String { text.string }
    func setString(_ s: String) { text.string = s; text.setSelectedRange(NSRange(location: (s as NSString).length, length: 0)); refreshSuggestions() }

    /// Cmd-Return. An empty prompt does nothing; no agent tab -> offers to start one.
    func send() {
        let prompt = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        if host.send(prompt) { sent(prompt) } else { askToStart(prompt) }
    }

    private func sent(_ prompt: String) {
        PromptHistory.push(prompt)
        text.string = ""
        PromptHistory.draft = ""
        close(refocus: false)
    }

    private func askToStart(_ prompt: String) {
        let alert = NSAlert()
        alert.messageText = "No Claude Code tab is running"
        alert.informativeText = "Start Claude Code in a new terminal tab and send this prompt to it?"
        alert.addButton(withTitle: "Start and Send")
        alert.addButton(withTitle: "Cancel")
        guard !AppEnv.headless else { return }
        alert.beginSheetModal(for: panel) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self else { return }
            self.startAndSend(prompt)
        }
    }

    func startAndSend(_ prompt: String) {
        host.startAgentAndSend(prompt)
        sent(prompt)
    }

    // MARK: keys

    /// Returns true when the event was consumed.
    func handleKey(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        let code = e.keyCode
        let isReturn = code == 36 || code == 76
        if isReturn, mods == .command { send(); return true }
        if code == 53, mods.isEmpty { escape(); return true }
        if !suggestions.isEmpty, mods.isEmpty {
            switch code {
            case 125: moveSelection(1); return true
            case 126: moveSelection(-1); return true
            case 48, 36, 76: acceptSuggestion(); return true      // Tab / Return
            default: break
            }
        }
        if mods.isEmpty, code == 126 || code == 125, historyApplies() { return stepHistory(older: code == 126) }
        return false
    }

    /// Up / Down is history only while the box is empty or shows a history entry the user has not edited.
    private func historyApplies() -> Bool {
        text.string.isEmpty || history.browsing
    }

    @discardableResult
    func stepHistory(older: Bool) -> Bool {
        guard let next = history.step(older: older, entries: PromptHistory.entries) else { return history.browsing || text.string.isEmpty }
        editing = true
        text.string = next
        text.setSelectedRange(NSRange(location: (next as NSString).length, length: 0))
        editing = false
        return true
    }

    // MARK: suggestions

    func textDidChange(_ notification: Notification) {
        if !editing, history.browsing { history.reset() }
        refreshSuggestions()
    }

    func textViewDidChangeSelection(_ notification: Notification) { if !editing { refreshSuggestions() } }

    private func refreshSuggestions() {
        let tok = ClaudeComposerLogic.token(in: text.string as NSString, caret: text.selectedRange().location)
        token = tok
        switch tok {
        case .file(let q, _):
            suggestions = host.searchFiles(q).prefix(Self.maxSuggestions).map { path in
                let name = (path as NSString).lastPathComponent
                let dir = (path as NSString).deletingLastPathComponent
                return (TerminalBridge.mention(path), name, dir)
            }
        case .slash(let q, _):
            if slashCache == nil { slashCache = host.slashEntries() }
            suggestions = ClaudeComposerLogic.filter(slashCache ?? [], query: q, limit: Self.maxSuggestions).map { e in
                ("/" + e.name, "/" + e.name, (e.isSkill ? "skill" : "command") + (e.isProject ? " · project" : "") + (e.detail.isEmpty ? "" : " · " + e.detail))
            }
        case nil:
            suggestions = []
        }
        listScroll.isHidden = suggestions.isEmpty
        table.reloadData()
        if !suggestions.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
        content.needsLayout = true
    }

    private func hideSuggestions() {
        suggestions = []
        listScroll.isHidden = true
        table.reloadData()
        content.needsLayout = true
    }

    func moveSelection(_ delta: Int) {
        guard !suggestions.isEmpty else { return }
        let row = max(0, min(suggestions.count - 1, table.selectedRow + delta))
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func acceptSuggestion() {
        guard let token, suggestions.indices.contains(table.selectedRow) else { return }
        let r = ClaudeComposerLogic.apply(suggestions[table.selectedRow].insert, to: text.string, token: token)
        editing = true
        text.string = r.text
        text.setSelectedRange(NSRange(location: r.caret, length: 0))
        editing = false
        hideSuggestions()
        self.token = nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int { suggestions.count }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard suggestions.indices.contains(row) else { return nil }
        let s = suggestions[row]
        let a = NSMutableAttributedString(string: s.title, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: Theme.foreground])
        if !s.detail.isEmpty {
            a.append(NSAttributedString(string: "   " + s.detail, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.gutter]))
        }
        return a
    }

    // MARK: image paste

    @discardableResult
    func pasteImage(_ image: NSImage) -> Bool {
        guard let png = ClaudeComposerLogic.pngData(from: image), let url = ClaudeComposerLogic.saveImage(png) else { return false }
        text.insertText(TerminalBridge.mention(url.path) + " ", replacementRange: text.selectedRange())
        return true
    }

    // MARK: test support

    var testSelectedRow: Int { table.selectedRow }
    var testSuggestionTitles: [String] { suggestions.map(\.title) }
    var testListVisible: Bool { !listScroll.isHidden }
    var testPanelVisible: Bool { !closed }
    func testCaretToEnd() { text.setSelectedRange(NSRange(location: (text.string as NSString).length, length: 0)) }
}
