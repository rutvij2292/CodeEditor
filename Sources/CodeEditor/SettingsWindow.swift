import AppKit

/// The Settings window (Cmd-,): an NSWindow with a toolbar of tabs. Panes are built lazily (only the selected tab's view exists)
/// and the whole window is released when it closes, so closed Settings cost ~nothing.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    static let contentSize = NSSize(width: 720, height: 520)
    private static let lastTabKey = "settings.lastTab"
    private static let frameName = "SettingsWindow"

    private(set) var window: NSWindow?
    private var tabs: NSTabViewController?

    struct PaneSpec {
        let title: String
        let symbol: String
        let make: () -> SettingsPane
    }

    static let panes: [PaneSpec] = [
        PaneSpec(title: "General", symbol: "gearshape", make: { GeneralPane() }),
        PaneSpec(title: "Editor", symbol: "textformat", make: { EditorSettingsPane() }),
        PaneSpec(title: "Languages", symbol: "chevron.left.forwardslash.chevron.right", make: { LanguagesPane() }),
        PaneSpec(title: "Terminal", symbol: "terminal", make: { TerminalPane() }),
        PaneSpec(title: "Keymap", symbol: "keyboard", make: { KeymapPane() }),
        PaneSpec(title: "About", symbol: "info.circle", make: { AboutPane() }),
    ]

    /// Shows (creating if needed) the Settings window. Never shows anything in headless verification runs.
    func show(pane: String? = nil) {
        guard !AppEnv.headless else { return }
        let w = makeWindow(selecting: pane)
        if !w.isVisible, !w.setFrameUsingName(Self.frameName) { w.center() }
        w.setFrameAutosaveName(Self.frameName)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Builds the window (not shown). `pane` is a pane title; default is the last used tab.
    @discardableResult
    func makeWindow(selecting pane: String? = nil) -> NSWindow {
        if let window {
            if let pane, let i = Self.panes.firstIndex(where: { $0.title == pane }) { tabs?.selectedTabViewItemIndex = i }
            return window
        }
        let tvc = SettingsTabController()
        tvc.tabStyle = .toolbar
        for spec in Self.panes {
            let vc = spec.make()
            vc.title = spec.title
            vc.preferredContentSize = Self.contentSize
            let item = NSTabViewItem(viewController: vc)
            item.label = spec.title
            item.image = NSImage(systemSymbolName: spec.symbol, accessibilityDescription: spec.title)
            tvc.addTabViewItem(item)
        }
        var index = UserDefaults.standard.integer(forKey: Self.lastTabKey)
        if let pane, let i = Self.panes.firstIndex(where: { $0.title == pane }) { index = i }
        tvc.selectedTabViewItemIndex = min(max(0, index), Self.panes.count - 1)
        let w = NSWindow(contentViewController: tvc)
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.title = Self.panes[tvc.selectedTabViewItemIndex].title
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.setContentSize(Self.contentSize)
        w.setAccessibilityLabel("Settings")
        tabs = tvc
        window = w
        return w
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window?.contentViewController = nil
        tabs = nil
        window = nil
    }

    /// For tests: drops the window without showing it.
    func discard() { windowWillClose(Notification(name: NSWindow.willCloseNotification)) }

    final class SettingsTabController: NSTabViewController {
        override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
            super.tabView(tabView, didSelect: tabViewItem)
            if !AppEnv.headless { UserDefaults.standard.set(selectedTabViewItemIndex, forKey: SettingsWindowController.lastTabKey) }
        }
    }
}

// MARK: - Pane base class and form helpers

/// Closure-backed control target.
final class SettingsAction: NSObject {
    let handler: (NSControl) -> Void
    init(_ handler: @escaping (NSControl) -> Void) { self.handler = handler }
    @objc func fire(_ sender: Any?) { if let c = sender as? NSControl { handler(c) } }
}

private final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// Base class: a scrolling vertical form. Subclasses override `build()` and use the helpers to add rows; every helper registers a
/// refresher so controls re-read their value when any preference changes.
class SettingsPane: NSViewController {
    static let labelWidth: CGFloat = 190
    let stack = NSStackView()
    private var actions: [SettingsAction] = []
    private var refreshers: [() -> Void] = []
    private var tokens: [NSObjectProtocol] = []

    /// Notifications that make controls re-read their values.
    var observedNotifications: [Notification.Name] { [Prefs.didChange, Theme.didChange, AutoSave.didChange, TerminalPanelController.settingsDidChange] }

    override func loadView() {
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: SettingsWindowController.contentSize))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: doc.topAnchor), stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor), stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        view = scroll
        build()
        for name in observedNotifications {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        }
        refresh()
    }

    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }

    func build() {}
    func restoreDefaults() {}

    func refresh() { refreshers.forEach { $0() } }
    func onRefresh(_ f: @escaping () -> Void) { refreshers.append(f) }
    func action(_ handler: @escaping (NSControl) -> Void) -> SettingsAction {
        let a = SettingsAction(handler)
        actions.append(a)
        return a
    }

    // MARK: Layout helpers

    var rowWidth: CGFloat { SettingsWindowController.contentSize.width - 48 }

    func section(_ title: String) {
        let l = NSTextField(labelWithString: title)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.setAccessibilityRole(.staticText)
        if !stack.arrangedSubviews.isEmpty { stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!) }
        stack.addArrangedSubview(l)
        stack.setCustomSpacing(8, after: l)
    }

    func note(_ text: String, indent: Bool = true) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.preferredMaxLayoutWidth = rowWidth - (indent ? SettingsPane.labelWidth + 10 : 0)
        return l
    }

    /// A row: right-aligned label column + control column (optional help under the control).
    @discardableResult
    func row(_ label: String?, _ control: NSView, help: String? = nil) -> NSStackView {
        let left = NSTextField(labelWithString: label.map { $0 + ":" } ?? "")
        left.alignment = .right
        left.translatesAutoresizingMaskIntoConstraints = false
        left.widthAnchor.constraint(equalToConstant: Self.labelWidth).isActive = true
        left.setContentHuggingPriority(.required, for: .horizontal)
        var right: NSView = control
        if let help {
            let v = NSStackView(views: [control, note(help, indent: true)])
            v.orientation = .vertical
            v.alignment = .leading
            v.spacing = 4
            right = v
        }
        let r = NSStackView(views: [left, right])
        r.orientation = .horizontal
        r.alignment = .firstBaseline
        r.spacing = 10
        stack.addArrangedSubview(r)
        return r
    }

    func fullWidth(_ v: NSView) {
        stack.addArrangedSubview(v)
        v.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
    }

    func restoreButton() {
        let b = NSButton(title: "Restore Defaults", target: nil, action: nil)
        b.target = action { [weak self] _ in self?.restoreDefaults(); self?.refresh() }
        b.action = #selector(SettingsAction.fire(_:))
        b.setAccessibilityLabel("Restore Defaults for this pane")
        stack.setCustomSpacing(24, after: stack.arrangedSubviews.last ?? b)
        let spacer = NSView()
        let r = NSStackView(views: [spacer, b])
        r.orientation = .horizontal
        stack.addArrangedSubview(r)
        r.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
    }

    // MARK: Controls

    func button(_ title: String, _ handler: @escaping () -> Void) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.target = action { _ in handler() }
        b.action = #selector(SettingsAction.fire(_:))
        b.bezelStyle = .rounded
        return b
    }

    @discardableResult
    func checkbox(_ title: String, label: String? = nil, help: String? = nil, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.target = action { c in set((c as? NSButton)?.state == .on) }
        b.action = #selector(SettingsAction.fire(_:))
        b.setAccessibilityLabel(title)
        onRefresh { b.state = get() ? .on : .off }
        row(label, b, help: help)
        return b
    }

    func popupControl(_ items: [String], get: @escaping () -> Int, set: @escaping (Int) -> Void, width: CGFloat = 200, label: String) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.addItems(withTitles: items)
        p.target = action { c in set((c as? NSPopUpButton)?.indexOfSelectedItem ?? 0) }
        p.action = #selector(SettingsAction.fire(_:))
        p.translatesAutoresizingMaskIntoConstraints = false
        p.widthAnchor.constraint(greaterThanOrEqualToConstant: width).isActive = true
        p.setAccessibilityLabel(label)
        onRefresh { let i = get(); if i >= 0, i < p.numberOfItems { p.selectItem(at: i) } }
        return p
    }

    func popup(_ label: String, _ items: [String], help: String? = nil, get: @escaping () -> Int, set: @escaping (Int) -> Void) {
        row(label, popupControl(items, get: get, set: set, label: label), help: help)
    }

    /// Numeric field with a stepper (and optional slider). Invalid text reverts; out-of-range values are clamped.
    func numberControl(range: ClosedRange<Double>, step: Double, decimals: Int = 0, unit: String? = nil, slider: Bool = false, label: String,
                       get: @escaping () -> Double, set: @escaping (Double) -> Void) -> NSView {
        let field = NSTextField(string: "")
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 64).isActive = true
        field.setAccessibilityLabel(label)
        let stepper = NSStepper()
        stepper.minValue = range.lowerBound; stepper.maxValue = range.upperBound; stepper.increment = step
        stepper.valueWraps = false
        stepper.setAccessibilityLabel(label + " stepper")
        let sl = NSSlider(value: range.lowerBound, minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        sl.translatesAutoresizingMaskIntoConstraints = false
        sl.widthAnchor.constraint(equalToConstant: 160).isActive = true
        sl.setAccessibilityLabel(label + " slider")
        func fmt(_ v: Double) -> String { String(format: "%.\(decimals)f", v) }
        func commit(_ v: Double) {
            let clamped = min(range.upperBound, max(range.lowerBound, v))
            let q = decimals == 0 ? clamped.rounded() : (clamped * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
            set(q)
        }
        field.target = action { [weak self] c in
            let text = (c as? NSTextField)?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
            if let v = Double(text) { commit(v) } else { NSSound.beep() }
            self?.refresh()     // revert invalid input / show the clamped value
        }
        field.action = #selector(SettingsAction.fire(_:))
        stepper.target = action { c in commit((c as? NSStepper)?.doubleValue ?? 0) }
        stepper.action = #selector(SettingsAction.fire(_:))
        sl.target = action { c in commit((c as? NSSlider)?.doubleValue ?? 0) }
        sl.action = #selector(SettingsAction.fire(_:))
        onRefresh {
            let v = get()
            field.stringValue = fmt(v); stepper.doubleValue = v; sl.doubleValue = v
        }
        var views: [NSView] = []
        if slider { views.append(sl) }
        views += [field, stepper]
        if let unit { views.append(NSTextField(labelWithString: unit)) }
        let h = NSStackView(views: views)
        h.orientation = .horizontal
        h.alignment = .centerY
        h.spacing = 6
        return h
    }

    func number(_ label: String, range: ClosedRange<Double>, step: Double, decimals: Int = 0, unit: String? = nil, slider: Bool = false,
                help: String? = nil, get: @escaping () -> Double, set: @escaping (Double) -> Void) {
        row(label, numberControl(range: range, step: step, decimals: decimals, unit: unit, slider: slider, label: label, get: get, set: set), help: help)
    }

    func textField(width: CGFloat = 300, placeholder: String = "", label: String, get: @escaping () -> String, set: @escaping (String) -> Void) -> NSTextField {
        let f = NSTextField(string: "")
        f.placeholderString = placeholder
        f.translatesAutoresizingMaskIntoConstraints = false
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        f.setAccessibilityLabel(label)
        f.target = action { c in set((c as? NSTextField)?.stringValue ?? "") }
        f.action = #selector(SettingsAction.fire(_:))
        onRefresh { if f.currentEditor() == nil { f.stringValue = get() } }
        return f
    }

    func infoLabel(_ get: @escaping () -> String, color: @escaping () -> NSColor = { .secondaryLabelColor }) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: "")
        l.font = .systemFont(ofSize: 12)
        l.isSelectable = true
        l.preferredMaxLayoutWidth = rowWidth - SettingsPane.labelWidth - 10
        onRefresh { l.stringValue = get(); l.textColor = color() }
        return l
    }

    func confirm(_ message: String, detail: String, button: String) -> Bool {
        guard !AppEnv.headless else { return false }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
