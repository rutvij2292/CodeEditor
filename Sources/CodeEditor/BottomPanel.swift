import AppKit

/// Root view of the bottom tool area: a tab strip (tool titles, badges, close button) over the selected tool's view.
final class BottomPanelView: NSView {
    let strip = NSStackView()
    let content = NSView()
    let closeButton = NSButton()
    private let separator = NSView()
    var onEscape: (() -> Void)?
    /// Shift-Escape inside a tool: hide the panel and return to the editor (PhpStorm).
    var onHide: (() -> Void)?
    /// Shift-Cmd-[ / ] inside a tool: previous / next tool tab.
    var onCycle: ((Int) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        strip.orientation = .horizontal
        strip.spacing = 2
        strip.alignment = .centerY
        strip.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 4)
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close panel")
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.toolTip = "Hide panel"
        separator.wantsLayer = true
        let bar = NSView()
        for v in [strip, closeButton, bar, separator, content] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(content); addSubview(bar); addSubview(separator)
        bar.addSubview(strip); bar.addSubview(closeButton)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor), bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 26),
            strip.leadingAnchor.constraint(equalTo: bar.leadingAnchor), strip.topAnchor.constraint(equalTo: bar.topAnchor),
            strip.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            strip.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor),
            closeButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 14), closeButton.heightAnchor.constraint(equalToConstant: 14),
            separator.topAnchor.constraint(equalTo: bar.bottomAnchor), separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor), separator.heightAnchor.constraint(equalToConstant: 1),
            content.topAnchor.constraint(equalTo: separator.bottomAnchor), content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    func restyle() {
        layer?.backgroundColor = Theme.background.blended(withFraction: Theme.isDark ? 0.04 : 0.02, of: Theme.foreground)?.cgColor
        separator.layer?.backgroundColor = Theme.foreground.withAlphaComponent(0.12).cgColor
        closeButton.contentTintColor = Theme.gutter
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }

    /// Escape inside any tool view arrives here through the responder chain.
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    /// Keys that only make sense while focus is inside the panel; the terminal keeps plain Escape for the shell.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let r = window?.firstResponder as? NSView, r.isDescendant(of: self), window?.attachedSheet == nil else {
            return super.performKeyEquivalent(with: event)
        }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function, .numericPad, .capsLock])
        if event.keyCode == 53, mods == .shift { onHide?(); return true }
        if mods == [.command, .shift], let c = event.charactersIgnoringModifiers {
            if c == "[" || c == "{" { onCycle?(-1); return true }
            if c == "]" || c == "}" { onCycle?(1); return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Tabbed host for tool windows (Git, Find, Problems, ...). Tools register a view; the panel owns visibility,
/// the selected tab, badges, and remembers the selected tab and height (UserDefaults, keyed per window/project).
final class BottomPanel: NSObject {
    struct Tool {
        let id: String
        var title: String
        let view: NSView
        var badge: String?
    }

    let view = BottomPanelView()
    private(set) var tools: [Tool] = []
    private(set) var selectedID: String?
    private(set) var isVisible = false
    /// Last height the panel had when shown (updated when it is hidden or resized by the host).
    var height: CGFloat = 320
    /// The host shows/hides the split item in response.
    var onVisibilityChange: ((Bool) -> Void)?
    /// Called just before a tool becomes visible, so hosts can build it lazily.
    var onWillShow: ((String) -> Void)?
    /// Escape inside a tool, and the end of `requestClose`: the host moves focus back to the editor.
    var onEscape: (() -> Void)?
    /// Moves focus into a tool's primary control (after it was shown by a number key or tab cycling).
    var onFocusTool: ((String) -> Void)?

    /// Shortcut shown in tab tooltips.
    static let shortcutHints: [String: String] = ["bookmarks": "⌘2", "find": "⌘3", "tests": "⌘4", "todo": "⌘5", "problems": "⌘6",
                                                  "http": "⌘8", "git": "⌘9", "terminal": "⌥F12"]

    private let defaults: UserDefaults
    private var persistenceKey: String?
    private var buttons: [String: NSButton] = [:]
    private var preferredSelection: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        view.closeButton.target = self
        view.closeButton.action = #selector(closeClicked)
        view.onEscape = { [weak self] in self?.escapePressed() }
        view.onHide = { [weak self] in self?.requestClose() }
        view.onCycle = { [weak self] d in self?.cycle(d) }
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
    }

    /// Loads (and from now on stores) the selected tab and height under `key`.
    func setPersistence(key: String?) {
        persistenceKey = key
        guard let key, let saved = defaults.dictionary(forKey: "bottomPanel:" + key) else { return }
        if let h = saved["height"] as? Double, h > 80 { height = CGFloat(h) }
        if let s = saved["selected"] as? String {
            preferredSelection = s
            if tools.contains(where: { $0.id == s }) { select(s, notify: false) }
        }
    }

    private func persist() {
        guard let persistenceKey else { return }
        var dict: [String: Any] = ["height": Double(height)]
        if let selectedID { dict["selected"] = selectedID }
        defaults.set(dict, forKey: "bottomPanel:" + persistenceKey)
    }

    /// Adds a tool tab. `installCloseRequest` receives a closure the tool can call to ask the host to close the panel
    /// (it hides the panel and returns focus to the editor).
    func register(id: String, title: String, view toolView: NSView, installCloseRequest: ((@escaping () -> Void) -> Void)? = nil) {
        guard !tools.contains(where: { $0.id == id }) else { return }
        tools.append(Tool(id: id, title: title, view: toolView, badge: nil))
        let b = NSButton(title: title, target: self, action: #selector(tabClicked(_:)))
        b.isBordered = false
        b.identifier = NSUserInterfaceItemIdentifier(id)
        b.toolTip = Self.shortcutHints[id].map { "\(title) (\($0))" } ?? title
        b.wantsLayer = true
        b.layer?.cornerRadius = 5
        buttons[id] = b
        view.strip.addArrangedSubview(b)
        if selectedID == nil || preferredSelection == id { select(id, notify: false) } else { restyleButtons() }
        installCloseRequest? { [weak self] in self?.requestClose() }
    }

    /// Removes a tool tab (e.g. the terminal moving to the right dock). Its view is detached; selection falls back to the first tool.
    func unregister(_ id: String) {
        guard let i = tools.firstIndex(where: { $0.id == id }) else { return }
        let tool = tools.remove(at: i)
        if tool.view.superview === view.content { tool.view.removeFromSuperview() }
        if let b = buttons.removeValue(forKey: id) { view.strip.removeArrangedSubview(b); b.removeFromSuperview() }
        if selectedID == id {
            selectedID = nil
            if let first = tools.first { select(first.id, notify: false) } else { hide() }
        }
        restyleButtons()
    }

    func has(_ id: String) -> Bool { tools.contains { $0.id == id } }

    func badge(for id: String) -> String? { tools.first { $0.id == id }?.badge }

    func setBadge(_ text: String?, for id: String) {
        guard let i = tools.firstIndex(where: { $0.id == id }) else { return }
        let value = (text?.isEmpty ?? true) ? nil : text
        guard tools[i].badge != value else { return }
        tools[i].badge = value
        restyleButtons()
    }

    /// Shows the panel on tool `id`; `focus` runs once the tool is on screen.
    func show(_ id: String, focus: (() -> Void)? = nil) {
        guard has(id) else { return }
        onWillShow?(id)
        select(id, notify: false)
        if !isVisible {
            isVisible = true
            onVisibilityChange?(true)
        }
        persist()
        if let focus { DispatchQueue.main.async(execute: focus) }
    }

    func hide() {
        guard isVisible else { return }
        if view.bounds.height > 80 { height = view.bounds.height }
        isVisible = false
        persist()
        onVisibilityChange?(false)
    }

    /// Shows `id`; if it is already the visible tool, hides the panel instead.
    func toggle(_ id: String, focus: (() -> Void)? = nil) {
        if isVisible, selectedID == id { hide() } else { show(id, focus: focus) }
    }

    /// True when `responder` is a view inside the visible panel.
    func contains(_ responder: NSResponder?) -> Bool {
        isVisible && ((responder as? NSView)?.isDescendant(of: view) ?? false)
    }

    /// Selects the next / previous tool tab (wrapping) and focuses it.
    func cycle(_ delta: Int) {
        guard tools.count > 1, let cur = tools.firstIndex(where: { $0.id == selectedID }) else { return }
        let id = tools[(cur + delta + tools.count) % tools.count].id
        show(id) { [weak self] in self?.onFocusTool?(id) }
    }

    /// Hides the panel and returns focus to the editor (what Escape and a tool's own close request do).
    func requestClose() {
        hide()
        onEscape?()
    }

    /// Escape keeps the panel open (like PhpStorm) and hands focus back to the editor.
    private func escapePressed() { onEscape?() }
    @objc private func closeClicked() { requestClose() }
    @objc private func tabClicked(_ b: NSButton) { if let id = b.identifier?.rawValue { show(id) } }
    @objc private func themeChanged() { view.restyle(); restyleButtons() }

    private func select(_ id: String, notify: Bool) {
        guard let tool = tools.first(where: { $0.id == id }) else { return }
        if selectedID != id || tool.view.superview !== view.content {
            view.content.subviews.forEach { $0.removeFromSuperview() }
            tool.view.translatesAutoresizingMaskIntoConstraints = false
            view.content.addSubview(tool.view)
            NSLayoutConstraint.activate([
                tool.view.topAnchor.constraint(equalTo: view.content.topAnchor),
                tool.view.bottomAnchor.constraint(equalTo: view.content.bottomAnchor),
                tool.view.leadingAnchor.constraint(equalTo: view.content.leadingAnchor),
                tool.view.trailingAnchor.constraint(equalTo: view.content.trailingAnchor),
            ])
        }
        selectedID = id
        restyleButtons()
    }

    private func restyleButtons() {
        for tool in tools {
            guard let b = buttons[tool.id] else { continue }
            let selected = tool.id == selectedID
            let text = NSMutableAttributedString(string: tool.title, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: selected ? .semibold : .regular),
                .foregroundColor: selected ? Theme.foreground : Theme.gutter])
            if let badge = tool.badge {
                text.append(NSAttributedString(string: "  " + badge, attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: NSColor.controlAccentColor]))
            }
            b.attributedTitle = text
            b.layer?.backgroundColor = selected ? Theme.palette.tabSelected.cgColor : nil
        }
    }
}
