import AppKit

/// Icon buttons at the right of the title bar: Update / Commit / Push, Run tests, Search Everywhere, Claude Changes (with a
/// pending count), Settings. Each button runs the same action as its menu item.
final class ProjectToolbar: NSObject {
    private weak var window: NSWindow?
    /// The button row; the branch controller places it in the title bar next to the branch widget.
    let view = NSStackView()
    private var stack: NSStackView { view }
    /// Called when the row appears, disappears or changes size.
    var onLayout: (() -> Void)?
    private var buttons: [String: NSButton] = [:]
    private let badge = NSTextField(labelWithString: "")
    private var prefsObserver: NSObjectProtocol?

    struct Item { let id: String; let symbol: String; let tip: String; let action: Selector; let target: AnyObject? }

    init(window: NSWindow) {
        self.window = window
        super.init()
        prefsObserver = NotificationCenter.default.addObserver(forName: Prefs.didChange, object: nil, queue: .main) { [weak self] n in
            if n.userInfo?["key"] as? String == "showToolbar" { self?.sync() }
        }
        sync()
    }

    deinit { prefsObserver.map(NotificationCenter.default.removeObserver) }

    private var items: [Item?] {
        let app = NSApp.delegate as AnyObject?
        return [
            Item(id: "update", symbol: "arrow.down.circle", tip: "Update Project (⌘T)", action: #selector(AppDelegate.updateProject(_:)), target: app),
            Item(id: "commit", symbol: "checkmark.circle", tip: "Commit… (⌘K)", action: #selector(AppDelegate.commitChanges(_:)), target: app),
            Item(id: "push", symbol: "arrow.up.circle", tip: "Push… (⇧⌘K)", action: #selector(AppDelegate.pushChanges(_:)), target: app),
            nil,
            Item(id: "terminal", symbol: "terminal", tip: "Toggle Terminal (⌥F12)", action: #selector(AppDelegate.showTerminal(_:)), target: app),
            Item(id: "run", symbol: "play.fill", tip: "Run All Tests", action: #selector(TestActions.runAll(_:)), target: TestActions.shared),
            nil,
            Item(id: "search", symbol: "magnifyingglass", tip: "Search Everywhere (⇧⇧)", action: #selector(AppDelegate.searchEverywhere(_:)), target: app),
            Item(id: "claude", symbol: "sparkles", tip: "Claude Changes", action: #selector(AppDelegate.showClaudeChangesTool(_:)), target: app),
            Item(id: "settings", symbol: "gearshape", tip: "Settings (⌘,)", action: #selector(AppDelegate.showSettings(_:)), target: app),
        ]
    }

    private func build() {
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 10)
        for item in items {
            guard let item else {
                let sep = NSBox(); sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.heightAnchor.constraint(equalToConstant: 14).isActive = true
                stack.addArrangedSubview(sep)
                continue
            }
            let b = NSButton(frame: NSRect(x: 0, y: 0, width: 28, height: 24))
            b.bezelStyle = .regularSquare
            b.isBordered = false
            b.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.tip)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            b.imagePosition = .imageOnly
            b.contentTintColor = item.id == "run" ? .systemGreen : .secondaryLabelColor
            b.toolTip = item.tip
            b.target = item.target
            b.action = item.action
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: 28).isActive = true
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            stack.addArrangedSubview(b)
            buttons[item.id] = b
        }
        badge.font = .systemFont(ofSize: 9, weight: .bold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.systemOrange.cgColor
        badge.layer?.cornerRadius = 7
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        if let claude = buttons["claude"] {
            claude.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: claude.topAnchor, constant: -2),
                badge.trailingAnchor.constraint(equalTo: claude.trailingAnchor, constant: 2),
                badge.heightAnchor.constraint(equalToConstant: 14),
                badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 14),
            ])
        }
        stack.setFrameSize(stack.fittingSize)
    }

    /// Shows / hides the bar to match `Prefs.showToolbar`.
    func sync() {
        if Prefs.showToolbar {
            if buttons.isEmpty { build() }
            stack.isHidden = false
            stack.setFrameSize(stack.fittingSize)
        } else {
            stack.isHidden = true
        }
        onLayout?()
    }

    var isVisible: Bool { !stack.isHidden && !buttons.isEmpty }

    /// Pending Claude change count on the sparkle button.
    func setClaudeBadge(_ text: String?) {
        badge.stringValue = text ?? ""
        badge.isHidden = text == nil
    }

    /// Greys out buttons that need a repository.
    func setGitAvailable(_ on: Bool) {
        for id in ["update", "commit", "push"] { buttons[id]?.isEnabled = on }
    }
}
