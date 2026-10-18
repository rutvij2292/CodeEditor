import AppKit

/// The single small "New Branch" sheet (also used, name field only, for Rename): live ref-name validation, start point
/// combo (defaults to the current branch; accepts branches, tags or a commit), "Checkout after creating", "Overwrite if exists".
final class NewBranchSheet: NSObject, NSTextFieldDelegate, NSComboBoxDelegate {
    struct Result { var name: String; var start: String?; var checkout: Bool; var overwrite: Bool }

    private static var current: NewBranchSheet?
    static var isShown: Bool { current != nil }

    // Test hooks.
    static func setName(_ s: String) { current?.nameField.stringValue = s; current?.validate() }
    static func setOverwrite(_ on: Bool) { current?.overwrite.state = on ? .on : .off; current?.validate() }
    static func setCheckout(_ on: Bool) { current?.checkout.state = on ? .on : .off }
    static func setStart(_ s: String) { current?.startCombo.stringValue = s }
    static var message: String { current?.message.stringValue ?? "" }
    static var createEnabled: Bool { current?.createButton.isEnabled ?? false }
    static func submit() { current?.create() }
    static func cancel() { current?.finish() }
    static func snapshot(to path: String) { if let v = current?.panel.contentView?.superview { Verification.render(v, to: path) } }

    /// `submit` runs the git work (off the main thread) and calls back with an error message, or nil on success.
    static func presentNew(over window: NSWindow, startItems: [String], defaultStart: String, startLabel: String,
                           existing: Set<String>, initialName: String = "",
                           submit: @escaping (Result, @escaping (String?) -> Void) -> Void) {
        let s = NewBranchSheet(title: "New Branch", existing: existing, startItems: startItems, defaultStart: defaultStart,
                               startLabel: startLabel, rename: false, initialName: initialName) { r, done in submit(r, done) }
        current = s
        s.present(over: window)
    }

    static func presentRename(over window: NSWindow, old: String, existing: Set<String>,
                              submit: @escaping (String, @escaping (String?) -> Void) -> Void) {
        let s = NewBranchSheet(title: "Rename Branch “\(old)”", existing: existing.subtracting([old]), startItems: [], defaultStart: "",
                               startLabel: "", rename: true, initialName: old) { r, done in submit(r.name, done) }
        current = s
        s.present(over: window)
    }

    private let existing: Set<String>
    private let rename: Bool
    private let onSubmit: (Result, @escaping (String?) -> Void) -> Void
    private let panel: NSPanel
    private let nameField = NSTextField()
    private let startCombo = NSComboBox()
    private let checkout = NSButton(checkboxWithTitle: "Checkout after creating", target: nil, action: nil)
    private let overwrite = NSButton(checkboxWithTitle: "Overwrite if exists", target: nil, action: nil)
    private let message = NSTextField(labelWithString: "")
    private let createButton: NSButton
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private weak var parent: NSWindow?
    private var busy = false

    private init(title: String, existing: Set<String>, startItems: [String], defaultStart: String, startLabel: String,
                 rename: Bool, initialName: String, submit: @escaping (Result, @escaping (String?) -> Void) -> Void) {
        self.existing = existing
        self.rename = rename
        self.onSubmit = submit
        createButton = NSButton(title: rename ? "Rename" : "Create", target: nil, action: nil)
        let w: CGFloat = 460
        let h: CGFloat = rename ? 128 : 236
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        panel.title = title
        panel.appearance = NSApp.appearance
        panel.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        panel.contentView = root
        var y = h - 20
        func label(_ t: String) -> NSTextField {
            let l = NSTextField(labelWithString: t)
            l.font = .systemFont(ofSize: 11, weight: .medium); l.textColor = .secondaryLabelColor
            return l
        }
        let nl = label(rename ? "New name" : "Branch name")
        nl.frame = NSRect(x: 20, y: y - 14, width: w - 40, height: 14); root.addSubview(nl); y -= 18
        nameField.frame = NSRect(x: 20, y: y - 24, width: w - 40, height: 24)
        nameField.placeholderString = "feature/my-branch"
        nameField.stringValue = initialName
        nameField.delegate = self
        root.addSubview(nameField); y -= 28
        message.frame = NSRect(x: 20, y: y - 16, width: w - 40, height: 16)
        message.font = .systemFont(ofSize: 11)
        message.lineBreakMode = .byTruncatingTail
        root.addSubview(message); y -= 24
        if !rename {
            let sl = label("Start from")
            sl.frame = NSRect(x: 20, y: y - 14, width: w - 40, height: 14); root.addSubview(sl); y -= 18
            startCombo.frame = NSRect(x: 20, y: y - 26, width: w - 40, height: 26)
            startCombo.addItems(withObjectValues: startItems)
            startCombo.stringValue = defaultStart
            startCombo.completes = true
            startCombo.numberOfVisibleItems = 12
            startCombo.toolTip = "A branch, tag or commit hash. Default: \(startLabel)"
            startCombo.delegate = self
            root.addSubview(startCombo); y -= 34
            checkout.state = .on
            checkout.frame = NSRect(x: 20, y: y - 18, width: w - 40, height: 18); root.addSubview(checkout); y -= 22
            overwrite.state = .off
            overwrite.target = self; overwrite.action = #selector(optionChanged)
            overwrite.frame = NSRect(x: 20, y: y - 18, width: w - 40, height: 18); root.addSubview(overwrite)
        }
        createButton.bezelStyle = .rounded; createButton.keyEquivalent = "\r"
        createButton.target = self; createButton.action = #selector(createTapped)
        cancelButton.bezelStyle = .rounded; cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self; cancelButton.action = #selector(cancelTapped)
        createButton.frame = NSRect(x: w - 20 - 86, y: 14, width: 86, height: 28)
        cancelButton.frame = NSRect(x: w - 20 - 86 - 8 - 80, y: 14, width: 80, height: 28)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
        spinner.frame = NSRect(x: 20, y: 20, width: 16, height: 16)
        for v in [createButton, cancelButton, spinner] { root.addSubview(v) }
        panel.initialFirstResponder = nameField
        validate()
    }

    private func present(over window: NSWindow) {
        parent = window
        if AppEnv.headless {
            // never show a visible window in headless runs; the content still lays out for snapshots
            panel.contentView?.layoutSubtreeIfNeeded()
            return
        }
        window.beginSheet(panel) { _ in }
        panel.makeFirstResponder(nameField)
    }

    private func finish() {
        if let p = parent, !AppEnv.headless { p.endSheet(panel) }
        panel.orderOut(nil)
        if Self.current === self { Self.current = nil }
    }

    private var name: String { nameField.stringValue.trimmingCharacters(in: .whitespaces) }

    private func validate() {
        let n = name
        var text = "", color = NSColor.secondaryLabelColor, ok = true
        if n.isEmpty { ok = false }
        else if let problem = GitRefName.validate(n) { text = problem; color = .systemRed; ok = false }
        else if existing.contains(n) {
            if !rename, overwrite.state == .on { text = "“\(n)” exists and will be reset to the start point."; color = .systemOrange }
            else { text = "“\(n)” already exists" + (rename ? "." : " — tick Overwrite to reset it."); color = .systemRed; ok = false }
        }
        message.stringValue = text
        message.textColor = color
        createButton.isEnabled = ok && !busy
    }

    @objc private func optionChanged() { validate() }
    func controlTextDidChange(_ obj: Notification) { validate() }
    func comboBoxSelectionDidChange(_ notification: Notification) { validate() }
    @objc private func cancelTapped() { if !busy { finish() } }
    @objc private func createTapped() { create() }

    fileprivate func create() {
        guard createButton.isEnabled, !busy else { return }
        busy = true
        spinner.startAnimation(nil)
        createButton.isEnabled = false
        let start = startCombo.stringValue.trimmingCharacters(in: .whitespaces)
        let result = Result(name: name, start: start.isEmpty ? nil : start, checkout: checkout.state == .on, overwrite: overwrite.state == .on)
        onSubmit(result) { [weak self] error in
            guard let self else { return }
            self.busy = false
            self.spinner.stopAnimation(nil)
            if let error {
                self.message.stringValue = error.split(separator: "\n").first.map(String.init) ?? error
                self.message.textColor = .systemRed
                self.message.toolTip = error
                self.createButton.isEnabled = true
            } else {
                self.finish()
            }
        }
    }
}
