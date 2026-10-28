import AppKit

/// On-demand diff window for one file of a log commit (double-click a file in the Log tab). One window is reused:
/// the arrows step through the commit's files, Esc closes it.
private final class EscWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(nil) }
}

final class CommitDiffWindow: NSObject, NSWindowDelegate {
    private let repo: GitRepo
    private let window: NSWindow
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
    private var token = 0

    init(repo: GitRepo) {
        self.repo = repo
        window = EscWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 400)
        window.delegate = self
        window.tabbingMode = .disallowed
        build()
        if !AppEnv.headless { window.setFrameAutosaveName("CommitDiffWindow") }
    }

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
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        message.font = .systemFont(ofSize: 13)
        message.alignment = .center
        diffView.pickMode = .none
        let bar = NSStackView(views: [prev, counter, next, pathLabel])
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        let root = NSView()
        for v in [bar, diffView, message] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor), bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            diffView.topAnchor.constraint(equalTo: bar.bottomAnchor), diffView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            diffView.leadingAnchor.constraint(equalTo: root.leadingAnchor), diffView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            message.centerXAnchor.constraint(equalTo: root.centerXAnchor), message.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        window.contentView = root
    }

    func show(commit: GitCommit, files: [GitFileChange], index: Int, over parent: NSWindow?) {
        self.commit = commit
        self.files = files
        self.index = index
        if !window.isVisible, !AppEnv.headless {
            if !window.setFrameUsingName("CommitDiffWindow"), let p = parent {
                window.setFrameOrigin(NSPoint(x: p.frame.midX - 550, y: p.frame.midY - 360))
            }
        }
        if !AppEnv.headless { window.makeKeyAndOrderFront(nil) }
        load()
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
        window.title = "\(c.shortHash) — \((file.path as NSString).lastPathComponent)"
        counter.stringValue = "\(index + 1)/\(files.count) files"
        pathLabel.stringValue = file.path
        prev.isEnabled = index > 0
        next.isEnabled = index < files.count - 1
        token += 1
        let t = token
        let repo = repo
        reader.async {
            let res = Result { try repo.commitDiffSides(rev: c.hash, file: file) }
            DispatchQueue.main.async { [weak self] in
                guard let self, t == self.token else { return }
                switch res {
                case .success(let sides):
                    self.message.isHidden = true
                    self.diffView.isHidden = false
                    self.diffView.show(old: sides.old, new: sides.new, oldTitle: "\(c.shortHash)^", newTitle: c.shortHash,
                                       fileExtension: (file.path as NSString).pathExtension)
                case .failure(let e):
                    self.diffView.isHidden = true
                    self.message.stringValue = e.localizedDescription.hasPrefix("Binary") ? "Binary file: diff not shown" : e.localizedDescription
                    self.message.isHidden = false
                }
            }
        }
    }

    func windowWillClose(_ notification: Notification) { token += 1 }
}
