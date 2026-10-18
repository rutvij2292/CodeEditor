import AppKit

/// IDE-style status bar under the editor: Git branch on the left; caret, indentation, encoding, language and server on the right.
final class StatusBar: NSView {
    var onGoToLine: (() -> Void)?
    var onChooseIndent: ((NSView) -> Void)?
    var onShowGit: (() -> Void)?

    private let branch = StatusBar.button()
    private let position = StatusBar.button()
    private let indent = StatusBar.button()
    private let lineEnding = StatusBar.label()
    private let encoding = StatusBar.label()
    private let language = StatusBar.label()
    private let server = StatusBar.label()
    private let notice = StatusBar.label()
    private var noticeTimer: Timer?
    private let topLine = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        branch.target = self; branch.action = #selector(branchTapped)
        position.target = self; position.action = #selector(positionTapped)
        indent.target = self; indent.action = #selector(indentTapped)
        let right = NSStackView(views: [server, language, indent, lineEnding, encoding, position])
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
        for l in [lineEnding, encoding, language, server, notice] { l.textColor = Theme.gutter }
        for b in [branch, position, indent] { b.contentTintColor = Theme.gutter; setTitle(b, b.title) }
    }

    private func setTitle(_ b: NSButton, _ text: String) {
        b.attributedTitle = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.gutter])
    }

    func update(line: Int?, column: Int?, selected: Int, indent indentLabel: String?, language languageName: String?,
                lineEnding eol: String?, branch branchName: String?, server serverText: String) {
        setTitle(position, line.map { "\($0):\(column ?? 1)" + (selected > 0 ? " (\(selected) sel)" : "") } ?? "")
        setTitle(indent, indentLabel ?? "")
        encoding.stringValue = line == nil ? "" : "UTF-8"
        lineEnding.stringValue = eol ?? ""
        language.stringValue = languageName ?? ""
        server.stringValue = serverText
        setTitle(branch, branchName ?? "")
    }

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
    @objc private func branchTapped() { onShowGit?() }
}
