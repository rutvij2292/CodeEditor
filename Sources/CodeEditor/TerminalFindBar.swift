import AppKit

/// Small floating find bar for the terminal panel (Cmd-F). Created on first use and released on close.
final class TerminalFindBar: NSView, NSTextFieldDelegate {
    static let size = NSSize(width: 340, height: 28)

    let field = NSTextField()
    private let count = NSTextField(labelWithString: "")
    private let caseButton = NSButton()
    /// query, caseSensitive: the text or options changed (restart the search from the top of the screen).
    var onChange: ((String, Bool) -> Void)?
    /// forward?, query, caseSensitive
    var onStep: ((Bool, String, Bool) -> Void)?
    var onClose: (() -> Void)?

    var countText: String { count.stringValue }
    func setCaseSensitive(_ on: Bool) { caseButton.state = on ? .on : .off }
    var query: String { field.stringValue }
    var caseSensitive: Bool { caseButton.state == .on }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        field.placeholderString = "Find in terminal"
        field.font = .systemFont(ofSize: 12)
        field.delegate = self
        field.focusRingType = .none
        field.setAccessibilityLabel("Find in terminal")
        count.font = .systemFont(ofSize: 11)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        caseButton.setButtonType(.pushOnPushOff)
        caseButton.bezelStyle = .texturedRounded
        caseButton.title = "Aa"
        caseButton.font = .systemFont(ofSize: 11)
        caseButton.toolTip = "Match case"
        caseButton.target = self; caseButton.action = #selector(caseToggled)
        let prev = button("chevron.up", "Previous match", #selector(prevTapped))
        let next = button("chevron.down", "Next match", #selector(nextTapped))
        let close = button("xmark", "Close (Esc)", #selector(closeTapped))
        for v in [field, count, caseButton, prev, next, close] { addSubview(v) }
        field.frame = NSRect(x: 8, y: 4, width: 130, height: 20)
        count.frame = NSRect(x: 142, y: 6, width: 60, height: 16)
        caseButton.frame = NSRect(x: 204, y: 3, width: 32, height: 22)
        prev.frame = NSRect(x: 240, y: 3, width: 24, height: 22)
        next.frame = NSRect(x: 266, y: 3, width: 24, height: 22)
        close.frame = NSRect(x: 304, y: 3, width: 24, height: 22)
        applyColors()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton()
        b.isBordered = false
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.target = self; b.action = action
        return b
    }

    private func applyColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.97).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); applyColors() }

    func setCount(_ text: String, found: Bool) {
        count.stringValue = text
        count.textColor = found ? .secondaryLabelColor : .systemRed
    }

    func focus() {
        window?.makeFirstResponder(field)
        field.selectText(nil)
    }

    @objc private func caseToggled() { onChange?(query, caseSensitive) }
    @objc private func prevTapped() { onStep?(false, query, caseSensitive) }
    @objc private func nextTapped() { onStep?(true, query, caseSensitive) }
    @objc private func closeTapped() { onClose?() }

    func controlTextDidChange(_ obj: Notification) { onChange?(query, caseSensitive) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.insertNewline(_:)):
            onStep?(!(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false), query, caseSensitive); return true
        case #selector(NSResponder.cancelOperation(_:)): onClose?(); return true
        default: return false
        }
    }
}
