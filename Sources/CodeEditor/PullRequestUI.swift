import AppKit

// UI of "Resolve Pull Request Conflicts…": a small prompt sheet and the resolver window that embeds the 3-way MergeView.

// MARK: small building blocks

enum PRUI {
    static var green: NSColor { Theme.isDark ? NSColor(srgbRed: 0.40, green: 0.78, blue: 0.47, alpha: 1) : NSColor(srgbRed: 0.13, green: 0.55, blue: 0.25, alpha: 1) }
    static var orange: NSColor { Theme.isDark ? NSColor(srgbRed: 0.95, green: 0.66, blue: 0.30, alpha: 1) : NSColor(srgbRed: 0.80, green: 0.45, blue: 0.05, alpha: 1) }
    static var red: NSColor { Theme.isDark ? NSColor(srgbRed: 0.97, green: 0.46, blue: 0.44, alpha: 1) : NSColor(srgbRed: 0.78, green: 0.17, blue: 0.17, alpha: 1) }
    static var blue: NSColor { Theme.isDark ? NSColor(srgbRed: 0.45, green: 0.68, blue: 0.98, alpha: 1) : NSColor(srgbRed: 0.10, green: 0.40, blue: 0.85, alpha: 1) }
    static var card: NSColor { Theme.isDark ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 0, alpha: 0.035) }

    static func label(_ s: String, _ size: CGFloat = 12, _ weight: NSFont.Weight = .regular, _ color: NSColor? = nil) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color ?? Theme.foreground
        l.lineBreakMode = .byTruncatingTail
        return l
    }
    static func wrapping(_ s: String, _ size: CGFloat = 12, _ color: NSColor? = nil) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: size)
        l.textColor = color ?? DiffColors.secondary
        l.isSelectable = false
        return l
    }
    static func button(_ title: String, _ target: AnyObject, _ action: Selector, primary: Bool = false) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .large
        if primary { b.keyEquivalent = "\r" }
        return b
    }
    static func symbol(_ name: String, _ size: CGFloat, _ color: NSColor) -> NSImageView {
        let v = NSImageView()
        v.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold))
        v.contentTintColor = color
        v.setContentHuggingPriority(.required, for: .horizontal)
        return v
    }
    static func stack(_ views: [NSView], _ axis: NSUserInterfaceLayoutOrientation, spacing: CGFloat, alignment: NSLayoutConstraint.Attribute? = nil) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = axis
        s.spacing = spacing
        if let a = alignment { s.alignment = a }
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }
    static func pin(_ v: NSView, in host: NSView, insets: NSEdgeInsets = NSEdgeInsets()) {
        v.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: host.topAnchor, constant: insets.top), v.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -insets.bottom),
            v.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: insets.left), v.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -insets.right),
        ])
    }
}

/// Rounded status pill ("Conflicted", branch names…).
final class PRChip: NSView {
    private let text: String
    private let tint: () -> NSColor
    private let mono: Bool
    private let symbolName: String?
    init(_ text: String, mono: Bool = false, symbol: String? = nil, tint: @escaping () -> NSColor) {
        self.text = text; self.tint = tint; self.mono = mono; self.symbolName = symbol
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
    private var attrs: [NSAttributedString.Key: Any] {
        [.font: mono ? NSFont.monospacedSystemFont(ofSize: 11, weight: .medium) : NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: tint()]
    }
    private var iconWidth: CGFloat { symbolName == nil ? 0 : 14 }
    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil((text as NSString).size(withAttributes: attrs).width) + 18 + iconWidth, height: 20)
    }
    override func draw(_ dirtyRect: NSRect) {
        let c = tint()
        c.withAlphaComponent(Theme.isDark ? 0.20 : 0.13).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        var x: CGFloat = 9
        if let n = symbolName, let img = NSImage(systemSymbolName: n, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)) {
            let tinted = NSImage(size: img.size, flipped: false) { r in img.draw(in: r); c.set(); r.fill(using: .sourceAtop); return true }
            tinted.draw(at: NSPoint(x: 8, y: (bounds.height - img.size.height) / 2), from: .zero, operation: .sourceOver, fraction: 1)
            x += iconWidth - 1
        }
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}

// MARK: prompt

final class PRPromptController: NSObject, NSTextFieldDelegate {
    enum Tone { case info, error, success }

    let view = DiffFillView { Theme.background }
    var onSubmit: ((PRReference, PRStrategy, String?) -> Void)?
    var onCancel: (() -> Void)?

    private let field = NSTextField()
    private let valid = PRUI.label("", 11, .medium)
    private let base = NSTextField()
    private let strategy = NSSegmentedControl(labels: ["Merge base into PR", "Rebase PR onto base"], trackingMode: .selectOne, target: nil, action: nil)
    private let ghDot = NSView()
    private let ghLabel = PRUI.wrapping("Checking GitHub CLI…", 11)
    private let message = PRUI.wrapping("", 12)
    private let spinner = NSProgressIndicator()
    private let messageRow: NSStackView
    private let cancel: NSButton, go: NSButton
    private(set) var busy = false

    override init() {
        cancel = NSButton(); go = NSButton()
        messageRow = NSStackView()
        super.init()
        build()
    }

    private func build() {
        view.translatesAutoresizingMaskIntoConstraints = false
        let icon = PRUI.symbol("arrow.triangle.merge", 22, PRUI.blue)
        let title = PRUI.label("Resolve Pull Request Conflicts", 17, .semibold)
        let sub = PRUI.label("Merge the base branch into a PR locally, fix conflicts side by side, push.", 12, .regular, DiffColors.secondary)
        let titleBlock = PRUI.stack([title, sub], .vertical, spacing: 2, alignment: .leading)
        let header = PRUI.stack([icon, titleBlock], .horizontal, spacing: 12, alignment: .centerY)

        field.placeholderString = "123, #123 or https://github.com/owner/repo/pull/123"
        field.font = .systemFont(ofSize: 15)
        field.controlSize = .large
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.focusRingType = .none
        valid.lineBreakMode = .byTruncatingTail

        base.placeholderString = "Default branch of origin"
        base.font = .systemFont(ofSize: 12)
        base.delegate = self
        strategy.selectedSegment = 0
        strategy.segmentStyle = .rounded
        strategy.controlSize = .small
        let baseRow = PRUI.stack([PRUI.label("Base branch", 11, .medium, DiffColors.secondary), base], .horizontal, spacing: 10, alignment: .firstBaseline)
        let stratRow = PRUI.stack([PRUI.label("Update with", 11, .medium, DiffColors.secondary), strategy], .horizontal, spacing: 10, alignment: .firstBaseline)
        baseRow.arrangedSubviews[0].widthAnchor.constraint(equalToConstant: 72).isActive = true
        stratRow.arrangedSubviews[0].widthAnchor.constraint(equalToConstant: 72).isActive = true

        ghDot.wantsLayer = true
        ghDot.layer?.cornerRadius = 4
        ghDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([ghDot.widthAnchor.constraint(equalToConstant: 8), ghDot.heightAnchor.constraint(equalToConstant: 8)])
        let ghRow = PRUI.stack([ghDot, ghLabel], .horizontal, spacing: 8, alignment: .top)
        let ghCard = DiffFillView { PRUI.card }
        ghCard.wantsLayer = true
        ghCard.layer?.cornerRadius = 8
        ghCard.translatesAutoresizingMaskIntoConstraints = false
        PRUI.pin(ghRow, in: ghCard, insets: NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 12))

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        message.maximumNumberOfLines = 4
        messageRow.setViews([spinner, message], in: .leading)
        messageRow.orientation = .horizontal
        messageRow.spacing = 8
        messageRow.alignment = .top
        messageRow.translatesAutoresizingMaskIntoConstraints = false
        messageRow.isHidden = true

        cancel.title = "Cancel"; cancel.target = self; cancel.action = #selector(cancelTapped)
        cancel.bezelStyle = .rounded; cancel.controlSize = .large; cancel.keyEquivalent = "\u{1b}"
        go.title = "Resolve Conflicts"; go.target = self; go.action = #selector(goTapped)
        go.bezelStyle = .rounded; go.controlSize = .large; go.keyEquivalent = "\r"
        go.isEnabled = false
        let spacer = NSView()
        let buttons = PRUI.stack([spacer, cancel, go], .horizontal, spacing: 10)

        let fieldBlock = PRUI.stack([field, valid], .vertical, spacing: 4, alignment: .leading)
        let content = PRUI.stack([header, fieldBlock, stratRow, baseRow, ghCard, messageRow, buttons], .vertical, spacing: 14, alignment: .leading)
        content.setCustomSpacing(18, after: header)
        content.setCustomSpacing(20, after: messageRow)
        PRUI.pin(content, in: view, insets: NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24))
        for v in [field, fieldBlock, ghCard, messageRow, buttons] as [NSView] { v.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true }
        base.widthAnchor.constraint(greaterThanOrEqualToConstant: 220).isActive = true
        view.widthAnchor.constraint(equalToConstant: 500).isActive = true
        setGHStatus(nil)
    }

    var window: NSWindow? { view.window }
    func focus() { view.window?.makeFirstResponder(field) }
    func setText(_ s: String) { field.stringValue = s; validate() }
    func setDefaultBase(_ b: String?) { base.placeholderString = b.map { "Default: \($0)" } ?? "Default branch of origin" }

    func setGHStatus(_ signedIn: Bool?) {
        switch signedIn {
        case .some(true):
            ghDot.layer?.backgroundColor = PRUI.green.cgColor
            ghLabel.stringValue = "GitHub CLI is signed in. The title, branches and fork status are detected automatically."
        case .some(false):
            ghDot.layer?.backgroundColor = PRUI.orange.cgColor
            ghLabel.stringValue = "Using plain git (works without any setup). Run `gh auth login` in a terminal to also get the PR title and exact branches."
        case .none:
            ghDot.layer?.backgroundColor = DiffColors.secondary.cgColor
            ghLabel.stringValue = "Checking GitHub CLI…"
        }
    }

    func setBusy(_ step: String?) {
        busy = step != nil
        field.isEnabled = !busy; base.isEnabled = !busy; strategy.isEnabled = !busy
        go.isEnabled = !busy && PRReference.parse(field.stringValue) != nil
        if let s = step { show(s, .info); spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        if step != nil { messageRow.isHidden = false }
    }

    func show(_ text: String, _ tone: Tone) {
        message.stringValue = text
        message.textColor = tone == .error ? PRUI.red : tone == .success ? PRUI.green : DiffColors.secondary
        messageRow.isHidden = text.isEmpty
    }

    private func validate() {
        if let r = PRReference.parse(field.stringValue) {
            valid.stringValue = "Pull request #\(r.number)" + (r.owner.map { "  ·  \($0)/\(r.repo ?? "")" } ?? "")
            valid.textColor = PRUI.green
        } else {
            valid.stringValue = field.stringValue.isEmpty ? " " : "Not a pull request number or URL"
            valid.textColor = field.stringValue.isEmpty ? DiffColors.secondary : PRUI.orange
        }
        go.isEnabled = !busy && PRReference.parse(field.stringValue) != nil
    }

    func controlTextDidChange(_ obj: Notification) {
        if !busy, !messageRow.isHidden { messageRow.isHidden = true }
        validate()
    }
    @objc private func cancelTapped() { onCancel?() }
    @objc private func goTapped() {
        guard let ref = PRReference.parse(field.stringValue) else { return }
        let b = base.stringValue.trimmingCharacters(in: .whitespaces)
        onSubmit?(ref, strategy.selectedSegment == 1 ? .rebase : .merge, b.isEmpty ? nil : b)
    }
}

// MARK: resolver window

final class PRResolverController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    struct FileRow { var path: String; var kind: PRConflictKind; var resolved: Bool }
    private static var open: [ObjectIdentifier: PRResolverController] = [:]
    static func retain(_ c: PRResolverController) { open[ObjectIdentifier(c)] = c }

    let window: NSWindow
    let repo: GitRepo
    private(set) var session: PRSession
    private(set) var rows: [FileRow] = []
    private weak var project: ProjectWindow?
    private let work = DispatchQueue(label: "kode.pr.resolver")
    private var committed = false
    private var finished = false
    private var selected = -1

    private let root = DiffFillView { Theme.background }
    private let titleLabel = NSTextField(labelWithString: "")
    private let chips = NSStackView()
    private let progressLabel = PRUI.label("", 12, .semibold)
    private let progress = NSProgressIndicator()
    private let table = NSTableView()
    private let mergeView = MergeView()
    private let messageCard = DiffFillView { Theme.background }
    private let cardTitle = PRUI.label("", 15, .semibold)
    private let cardText = PRUI.wrapping("", 12)
    private let keepYours = NSButton(), keepTheirs = NSButton()
    private let placeholder = PRUI.label("Select a file to start resolving", 13, .regular, DiffColors.secondary)
    private let banner = DiffFillView { PRUI.orange.withAlphaComponent(0.14) }
    private let bannerLabel = PRUI.wrapping("", 11, nil)
    private let hint = PRUI.wrapping("", 12)
    private let abortButton = NSButton(), commitButton = NSButton(), pushButton = NSButton(), retryButton = NSButton()
    private let busySpinner = NSProgressIndicator()
    private var success: NSView?

    init(repo: GitRepo, session: PRSession, project: ProjectWindow?, size: NSSize = NSSize(width: 1320, height: 840)) {
        self.repo = repo; self.session = session; self.project = project
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Resolve Pull Request #\(session.info.number)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 980, height: 600)
        window.delegate = self
        window.tabbingMode = .disallowed
        window.contentView = root
        build()
        reloadRows(initial: true)
        update()
    }

    // MARK: layout

    private func build() {
        let header = DiffFillView { DiffColors.chrome }
        let footer = DiffFillView { DiffColors.chrome }
        let sidebar = DiffFillView { Theme.chrome.sidebarBackground }
        let detail = NSView()
        for v in [header, footer, sidebar, detail] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        func rule(_ host: NSView, top: Bool) {
            let r = DiffFillView { DiffColors.separator }
            r.translatesAutoresizingMaskIntoConstraints = false
            host.addSubview(r)
            NSLayoutConstraint.activate([r.heightAnchor.constraint(equalToConstant: 1), r.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                                         r.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                                         top ? r.topAnchor.constraint(equalTo: host.topAnchor) : r.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        }
        rule(header, top: false); rule(footer, top: true)
        let vline = DiffFillView { DiffColors.separator }
        vline.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(vline)
        NSLayoutConstraint.activate([vline.widthAnchor.constraint(equalToConstant: 1), vline.topAnchor.constraint(equalTo: sidebar.topAnchor),
                                     vline.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor), vline.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor)])
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor), header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor), header.heightAnchor.constraint(equalToConstant: 76),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor), footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor), footer.heightAnchor.constraint(equalToConstant: 64),
            sidebar.topAnchor.constraint(equalTo: header.bottomAnchor), sidebar.bottomAnchor.constraint(equalTo: footer.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor), sidebar.widthAnchor.constraint(equalToConstant: 280),
            detail.topAnchor.constraint(equalTo: header.bottomAnchor), detail.bottomAnchor.constraint(equalTo: footer.topAnchor),
            detail.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), detail.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])

        // header
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.attributedStringValue = headerTitle()
        chips.orientation = .horizontal
        chips.spacing = 8
        chips.alignment = .centerY
        chips.translatesAutoresizingMaskIntoConstraints = false
        buildChips()
        let progressBox = PRUI.stack([progressLabel, progress], .vertical, spacing: 6, alignment: .trailing)
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.controlSize = .small
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 190).isActive = true
        header.addSubview(titleLabel); header.addSubview(chips); header.addSubview(progressBox)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 22), titleLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: progressBox.leadingAnchor, constant: -20),
            chips.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 22), chips.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 9),
            chips.trailingAnchor.constraint(lessThanOrEqualTo: progressBox.leadingAnchor, constant: -20),
            progressBox.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -22), progressBox.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        // sidebar
        let sideTitle = PRUI.label("CONFLICTED FILES", 10, .semibold, DiffColors.secondary)
        sideTitle.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sideTitle)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 46
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.style = .plain
        table.selectionHighlightStyle = .regular
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        scroll.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(scroll)
        NSLayoutConstraint.activate([
            sideTitle.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 14), sideTitle.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            scroll.topAnchor.constraint(equalTo: sideTitle.bottomAnchor, constant: 8), scroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 6), scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -7),
        ])

        // detail: banner + (mergeView | message card | placeholder)
        banner.translatesAutoresizingMaskIntoConstraints = false
        bannerLabel.maximumNumberOfLines = 2
        PRUI.pin(bannerLabel, in: banner, insets: NSEdgeInsets(top: 7, left: 16, bottom: 7, right: 16))
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        detail.addSubview(banner); detail.addSubview(content)
        bannerHeight = banner.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: detail.topAnchor), banner.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: detail.trailingAnchor), bannerHeight,
            content.topAnchor.constraint(equalTo: banner.bottomAnchor), content.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: detail.leadingAnchor), content.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
        ])
        banner.isHidden = true
        PRUI.pin(mergeView, in: content)
        PRUI.pin(messageCard, in: content)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(placeholder)
        NSLayoutConstraint.activate([placeholder.centerXAnchor.constraint(equalTo: content.centerXAnchor), placeholder.centerYAnchor.constraint(equalTo: content.centerYAnchor)])
        buildCard()
        mergeView.onResolved = { [weak self] text in self?.applyMerged(text) }

        // footer
        abortButton.title = "Abort"; abortButton.target = self; abortButton.action = #selector(abortTapped)
        commitButton.title = "Commit Merge"; commitButton.target = self; commitButton.action = #selector(commitOnlyTapped)
        pushButton.title = "Commit Merge and Push"; pushButton.target = self; pushButton.action = #selector(commitPushTapped)
        retryButton.title = "Pull and Retry Push"; retryButton.target = self; retryButton.action = #selector(pullRetryTapped)
        for b in [abortButton, commitButton, pushButton, retryButton] { b.bezelStyle = .rounded; b.controlSize = .large }
        pushButton.keyEquivalent = "\r"
        retryButton.isHidden = true
        abortButton.contentTintColor = PRUI.red
        busySpinner.style = .spinning; busySpinner.controlSize = .small; busySpinner.isDisplayedWhenStopped = false
        hint.maximumNumberOfLines = 2
        hint.translatesAutoresizingMaskIntoConstraints = false
        let right = PRUI.stack([retryButton, commitButton, pushButton], .horizontal, spacing: 10)
        let left = PRUI.stack([abortButton, busySpinner], .horizontal, spacing: 10, alignment: .centerY)
        footer.addSubview(left); footer.addSubview(right); footer.addSubview(hint)
        NSLayoutConstraint.activate([
            left.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 18), left.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -18), right.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            hint.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: 18), hint.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -18),
            hint.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
        ])
    }

    private var bannerHeight: NSLayoutConstraint!

    private func buildCard() {
        let icon = PRUI.symbol("doc.badge.gearshape", 30, DiffColors.secondary)
        keepYours.target = self; keepYours.action = #selector(keepYoursTapped)
        keepTheirs.target = self; keepTheirs.action = #selector(keepTheirsTapped)
        for b in [keepYours, keepTheirs] { b.bezelStyle = .rounded; b.controlSize = .large }
        cardText.maximumNumberOfLines = 6
        cardText.alignment = .center
        cardTitle.alignment = .center
        let buttons = PRUI.stack([keepYours, keepTheirs], .horizontal, spacing: 10)
        let stack = PRUI.stack([icon, cardTitle, cardText, buttons], .vertical, spacing: 12, alignment: .centerX)
        stack.setCustomSpacing(18, after: cardText)
        messageCard.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: messageCard.centerXAnchor), stack.centerYAnchor.constraint(equalTo: messageCard.centerYAnchor, constant: -20),
                                     cardText.widthAnchor.constraint(lessThanOrEqualToConstant: 460)])
        messageCard.isHidden = true
    }

    private var yoursName: String { session.headLabel }
    private var theirsName: String { "origin/\(session.baseRef)" }

    private func headerTitle() -> NSAttributedString {
        let s = NSMutableAttributedString(string: "PR #\(session.info.number)", attributes: [.font: NSFont.systemFont(ofSize: 17, weight: .bold), .foregroundColor: PRUI.blue])
        let t = session.info.title ?? "Pull request \(session.info.number)"
        s.append(NSAttributedString(string: "   \(t)", attributes: [.font: NSFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: Theme.foreground]))
        return s
    }

    private func buildChips() {
        for v in chips.arrangedSubviews { chips.removeArrangedSubview(v); v.removeFromSuperview() }
        let arrow = PRUI.symbol("arrow.right", 10, DiffColors.secondary)
        chips.addArrangedSubview(PRChip(session.headLabel, mono: true, tint: { PRUI.blue }))
        chips.addArrangedSubview(arrow)
        chips.addArrangedSubview(PRChip(session.baseRef, mono: true, tint: { PRUI.green }))
        chips.addArrangedSubview(PRChip(session.strategy == .merge ? "Merge" : "Rebase", tint: { DiffColors.secondary }))
        if session.isFork { chips.addArrangedSubview(PRChip("Fork", symbol: "exclamationmark.triangle.fill", tint: { PRUI.orange })) }
        if session.info.mergeable == "CONFLICTING" { chips.addArrangedSubview(PRChip("Conflicts on GitHub", tint: { PRUI.red })) }
    }

    // MARK: state

    private func reloadRows(initial: Bool) {
        let unresolved = PRFlow.stillUnmerged(repo)
        if initial || !session.conflicts.isEmpty {
            let known = Dictionary(uniqueKeysWithValues: rows.map { ($0.path, $0.resolved) })
            let paths = initial ? session.conflicts : (rows.map(\.path) + session.conflicts.filter { p in !rows.contains { $0.path == p } })
            rows = paths.map { p in
                FileRow(path: p, kind: PRFlow.conflictKind(repo, path: p, strategy: session.strategy), resolved: unresolved.contains(p) ? false : (known[p] ?? false))
            }
            if initial { rows = session.conflicts.map { FileRow(path: $0, kind: unresolved.contains($0) ? PRFlow.conflictKind(repo, path: $0, strategy: session.strategy) : .text, resolved: !unresolved.contains($0)) } }
        }
        for i in rows.indices where !unresolved.contains(rows[i].path) { rows[i].resolved = true }
        table.reloadData()
    }

    private var resolvedCount: Int { rows.filter(\.resolved).count }

    private func update() {
        let total = rows.count
        progress.maxValue = Double(max(total, 1))
        progress.doubleValue = Double(resolvedCount)
        progressLabel.stringValue = total == 0 ? "No conflicts" : "\(resolvedCount) of \(total) file\(total == 1 ? "" : "s") resolved"
        progressLabel.textColor = resolvedCount == total && total > 0 ? PRUI.green : Theme.foreground
        let ready = resolvedCount == total
        commitButton.isEnabled = ready && !committed
        pushButton.isEnabled = ready && (session.pushRemote != nil || committed)
        pushButton.title = committed ? "Push" : (session.strategy == .merge ? "Commit Merge and Push" : "Continue Rebase and Push")
        commitButton.title = session.strategy == .merge ? "Commit Merge" : "Continue Rebase"
        commitButton.isHidden = committed
        abortButton.isEnabled = !committed || true
        if committed { /* keep hint from push errors */ }
        else if !ready { setHint("Resolve every file, then commit. Pick lines with the arrows in the gutters, or use Accept Yours / Theirs.", .info) }
        else if session.pushRemote == nil { setHint("All resolved. This PR comes from a fork we can't push to automatically. Commit, then push from the fork.", .info) }
        else { setHint(session.isFork ? "Ready. Pushing to a fork works only if the author allowed maintainer edits." : "All files resolved. Ready to commit and push to \(session.headRefName ?? "the PR branch").", .ok) }
    }

    private enum HintTone { case info, ok, error }
    private func setHint(_ s: String, _ t: HintTone) {
        hint.stringValue = s
        hint.textColor = t == .error ? PRUI.red : t == .ok ? PRUI.green : DiffColors.secondary
    }

    private func setBusy(_ b: Bool) {
        b ? busySpinner.startAnimation(nil) : busySpinner.stopAnimation(nil)
        for x in [abortButton, commitButton, pushButton, retryButton, keepYours, keepTheirs] { x.isEnabled = !b && x.isEnabled }
        if !b { update() }
    }

    func select(_ row: Int) {
        guard rows.indices.contains(row) else { return }
        selected = row
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        showSelected()
    }

    private func showSelected() {
        placeholder.isHidden = true
        guard rows.indices.contains(selected) else { mergeView.isHidden = true; messageCard.isHidden = true; placeholder.isHidden = false; return }
        let r = rows[selected]
        if let hintText = PRFlow.lockfileHint(for: r.path) {
            bannerLabel.stringValue = hintText
            banner.isHidden = false; bannerHeight.constant = 46
        } else { banner.isHidden = true; bannerHeight.constant = 0 }
        let rebase = session.strategy == .rebase
        if r.resolved {
            mergeView.isHidden = true
            messageCard.isHidden = false
            cardTitle.stringValue = (r.path as NSString).lastPathComponent
            cardText.stringValue = "Resolved and staged. Nothing more to do for this file."
            keepYours.isHidden = true; keepTheirs.isHidden = true
            return
        }
        keepYours.isHidden = false; keepTheirs.isHidden = false
        if r.kind == .text {
            messageCard.isHidden = true
            mergeView.isHidden = false
            guard let v = try? repo.conflictVersions(of: r.path) else { return }
            let yours = rebase ? v.theirs : v.ours, theirs = rebase ? v.ours : v.theirs
            if r.resolved, let current = try? repo.workingContent(of: r.path) {
                // already resolved: show the resolution as the starting result (re-pick is not possible after `git add`)
                mergeView.show(base: v.base, ours: yours ?? "", theirs: theirs ?? "", oursTitle: "Yours · \(yoursName)", theirsTitle: "Theirs · \(theirsName)",
                               fileExtension: (r.path as NSString).pathExtension)
                _ = current
            } else {
                mergeView.show(base: v.base, ours: yours ?? "", theirs: theirs ?? "", oursTitle: "Yours · \(yoursName)", theirsTitle: "Theirs · \(theirsName)",
                               fileExtension: (r.path as NSString).pathExtension)
            }
        } else {
            mergeView.isHidden = true
            messageCard.isHidden = false
            switch r.kind {
            case .binary:
                cardTitle.stringValue = (r.path as NSString).lastPathComponent
                cardText.stringValue = "This file can't be merged line by line (binary or too large). Choose which version to keep."
            case .yoursDeleted:
                cardTitle.stringValue = "Deleted in \(yoursName), changed in \(theirsName)"
                cardText.stringValue = "Keep the deletion, or keep the version from \(theirsName)?"
            case .theirsDeleted:
                cardTitle.stringValue = "Changed in \(yoursName), deleted in \(theirsName)"
                cardText.stringValue = "Keep your changes, or accept the deletion from \(theirsName)?"
            case .text: break
            }
            if r.kind == .yoursDeleted { keepYours.title = "Keep Deletion"; keepTheirs.title = "Keep File" }
            else if r.kind == .theirsDeleted { keepYours.title = "Keep File"; keepTheirs.title = "Accept Deletion" }
            else { keepYours.title = "Keep Yours"; keepTheirs.title = "Keep Theirs" }
            keepYours.isEnabled = !r.resolved; keepTheirs.isEnabled = !r.resolved
            if r.resolved { cardText.stringValue += "\nAlready resolved." }
        }
    }

    // MARK: actions

    private func applyMerged(_ text: String) {
        guard rows.indices.contains(selected) else { return }
        let path = rows[selected].path
        setBusy(true)
        work.async { [repo] in
            let err = Result { try repo.markResolved(path: path, content: text) }
            DispatchQueue.main.async { [weak self] in self?.afterResolve(err) }
        }
    }

    @objc private func keepYoursTapped() { wholeFile(yours: true) }
    @objc private func keepTheirsTapped() { wholeFile(yours: false) }
    private func wholeFile(yours: Bool) {
        guard rows.indices.contains(selected) else { return }
        let path = rows[selected].path, strategy = session.strategy
        setBusy(true)
        work.async { [repo] in
            let r = Result { try PRFlow.resolveWholeFile(repo, path: path, yours: yours, strategy: strategy) }
            DispatchQueue.main.async { [weak self] in self?.afterResolve(r) }
        }
    }

    private func afterResolve(_ r: Result<Void, Error>) {
        setBusy(false)
        if case .failure(let e) = r { setHint(e.localizedDescription, .error); return }
        reloadRows(initial: false)
        update()
        if let next = rows.indices.first(where: { !rows[$0].resolved }) { select(next) }
        else { table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false); showSelected() }
    }

    @objc private func commitOnlyTapped() { finish(push: false) }
    @objc private func commitPushTapped() { finish(push: true) }

    private func finish(push: Bool) {
        setBusy(true)
        retryButton.isHidden = true
        let s = session, alreadyCommitted = committed
        work.async { [repo] in
            var result: Result<PRFlow.CommitOutcome, Error> = .success(.committed)
            if !alreadyCommitted { result = Result { try PRFlow.commit(repo, s) } }
            var pushError: PRError?
            if case .success(.committed) = result, push {
                do { try PRFlow.push(repo, s) } catch { pushError = error as? PRError ?? PRError.classify(error.localizedDescription) }
            }
            DispatchQueue.main.async { [weak self] in self?.afterFinish(result, pushRequested: push, pushError: pushError) }
        }
    }

    private func afterFinish(_ result: Result<PRFlow.CommitOutcome, Error>, pushRequested: Bool, pushError: PRError?) {
        setBusy(false)
        switch result {
        case .failure(let e): setHint(e.localizedDescription, .error); return
        case .success(.moreConflicts(let files)):
            session.conflicts = files
            rows = []; reloadRows(initial: true); selected = -1; update(); showSelected()
            setHint("Rebase moved on to the next commit and found more conflicts (\(files.count) file\(files.count == 1 ? "" : "s")).", .info)
            if !rows.isEmpty { select(0) }
            return
        case .success(.committed): committed = true
        }
        if let e = pushError {
            update()
            setHint(e.message, .error)
            retryButton.isHidden = e.kind != .nonFastForward
            retryButton.isEnabled = true
            return
        }
        if pushRequested { showSuccess(pushed: true) } else { update(); showSuccess(pushed: false) }
    }

    @objc private func pullRetryTapped() {
        setBusy(true)
        retryButton.isHidden = true
        let s = session
        work.async { [repo] in
            var conflicts: [String] = []
            var err: PRError?
            do { conflicts = try PRFlow.pullRemoteHead(repo, s) } catch { err = error as? PRError ?? PRError.classify(error.localizedDescription) }
            if err == nil, conflicts.isEmpty { do { try PRFlow.push(repo, s) } catch { err = error as? PRError ?? PRError.classify(error.localizedDescription) } }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.setBusy(false)
                if let e = err { self.setHint(e.message, .error); self.retryButton.isHidden = e.kind != .nonFastForward; return }
                if !conflicts.isEmpty {                         // the teammate's changes conflict: back to resolving
                    self.committed = false
                    self.session.conflicts = conflicts
                    self.rows = []; self.reloadRows(initial: true); self.selected = -1; self.update(); self.showSelected()
                    self.setHint("Their changes conflict with yours in \(conflicts.count) file\(conflicts.count == 1 ? "" : "s"). Resolve them and push again.", .info)
                    if !self.rows.isEmpty { self.select(0) }
                    return
                }
                self.showSuccess(pushed: true)
            }
        }
    }

    @objc private func abortTapped() {
        let alert = NSAlert()
        alert.messageText = committed ? "Close without pushing?" : "Abort and restore your previous state?"
        alert.informativeText = committed
            ? "The merge is committed locally on \(session.localBranch). Closing keeps it there; nothing is pushed."
            : "The merge is cancelled and you'll be back on \(session.preBranch ?? "your previous commit") with your changes\(session.stashed ? " restored from the stash" : " untouched"). Files you resolved here are discarded."
        alert.addButton(withTitle: committed ? "Close" : "Abort Merge")
        alert.addButton(withTitle: "Keep Working")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window) { [weak self] r in
            guard r == .alertFirstButtonReturn, let self else { return }
            if self.committed { self.finished = true; self.window.close(); return }
            self.restoreAndClose()
        }
    }

    private func restoreAndClose() {
        setBusy(true)
        let s = session
        work.async { [repo] in
            let notes = (try? PRFlow.restore(repo, s)) ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.finished = true
                self.window.close()
                self.project?.refreshGitStatus()
                if let n = notes.first, !AppEnv.headless { let a = NSAlert(); a.messageText = n; a.runModal() }
            }
        }
    }

    // MARK: success

    private func showSuccess(pushed: Bool) {
        finished = true
        let note = PRFlow.popStash(repo, session)
        project?.refreshGitStatus()
        let v = DiffFillView { Theme.background }
        v.translatesAutoresizingMaskIntoConstraints = false
        let icon = PRUI.symbol(pushed ? "checkmark.circle.fill" : "checkmark.seal.fill", 54, PRUI.green)
        let title = PRUI.label(pushed ? "Conflicts resolved and pushed" : "Merge committed", 22, .semibold)
        var text = pushed
            ? "PR #\(session.info.number) now includes \(theirsName) and was pushed to \(session.headLabel). GitHub can take a few seconds to refresh the “can be merged” status."
            : "The merge commit is on \(session.localBranch). Push it when you're ready."
        if let note { text += "\n\n" + note }
        if !session.stashed.description.isEmpty, session.stashed, note == nil { text += "\n\nYour earlier uncommitted changes were restored." }
        let sub = PRUI.wrapping(text, 13)
        sub.alignment = .center
        sub.maximumNumberOfLines = 6
        let open = PRUI.button(pushed ? "Open Pull Request" : "Push Now", self, pushed ? #selector(openPR) : #selector(pushNow), primary: true)
        let done = PRUI.button("Done", self, #selector(doneTapped))
        let buttons = PRUI.stack(pushed ? [open, done] : [open, done], .horizontal, spacing: 10)
        let stack = PRUI.stack([icon, title, sub, buttons], .vertical, spacing: 12, alignment: .centerX)
        stack.setCustomSpacing(20, after: sub)
        v.addSubview(stack)
        NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo: v.centerXAnchor), stack.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -16),
                                     sub.widthAnchor.constraint(lessThanOrEqualToConstant: 520)])
        success?.removeFromSuperview()
        root.addSubview(v)
        NSLayoutConstraint.activate([v.topAnchor.constraint(equalTo: root.topAnchor, constant: 76), v.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                                     v.leadingAnchor.constraint(equalTo: root.leadingAnchor), v.trailingAnchor.constraint(equalTo: root.trailingAnchor)])
        success = v
        window.makeFirstResponder(open)
    }

    var prURL: URL? {
        if let u = session.info.url, let url = URL(string: u) { return url }
        guard let o = try? repo.text(["remote", "get-url", "origin"]).trimmingCharacters(in: .whitespacesAndNewlines), let s = PRFlow.slug(ofRemoteURL: o) else { return nil }
        return URL(string: "https://\(s.host)/\(s.owner)/\(s.repo)/pull/\(session.info.number)")
    }
    func showSuccessForSnapshot() { showSuccess(pushed: true) }
    @objc private func openPR() { if let u = prURL, !AppEnv.headless { NSWorkspace.shared.open(u) } }
    @objc private func pushNow() { success?.removeFromSuperview(); success = nil; finished = false; finish(push: true) }
    @objc private func doneTapped() { finished = true; window.close() }

    // MARK: table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = rows[row]
        let cell = NSView()
        let (symbol, color, state): (String, NSColor, String) = r.resolved ? ("checkmark.circle.fill", PRUI.green, "Resolved") : ("exclamationmark.triangle.fill", PRUI.orange, "Conflicted")
        let icon = PRUI.symbol(symbol, 14, color)
        let name = PRUI.label((r.path as NSString).lastPathComponent, 13, .medium)
        let dir = (r.path as NSString).deletingLastPathComponent
        let sub = PRUI.label(dir.isEmpty ? kindText(r.kind) : dir + (r.kind == .text ? "" : " · " + kindText(r.kind)), 11, .regular, DiffColors.secondary)
        sub.lineBreakMode = .byTruncatingHead
        sub.isHidden = sub.stringValue.isEmpty
        let chip = PRChip(state, tint: { color })
        let text = PRUI.stack([name, sub], .vertical, spacing: 1, alignment: .leading)
        for v in [icon, text, chip] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(v) }
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            chip.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), chip.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: chip.leadingAnchor, constant: -8),
        ])
        return cell
    }
    private func kindText(_ k: PRConflictKind) -> String {
        switch k { case .text: return ""; case .binary: return "binary"; case .yoursDeleted: return "deleted by you"; case .theirsDeleted: return "deleted upstream" }
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let r = table.selectedRow
        guard r >= 0, r != selected else { return }
        selected = r
        showSelected()
    }

    // MARK: window

    func present() {
        PRResolverController.retain(self)
        if !AppEnv.headless {
            if let p = project?.window.frame { window.setFrameOrigin(NSPoint(x: p.midX - window.frame.width / 2, y: p.midY - window.frame.height / 2)) }
            window.makeKeyAndOrderFront(nil)
        }
        if let first = rows.indices.first(where: { !rows[$0].resolved }) ?? rows.indices.first { select(first) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if finished || repo.operationInProgress() == nil { return true }
        let alert = NSAlert()
        alert.messageText = "Pull request resolution is unfinished"
        alert.informativeText = "The merge is still in progress in the repository. You can abort it to restore your previous state, or keep it and finish later from the Git panel."
        alert.addButton(withTitle: "Keep Merge State")
        alert.addButton(withTitle: "Abort and Restore")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] r in
            guard let self else { return }
            if r == .alertFirstButtonReturn { self.finished = true; self.window.close() }
            else if r == .alertSecondButtonReturn { self.restoreAndClose() }
        }
        return false
    }
    func windowWillClose(_ notification: Notification) { PRResolverController.open[ObjectIdentifier(self)] = nil }
}

// MARK: flow coordinator (prompt sheet -> prepare -> resolver)

final class PRCoordinator: NSObject {
    private static var active: [ObjectIdentifier: PRCoordinator] = [:]
    private weak var project: ProjectWindow?
    private let prompt = PRPromptController()
    private let sheet: NSWindow
    private var repo: GitRepo?
    private let work = DispatchQueue(label: "kode.pr.prepare")

    static func show(for project: ProjectWindow) {
        if let c = active[ObjectIdentifier(project)] { c.sheet.makeKeyAndOrderFront(nil); return }
        guard let root = project.root else { return }
        let c = PRCoordinator(project: project)
        active[ObjectIdentifier(project)] = c
        DispatchQueue.global(qos: .userInitiated).async {
            let repoRoot = GitRepo.repoRoot(for: root)
            DispatchQueue.main.async { c.begin(repoRoot: repoRoot) }
        }
    }

    private init(project: ProjectWindow) {
        self.project = project
        sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 360), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        sheet.isReleasedWhenClosed = false
        sheet.contentView = prompt.view
        prompt.view.frame = NSRect(x: 0, y: 0, width: 500, height: 360)
        prompt.onCancel = { [weak self] in self?.close() }
        prompt.onSubmit = { [weak self] ref, strategy, base in self?.submit(ref, strategy, base) }
    }

    private func begin(repoRoot: URL?) {
        guard let project, let repoRoot else {
            close()
            if !AppEnv.headless, let w = self.project?.window { let a = NSAlert(); a.messageText = "This project is not a Git repository"; a.beginSheetModal(for: w) }
            return
        }
        repo = GitRepo(root: repoRoot)
        let r = repo!
        prompt.setDefaultBase(((try? r.text(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"])) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "origin/", with: "").nilIfEmpty)
        sheet.layoutIfNeeded()
        sheet.setContentSize(NSSize(width: 500, height: max(prompt.view.fittingSize.height, 300)))
        project.window.beginSheet(sheet)
        prompt.focus()
        work.async { let ok = GHCLI.isSignedIn(); DispatchQueue.main.async { [weak self] in self?.prompt.setGHStatus(ok) } }
    }

    private func close() {
        if let project { project.window.endSheet(sheet); PRCoordinator.active[ObjectIdentifier(project)] = nil }
    }

    private func submit(_ ref: PRReference, _ strategy: PRStrategy, _ base: String?, stash: Bool = false) {
        guard let repo else { return }
        prompt.setBusy("Looking up pull request #\(ref.number)…")
        work.async { [weak self] in
            do {
                let (info, note) = try PRFlow.resolveInfo(repo: repo, ref: ref)
                let session = try PRFlow.prepare(repo: repo, info: info, strategy: strategy, baseOverride: base, stashDirty: stash) { step in
                    DispatchQueue.main.async { self?.prompt.show(step, .info) }
                }
                DispatchQueue.main.async { self?.prepared(session, note: note) }
            } catch {
                let e = error as? PRError ?? PRError.classify((error as? GitError)?.message ?? error.localizedDescription)
                DispatchQueue.main.async { self?.failed(e, ref, strategy, base) }
            }
        }
    }

    private func prepared(_ session: PRSession, note: String?) {
        prompt.setBusy(nil)
        guard let repo else { return }
        if session.noConflicts {
            let t = session.info.title.map { "“\($0)” " } ?? ""
            prompt.show("PR #\(session.info.number) \(t)has no conflicts with \(session.baseRef). It can be merged as is, so nothing was changed.", .success)
            return
        }
        close()
        let c = PRResolverController(repo: repo, session: session, project: project)
        c.present()
        project?.refreshGitStatus()
    }

    private func failed(_ e: PRError, _ ref: PRReference, _ strategy: PRStrategy, _ base: String?) {
        prompt.setBusy(nil)
        guard e.kind == .dirty else { prompt.show(e.message, .error); return }
        let a = NSAlert()
        a.messageText = "Set aside your uncommitted changes?"
        a.informativeText = e.message + " Kode will stash them (including untracked files) and restore them when you finish or abort. Nothing is lost."
        a.addButton(withTitle: "Stash and Continue")
        a.addButton(withTitle: "Cancel")
        a.beginSheetModal(for: sheet) { [weak self] r in
            if r == .alertFirstButtonReturn { self?.submit(ref, strategy, base, stash: true) }
            else { self?.prompt.show("Cancelled. Your working tree was not touched.", .info) }
        }
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

extension AppDelegate {
    @objc func resolvePullRequest(_ sender: Any?) { if let w = active { PRCoordinator.show(for: w) } }
}
