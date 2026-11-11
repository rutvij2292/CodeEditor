import AppKit

/// On-demand diff for one file of a log commit (double-click a file in the Log tab). It lives in an editor tab (like the
/// Commit panel's diff), not a separate window: the arrows step through the commit's files.
final class CommitDiffView: NSView {
    private let repo: GitRepo
    private let diffView = SideBySideDiffView()
    private let message = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let counter = NSTextField(labelWithString: "")
    private let prev = NSButton(title: "", target: nil, action: nil)
    private let next = NSButton(title: "", target: nil, action: nil)
    private let reader = DispatchQueue(label: "git.commitdiff", qos: .userInitiated)
    private var commit: GitCommit?
    private var files: [GitFileChange] = []
    private var index = 0
    /// Set when several commits are shown as one combined diff: the revision before the oldest one ("" = empty tree).
    private var rangeBase: String?
    private var rangeLabel = ""
    private var token = 0
    /// Title for the hosting tab, updated on every file change.
    var onTitle: ((String) -> Void)?

    init(repo: GitRepo) {
        self.repo = repo
        super.init(frame: .zero)
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        for (b, name, tip) in [(prev, "chevron.left", "Previous file"), (next, "chevron.right", "Next file")] {
            b.image = NSImage(systemSymbolName: name, accessibilityDescription: tip)
            b.toolTip = tip
            b.isBordered = false
            b.bezelStyle = .texturedRounded
            b.target = self
        }
        prev.action = #selector(stepPrev)
        next.action = #selector(stepNext)
        counter.font = .systemFont(ofSize: 12, weight: .medium)
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        message.font = .systemFont(ofSize: 13)
        message.alignment = .center
        diffView.pickMode = .none
        let bar = NSStackView(views: [prev, counter, next, pathLabel])
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        for v in [bar, diffView, message] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor), bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            diffView.topAnchor.constraint(equalTo: bar.bottomAnchor), diffView.bottomAnchor.constraint(equalTo: bottomAnchor),
            diffView.leadingAnchor.constraint(equalTo: leadingAnchor), diffView.trailingAnchor.constraint(equalTo: trailingAnchor),
            message.centerXAnchor.constraint(equalTo: centerXAnchor), message.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func show(commit: GitCommit, files: [GitFileChange], index: Int, rangeBase: String? = nil, rangeLabel: String = "") {
        self.rangeBase = rangeBase
        self.rangeLabel = rangeLabel
        self.commit = commit
        self.files = files
        self.index = index
        load()
    }

    /// Title for the tab the host shows this view in.
    var tabTitle: String {
        guard let c = commit, index < files.count else { return "Diff" }
        return "\((files[index].path as NSString).lastPathComponent) @ \(rangeBase == nil ? c.shortHash : rangeLabel)"
    }

    @objc private func stepPrev() { step(-1) }
    @objc private func stepNext() { step(1) }
    private func step(_ d: Int) {
        let i = index + d
        guard i >= 0, i < files.count else { return }
        index = i
        load()
    }

    private func load() {
        guard let c = commit, index < files.count else { return }
        let file = files[index]
        let base = rangeBase, label = rangeLabel
        onTitle?(tabTitle)
        counter.stringValue = "\(index + 1)/\(files.count) files"
        pathLabel.stringValue = file.path
        prev.isEnabled = index > 0
        next.isEnabled = index < files.count - 1
        token += 1
        let t = token
        let repo = repo
        reader.async {
            let res = Result { try repo.commitDiffSides(rev: c.hash, file: file, base: base) }
            DispatchQueue.main.async { [weak self] in
                guard let self, t == self.token else { return }
                switch res {
                case .success(let sides):
                    self.message.isHidden = true
                    self.diffView.isHidden = false
                    self.diffView.show(old: sides.old, new: sides.new, oldTitle: base == nil ? "\(c.shortHash)^" : "\(label.components(separatedBy: "..").first ?? "")^", newTitle: c.shortHash,
                                       fileExtension: (file.path as NSString).pathExtension)
                case .failure(let e):
                    self.diffView.isHidden = true
                    self.message.stringValue = e.localizedDescription.hasPrefix("Binary") ? "Binary file: diff not shown" : e.localizedDescription
                    self.message.isHidden = false
                }
            }
        }
    }
}
