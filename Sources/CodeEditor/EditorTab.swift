import AppKit

enum LoadProblem: Error, Equatable {
    case notUTF8
    case tooLarge(Int)
    case unreadable
}

struct OpenOptions: Equatable {
    var encoding: String.Encoding = .utf8
    /// Show only the first 5 MB, read-only.
    var readOnlyTruncated = false
}

enum LineEnding: String { case lf = "LF", crlf = "CRLF" }

/// Banner above the editor ("File changed on disk — Reload / Keep mine / Show diff", read-only notices).
final class NoticeBanner: NSView {
    private let label = NSTextField(labelWithString: "")
    private let buttons = NSStackView()
    private let line = NSView()
    private final class ActionButton: NSButton {
        var run: (() -> Void)?
        @objc func fire() { run?() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 12)
        buttons.spacing = 6
        line.wantsLayer = true
        for v in [label, buttons, line] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttons.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 10),
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor), line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor), line.heightAnchor.constraint(equalToConstant: 1),
        ])
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    private(set) var message = ""
    private(set) var buttonTitles: [String] = []

    func restyle() {
        layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(Theme.isDark ? 0.16 : 0.28).cgColor
        line.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.5).cgColor
        label.textColor = Theme.foreground
    }

    func set(message: String, actions: [(String, () -> Void)]) {
        self.message = message
        buttonTitles = actions.map { $0.0 }
        label.stringValue = message
        buttons.arrangedSubviews.forEach { buttons.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (title, run) in actions {
            let b = ActionButton(title: title, target: nil, action: nil)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.run = run
            b.target = b
            b.action = #selector(ActionButton.fire)
            buttons.addArrangedSubview(b)
        }
    }
}

/// Editor view + banner slot. File drops (from Finder or the tree) are forwarded to the window.
final class EditorPane: NSView {
    let banner = NoticeBanner()
    private var bannerHeight: NSLayoutConstraint!
    var onDropURLs: (([URL]) -> Void)?

    init(content: NSView) {
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        banner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content); addSubview(banner)
        bannerHeight = banner.heightAnchor.constraint(equalToConstant: 0)
        banner.isHidden = true
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: topAnchor), banner.leadingAnchor.constraint(equalTo: leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: trailingAnchor), bannerHeight,
            content.topAnchor.constraint(equalTo: banner.bottomAnchor), content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    var isBannerVisible: Bool { !banner.isHidden }

    func showBanner(_ message: String, actions: [(String, () -> Void)]) {
        banner.set(message: message, actions: actions)
        banner.restyle()
        banner.isHidden = false
        bannerHeight.constant = 30
    }

    func hideBanner() { banner.isHidden = true; bannerHeight.constant = 0 }

    private func urls(_ info: NSDraggingInfo) -> [URL] {
        (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { urls(sender).isEmpty ? [] : .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { urls(sender).isEmpty ? [] : .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let list = urls(sender)
        guard !list.isEmpty else { return false }
        onDropURLs?(list)
        return true
    }
}

/// One open file: scroll view + text view + highlighter.
final class EditorTab: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    static let sizeLimit = 5_000_000
    private(set) var url: URL
    let scrollView = NSScrollView()
    private(set) var view: NSView!
    let textView: CodeTextView
    private var highlighter: Highlighter?
    private let storage: NSTextStorage
    private(set) var isDirty = false
    var onDirtyChange: (() -> Void)?
    var onSave: (() -> Void)?
    private var diskDate: Date?
    private var conflictDate: Date?
    private(set) var hasDiskConflict = false
    private(set) var encoding: String.Encoding = .utf8
    private(set) var isReadOnly = false
    private(set) var eol: LineEnding = .lf
    var onDropURLs: (([URL]) -> Void)? { didSet { pane?.onDropURLs = onDropURLs } }
    /// Asked to show a buffer-vs-disk diff (the window owns the UI).
    var onShowDiff: ((EditorTab) -> Void)?
    private var pane: EditorPane!
    private(set) var indent = IndentSettings.standard
    private var paragraph: NSParagraphStyle = .default

    /// Why a file cannot be opened as plain editable text, or nil if it can.
    static func loadProblem(for url: URL) -> LoadProblem? {
        if case .failure(let problem) = read(url, options: OpenOptions()) { return problem }
        return nil
    }

    static func read(_ url: URL, options: OpenOptions) -> Result<(text: String, readOnly: Bool), LoadProblem> {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
        if size > sizeLimit, !options.readOnlyTruncated { return .failure(.tooLarge(size)) }
        if size > sizeLimit {
            guard let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: sizeLimit) else {
                return .failure(.unreadable)
            }
            try? handle.close()
            // Cutting at a byte count can split a character: decode leniently.
            return .success((String(decoding: head, as: UTF8.self), true))
        }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        guard let text = String(data: data, encoding: options.encoding) else { return .failure(.notUTF8) }
        return .success((text, false))
    }

    static func detectLineEnding(_ text: String) -> LineEnding {
        var crlf = 0, lf = 0, previous: UInt8 = 0
        for b in text.utf8 {
            if b == 10 { lf += 1; if previous == 13 { crlf += 1 } }
            previous = b
        }
        return crlf > 0 && crlf * 2 >= lf ? .crlf : .lf
    }

    /// Buffer text with every line ending normalised to the file's style (typing adds bare "\n").
    func serializedText() -> String {
        let lf = textView.string.replacingOccurrences(of: "\r\n", with: "\n")
        return eol == .crlf ? lf.replacingOccurrences(of: "\n", with: "\r\n") : lf
    }

    init?(url: URL, options: OpenOptions = OpenOptions()) {
        self.url = url
        guard case .success(let loaded) = Self.read(url, options: options) else { return nil }
        let text = loaded.text
        encoding = options.encoding
        isReadOnly = loaded.readOnly
        eol = Self.detectLineEnding(text)
        // Classic TextKit 1 stack: the highlighter and ruler both need NSLayoutManager.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                     height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        self.storage = storage
        layout.addTextContainer(container)
        textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
        super.init()

        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = Theme.font
        textView.textColor = Theme.foreground
        textView.backgroundColor = Theme.background
        textView.insertionPointColor = Theme.foreground
        indent = IndentSettings.resolve(for: url, text: text)
        paragraph = Self.paragraphStyle(for: indent)
        textView.indentUnit = indent.unit
        textView.useTabs = indent.useTabs
        textView.tabColumns = indent.size
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: Theme.font, .foregroundColor: Theme.foreground, .paragraphStyle: paragraph]
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        container.widthTracksTextView = false
        textView.string = text
        textView.textStorage?.setAttributes(textView.typingAttributes,
                                            range: NSRange(location: 0, length: (text as NSString).length))
        textView.delegate = self
        if isReadOnly { textView.isEditable = false }
        // File URLs dropped on the editor open tabs (handled by the pane); plain text drags keep working.
        textView.unregisterDraggedTypes()
        textView.registerForDraggedTypes([.string])
        textView.commentStyle = CodeTextView.commentStyle(forExtension: url.pathExtension)
        diskDate = Self.modificationDate(url)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.background
        pane = EditorPane(content: EditorContainer(scrollView: scrollView, gutter: GutterView(textView: textView, scrollView: scrollView)))
        view = pane
        if isReadOnly { pane.showBanner("Read-only: showing the first 5 MB of a larger file.", actions: []) }

        storage.delegate = self
        highlighter = Highlighter(textView: textView, fileName: url.lastPathComponent)
        EditorEvents.notifyOpened(self)
    }

    /// Tab characters in the file render exactly `size` columns wide (AppKit's default is ~3.6 columns).
    private static func paragraphStyle(for indent: IndentSettings) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let column = ("0" as NSString).size(withAttributes: [.font: Theme.font]).width
        style.tabStops = []
        style.defaultTabInterval = column * CGFloat(indent.size)
        return style
    }

    func applyIndent(_ new: IndentSettings) {
        indent = new
        paragraph = Self.paragraphStyle(for: new)
        textView.indentUnit = new.unit
        textView.useTabs = new.useTabs
        textView.tabColumns = new.size
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        textView.textStorage?.addAttribute(.paragraphStyle, value: paragraph,
                                           range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
    }

    var lineEnding: String { eol.rawValue }

    func textDidChange(_ notification: Notification) {
        if !isDirty { isDirty = true; onDirtyChange?() }
    }

    /// Feeds each edit to the incremental parser; it repaints at the end of the run loop.
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        highlighter?.textDidEdit(range: editedRange, changeInLength: delta)
    }

    private static func modificationDate(_ url: URL) -> Date? {
        // URL caches resource values, so ask the file system directly.
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    @objc private func themeChanged() {
        textView.textColor = Theme.foreground
        textView.backgroundColor = Theme.background
        textView.insertionPointColor = Theme.foreground
        textView.typingAttributes = [.font: Theme.font, .foregroundColor: Theme.foreground, .paragraphStyle: paragraph]
        textView.textStorage?.addAttribute(.foregroundColor, value: Theme.foreground,
                                           range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        scrollView.backgroundColor = Theme.background
        pane.banner.restyle()
        highlighter?.apply()
    }

    // MARK: Disk changes

    /// Picks up edits made outside the app (agents, git). Clean buffers reload in place; for dirty ones the window
    /// shows a banner (Reload / Keep mine / Show diff) and nothing is overwritten.
    func reloadIfChangedOnDisk() {
        guard !isReadOnly, let date = Self.modificationDate(url), date != diskDate else { return }
        if isDirty {
            guard !hasDiskConflict || conflictDate != date else { return }
            conflictDate = date
            hasDiskConflict = true
            showConflictBanner()
            return
        }
        guard case .success(let loaded) = Self.read(url, options: OpenOptions(encoding: encoding)) else { return }
        diskDate = date
        guard loaded.text != textView.string else { return }
        replaceBuffer(with: loaded.text)
    }

    private func replaceBuffer(with text: String) {
        let selection = textView.selectedRange()
        let origin = scrollView.contentView.bounds.origin
        eol = Self.detectLineEnding(text)
        textView.string = text
        textView.textStorage?.setAttributes(textView.typingAttributes,
                                            range: NSRange(location: 0, length: (text as NSString).length))
        textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        scrollView.contentView.scroll(to: origin)
        highlighter?.reparse()
        textView.undoManager?.removeAllActions()
    }

    /// Text currently on disk (for the diff view).
    func currentDiskText() -> String? {
        if case .success(let loaded) = Self.read(url, options: OpenOptions(encoding: encoding)) { return loaded.text }
        return nil
    }

    private func showConflictBanner() {
        pane.showBanner("File changed on disk — your unsaved edits are kept.", actions: [
            ("Reload", { [weak self] in self?.reloadFromDisk() }),
            ("Keep mine", { [weak self] in self?.keepMine() }),
            ("Show diff", { [weak self] in if let self { self.onShowDiff?(self) } }),
        ])
    }

    /// Discards the buffer's edits and loads the disk version.
    func reloadFromDisk() {
        if let text = currentDiskText() {
            replaceBuffer(with: text)
            diskDate = Self.modificationDate(url)
            let wasDirty = isDirty
            isDirty = false
            if wasDirty { onDirtyChange?() }
        }
        clearConflict()
    }

    /// Keeps the buffer; a later save may overwrite the disk version without asking again.
    func keepMine() {
        diskDate = Self.modificationDate(url)
        clearConflict()
    }

    private func clearConflict() {
        hasDiskConflict = false
        conflictDate = nil
        pane.hideBanner()
    }

    var isBannerVisible: Bool { pane.isBannerVisible }
    var bannerMessage: String { pane.banner.message }
    var bannerButtons: [String] { pane.banner.buttonTitles }

    /// The disk version is newer than what this buffer was loaded from or last saved as.
    var hasNewerDiskVersion: Bool {
        guard let date = Self.modificationDate(url), let known = diskDate else { return false }
        return date != known
    }

    func retarget(to newURL: URL) { url = newURL }

    var caretLocation: Int { textView.selectedRange().location }
    var scrollY: Double { Double(scrollView.contentView.bounds.origin.y) }

    func restore(caret: Int, scrollY: Double) {
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: min(max(0, caret), length), length: 0))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, scrollY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Writes the buffer (keeping the file's encoding and line endings). Returns false if nothing was written.
    /// A newer disk version is never overwritten silently: the user is asked (headless runs decline).
    @discardableResult
    func save(overwriteNewer: Bool = false) -> Bool {
        guard !isReadOnly else { return false }
        if !overwriteNewer, hasNewerDiskVersion {
            if AppEnv.headless { return false }
            let alert = NSAlert()
            alert.messageText = "“\(url.lastPathComponent)” changed on disk"
            alert.informativeText = "Saving will overwrite the newer version on disk with your buffer."
            alert.addButton(withTitle: "Overwrite")
            alert.addButton(withTitle: "Show Diff")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: break
            case .alertSecondButtonReturn: onShowDiff?(self); return false
            default: return false
            }
        }
        do {
            guard let data = serializedText().data(using: encoding) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            try data.write(to: url, options: .atomic)
            isDirty = false
            diskDate = Self.modificationDate(url)
            clearConflict()
            onDirtyChange?()
            onSave?()
            EditorEvents.notifySaved(self)
            return true
        } catch {
            if !AppEnv.headless { NSAlert(error: error).runModal() }
            return false
        }
    }
}
