import AppKit

/// IDE-style status bar under the editor: Git branch on the left; caret, indentation, encoding, language and server on the right.
final class StatusBar: NSView {
    var onGoToLine: (() -> Void)?
    var onChooseIndent: ((NSView) -> Void)?
    var onShowGit: (() -> Void)?
    var onChooseEncoding: ((NSView) -> Void)?
    var onToggleTerminal: (() -> Void)?
    /// Cycles the Source / Split / Preview viewer mode (shown for Markdown, JSON and YAML files only).
    var onCycleViewer: (() -> Void)?
    private let viewerButton = StatusBar.button()

    private let branch = StatusBar.button()
    private let position = StatusBar.button()
    private let indent = StatusBar.button()
    private let lineEnding = StatusBar.label()
    private let encoding = StatusBar.button()
    private let language = StatusBar.label()
    private let server = StatusBar.label()
    private let notice = StatusBar.label()
    private let powerLabel = StatusBar.label()
    private var noticeTimer: Timer?
    private let topLine = NSView()
    private let terminalButton = NSButton()
    private let terminalDot = NSView()
    private(set) var terminalAttention: TerminalPanelController.Attention = .none

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        branch.target = self; branch.action = #selector(branchTapped)
        position.target = self; position.action = #selector(positionTapped)
        indent.target = self; indent.action = #selector(indentTapped)
        encoding.target = self; encoding.action = #selector(encodingTapped)
        terminalButton.isBordered = false
        terminalButton.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Toggle terminal")
        terminalButton.imageScaling = .scaleProportionallyDown
        terminalButton.toolTip = "Toggle terminal (\u{2325}F12)  \u{2022}  focus terminal/editor (\u{2303}`)"
        terminalButton.target = self; terminalButton.action = #selector(terminalTapped)
        terminalButton.translatesAutoresizingMaskIntoConstraints = false
        terminalButton.widthAnchor.constraint(equalToConstant: 18).isActive = true
        terminalButton.heightAnchor.constraint(equalToConstant: 16).isActive = true
        terminalDot.wantsLayer = true
        terminalDot.layer?.cornerRadius = 3
        terminalDot.isHidden = true
        terminalDot.translatesAutoresizingMaskIntoConstraints = false
        terminalDot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        terminalDot.heightAnchor.constraint(equalToConstant: 6).isActive = true
        let terminalBox = NSStackView(views: [terminalDot, terminalButton])
        terminalBox.spacing = 3
        terminalBox.alignment = .centerY
        powerLabel.stringValue = "\u{1F343} Power saver"
        powerLabel.toolTip = "Power saver is on: longer debounces, inline blame and live git diff paused (Settings > General > Energy)"
        powerLabel.isHidden = !PowerState.shared.saver
        NotificationCenter.default.addObserver(forName: PowerState.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.powerLabel.isHidden = !PowerState.shared.saver
        }
        viewerButton.target = self; viewerButton.action = #selector(viewerTapped)
        viewerButton.toolTip = "View mode: Source / Split / Preview (\u{2303}\u{2325}\u{2318}V)"
        viewerButton.isHidden = true
        let right = NSStackView(views: [powerLabel, server, language, viewerButton, indent, lineEnding, encoding, position, terminalBox])
        right.spacing = 14
        notice.setContentHuggingPriority(.init(1), for: .horizontal)
        notice.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        notice.alignment = .center
        let row = NSStackView(views: [branch, notice, right])
        row.distribution = .fill
        row.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 12)
        row.translatesAutoresizingMaskIntoConstraints = false
        topLine.wantsLayer = true
        topLine.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row); addSubview(topLine)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            topLine.leadingAnchor.constraint(equalTo: leadingAnchor), topLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            topLine.topAnchor.constraint(equalTo: topAnchor), topLine.heightAnchor.constraint(equalToConstant: 1),
            heightAnchor.constraint(equalToConstant: 22),
        ])
        restyle()
        NotificationCenter.default.addObserver(self, selector: #selector(restyle), name: Theme.didChange, object: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func label() -> NSTextField {
        let l = NSTextField(labelWithString: "")
        l.font = .systemFont(ofSize: 11)
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }

    private static func button() -> NSButton {
        let b = NSButton(title: "", target: nil, action: nil)
        b.isBordered = false
        b.font = .systemFont(ofSize: 11)
        return b
    }

    @objc private func restyle() {
        layer?.backgroundColor = Theme.background.blended(withFraction: Theme.isDark ? 0.05 : 0.025, of: Theme.foreground)?.cgColor
        topLine.layer?.backgroundColor = Theme.foreground.withAlphaComponent(0.12).cgColor
        for l in [lineEnding, language, server, notice] { l.textColor = Theme.gutter }
        for b in [branch, position, indent, encoding, viewerButton] { b.contentTintColor = Theme.gutter; setTitle(b, b.title) }
        terminalButton.contentTintColor = Theme.gutter
        setTerminal(attention: terminalAttention)
    }

    private func setTitle(_ b: NSButton, _ text: String) {
        b.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.gutter])
    }

    func update(line: Int?, column: Int?, selected: Int, indent indentLabel: String?, language languageName: String?,
                lineEnding eol: String?, branch branchName: String?, server serverText: String, encoding encodingName: String? = nil) {
        setTitle(position, line.map { "\($0):\(column ?? 1)" + (selected > 0 ? " (\(selected) sel)" : "") } ?? "")
        setTitle(indent, indentLabel ?? "")
        setTitle(encoding, line == nil ? "" : (encodingName ?? "UTF-8"))
        lineEnding.stringValue = eol ?? ""
        language.stringValue = languageName ?? ""
        server.stringValue = serverText
        setTitle(branch, branchName ?? "")
    }

    func setViewer(visible: Bool, text: String) {
        viewerButton.isHidden = !visible
        setTitle(viewerButton, visible ? "\u{25A7} " + text : "")
    }
    var viewerText: String { viewerButton.isHidden ? "" : viewerButton.attributedTitle.string }
    @objc private func viewerTapped() { onCycleViewer?() }

    /// Terminal toggle state: orange dot = background output, green = an agent finished.
    func setTerminal(attention: TerminalPanelController.Attention) {
        terminalAttention = attention
        terminalDot.isHidden = attention == .none
        terminalDot.layer?.backgroundColor = (attention == .done ? NSColor.systemGreen : NSColor.systemOrange).cgColor
    }
    var terminalDotVisible: Bool { !terminalDot.isHidden }
    func clickTerminalButton() { terminalTapped() }

    var encodingText: String { encoding.attributedTitle.string }
    var branchText: String { branch.attributedTitle.string }
    var noticeText: String { notice.stringValue }

    /// "⎇ main ↑1 ↓2 · 3 changes" (arrows only when non-zero; "·" part only when there are changes).
    static func gitSummary(branch: String?, ahead: Int, behind: Int, changes: Int) -> String {
        guard var text = branch.map({ "⎇ " + $0 }) else { return "" }
        if ahead > 0 { text += " ↑\(ahead)" }
        if behind > 0 { text += " ↓\(behind)" }
        if changes > 0 { text += " · \(changes) change\(changes == 1 ? "" : "s")" }
        return text
    }

    /// Short message in the middle of the bar (e.g. "Closed deleted file x.php"); clears itself.
    func flash(_ text: String, seconds: TimeInterval = 5) {
        notice.stringValue = text
        noticeTimer?.invalidate()
        noticeTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.notice.stringValue = "" }
    }

    @objc private func positionTapped() { onGoToLine?() }
    @objc private func indentTapped() { onChooseIndent?(indent) }
    @objc private func encodingTapped() { onChooseEncoding?(encoding) }
    @objc private func terminalTapped() { onToggleTerminal?() }
    @objc private func branchTapped() { onShowGit?() }
}
