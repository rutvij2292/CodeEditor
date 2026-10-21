import AppKit

// PhpStorm-style floating "Find in Files" / "Replace in Files" popup (Cmd-Shift-F / Cmd-Shift-R).
// Searches through the shared FindEngine (debounced, cancelled on change / close); the bottom Find panel stays the target of
// "Open in Find Window". Everything is created on open and released on close; results are capped and rows are reused lazily.

struct FindPopupHost {
    var root: URL
    var engine: FindEngine
    var openBuffer: (URL) -> EditorTab?
    var openMatch: (FindMatch) -> Void
    var openFilePaths: () -> Set<String>
    /// Hands query + options (+ replacement, mode) to the bottom Find panel and shows it.
    var openInFindWindow: (FindOptions, String?, Bool) -> Void
}

/// Options remembered between popup openings (session memory; mask history persists in UserDefaults).
private struct FindPopupMemory {
    var query = ""
    var replacement = ""
    var caseSensitive = false
    var wholeWord = false
    var regex = false
    var preserveCase = false
    var wrap = false
    var useMask = false
    var mask = ""
    var includeIgnored = false
    var scope = 0                 // 0 project, 1 module, 2 directory, 3 open files
    var directory: URL?
    var pinned = false
    var newTab = false
}

// MARK: - Small views

private final class FindPopupPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    var onEscape: (() -> Void)?
    var onFocus: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
    override func makeFirstResponder(_ r: NSResponder?) -> Bool {
        let ok = super.makeFirstResponder(r)
        onFocus?()
        return ok
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Small flat toggle / tab: text or SF Symbol, accent-tinted when on.
private final class ChipButton: NSButton {
    var isOn = false { didSet { restyle() } }
    var radius: CGFloat = 4
    private let text: String?

    init(text: String? = nil, symbol: String? = nil, tip: String) {
        self.text = text
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        focusRingType = .none
        imagePosition = text == nil ? .imageOnly : .noImage
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        }
        toolTip = tip
        wantsLayer = true
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { false }

    func restyle() {
        layer?.cornerRadius = radius
        layer?.backgroundColor = isOn ? NSColor.controlAccentColor.withAlphaComponent(Theme.isDark ? 0.40 : 0.22).cgColor : NSColor.clear.cgColor
        let color = isOn ? Theme.foreground : Theme.gutter
        contentTintColor = color
        if let text {
            let para = NSMutableParagraphStyle(); para.alignment = .center
            attributedTitle = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold), .foregroundColor: color, .paragraphStyle: para])
        }
    }
}

private final class FindPopupRowBackground: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(Theme.isDark ? 0.38 : 0.26).setFill()
        bounds.fill()
    }
}

private final class FindPopupTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}

private final class FindPopupRowCell: NSView {
    let text = NSTextField(labelWithString: "")
    let loc = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        text.lineBreakMode = .byTruncatingTail
        text.cell?.usesSingleLineMode = true
        loc.lineBreakMode = .byTruncatingHead
        loc.alignment = .right
        loc.font = .systemFont(ofSize: 12)
        addSubview(text); addSubview(loc)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ m: FindMatch, root: URL) {
        let f = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let raw = m.lineText as NSString
        var lead = 0
        while lead < raw.length, [32, 9].contains(raw.character(at: lead)) { lead += 1 }
        let line = raw.substring(from: lead)
        let s = NSMutableAttributedString(string: line, attributes: [.font: f, .foregroundColor: Theme.foreground])
        let start = max(0, m.textOffset - lead)
        let len = min(m.length, max(0, (line as NSString).length - start))
        if len > 0, start < (line as NSString).length {
            let yellow = NSColor(calibratedRed: 1, green: 0.84, blue: 0.2, alpha: Theme.isDark ? 0.40 : 0.75)
            s.addAttribute(.backgroundColor, value: yellow, range: NSRange(location: start, length: len))
        }
        text.attributedStringValue = s
        loc.stringValue = "\(m.url.lastPathComponent) \(m.line)"
        loc.textColor = Theme.gutter
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let lw = min(ceil(loc.attributedStringValue.size().width) + 6, bounds.width * 0.4)
        loc.frame = NSRect(x: bounds.width - lw - 14, y: (h - 16) / 2, width: lw, height: 16)
        text.frame = NSRect(x: 14, y: (h - 17) / 2, width: max(0, loc.frame.minX - 24), height: 17)
    }
}

// MARK: - Popup

final class FindPopup: NSObject, NSTextFieldDelegate, NSComboBoxDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var current: FindPopup?
    private static var memory = FindPopupMemory()
    static let displayCap = 100          // status shows "100+" beyond this
    static let listCap = 1000            // rows kept for the list

    static var isOpen: Bool { current != nil }
    static var isReplaceMode: Bool { current?.replaceMode ?? false }

    /// Opens the popup over `window` (or re-focuses / switches mode when it is already open).
    @discardableResult
    static func present(over window: NSWindow, host: FindPopupHost, seed: String?, replace: Bool) -> FindPopup {
        if let c = current, !c.closed, c.parent === window {
            c.setReplaceMode(replace || c.replaceMode)
            if let seed { c.field.stringValue = seed; c.optionChanged() }
            c.focusQuery()
            return c
        }
        dismiss()
        let p = FindPopup(parent: window, host: host)
        current = p
        p.show(seed: seed, replace: replace)
        return p
    }

    static func dismiss() { current?.close(refocus: true) }
    static var shared: FindPopup? { current }

    static func snapshot(to path: String) {
        guard let v = current?.panel.contentView else { return }
        v.layoutSubtreeIfNeeded()
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    // MARK: state

    private weak var parent: NSWindow?
    private let host: FindPopupHost
    private let panel: FindPopupPanel
    private var closed = false
    private(set) var replaceMode = false
    private var observers: [NSObjectProtocol] = []
    private var token: CancelToken?
    private var debounce: DispatchWorkItem?
    private var generation = 0
    private(set) var results: [FindMatch] = []
    private(set) var truncated = false
    private(set) var searching = false
    private var errorText: String?
    private var note: String?
    private var suspendClose = false
    private var previewCache: (path: String, lines: [Substring])?
    private var previewKey: FindKey?
    private var openPaths: Set<String> = []

    // MARK: views

    private let root = FlippedView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let maskCheck = NSButton(checkboxWithTitle: "File mask:", target: nil, action: nil)
    private let maskField = NSComboBox()
    private let filterButton = ChipButton(symbol: "line.3.horizontal.decrease", tip: "Also search ignored folders (vendor, node_modules, ...)")
    private let pinButton = ChipButton(symbol: "pin", tip: "Keep this popup open when it loses focus")
    private let queryBox = FlippedView()
    private let searchIcon = NSImageView()
    let field = NSTextField()
    private let clearButton = ChipButton(symbol: "xmark.circle.fill", tip: "Clear")
    private let wrapButton = ChipButton(symbol: "text.alignleft", tip: "Wrap long lines in the preview")
    private let caseButton = ChipButton(text: "Cc", tip: "Match case")
    private let wordButton = ChipButton(text: "W", tip: "Words")
    private let regexButton = ChipButton(text: ".*", tip: "Regex")
    private let replaceBox = FlippedView()
    let replaceField = NSTextField()
    private let preserveButton = ChipButton(text: "AA", tip: "Preserve case")
    private var tabs: [ChipButton] = []
    private let dirField = NSTextField()
    private let dirButton = ChipButton(symbol: "folder", tip: "Choose directory")
    private let divider1 = NSView(), divider2 = NSView(), divider3 = NSView()
    private let table = FindPopupTable()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let previewScroll = NSTextView.scrollableTextView()
    private var preview: NSTextView { previewScroll.documentView as! NSTextView }
    private let newTabCheck = NSButton(checkboxWithTitle: "Open results in new tab", target: nil, action: nil)
    private let openWindowButton = NSButton(title: "⌘↵ Open in Find Window", target: nil, action: nil)
    private let replaceAllButton = NSButton(title: "Replace All", target: nil, action: nil)
    private let replaceButton = NSButton(title: "Replace", target: nil, action: nil)

    private static let width: CGFloat = 800
    private static let rowH: CGFloat = 24

    private init(parent: NSWindow, host: FindPopupHost) {
        self.parent = parent
        self.host = host
        panel = FindPopupPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 560),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.contentView = root
        root.wantsLayer = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        root.layer?.borderWidth = 0.5
        panel.onKey = { [weak self] e in self?.handleKey(e) ?? false }
        panel.onEscape = { [weak self] in self?.close(refocus: true) }
        panel.onFocus = { [weak self] in self?.updateFocusRing() }
        build()
        observers.append(NotificationCenter.default.addObserver(forName: Theme.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.restyle(); self?.table.reloadData(); self?.updatePreview(force: true)
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            guard let self, !Self.memory.pinned, !self.suspendClose else { return }
            self.close(refocus: false)
        })
    }

    // MARK: build

    private func build() {
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.lineBreakMode = .byTruncatingTail

        maskCheck.controlSize = .small
        maskCheck.font = .systemFont(ofSize: 12)
        maskCheck.target = self; maskCheck.action = #selector(maskToggled)
        maskField.controlSize = .small
        maskField.font = .systemFont(ofSize: 12)
        maskField.placeholderString = "*.vue, *.php"
        maskField.completes = false
        maskField.numberOfVisibleItems = 8
        maskField.addItems(withObjectValues: Self.maskHistory)
        maskField.delegate = self
        for b in [filterButton, pinButton] { b.target = self }
        filterButton.action = #selector(filterClicked)
        pinButton.action = #selector(pinClicked)

        queryBox.wantsLayer = true
        queryBox.layer?.cornerRadius = 6
        queryBox.layer?.borderWidth = 1
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = "Search"
        field.delegate = self
        field.cell?.isScrollable = true; field.cell?.usesSingleLineMode = true
        clearButton.target = self; clearButton.action = #selector(clearClicked)
        for b in [wrapButton, caseButton, wordButton, regexButton] { b.target = self; b.action = #selector(chipClicked(_:)) }
        for v in [searchIcon, field, clearButton, wrapButton, caseButton, wordButton, regexButton] as [NSView] { queryBox.addSubview(v) }

        replaceBox.wantsLayer = true
        replaceBox.layer?.cornerRadius = 6
        replaceBox.layer?.borderWidth = 1
        replaceField.isBordered = false; replaceField.drawsBackground = false; replaceField.focusRingType = .none
        replaceField.font = .systemFont(ofSize: 14)
        replaceField.placeholderString = "Replace"
        replaceField.delegate = self
        replaceField.cell?.isScrollable = true; replaceField.cell?.usesSingleLineMode = true
        preserveButton.target = self; preserveButton.action = #selector(chipClicked(_:))
        replaceBox.addSubview(replaceField); replaceBox.addSubview(preserveButton)

        for (i, t) in ["In Project", "Module", "Directory", "Scope"].enumerated() {
            let b = ChipButton(text: t, tip: ["Whole project", "Current module (the whole project)", "A chosen folder", "Open files"][i])
            b.radius = 5
            b.tag = i
            b.target = self; b.action = #selector(tabClicked(_:))
            tabs.append(b)
        }
        dirField.font = .systemFont(ofSize: 12)
        dirField.placeholderString = "Directory"
        dirField.bezelStyle = .roundedBezel
        dirField.controlSize = .small
        dirField.delegate = self
        dirButton.target = self; dirButton.action = #selector(chooseDirectory)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        table.addTableColumn(col)
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Self.rowH
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.allowsEmptySelection = true
        table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(doubleClicked)
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.alignment = .center

        pathLabel.font = .systemFont(ofSize: 11.5)
        pathLabel.lineBreakMode = .byTruncatingHead
        previewScroll.hasVerticalScroller = true
        previewScroll.hasHorizontalScroller = true
        previewScroll.autohidesScrollers = true
        previewScroll.drawsBackground = true
        preview.isEditable = false
        preview.isSelectable = false
        preview.textContainerInset = NSSize(width: 6, height: 4)

        newTabCheck.controlSize = .small; newTabCheck.font = .systemFont(ofSize: 12)
        newTabCheck.target = self; newTabCheck.action = #selector(newTabToggled)
        openWindowButton.target = self; openWindowButton.action = #selector(openInWindowClicked)
        openWindowButton.bezelStyle = .rounded; openWindowButton.controlSize = .regular
        replaceAllButton.target = self; replaceAllButton.action = #selector(replaceAllClicked)
        replaceAllButton.bezelStyle = .rounded
        replaceButton.target = self; replaceButton.action = #selector(replaceClicked)
        replaceButton.bezelStyle = .rounded
        replaceButton.keyEquivalent = "\r"
        replaceButton.isBordered = false
        replaceButton.wantsLayer = true
        replaceButton.layer?.cornerRadius = 6
        replaceButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        replaceButton.attributedTitle = NSAttributedString(string: "Replace", attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 13)])

        for v in [titleLabel, statusLabel, maskCheck, maskField, filterButton, pinButton, queryBox, replaceBox, dirField, dirButton,
                  divider1, divider2, divider3, scroll, emptyLabel, pathLabel, previewScroll, newTabCheck, openWindowButton,
                  replaceAllButton, replaceButton] as [NSView] { root.addSubview(v) }
        for t in tabs { root.addSubview(t) }
        restyle()
    }

    private func restyle() {
        root.layer?.backgroundColor = Theme.background.cgColor
        root.layer?.borderColor = Theme.gutter.withAlphaComponent(0.45).cgColor
        for d in [divider1, divider2, divider3] { d.wantsLayer = true; d.layer?.backgroundColor = Theme.gutter.withAlphaComponent(0.28).cgColor }
        titleLabel.textColor = Theme.foreground
        statusLabel.textColor = Theme.gutter
        maskCheck.attributedTitle = NSAttributedString(string: "File mask:", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.foreground])
        newTabCheck.attributedTitle = NSAttributedString(string: "Open results in new tab", attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.foreground])
        searchIcon.contentTintColor = Theme.gutter
        field.textColor = Theme.foreground
        replaceField.textColor = Theme.foreground
        field.placeholderAttributedString = NSAttributedString(string: "Search", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: Theme.gutter])
        replaceField.placeholderAttributedString = NSAttributedString(string: "Replace", attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: Theme.gutter])
        dirField.textColor = Theme.foreground
        emptyLabel.textColor = Theme.gutter
        pathLabel.textColor = Theme.gutter
        previewScroll.backgroundColor = Theme.background
        preview.backgroundColor = Theme.background
        for c in [filterButton, pinButton, clearButton, wrapButton, caseButton, wordButton, regexButton, preserveButton, dirButton] + tabs { c.restyle() }
        updateFocusRing()
    }

    private func updateFocusRing() {
        let fr = panel.firstResponder
        func focused(_ f: NSTextField) -> Bool { (fr as? NSText)?.delegate === f || fr === f }
        let accent = NSColor.controlAccentColor
        let idle = Theme.gutter.withAlphaComponent(0.45)
        queryBox.layer?.borderColor = (errorText != nil ? NSColor.systemRed : focused(field) ? accent : idle).cgColor
        queryBox.layer?.borderWidth = focused(field) || errorText != nil ? 2 : 1
        replaceBox.layer?.borderColor = (focused(replaceField) ? accent : idle).cgColor
        replaceBox.layer?.borderWidth = focused(replaceField) ? 2 : 1
    }

    // MARK: show / close

    private func show(seed: String?, replace: Bool) {
        guard let parent else { return }
        let m = Self.memory
        field.stringValue = seed ?? m.query
        replaceField.stringValue = m.replacement
        caseButton.isOn = m.caseSensitive; wordButton.isOn = m.wholeWord; regexButton.isOn = m.regex
        preserveButton.isOn = m.preserveCase; wrapButton.isOn = m.wrap
        maskCheck.state = m.useMask ? .on : .off
        maskField.stringValue = m.mask
        maskField.isEnabled = m.useMask
        filterButton.isOn = m.includeIgnored
        pinButton.isOn = m.pinned
        newTabCheck.state = m.newTab ? .on : .off
        dirField.stringValue = (m.directory ?? host.root).path
        selectTab(m.scope, search: false)
        replaceMode = false
        setReplaceMode(replace)
        parent.addChildWindow(panel, ordered: .above)
        if !AppEnv.headless { panel.makeKeyAndOrderFront(nil) }
        focusQuery()
        restyle()
        optionChanged()
    }

    func focusQuery() {
        panel.makeFirstResponder(field)
        if let ed = field.currentEditor() { ed.selectedRange = NSRange(location: 0, length: (field.stringValue as NSString).length) }
    }

    private func saveMemory() {
        Self.memory = FindPopupMemory(
            query: field.stringValue, replacement: replaceField.stringValue,
            caseSensitive: caseButton.isOn, wholeWord: wordButton.isOn, regex: regexButton.isOn, preserveCase: preserveButton.isOn,
            wrap: wrapButton.isOn, useMask: maskCheck.state == .on, mask: maskField.stringValue, includeIgnored: filterButton.isOn,
            scope: scopeIndex, directory: directoryURL, pinned: pinButton.isOn, newTab: newTabCheck.state == .on)
    }

    private func close(refocus: Bool) {
        guard !closed else { return }
        closed = true
        saveMemory()
        recordMaskHistory()
        debounce?.cancel(); token?.cancel(); token = nil
        generation += 1
        if Self.current === self { Self.current = nil }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        let parent = self.parent
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if (refocus || parent?.isKeyWindow == false), !AppEnv.headless { parent?.makeKey() }
        field.delegate = nil; replaceField.delegate = nil; maskField.delegate = nil; dirField.delegate = nil
        table.dataSource = nil; table.delegate = nil
        results = []; previewCache = nil; previewKey = nil
        preview.textStorage?.setAttributedString(NSAttributedString())
    }

    // MARK: modes / scope

    private(set) var scopeIndex = 0
    private var directoryURL: URL? {
        scopeIndex == 2 ? URL(fileURLWithPath: (dirField.stringValue as NSString).expandingTildeInPath, isDirectory: true) : nil
    }

    func setReplaceMode(_ on: Bool) {
        replaceMode = on
        titleLabel.stringValue = on ? "Replace in Files" : "Find in Files"
        for v in [replaceBox, replaceAllButton, replaceButton] as [NSView] { v.isHidden = !on }
        layoutAll()
        updateButtons()
    }

    private func selectTab(_ i: Int, search: Bool = true) {
        scopeIndex = i
        for t in tabs { t.isOn = t.tag == i }
        dirField.isHidden = i != 2; dirButton.isHidden = i != 2
        layoutAll()
        if search { optionChanged() }
    }

    @objc private func tabClicked(_ b: ChipButton) { selectTab(b.tag) }

    @objc private func chooseDirectory() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.directoryURL = URL(fileURLWithPath: dirField.stringValue)
        p.prompt = "Search Here"
        suspendClose = true
        p.beginSheetModal(for: panel) { [weak self] r in
            guard let self else { return }
            self.suspendClose = false
            if r == .OK, let u = p.url { self.dirField.stringValue = u.path; self.optionChanged() }
        }
    }

    // MARK: layout

    private var panelHeight: CGFloat { replaceMode ? 610 : 570 }

    private func layoutAll() {
        guard !closed else { return }
        let w = Self.width
        let h = panelHeight
        if let parent {
            let pf = parent.frame
            let frame = NSRect(x: pf.midX - w / 2, y: pf.maxY - 70 - h, width: w, height: h)
            panel.setFrame(frame, display: false)
        }
        root.frame = NSRect(x: 0, y: 0, width: w, height: h)
        // header
        titleLabel.sizeToFit()
        titleLabel.frame.origin = NSPoint(x: 16, y: 13)
        var rx = w - 14
        pinButton.frame = NSRect(x: rx - 26, y: 10, width: 26, height: 24); rx -= 30
        filterButton.frame = NSRect(x: rx - 26, y: 10, width: 26, height: 24); rx -= 34
        maskField.frame = NSRect(x: rx - 150, y: 11, width: 150, height: 22); rx -= 154
        maskCheck.sizeToFit()
        maskCheck.frame.origin = NSPoint(x: rx - maskCheck.frame.width, y: 12); rx = maskCheck.frame.minX - 10
        statusLabel.frame = NSRect(x: titleLabel.frame.maxX + 12, y: 14, width: max(40, rx - titleLabel.frame.maxX - 16), height: 16)
        // query
        var y: CGFloat = 46
        queryBox.frame = NSRect(x: 14, y: y, width: w - 28, height: 36)
        layoutBox(queryBox, trailing: [regexButton, wordButton, caseButton, wrapButton], leading: searchIcon, field: field, clear: clearButton)
        y += 42
        if replaceMode {
            replaceBox.frame = NSRect(x: 14, y: y, width: w - 28, height: 36)
            let bw = replaceBox.bounds.width
            preserveButton.frame = NSRect(x: bw - 36, y: 6, width: 28, height: 24)
            replaceField.frame = NSRect(x: 12, y: 8, width: bw - 56, height: 20)
            y += 42
        }
        // tabs
        var tx: CGFloat = 14
        for t in tabs {
            let tw = ceil((t.attributedTitle.size().width)) + 22
            t.frame = NSRect(x: tx, y: y + 2, width: tw, height: 24); tx += tw + 4
        }
        dirButton.frame = NSRect(x: w - 14 - 26, y: y + 2, width: 26, height: 24)
        dirField.frame = NSRect(x: tx + 10, y: y + 3, width: w - 14 - 30 - tx - 10, height: 22)
        y += 32
        divider1.frame = NSRect(x: 0, y: y, width: w, height: 1)
        // results / preview / footer
        let footerH: CGFloat = 48
        let resultsH: CGFloat = 206
        scroll.frame = NSRect(x: 0, y: y + 1, width: w, height: resultsH)
        emptyLabel.frame = NSRect(x: 0, y: y + 1 + (resultsH - 18) / 2, width: w, height: 18)
        table.tableColumns[0].width = w
        y += 1 + resultsH
        divider2.frame = NSRect(x: 0, y: y, width: w, height: 1)
        pathLabel.frame = NSRect(x: 14, y: y + 5, width: w - 28, height: 16)
        y += 26
        previewScroll.frame = NSRect(x: 0, y: y, width: w, height: h - footerH - y - 1)
        divider3.frame = NSRect(x: 0, y: h - footerH - 1, width: w, height: 1)
        let fy = h - footerH + 11
        newTabCheck.sizeToFit()
        newTabCheck.frame.origin = NSPoint(x: 14, y: fy + 4)
        var bx = w - 14
        let ow: CGFloat = 188
        openWindowButton.frame = NSRect(x: bx - ow, y: fy, width: ow, height: 28); bx -= ow + 8
        if replaceMode {
            replaceButton.frame = NSRect(x: bx - 84, y: fy, width: 84, height: 28); bx -= 92
            replaceAllButton.frame = NSRect(x: bx - 100, y: fy, width: 100, height: 28)
        }
        root.layoutSubtreeIfNeeded()
        updateFocusRing()
    }

    private func layoutBox(_ box: NSView, trailing: [NSView], leading: NSView, field: NSTextField, clear: NSView) {
        let bw = box.bounds.width
        leading.frame = NSRect(x: 10, y: 10, width: 16, height: 16)
        var x = bw - 8
        for b in trailing {
            let bwid: CGFloat = (b === wrapButton) ? 26 : 28
            b.frame = NSRect(x: x - bwid, y: 6, width: bwid, height: 24); x -= bwid + 2
        }
        clear.frame = NSRect(x: x - 22, y: 8, width: 20, height: 20); x -= 26
        field.frame = NSRect(x: 34, y: 8, width: max(60, x - 34), height: 20)
    }

    // MARK: options / searching

    var currentOptions: FindOptions {
        var o = FindOptions(query: field.stringValue)
        o.caseSensitive = caseButton.isOn
        o.wholeWord = wordButton.isOn
        o.isRegex = regexButton.isOn
        o.preserveCase = preserveButton.isOn
        o.includeIgnored = filterButton.isOn
        o.fileMask = maskCheck.state == .on ? maskField.stringValue : ""
        if scopeIndex == 2 {
            let u = URL(fileURLWithPath: (dirField.stringValue as NSString).expandingTildeInPath, isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue { o.directory = u }
        }
        return o
    }

    private func optionChanged() { scheduleSearch(immediately: true) }

    private func scheduleSearch(immediately: Bool) {
        debounce?.cancel()
        if immediately { startSearch(); return }
        let item = DispatchWorkItem { [weak self] in self?.startSearch() }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func inScope(_ m: FindMatch) -> Bool { scopeIndex != 3 || openPaths.contains(m.url.standardizedFileURL.path) || openPaths.contains(m.url.path) }

    private func startSearch() {
        token?.cancel(); token = nil
        generation += 1
        let gen = generation
        results = []; truncated = false; errorText = nil; note = nil
        previewKey = nil
        if scopeIndex == 3 { openPaths = host.openFilePaths() }
        table.reloadData()
        let o = currentOptions
        guard !o.query.isEmpty else { searching = false; refreshChrome(); DispatchQueue.main.async { [weak self] in self?.onSearchDone?() }; return }
        if o.isRegex, let err = FindEngine.validate(o) {
            errorText = err; searching = false; refreshChrome()
            DispatchQueue.main.async { [weak self] in self?.onSearchDone?() }
            return
        }
        searching = true
        refreshChrome()
        token = host.engine.search(o, batch: { [weak self] ms in self?.ingest(ms, gen) }, done: { [weak self] stats in
            guard let self, gen == self.generation else { return }
            self.searching = false
            if let e = stats.error { self.errorText = e }
            self.truncated = self.truncated || stats.truncated
            self.finishResults()
        })
    }

    private func ingest(_ ms: [FindMatch], _ gen: Int) {
        guard gen == generation, !closed else { return }
        let room = Self.listCap - results.count
        guard room > 0 else { return }
        let keep = ms.filter(inScope)
        results.append(contentsOf: keep.prefix(room))
        if results.count >= Self.listCap {
            truncated = true
            token?.cancel()
            searching = false
            finishResults()
            return
        }
        let firstRows = table.selectedRow < 0
        table.reloadData()
        if firstRows, !results.isEmpty { select(0) }
        refreshChrome()
    }

    private func finishResults() {
        results.sort { ($0.url.path, $0.line, $0.column) < ($1.url.path, $1.line, $1.column) }
        table.reloadData()
        if !results.isEmpty { select(0) }
        previewKey = nil
        updatePreview(force: true)
        refreshChrome()
        onSearchDone?()
    }

    var onSearchDone: (() -> Void)?     // test hook

    private func select(_ row: Int) {
        guard !results.isEmpty else { return }
        let r = min(max(row, 0), results.count - 1)
        table.selectRowIndexes([r], byExtendingSelection: false)
        table.scrollRowToVisible(r)
    }

    // MARK: status

    private static let nf: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; return f }()

    var statusText: String {
        if let n = note { return n }
        if let e = errorText { return e }
        guard !field.stringValue.isEmpty else { return "" }
        let n = results.count
        if n == 0 { return searching ? "Searching…" : "No matches" }
        let shown = results.prefix(Self.displayCap)
        let files = Set(shown.map { $0.url.path }).count
        let capped = n > Self.displayCap
        return "\(capped ? "\(Self.displayCap)+" : "\(n)") match\(n == 1 ? "" : "es") in \(files)\(capped ? "+" : "") file\(files == 1 ? "" : "s")"
    }

    private func refreshChrome() {
        statusLabel.stringValue = statusText
        statusLabel.textColor = errorText != nil && note == nil ? .systemRed : Theme.gutter
        emptyLabel.stringValue = errorText != nil ? "" : field.stringValue.isEmpty ? "Type to search" : searching ? "Searching…" : "No matches"
        emptyLabel.isHidden = !results.isEmpty
        scroll.isHidden = results.isEmpty
        clearButton.isHidden = field.stringValue.isEmpty
        updateFocusRing()
        updateButtons()
        if results.isEmpty { pathLabel.stringValue = ""; preview.textStorage?.setAttributedString(NSAttributedString()) }
    }

    private func updateButtons() {
        replaceButton.isEnabled = !results.isEmpty && table.selectedRow >= 0
        replaceButton.alphaValue = replaceButton.isEnabled ? 1 : 0.5
        replaceAllButton.isEnabled = !results.isEmpty
    }

    // MARK: preview

    private func updatePreview(force: Bool = false) {
        let row = table.selectedRow
        guard row >= 0, row < results.count else { return }
        let m = results[row]
        if !force, previewKey == m.key { return }
        previewKey = m.key
        pathLabel.stringValue = relPath(m.url)
        let lines: [Substring]
        if let c = previewCache, c.path == m.url.path { lines = c.lines } else {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: m.url.path), (attrs[.size] as? Int ?? 0) <= 1_500_000,
                  let data = try? Data(contentsOf: m.url) else {
                preview.textStorage?.setAttributedString(NSAttributedString(string: "  Preview unavailable (file too large or unreadable)",
                    attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.gutter]))
                return
            }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            previewCache = (m.url.path, lines)
        }
        let base = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let num: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: Theme.gutter]
        let txt: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: Theme.foreground]
        let first = max(1, m.line - 200), last = min(lines.count, m.line + 300)
        let out = NSMutableAttributedString()
        var matchRange: NSRange?
        let digits = String(last).count
        guard first <= last else { return }
        for ln in first...last {
            let numStr = String(ln)
            out.append(NSAttributedString(string: String(repeating: " ", count: digits - numStr.count) + numStr + "   ", attributes: num))
            var line = String(lines[ln - 1])
            if line.hasSuffix("\r") { line.removeLast() }
            let start = out.length
            out.append(NSAttributedString(string: line + "\n", attributes: txt))
            if ln == m.line {
                let len = (line as NSString).length
                let loc = min(max(0, m.column - 1), len)
                matchRange = NSRange(location: start + loc, length: min(m.length, len - loc))
                out.addAttribute(.backgroundColor, value: NSColor.controlAccentColor.withAlphaComponent(Theme.isDark ? 0.14 : 0.10),
                                 range: NSRange(location: start, length: (line as NSString).length))
            }
        }
        if let r = matchRange, r.length > 0 {
            out.addAttribute(.backgroundColor, value: NSColor(calibratedRed: 1, green: 0.84, blue: 0.2, alpha: Theme.isDark ? 0.45 : 0.8), range: r)
        }
        preview.textContainer?.widthTracksTextView = wrapButton.isOn
        preview.isHorizontallyResizable = !wrapButton.isOn
        if !wrapButton.isOn { preview.textContainer?.containerSize = NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude) }
        preview.textStorage?.setAttributedString(out)
        if let r = matchRange {
            preview.layoutManager?.ensureLayout(for: preview.textContainer!)
            let g = preview.layoutManager!.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
            let rect = preview.layoutManager!.boundingRect(forGlyphRange: g, in: preview.textContainer!)
            let vis = previewScroll.contentView.bounds.height
            previewScroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, rect.midY - vis / 2)))
            previewScroll.reflectScrolledClipView(previewScroll.contentView)
        }
    }

    private func relPath(_ url: URL) -> String {
        let p = url.path, base = (host.root.path as NSString).standardizingPath
        if p.hasPrefix(base + "/") { return String(p.dropFirst(base.count + 1)) }
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let real = realpath(base, &buf) != nil ? String(cString: buf) : base
        if p.hasPrefix(real + "/") { return String(p.dropFirst(real.count + 1)) }
        return p
    }

    // MARK: actions

    @objc private func chipClicked(_ b: ChipButton) {
        b.isOn.toggle()
        if b === wrapButton { updatePreview(force: true) } else { optionChanged() }
    }
    @objc private func filterClicked() { filterButton.isOn.toggle(); optionChanged() }
    @objc private func pinClicked() { pinButton.isOn.toggle(); Self.memory.pinned = pinButton.isOn }
    @objc private func clearClicked() { field.stringValue = ""; optionChanged(); focusQuery() }
    @objc private func maskToggled() {
        maskField.isEnabled = maskCheck.state == .on
        if maskCheck.state == .on { panel.makeFirstResponder(maskField) }
        optionChanged()
    }
    @objc private func newTabToggled() { Self.memory.newTab = newTabCheck.state == .on }
    @objc private func doubleClicked() { if table.clickedRow >= 0 { openSelected() } }
    @objc private func openInWindowClicked() { openInFindWindow() }
    @objc private func replaceClicked() { replaceSelected() }
    @objc private func replaceAllClicked() { replaceAll(confirm: true) }

    func openSelected() {
        let r = table.selectedRow
        guard r >= 0, r < results.count else { return }
        let m = results[r]
        let parent = self.parent
        let pinned = pinButton.isOn
        if !pinned { close(refocus: true) } else { saveMemory() }
        DispatchQueue.main.async { [host] in
            if parent?.isKeyWindow == false, !AppEnv.headless { parent?.makeKey() }
            host.openMatch(m)
        }
    }

    func openInFindWindow() {
        let o = currentOptions
        let rep = replaceField.stringValue
        let mode = replaceMode
        let parent = self.parent
        if pinButton.isOn { saveMemory() } else { close(refocus: false) }
        host.openInFindWindow(o, mode ? rep : nil, mode)
        _ = parent
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        guard e.type == .keyDown else { return false }
        let mods = e.modifierFlags.intersection([.command, .shift, .option, .control])
        if mods == .command, e.keyCode == 36 || e.keyCode == 76 { openInFindWindow(); return true }
        if mods == [.command, .shift], e.charactersIgnoringModifiers?.lowercased() == "r" { setReplaceMode(true); return true }
        if mods == [.command, .shift], e.charactersIgnoringModifiers?.lowercased() == "f" { setReplaceMode(false); focusQuery(); return true }
        return false
    }

    // MARK: replace

    private func replaceNote(_ r: FindReplaceReport) -> String {
        if let e = r.error { return "Replace failed: \(e)" }
        let files = r.filesChanged + r.buffersEdited
        var s = "Replaced \(r.replaced.count) match\(r.replaced.count == 1 ? "" : "es") in \(files) file\(files == 1 ? "" : "s")"
        if r.buffersEdited > 0 { s += " (\(r.buffersEdited) open, unsaved)" }
        if !r.skipped.isEmpty { s += " · skipped \(Set(r.skipped.map { $0.url.lastPathComponent }).count) (changed since search)" }
        return s
    }

    /// Replace: the selected match only.
    func replaceSelected(completion: (() -> Void)? = nil) {
        guard replaceMode, table.selectedRow >= 0, table.selectedRow < results.count else { return }
        let idx = table.selectedRow
        let report = host.engine.replace([results[idx]], with: replaceField.stringValue, options: currentOptions, openBuffer: host.openBuffer)
        let text = replaceNote(report)
        let keepRow = idx
        onSearchDone = { [weak self] in
            self?.onSearchDone = nil
            self?.select(keepRow)
            self?.updatePreview(force: true)
            completion?()
        }
        startSearch()
        note = text
        refreshChrome()
    }

    /// Replace All: every match (re-searches without the list cap when the list was truncated).
    func replaceAll(confirm: Bool, completion: (() -> Void)? = nil) {
        guard replaceMode, !results.isEmpty else { return }
        let o = currentOptions
        let go: ([FindMatch]) -> Void = { [weak self] all in
            guard let self, !self.closed else { return }
            let files = Set(all.map { $0.url.path }).count
            let apply = {
                let report = self.host.engine.replace(all, with: self.replaceField.stringValue, options: o, openBuffer: self.host.openBuffer)
                let text = self.replaceNote(report)
                self.onSearchDone = { [weak self] in self?.onSearchDone = nil; completion?() }
                self.startSearch()
                self.note = text
                self.refreshChrome()
            }
            if confirm, files > 1 {
                let a = NSAlert()
                a.messageText = "Replace \(all.count) matches in \(files) files?"
                a.informativeText = "Open files are edited in their editor (undo with Cmd-Z, then save). Other files are written to disk; \"Undo Last Replace\" in the Find window restores them."
                a.addButton(withTitle: "Replace"); a.addButton(withTitle: "Cancel")
                self.suspendClose = true
                a.beginSheetModal(for: self.panel) { r in
                    self.suspendClose = false
                    if r == .alertFirstButtonReturn { apply() }
                }
            } else { apply() }
        }
        if !truncated { go(results); return }
        var all: [FindMatch] = []
        _ = host.engine.search(o, batch: { [weak self] ms in all += ms.filter { self?.inScope($0) ?? true } }, done: { _ in go(all) })
    }

    // MARK: mask history

    private static let historyKey = "findPopupMaskHistory"
    private static var memoryHistory: [String] = []
    static var maskHistory: [String] {
        get { AppEnv.headless ? memoryHistory : (UserDefaults.standard.stringArray(forKey: historyKey) ?? []) }
        set { if AppEnv.headless { memoryHistory = newValue } else { UserDefaults.standard.set(newValue, forKey: historyKey) } }
    }
    private func recordMaskHistory() {
        let m = maskField.stringValue.trimmingCharacters(in: .whitespaces)
        guard maskCheck.state == .on, !m.isEmpty else { return }
        Self.maskHistory = Array(([m] + Self.maskHistory.filter { $0 != m }).prefix(12))
    }

    // MARK: delegates

    func controlTextDidChange(_ obj: Notification) {
        let f = obj.object as AnyObject
        if f === field || f === maskField { scheduleSearch(immediately: false) }
        refreshChrome()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if (obj.object as AnyObject) === dirField { optionChanged() }
        updateFocusRing()
    }

    func controlTextDidBeginEditing(_ obj: Notification) { updateFocusRing() }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.optionChanged() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        guard control === field || control === replaceField else { return false }
        switch sel {
        case #selector(NSResponder.moveUp(_:)): select(table.selectedRow - 1)
        case #selector(NSResponder.moveDown(_:)): select(table.selectedRow + 1)
        case #selector(NSResponder.pageUp(_:)), Selector(("movePageUp:")), #selector(NSResponder.scrollPageUp(_:)): select(table.selectedRow - 8)
        case #selector(NSResponder.pageDown(_:)), Selector(("movePageDown:")), #selector(NSResponder.scrollPageDown(_:)): select(table.selectedRow + 8)
        case #selector(NSResponder.insertNewline(_:)):
            if control === replaceField { replaceSelected() } else { openSelected() }
        case #selector(NSResponder.cancelOperation(_:)): close(refocus: true)
        default: return false
        }
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { FindPopupRowBackground() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("fr")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? FindPopupRowCell) ?? {
            let c = FindPopupRowCell(frame: .zero); c.identifier = id; return c
        }()
        guard row < results.count else { return cell }
        cell.configure(results[row], root: host.root)
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) { updatePreview(); updateButtons() }

    // MARK: test hooks

    var selectedRow: Int { table.selectedRow }
    func testType(_ q: String) { field.stringValue = q; optionChanged() }
    func testSetReplacement(_ r: String) { replaceField.stringValue = r }
    func testToggle(_ name: String) {
        switch name {
        case "case": caseButton.isOn.toggle()
        case "word": wordButton.isOn.toggle()
        case "regex": regexButton.isOn.toggle()
        case "preserve": preserveButton.isOn.toggle()
        case "ignored": filterButton.isOn.toggle()
        case "pin": pinButton.isOn.toggle()
        default: break
        }
        optionChanged()
    }
    func testSetMask(_ m: String?) {
        maskCheck.state = m == nil ? .off : .on
        maskField.stringValue = m ?? ""
        maskField.isEnabled = m != nil
        optionChanged()
    }
    func testSelectTab(_ i: Int) { selectTab(i) }
    func testSetDirectory(_ u: URL) { dirField.stringValue = u.path }
    func testKey(_ sel: Selector) -> Bool { control(field, textView: NSTextView(), doCommandBy: sel) }
    func testPerformKey(_ e: NSEvent) -> Bool { handleKey(e) }
    var testPinned: Bool { pinButton.isOn }
    var testPanel: NSPanel { panel }
    var testTitle: String { titleLabel.stringValue }
    var testPathLabel: String { pathLabel.stringValue }
    var testPreviewText: String { preview.string }
    var testReplaceBoxVisible: Bool { !replaceBox.isHidden }
}
