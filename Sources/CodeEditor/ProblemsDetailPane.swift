import AppKit

/// Right-hand pane of the Problems panel: the selected problem, its code snippet, and (on request) Claude's evaluation.
final class ProblemsDetailPane: NSView {
    enum State { case idle, evaluating, failed(String) }

    var onEvaluate: (() -> Void)?
    var onApply: (() -> Void)?
    var onHandOff: (() -> Void)?

    private let placeholder = NSTextField(labelWithString: "Select a problem to see details")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let explanationLabel = NSTextField(wrappingLabelWithString: "")
    private let fixLabel = NSTextField(wrappingLabelWithString: "")
    private let evaluateButton = NSButton(title: "Evaluate with Claude", target: nil, action: nil)
    private let applyButton = NSButton(title: "Apply fix", target: nil, action: nil)
    private let handOffButton = NSButton(title: "Hand to agent", target: nil, action: nil)
    private let separator = NSView()
    private var hasProblem = false
    private var failed = false
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for l in [messageLabel, snippetLabel, statusLabel, explanationLabel, fixLabel] {
            l.isSelectable = true
            l.maximumNumberOfLines = 0
            l.lineBreakMode = .byWordWrapping
        }
        messageLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        metaLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        metaLabel.lineBreakMode = .byTruncatingMiddle
        snippetLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        explanationLabel.font = .systemFont(ofSize: 12)
        fixLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        placeholder.font = .systemFont(ofSize: 12)
        placeholder.alignment = .center
        for (b, sel) in [(evaluateButton, #selector(evaluateTapped)), (applyButton, #selector(applyTapped)), (handOffButton, #selector(handOffTapped))] {
            b.target = self
            b.action = sel
            b.bezelStyle = .rounded
            b.controlSize = .small
        }
        applyButton.keyEquivalent = ""
        for v in [placeholder, messageLabel, metaLabel, snippetLabel, separator, statusLabel, explanationLabel, fixLabel, evaluateButton, applyButton, handOffButton] as [NSView] { addSubview(v) }
        separator.wantsLayer = true
        applyTheme()
        show(problem: nil, path: "", answer: nil, state: .idle, snippet: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Test support

    var messageText: String { messageLabel.stringValue }
    var explanationText: String { explanationLabel.stringValue }
    var statusLineText: String { statusLabel.stringValue }
    var applyVisible: Bool { !applyButton.isHidden }
    var handOffVisible: Bool { !handOffButton.isHidden }
    var evaluateVisible: Bool { !evaluateButton.isHidden }
    func performApply() { onApply?() }
    func performHandOff() { onHandOff?() }
    func performEvaluate() { onEvaluate?() }

    @objc private func evaluateTapped() { onEvaluate?() }
    @objc private func applyTapped() { onApply?() }
    @objc private func handOffTapped() { onHandOff?() }

    // MARK: Content

    static func verdictText(_ v: ProblemAnswer.Verdict) -> String {
        switch v { case .real: return "Real problem"; case .falsePositive: return "Likely a false positive"; case .ignorable: return "Safe to ignore" }
    }
    static func difficultyText(_ d: ProblemAnswer.Difficulty) -> String {
        switch d { case .easy: return "easy to fix"; case .moderate: return "moderate to fix"; case .hard: return "hard to fix" }
    }

    func show(problem: (url: URL, d: FileProblems.Diagnostic)?, path: String, answer: ProblemAnswer?, state: State, snippet: String?) {
        hasProblem = problem != nil
        placeholder.isHidden = hasProblem
        for v in [messageLabel, metaLabel, snippetLabel, separator, statusLabel, explanationLabel, fixLabel, evaluateButton, applyButton, handOffButton] as [NSView] { v.isHidden = !hasProblem }
        failed = false
        guard let problem else { needsLayout = true; return }
        let d = problem.d
        messageLabel.stringValue = d.message.replacingOccurrences(of: "\n", with: " ")
        var meta = "\(path):\(d.line):\(d.column)"
        if let s = d.source, !s.isEmpty { meta += "  \(s)" + (d.code.map { " (\($0))" } ?? "") }
        metaLabel.stringValue = meta
        snippetLabel.stringValue = snippet ?? ""
        snippetLabel.isHidden = snippet == nil
        statusLabel.stringValue = ""
        explanationLabel.stringValue = ""
        fixLabel.stringValue = ""
        evaluateButton.title = "Evaluate with Claude"
        statusLabel.textColor = Theme.foreground
        if let a = answer {
            statusLabel.stringValue = Self.verdictText(a.verdict) + " · " + Self.difficultyText(a.difficulty)
            explanationLabel.stringValue = a.explanation
            let canApply = a.difficulty == .easy && a.oldText != nil && a.newText != nil
            if canApply, let o = a.oldText, let n = a.newText { fixLabel.stringValue = "Replace:\n\(o)\n\nWith:\n\(n.isEmpty ? "(delete)" : n)" }
            evaluateButton.isHidden = true
            applyButton.isHidden = !canApply
            handOffButton.isHidden = canApply
        } else {
            applyButton.isHidden = true
            handOffButton.isHidden = true
            switch state {
            case .idle: break
            case .evaluating:
                statusLabel.stringValue = "Asking Claude…"
                evaluateButton.isHidden = true
            case .failed(let msg):
                failed = true
                statusLabel.stringValue = msg
                statusLabel.textColor = .systemRed
                evaluateButton.title = "Try again"
            }
        }
        needsLayout = true
    }

    // MARK: Layout and theme

    func applyTheme() {
        appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        layer?.backgroundColor = Theme.background.cgColor
        separator.layer?.backgroundColor = (Theme.isDark ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.10)).cgColor
        let dim = Theme.isDark ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.40, alpha: 1)
        for l in [messageLabel, snippetLabel, explanationLabel, fixLabel] { l.textColor = Theme.foreground }
        statusLabel.textColor = Theme.foreground
        metaLabel.textColor = dim
        placeholder.textColor = Theme.gutter
    }

    private func height(of label: NSTextField, width: CGFloat) -> CGFloat {
        guard !label.stringValue.isEmpty else { return 0 }
        let r = (label.attributedStringValue).boundingRect(with: NSSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(r.height) + 2
    }

    override func layout() {
        super.layout()
        let w = bounds.width, pad: CGFloat = 12, inner = max(40, w - pad * 2)
        placeholder.frame = NSRect(x: 0, y: bounds.height / 2 - 10, width: w, height: 20)
        guard hasProblem else { return }
        var y: CGFloat = 10
        func place(_ l: NSTextField, gap: CGFloat = 6) {
            let h = height(of: l, width: inner)
            l.frame = NSRect(x: pad, y: y, width: inner, height: h)
            if h > 0 { y += h + gap }
        }
        place(messageLabel)
        metaLabel.frame = NSRect(x: pad, y: y, width: inner, height: 15); y += 21
        if !snippetLabel.isHidden { place(snippetLabel, gap: 10) }
        separator.frame = NSRect(x: pad, y: y, width: inner, height: 1); y += 11
        place(statusLabel)
        place(explanationLabel, gap: 8)
        place(fixLabel, gap: 10)
        var x = pad
        for b in [evaluateButton, applyButton, handOffButton] where !b.isHidden {
            b.sizeToFit()
            b.frame = NSRect(x: x, y: y, width: b.frame.width + 8, height: 22)
            x += b.frame.width + 8
        }
    }
}
