import AppKit

/// "Ask Claude about this selection": a small floating chat about the selected code, answered by the user's own Claude Code CLI
/// (`claude -p`, subscription login, no API key; see ClaudeCLI). Each question is one short-lived process; follow-ups re-send the
/// transcript, so nothing stays resident and no session files are written. "Continue in terminal" hands the same context to the
/// interactive Claude Code tab for anything that needs tools or file access.
final class ClaudeAskPanel: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    struct Context {
        let path: String
        let startLine: Int
        let endLine: Int
        let code: String
    }

    private static var current: ClaudeAskPanel?
    private static let maxCode = 40_000
    private static let modelKey = "askClaudeModel"
    private static let models: [(title: String, id: String)] = [("Haiku · fast", "haiku"), ("Sonnet", "sonnet"), ("Opus · deepest", "opus")]

    static func present(over window: NSWindow, context: Context, cwd: URL?, continueInTerminal: @escaping (String) -> Void) {
        current?.close()
        let p = ClaudeAskPanel(parent: window, context: context, cwd: cwd, continueInTerminal: continueInTerminal)
        current = p
        p.show()
    }

    static func dismiss() { current?.close() }

    private weak var parent: NSWindow?
    private let context: Context
    private let cwd: URL?
    private let continueInTerminal: (String) -> Void
    private let panel: NSPanel
    private let transcript = MarkdownPreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 380))
    private let field = NSTextField()
    private let sendButton = NSButton(title: "Ask", target: nil, action: nil)
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let terminalButton = NSButton(title: "Continue in Terminal", target: nil, action: nil)
    private var turns: [ClaudeCLI.Turn] = []
    private var process: Process?
    private var busy = false
    private var closed = false

    private init(parent: NSWindow, context: Context, cwd: URL?, continueInTerminal: @escaping (String) -> Void) {
        self.parent = parent
        self.context = context
        self.cwd = cwd
        self.continueInTerminal = continueInTerminal
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 500),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: true)
        super.init()
        panel.title = "Ask Claude · \(context.path):\(context.startLine)–\(context.endLine)"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.minSize = NSSize(width: 420, height: 320)
        build()
        showIntro()
    }

    private func build() {
        let content = NSView()
        panel.contentView = content
        transcript.translatesAutoresizingMaskIntoConstraints = false

        field.placeholderString = "Ask about this code…  (Return to send, Esc to close)"
        field.font = .systemFont(ofSize: 14)
        field.delegate = self
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true

        modelPopup.addItems(withTitles: Self.models.map(\.title))
        let saved = UserDefaults.standard.string(forKey: Self.modelKey) ?? "sonnet"
        modelPopup.selectItem(at: Self.models.firstIndex { $0.id == saved } ?? 1)
        modelPopup.controlSize = .small
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        modelPopup.toolTip = "Model used for the next question"

        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = ""
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        terminalButton.bezelStyle = .rounded
        terminalButton.controlSize = .small
        terminalButton.target = self
        terminalButton.action = #selector(terminalTapped)
        terminalButton.toolTip = "Paste this selection and your last question into the Claude Code terminal tab (tools, file access, full session)"
        let copyButton = NSButton(title: "Copy Answer", target: self, action: #selector(copyTapped))
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .small

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let inputRow = NSStackView(views: [field, sendButton])
        inputRow.spacing = 8
        let toolRow = NSStackView(views: [modelPopup, spacer, copyButton, terminalButton])
        toolRow.spacing = 8
        let bottom = NSStackView(views: [inputRow, toolRow])
        bottom.orientation = .vertical
        bottom.alignment = .leading
        bottom.spacing = 6
        bottom.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(transcript)
        content.addSubview(bottom)
        NSLayoutConstraint.activate([
            transcript.topAnchor.constraint(equalTo: content.topAnchor),
            transcript.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            transcript.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            transcript.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -8),
            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            inputRow.widthAnchor.constraint(equalTo: bottom.widthAnchor),
            toolRow.widthAnchor.constraint(equalTo: bottom.widthAnchor),
        ])
    }

    private func show() {
        guard let parent else { return }
        let pf = parent.frame
        var f = panel.frame
        f.origin = NSPoint(x: pf.midX - f.width / 2, y: pf.maxY - f.height - 90)
        panel.setFrame(f, display: false)
        parent.addChildWindow(panel, ordered: .above)
        if !AppEnv.headless { panel.makeKeyAndOrderFront(nil) }
        panel.makeFirstResponder(field)
    }

    private func close() {
        guard !closed else { return }
        closed = true
        if process?.isRunning == true { process?.terminate() }
        process = nil
        if Self.current === self { Self.current = nil }
        let parent = self.parent
        parent?.removeChildWindow(panel)
        panel.delegate = nil
        panel.orderOut(nil)
        if !AppEnv.headless { parent?.makeKey() }
    }

    func windowWillClose(_ notification: Notification) { close() }

    // MARK: transcript

    private func showIntro() {
        var lines = context.code.components(separatedBy: "\n")
        let more = lines.count > 12 ? lines.count - 12 : 0
        lines = Array(lines.prefix(12))
        var md = "**Selected code** — `\(context.path)` lines \(context.startLine)–\(context.endLine)\n\n```\(Self.fenceLanguage(context.path))\n\(lines.joined(separator: "\n"))\n```\n"
        if more > 0 { md += "\n_…and \(more) more lines are sent with your question._\n" }
        md += "\nAsk anything about it below. Answers come from your Claude Code login — no API key is used."
        render(md)
    }

    private func renderTurns(pending: Bool) {
        var md = ""
        for t in turns {
            md += "**You:** \(t.question)\n\n"
            if let a = t.answer { md += a + "\n\n---\n\n" }
        }
        if pending { md += "_Claude is thinking…_\n" }
        render(md)
    }

    private func render(_ md: String) {
        transcript.show(blocks: MarkdownParser.parse(md))
        if !turns.isEmpty { transcript.textView.scrollToEndOfDocument(nil) }
    }

    private static func fenceLanguage(_ path: String) -> String { URL(fileURLWithPath: path).pathExtension }

    // MARK: actions

    @objc private func modelChanged() {
        UserDefaults.standard.set(Self.models[max(0, modelPopup.indexOfSelectedItem)].id, forKey: Self.modelKey)
    }

    @objc private func sendTapped() {
        if busy { stop(); return }
        let q = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        field.stringValue = ""
        ask(q)
    }

    private func stop() {
        if process?.isRunning == true { process?.terminate() }
    }

    private func ask(_ question: String) {
        turns.append(.init(question: question, answer: nil))
        setBusy(true)
        renderTurns(pending: true)
        var code = context.code
        if code.count > Self.maxCode { code = String(code.prefix(Self.maxCode)) + "\n[selection truncated]" }
        let prompt = ClaudeCLI.chatPrompt(path: context.path, startLine: context.startLine, endLine: context.endLine, code: code, turns: turns)
        let model = Self.models[max(0, modelPopup.indexOfSelectedItem)].id
        process = ClaudeCLI.run(prompt: prompt, model: model, system: "You are answering inside a code editor's side panel. Be direct and brief.",
                                cwd: cwd, completion: { [weak self] result in
            guard let self, !self.closed else { return }
            self.process = nil
            self.setBusy(false)
            switch result {
            case .success(let text): self.turns[self.turns.count - 1].answer = text
            case .failure(let f):
                self.turns[self.turns.count - 1].answer = f.message == "Cancelled" ? "_Stopped._" : "⚠️ \(f.message)"
            }
            self.renderTurns(pending: false)
            self.panel.makeFirstResponder(self.field)
        })
        if process == nil { setBusy(false) }
    }

    private func setBusy(_ on: Bool) {
        busy = on
        sendButton.title = on ? "Stop" : "Ask"
        field.isEnabled = !on
    }

    @objc private func copyTapped() {
        guard let answer = turns.last(where: { $0.answer != nil })?.answer else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
    }

    @objc private func terminalTapped() {
        let question = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (turns.last?.question ?? "") : field.stringValue
        let block = TerminalBridge.fencedBlock(path: context.path, start: context.startLine, end: context.endLine, text: context.code)
        continueInTerminal(question.isEmpty ? block : block + "\n" + question)
        close()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { sendTapped(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { close(); return true }
        return false
    }
}
