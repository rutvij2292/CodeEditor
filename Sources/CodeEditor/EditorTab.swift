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
    /// Open a file over the 5 MB limit (up to `EditorTab.hardLimit`) editable, with highlighting/LSP/bracket features off.
    var openAnyway = false
    /// Sniff a byte-order mark and honour it. Off when the user picked an encoding explicitly ("Reopen with encoding").
    var autoDetect = true
}

/// A decoded file plus what is needed to write it back unchanged.
struct LoadedFile {
    var text: String
    var readOnly: Bool
    var encoding: String.Encoding
    var bom: Bool
    /// Decoding replaced undecodable bytes: writing this text back would corrupt the file.
    var lossy: Bool
    var large: Bool
}

/// What an external reload changed (for the status message, the flash and tests).
struct ExternalChange {
    var url: URL
    var date: Date
    /// Changed regions in the NEW text (UTF-16 ranges, whole lines).
    var ranges: [NSRange]
    var firstLine: Int?
    var lastLine: Int?
    var wholeText: Bool
}

enum LineEnding: String { case lf = "LF", crlf = "CRLF" }

/// Banner above the editor ("File changed on disk — Reload / Keep mine / Show diff", read-only notices).
final class NoticeBanner: NSView {
    private let label = NSTextField(labelWithString: "")
    private let buttons = NSStackView()
    private let line = NSView()
    private let icon = NSImageView()
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
        icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        for v in [icon, label, buttons, line] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
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
        layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(Theme.isDark ? 0.10 : 0.09).cgColor     // a tint, not a yellow slab
        line.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.25).cgColor
        icon.contentTintColor = .systemOrange
        label.textColor = Theme.foreground
    }

    private var handlers: [String: () -> Void] = [:]
    /// Runs the action behind a button (tests, menus).
    func press(_ title: String) { handlers[title]?() }

    func set(message: String, actions: [(String, () -> Void)]) {
        self.message = message
        buttonTitles = actions.map { $0.0 }
        handlers = Dictionary(actions.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })
        label.stringValue = message
        buttons.arrangedSubviews.forEach { buttons.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (title, run) in actions {
            let b = ActionButton(title: title, target: nil, action: nil)
            b.bezelStyle = .recessed
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11.5)
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

    let breadcrumbBar: BreadcrumbBar
    private var breadcrumbHeight: NSLayoutConstraint!
    /// Viewer pane support (ViewerSystem.swift): the editor view and its trailing edge constraint, swapped for split / preview modes.
    let contentView: NSView
    var contentTrailing: NSLayoutConstraint!
    var viewerState = ViewerPaneState()

    init(content: NSView, breadcrumbs: BreadcrumbBar) {
        breadcrumbBar = breadcrumbs
        contentView = content
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        banner.translatesAutoresizingMaskIntoConstraints = false
        breadcrumbs.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content); addSubview(breadcrumbs); addSubview(banner)
        bannerHeight = banner.heightAnchor.constraint(equalToConstant: 0)
        breadcrumbHeight = breadcrumbs.heightAnchor.constraint(equalToConstant: BreadcrumbBar.height)
        banner.isHidden = true
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: topAnchor), banner.leadingAnchor.constraint(equalTo: leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: trailingAnchor), bannerHeight,
            breadcrumbs.topAnchor.constraint(equalTo: banner.bottomAnchor), breadcrumbs.leadingAnchor.constraint(equalTo: leadingAnchor),
            breadcrumbs.trailingAnchor.constraint(equalTo: trailingAnchor), breadcrumbHeight,
            content.topAnchor.constraint(equalTo: breadcrumbs.bottomAnchor), content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        contentTrailing = content.trailingAnchor.constraint(equalTo: trailingAnchor)
        contentTrailing.isActive = true
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    var isBannerVisible: Bool { !banner.isHidden }

    /// Shows/hides the breadcrumb bar without leaving a gap.
    func setBreadcrumbsVisible(_ visible: Bool) {
        breadcrumbBar.isHidden = !visible
        breadcrumbHeight.constant = visible ? BreadcrumbBar.height : 0
    }
    var breadcrumbsVisible: Bool { !breadcrumbBar.isHidden }

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
    /// Largest file "Open anyway" will load.
    static let hardLimit = 50_000_000
    private(set) var url: URL
    let scrollView = NSScrollView()
    private(set) var view: NSView!
    let textView: CodeTextView
    private(set) var highlighter: Highlighter?
    private let storage: NSTextStorage
    private(set) var isDirty = false
    var onDirtyChange: (() -> Void)?
    var onSave: (() -> Void)?
    private var diskStamp: FileStamp?
    private var conflictStamp: FileStamp?
    private(set) var hasDiskConflict = false
    private(set) var encoding: String.Encoding = .utf8
    /// The file started with a byte-order mark (written back unchanged).
    private(set) var hasBOM = false
    private(set) var isReadOnly = false
    /// Over the 5 MB limit: Highlighter, BracketColorizer, LSP sync and Completion must skip this tab.
    private(set) var isLargeFile = false
    /// A line over `longLineLimit` characters (minified bundles): TextKit 1 lays out and draws a whole line fragment at once,
    /// so such files get soft wrap and the same feature set as large files.
    private(set) var longLines = false
    static let longLineLimit = 20_000

    static func hasLongLine(_ text: String) -> Bool {
        var text = text
        return text.withUTF8 { buf in
            var run = 0
            for b in buf {
                if b == 10 { run = 0 } else { run += 1; if run > longLineLimit { return true } }
            }
            return false
        }
    }
    /// Decoded with replacement characters: never written back.
    private(set) var isLossyDecoded = false
    private var saveInFlight = false
    private var saveErrorShown = false
    private var idleWork: DispatchWorkItem?
    private let undo = UndoManager()
    private(set) var eol: LineEnding = .lf
    var onDropURLs: (([URL]) -> Void)? { didSet { pane?.onDropURLs = onDropURLs } }
    /// Asked to show a buffer-vs-disk diff (the window owns the UI).
    var onShowDiff: ((EditorTab) -> Void)?
    /// Banner "Save As…" / "Close" (the window owns the UI).
    var onSaveAs: ((EditorTab) -> Void)?
    var onCloseRequest: ((EditorTab) -> Void)?
    /// A clean buffer was reloaded because the file changed on disk.
    var onExternalReload: ((EditorTab, ExternalChange) -> Void)?
    /// Large file whose "Open anyway" button was pressed (window reopens it).
    var onOpenAnyway: ((EditorTab) -> Void)?
    private(set) var lastExternalChange: ExternalChange?
    private var flashView: FlashOverlay?
    private var pane: EditorPane!
    /// Project folder for the breadcrumb path (integrator sets e.g. `{ [unowned window] in window.root }`).
    /// Without it the nearest ancestor holding .git / composer.json / package.json is used.
    var projectRoot: (() -> URL?)?
    /// Opens a file chosen in a breadcrumb dropdown (integrator wires to ProjectWindow.open).
    var onOpenURL: ((URL) -> Void)?
    private(set) var breadcrumbs: BreadcrumbController!
    private(set) var indent = IndentSettings.standard
    private var paragraph: NSParagraphStyle = .default

    /// Why a file cannot be opened as plain editable text, or nil if it can.
    static func loadProblem(for url: URL) -> LoadProblem? {
        if case .failure(let problem) = read(url, options: OpenOptions()) { return problem }
        return nil
    }

    static func read(_ url: URL, options: OpenOptions) -> Result<LoadedFile, LoadProblem> {
        let size = Int(FileIO.stamp(url)?.size ?? 0)
        var large = false
        if size > sizeLimit {
            if options.readOnlyTruncated {
                guard let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: sizeLimit) else {
                    return .failure(.unreadable)
                }
                try? handle.close()
                // Cutting at a byte count can split a character: decode leniently (and never write it back).
                return .success(LoadedFile(text: String(decoding: head, as: UTF8.self), readOnly: true, encoding: .utf8,
                                           bom: false, lossy: true, large: true))
            }
            guard options.openAnyway, size <= hardLimit else { return .failure(.tooLarge(size)) }
            large = true
        }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        var encoding = options.encoding
        var payload = data
        var bom = false
        if let (sniffed, length) = TextEncodings.sniffBOM(data), options.autoDetect || sniffed == options.encoding {
            encoding = sniffed
            payload = data.dropFirst(length)
            bom = true
        }
        guard let text = String(data: payload, encoding: encoding) else { return .failure(.notUTF8) }
        return .success(LoadedFile(text: text, readOnly: false, encoding: encoding, bom: bom, lossy: false, large: large))
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

    static var contiguousLines: Int { Int(AppEnv.value("CE_CONTIGUOUS_LINES") ?? "") ?? 6_000 }
    static let maxBackgroundLayoutLines = 60_000
    private var completesLayoutLazily = false

    /// A lazily laid out file (non-contiguous) gets the rest of its layout in small slices while the app is idle, so the scroll bar's
    /// length settles within a moment instead of jumping when the user reaches the unlaid part.
    func completeLayoutGradually() {
        guard completesLayoutLazily, textView.layoutManager != nil else { return }
        var pos = 0
        func step(_ tab: EditorTab?) {
            guard let tab, let lm = tab.textView.layoutManager, !PowerState.shared.saver else { return }
            let total = tab.storage.length
            guard pos < total else { return }
            let len = min(40_000, total - pos)
            lm.ensureLayout(forCharacterRange: NSRange(location: pos, length: len))
            pos += len
            if AppEnv.value("CE_LAYOUT_DEBUG") != nil { fputs("LAYOUT slice to \(pos)/\(total) height \(tab.textView.layoutManager?.usedRect(for: tab.textView.textContainer!).height ?? 0)\n", stderr) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak tab] in step(tab) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in step(self) }
    }

    init?(url: URL, options: OpenOptions = OpenOptions()) {
        self.url = url
        guard case .success(let loaded) = Self.read(url, options: options) else { return nil }
        let text = loaded.text
        encoding = loaded.encoding
        hasBOM = loaded.bom
        isLossyDecoded = loaded.lossy
        longLines = Self.hasLongLine(loaded.text)
        isLargeFile = loaded.large || longLines
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
        // Non-contiguous layout lays out only the visible region on open (the rest is estimated), but its estimate of the document height
        // is ~40% off, so the scroll bar reaches the end and more lines pop in (trial on 2k and 10k line files). Files up to
        // `Self.contiguousLines` lines are laid out in full on open (tens of ms); bigger ones stay lazy and are completed in the background.
        let lineCount = text.utf8.reduce(0) { $1 == 10 ? $0 + 1 : $0 }
        layout.allowsNonContiguousLayout = loaded.large || (LayerTuning.nonContiguous && lineCount > Self.contiguousLines)
        completesLayoutLazily = layout.allowsNonContiguousLayout && !loaded.large && lineCount <= Self.maxBackgroundLayoutLines
        if let bg = LayerTuning.backgroundLayout { layout.backgroundLayoutEnabled = bg }
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
        textView.isContinuousSpellCheckingEnabled = false     // macOS squiggles under identifiers; a code editor must not
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.font = Self.currentFont()
        textView.textColor = Theme.foreground
        textView.backgroundColor = Theme.background
        textView.insertionPointColor = Theme.palette.caret
        indent = IndentSettings.resolve(for: url, text: text)
        paragraph = Self.paragraphStyle(for: indent)
        textView.indentUnit = indent.unit
        textView.markupExtension = url.pathExtension
        textView.useTabs = indent.useTabs
        textView.tabColumns = indent.size
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = Theme.textAttributes(paragraph: paragraph)
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
        diskStamp = FileIO.stamp(url)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged(_:)), name: Prefs.didChange, object: nil)
        breadcrumbs = BreadcrumbController(tab: self)
        NotificationCenter.default.addObserver(self, selector: #selector(selectionChanged), name: NSTextView.didChangeSelectionNotification, object: textView)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.background
        pane = EditorPane(content: EditorContainer(scrollView: scrollView, gutter: GutterView(textView: textView, scrollView: scrollView)),
                          breadcrumbs: breadcrumbs.bar)
        view = pane
        LayerTuning.apply([textView, scrollView.contentView, scrollView])
        pane.setBreadcrumbsVisible(Prefs.showBreadcrumbs)
        if isReadOnly {
            showLargeFileBanner()
        } else if longLines {
            pane.showBanner("Very long lines: soft wrap is on; highlighting, completion and language features are off.", actions: [])
            // Same state as CodeTextView.applySoftWrap(true) minus its whole-container ensureLayout/sizeToFit (seconds for 2 MB).
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            container.widthTracksTextView = true
            scrollView.hasHorizontalScroller = false
            container.containerSize = NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude)
        } else if isLargeFile {
            pane.showBanner("Large file: highlighting, completion and language features are off.", actions: [])
        }

        storage.delegate = self
        if !isLargeFile { highlighter = Highlighter(textView: textView, fileName: url.lastPathComponent) }
        EditorEvents.notifyOpened(self)
        if Prefs.showBreadcrumbs { breadcrumbs.schedule() }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// The editor font from the shared preferences (`Prefs.editorFontName` / `editorFontSize`; system monospaced when the
    /// family is empty or unknown). Mirrors what the settings package's dynamic `Theme.font` returns: once that lands on main
    /// the integrator can replace the body with `Theme.font` so there is a single source of truth.
    static func currentFont() -> NSFont { Theme.font }

    /// Tab characters render exactly `size` columns wide (AppKit's default is ~3.6) and the line height follows the preference.
    private static func paragraphStyle(for indent: IndentSettings) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        let column = ("0" as NSString).size(withAttributes: [.font: currentFont()]).width
        style.tabStops = []
        style.defaultTabInterval = column * CGFloat(indent.size)
        style.lineHeightMultiple = CGFloat(Prefs.lineHeightMultiple)
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
        scheduleIdleSave()
        breadcrumbs.noteEdit()
    }

    /// Per-tab undo stack (the window's shared manager would mix tabs and be absent in headless runs).
    func undoManager(for view: NSTextView) -> UndoManager? { undo }

    private func showLargeFileBanner() {
        var actions: [(String, () -> Void)] = []
        let size = Int(FileIO.stamp(url)?.size ?? 0)
        if size <= Self.hardLimit { actions.append(("Open anyway", { [weak self] in if let self { self.onOpenAnyway?(self) } })) }
        pane.showBanner("File too large to edit — showing the first 5 MB, read-only. Open anyway?", actions: actions)
    }

    /// Feeds each edit to the incremental parser; it repaints at the end of the run loop.
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        Perf.measure("highlight.textDidEdit") { highlighter?.textDidEdit(range: editedRange, changeInLength: delta) }
    }

    @objc private func selectionChanged() { breadcrumbs.noteSelection() }

    @objc private func themeChanged() {
        textView.textColor = Theme.foreground
        textView.backgroundColor = Theme.background
        textView.insertionPointColor = Theme.palette.caret
        textView.typingAttributes = Theme.textAttributes(paragraph: paragraph)
        textView.textStorage?.addAttribute(.foregroundColor, value: Theme.foreground,
                                           range: NSRange(location: 0, length: textView.textStorage?.length ?? 0))
        scrollView.backgroundColor = Theme.background
        pane.banner.restyle()
        applyTypography()
        highlighter?.apply()
    }

    @objc private func prefsChanged(_ note: Notification) {
        switch note.userInfo?["key"] as? String {
        case "editorFontName", "editorFontSize", "lineHeightMultiple": applyTypography()
        case "showBreadcrumbs":
            pane.setBreadcrumbsVisible(Prefs.showBreadcrumbs)
            if Prefs.showBreadcrumbs { breadcrumbs.refresh() }
        case "defaultIndentSize", "defaultIndentUsesTabs":
            let fresh = IndentSettings.resolve(for: url, text: textView.string)
            if fresh != indent { applyIndent(fresh) }
        default: break
        }
    }

    /// Re-applies font, tab stops and line height to the whole buffer (colours come from the highlighter's temporary
    /// attributes and are untouched), keeping the selection and scroll position, then repaints the highlighter.
    func applyTypography() {
        let font = Self.currentFont()
        let newParagraph = Self.paragraphStyle(for: indent)
        let storage = textView.textStorage
        let full = NSRange(location: 0, length: storage?.length ?? 0)
        if textView.font == font, paragraph.isEqual(newParagraph) { return }
        let selection = textView.selectedRanges
        let origin = scrollView.contentView.bounds.origin
        paragraph = newParagraph
        // Attribute-only edit: no text change, so no undo entry, no dirty flag, no highlighter edit.
        storage?.beginEditing()
        storage?.addAttributes([.font: font, .paragraphStyle: newParagraph], range: full)
        storage?.endEditing()
        textView.font = font
        textView.defaultParagraphStyle = newParagraph
        textView.typingAttributes[.font] = font
        textView.typingAttributes[.paragraphStyle] = newParagraph
        textView.selectedRanges = selection
        textView.needsDisplay = true
        highlighter?.apply()
        // Relayout (triggered above) can scroll the caret into view: put the viewport back, now and once layout settles.
        let restore = { [weak self] in
            guard let self else { return }
            self.scrollView.contentView.scroll(to: origin)
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
        restore()
        DispatchQueue.main.async(execute: restore)
    }

    /// Moves keyboard focus to the breadcrumb bar (Cmd-Opt-Up in PhpStorm). Left/Right move, Down/Return open the dropdown, Esc returns.
    func focusBreadcrumbs() {
        guard pane.breadcrumbsVisible else { return }
        breadcrumbs.refresh()
        breadcrumbs.bar.focusLast()
    }

    // MARK: Text comparison and minimal edits

    /// Literal UTF-16 equality. (Swift's `==` treats canonically equivalent strings as equal; a file whose only change is
    /// Unicode normalisation must still count as changed.)
    static func same(_ a: String, _ b: String) -> Bool { (a as NSString).isEqual(to: b) }

    struct Hunk: Equatable {
        var old: NSRange
        var text: String
    }

    /// Line-based changed regions turning `old` into `new`, ascending, in OLD coordinates. Huge inputs (or a huge differing
    /// middle) degrade to one replacement of the differing middle / the whole text; the result is always exact.
    static func hunks(from old: String, to new: String, maxMiddleLines: Int = 40_000, maxChars: Int = 8_000_000) -> [Hunk] {
        let oldNS = old as NSString, newNS = new as NSString
        if oldNS.isEqual(to: new) { return [] }
        let whole = [Hunk(old: NSRange(location: 0, length: oldNS.length), text: new)]
        if oldNS.length + newNS.length > maxChars { return whole }
        let a = DiffEngine.splitLines(old), b = DiffEngine.splitLines(new)
        var table: [[UInt8]: Int] = [:]
        func id(_ s: String) -> Int {
            let key = Array(s.utf8)
            if let v = table[key] { return v }
            table[key] = table.count
            return table.count - 1
        }
        let ia = a.map(id), ib = b.map(id)
        var lo = 0
        while lo < ia.count, lo < ib.count, ia[lo] == ib[lo] { lo += 1 }
        var ea = ia.count, eb = ib.count
        while ea > lo, eb > lo, ia[ea - 1] == ib[eb - 1] { ea -= 1; eb -= 1 }
        let ops: [DiffEngine.Op]
        if (ea - lo) + (eb - lo) > maxMiddleLines {
            ops = [DiffEngine.Op](repeating: .equal, count: lo) + [DiffEngine.Op](repeating: .delete, count: ea - lo)
                + [DiffEngine.Op](repeating: .insert, count: eb - lo) + [DiffEngine.Op](repeating: .equal, count: ia.count - ea)
        } else {
            ops = DiffEngine.edit(ia, ib, maxD: 2000)
        }
        var result: [Hunk] = []
        var i = 0, j = 0, offset = 0, k = 0
        while k < ops.count {
            if ops[k] == .equal { offset += a[i].utf16.count; i += 1; j += 1; k += 1; continue }
            let start = offset
            var deleted = 0
            var inserted = ""
            while k < ops.count, ops[k] != .equal {
                if ops[k] == .delete { deleted += a[i].utf16.count; i += 1 } else { inserted += b[j]; j += 1 }
                k += 1
            }
            offset += deleted
            result.append(Hunk(old: NSRange(location: start, length: deleted), text: inserted))
        }
        return result
    }

    /// Where an old-text offset lands after the hunks are applied.
    static func map(_ location: Int, through hunks: [Hunk]) -> Int {
        var delta = 0
        for h in hunks {
            let start = h.old.location, end = NSMaxRange(h.old)
            if location <= start { break }
            let n = (h.text as NSString).length
            if location >= end { delta += n - h.old.length } else { return start + delta + min(location - start, n) }
        }
        return location + delta
    }

    private func replaceRange(_ range: NSRange, with text: String) -> Bool {
        guard textView.shouldChangeText(in: range, replacementString: text) else { return false }
        storage.replaceCharacters(in: range, with: NSAttributedString(string: text, attributes: textView.typingAttributes))
        textView.didChangeText()
        return true
    }

    /// Turns the buffer into `newText` by replacing only the changed regions, in ONE undo group (Cmd-Z restores the previous
    /// text), keeping the caret/selection (mapped through the edits) and scroll position. The caller decides dirtiness.
    @discardableResult
    private func applyMinimalEdit(to newText: String, actionName: String) -> ExternalChange {
        let oldText = textView.string
        let hunks = Self.hunks(from: oldText, to: newText)
        let selection = textView.selectedRange()
        let origin = scrollView.contentView.bounds.origin
        var wholeText = false
        if !hunks.isEmpty {
            textView.breakUndoCoalescing()
            // An implicit per-event group may still be open (earlier edits in this run-loop turn): close it so this edit is its
            // own undo step instead of being folded into theirs.
            while undo.groupingLevel > 0 { undo.endUndoGrouping() }
            undo.beginUndoGrouping()
            for h in hunks.reversed() { _ = replaceRange(h.old, with: h.text) }
            if !Self.same(textView.string, newText) {
                // Safety net: the hunks did not reproduce the new text exactly. Replace everything (still undoable).
                wholeText = true
                _ = replaceRange(NSRange(location: 0, length: (textView.string as NSString).length), with: newText)
            }
            undo.setActionName(actionName)
            undo.endUndoGrouping()
            if !Self.same(textView.string, newText) {
                // A delegate vetoed the edits: integrity beats undo, take the text as is.
                textView.string = newText
                storage.setAttributes(textView.typingAttributes, range: NSRange(location: 0, length: (newText as NSString).length))
                wholeText = true
            }
        }
        let length = (newText as NSString).length
        let lo = min(Self.map(selection.location, through: hunks), length)
        let hi = min(Self.map(NSMaxRange(selection), through: hunks), length)
        textView.setSelectedRange(NSRange(location: lo, length: max(0, hi - lo)))
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        textView.lineEnding = (newText as NSString).range(of: "\r\n").location != NSNotFound ? "\r\n" : "\n"

        var ranges: [NSRange] = []
        var delta = 0
        for h in hunks {
            let n = (h.text as NSString).length
            ranges.append(NSRange(location: h.old.location + delta, length: n))
            delta += n - h.old.length
        }
        if wholeText { ranges = [NSRange(location: 0, length: length)] }
        let ns = newText as NSString
        func line(at location: Int) -> Int {
            var count = 1, i = 0
            while i < min(location, ns.length) { if ns.character(at: i) == 10 { count += 1 }; i += 1 }
            return count
        }
        let change = ExternalChange(url: url, date: Date(), ranges: ranges,
                                    firstLine: ranges.first.map { line(at: $0.location) },
                                    lastLine: ranges.last.map { line(at: max($0.location, NSMaxRange($0) - 1)) },
                                    wholeText: wholeText || hunks.count == 1 && hunks[0].old.length == (oldText as NSString).length)
        lastExternalChange = change
        return change
    }

    private func markClean() {
        idleWork?.cancel(); idleWork = nil
        if isDirty { isDirty = false; onDirtyChange?() }
    }

    /// Replaces the buffer with `text` as one undoable edit and leaves it dirty (used by Local History restore).
    func replaceText(_ text: String, actionName: String) {
        snapshotBuffer()
        applyMinimalEdit(to: text, actionName: actionName)
    }

    // MARK: Disk changes

    private var reloadOptions: OpenOptions { OpenOptions(encoding: encoding, autoDetect: false) }

    private enum DiskProblem { case deleted, directory }
    private var diskProblem: DiskProblem?
    var isDeletedOnDisk: Bool { diskProblem == .deleted }

    /// The buffer as it would be written (nil if the text cannot be encoded).
    private func encodedData() -> Data? {
        guard let body = serializedText().data(using: encoding) else { return nil }
        return hasBOM ? Data(TextEncodings.bomBytes(for: encoding)) + body : body
    }

    /// Copies the buffer into Local History (before it is discarded or replaced).
    private func snapshotBuffer() {
        guard !isLargeFile, let data = encodedData() else { return }
        LocalHistory.snapshot(data, of: url)
    }

    /// Picks up edits made outside the app (agents, git). Clean buffers reload in place as one undoable minimal edit; for dirty
    /// ones the window shows a banner (Reload / Keep mine / Show diff) and nothing is overwritten.
    func reloadIfChangedOnDisk() {
        guard !isReadOnly else { return }
        switch FileIO.kind(url) {
        case .missing:
            if diskProblem != .deleted { diskProblem = .deleted; showDeletedBanner() }
            return
        case .directory:
            if diskProblem != .directory {
                diskProblem = .directory
                pane.showBanner("“\(url.lastPathComponent)” was replaced by a directory on disk.", actions: [
                    ("Save As…", { [weak self] in if let self { self.onSaveAs?(self) } })])
            }
            return
        case .file: break
        }
        guard let stamp = FileIO.stamp(url) else { return }
        let recovered = diskProblem != nil
        if stamp == diskStamp, !recovered { return }
        diskProblem = nil
        if isDirty {
            guard !hasDiskConflict || conflictStamp != stamp else { return }
            conflictStamp = stamp
            hasDiskConflict = true
            showConflictBanner()
            return
        }
        guard case .success(let loaded) = Self.read(url, options: reloadOptions) else { return }
        diskStamp = stamp
        if recovered { clearConflict() }
        guard !Self.same(loaded.text, textView.string) else { return }
        snapshotBuffer()
        hasBOM = loaded.bom
        eol = Self.detectLineEnding(loaded.text)
        let change = applyMinimalEdit(to: loaded.text, actionName: "Reload from Disk")
        markClean()
        flash(change.ranges)
        onExternalReload?(self, change)
    }

    /// Text currently on disk (for the diff view).
    func currentDiskText() -> String? {
        if case .success(let loaded) = Self.read(url, options: reloadOptions) { return loaded.text }
        return nil
    }

    private func showConflictBanner() {
        pane.showBanner("File changed on disk — your unsaved edits are kept.", actions: [
            ("Reload", { [weak self] in self?.reloadFromDisk() }),
            ("Keep mine", { [weak self] in self?.keepMine() }),
            ("Show diff", { [weak self] in if let self { self.onShowDiff?(self) } }),
        ])
    }

    private func showDeletedBanner() {
        pane.showBanner("“\(url.lastPathComponent)” was deleted from disk — your buffer is kept.", actions: [
            ("Recreate", { [weak self] in self?.save(overwriteNewer: true) }),
            ("Save As…", { [weak self] in if let self { self.onSaveAs?(self) } }),
            ("Close", { [weak self] in if let self { self.onCloseRequest?(self) } }),
        ])
    }

    /// Discards the buffer's edits and loads the disk version (as an undoable edit; the discarded text goes to Local History).
    func reloadFromDisk() {
        if case .success(let loaded) = Self.read(url, options: reloadOptions) {
            if isDirty { snapshotBuffer() }
            hasBOM = loaded.bom
            eol = Self.detectLineEnding(loaded.text)
            let change = applyMinimalEdit(to: loaded.text, actionName: "Reload from Disk")
            diskStamp = FileIO.stamp(url)
            markClean()
            flash(change.ranges)
        }
        clearConflict()
    }

    /// Keeps the buffer; a later save may overwrite the disk version without asking again.
    func keepMine() {
        diskStamp = FileIO.stamp(url)
        clearConflict()
    }

    private func clearConflict() {
        hasDiskConflict = false
        conflictStamp = nil
        diskProblem = nil
        saveErrorShown = false
        pane.hideBanner()
    }

    var isBannerVisible: Bool { pane.isBannerVisible }
    var bannerMessage: String { pane.banner.message }
    var bannerButtons: [String] { pane.banner.buttonTitles }
    /// Presses a banner button by title (tests, menus).
    func pressBannerButton(_ title: String) { pane.banner.press(title) }

    /// The disk version is newer than what this buffer was loaded from or last saved as.
    var hasNewerDiskVersion: Bool {
        guard let stamp = FileIO.stamp(url), let known = diskStamp else { return false }
        return stamp != known
    }

    func retarget(to newURL: URL) {
        url = newURL
        if let stamp = FileIO.stamp(newURL) { diskStamp = stamp }
        breadcrumbs.refresh()
    }

    var caretLocation: Int { textView.selectedRange().location }
    var scrollY: Double { Double(scrollView.contentView.bounds.origin.y) }

    func restore(caret: Int, scrollY: Double) {
        let length = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: min(max(0, caret), length), length: 0))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, scrollY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: Flash of externally changed lines

    var isFlashing: Bool { flashView?.superview != nil }
    var flashBandCount: Int { flashView?.superview != nil ? flashView?.bands.count ?? 0 : 0 }

    /// Tints the changed lines for 1.5 s (an overlay above the text view: syntax colours and bracket highlights are untouched).
    func flash(_ ranges: [NSRange], duration: TimeInterval = 1.5) {
        flashView?.removeFromSuperview()
        flashView = nil
        guard !ranges.isEmpty, !isLargeFile, let lm = textView.layoutManager, textView.textContainer != nil else { return }
        let length = storage.length
        guard length > 0 else { return }
        var bands: [NSRect] = []
        let inset = textView.textContainerOrigin
        for r in ranges.prefix(60) {
            var range = r
            if range.length == 0 { range = NSRange(location: min(range.location, length - 1), length: 1) }
            range = NSIntersectionRange(range, NSRange(location: 0, length: length))
            guard range.length > 0 else { continue }
            lm.ensureLayout(forCharacterRange: range)
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            lm.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
                if bands.count < 400 { bands.append(NSRect(x: 0, y: rect.minY + inset.y, width: self.textView.bounds.width, height: rect.height)) }
            }
        }
        guard !bands.isEmpty else { return }
        let overlay = FlashOverlay(frame: textView.bounds)
        overlay.bands = bands
        overlay.autoresizingMask = [.width]
        textView.addSubview(overlay)
        flashView = overlay
        overlay.wantsLayer = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        overlay.layer?.add(fade, forKey: "fade")
        Timer.scheduledTimer(withTimeInterval: duration + 0.1, repeats: false) { [weak overlay] _ in overlay?.removeFromSuperview() }
    }

    // MARK: Encoding

    var encodingName: String { TextEncodings.name(encoding, bom: hasBOM) }

    /// "Save with encoding": the next save writes the text in `new`. False if some character cannot be represented.
    @discardableResult
    func setSaveEncoding(_ new: String.Encoding) -> Bool {
        guard !isReadOnly, !isLossyDecoded, serializedText().data(using: new) != nil else { return false }
        encoding = new
        hasBOM = new == .utf16LittleEndian || new == .utf16BigEndian
        if !isDirty { isDirty = true; onDirtyChange?() }
        return true
    }

    // MARK: Saving

    private var saveStarted = Date.distantPast

    /// Writes the buffer (keeping the file's real target, permissions, encoding, BOM and line endings). Returns true only if the
    /// write has happened by the time this returns (a will-save hook may finish asynchronously: use `completion`).
    /// A newer disk version is never overwritten silently: the user is asked (headless runs decline).
    @discardableResult
    func save(overwriteNewer: Bool = false, overwriteReadOnly: Bool = false, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard !isReadOnly, !isLossyDecoded else { completion?(false); return false }
        if saveInFlight, Date().timeIntervalSince(saveStarted) < 15 { completion?(false); return false }
        if !overwriteNewer, hasNewerDiskVersion {
            if AppEnv.headless { completion?(false); return false }
            let alert = NSAlert()
            alert.messageText = "“\(url.lastPathComponent)” changed on disk"
            alert.informativeText = "Saving will overwrite the newer version on disk with your buffer."
            alert.addButton(withTitle: "Overwrite")
            alert.addButton(withTitle: "Show Diff")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: break
            case .alertSecondButtonReturn: onShowDiff?(self); completion?(false); return false
            default: completion?(false); return false
            }
            return runSave(auto: false, allowNewer: true, overwriteReadOnly: overwriteReadOnly, completion: completion)
        }
        return runSave(auto: false, allowNewer: overwriteNewer, overwriteReadOnly: overwriteReadOnly, completion: completion)
    }

    private func runSave(auto: Bool, allowNewer: Bool, overwriteReadOnly: Bool, completion: ((Bool) -> Void)?) -> Bool {
        saveInFlight = true
        saveStarted = Date()
        var proceeded = false
        var finished = false
        var ok = false
        EditorEvents.notifyWillSave(self) { [weak self] in
            guard !proceeded else { return }
            proceeded = true
            guard let self else { completion?(false); return }
            ok = self.writeNow(auto: auto, allowNewer: allowNewer, overwriteReadOnly: overwriteReadOnly)
            self.saveInFlight = false
            finished = true
            completion?(ok)
        }
        return finished && ok
    }

    private func writeNow(auto: Bool, allowNewer: Bool, overwriteReadOnly: Bool) -> Bool {
        // The disk may have moved on while a will-save hook (formatter) was running.
        if !allowNewer, hasNewerDiskVersion {
            if !hasDiskConflict { reloadIfChangedOnDisk() }
            return false
        }
        if auto, textView.hasMarkedText() { return false }
        guard let data = encodedData() else {
            showSaveError(FileIOError.cannotEncode(encodingName))
            return false
        }
        if !isLargeFile { LocalHistory.snapshotDisk(of: url) }
        do {
            try FileIO.write(data, to: url, overwriteReadOnly: overwriteReadOnly)
        } catch {
            showSaveError(error)
            return false
        }
        markClean()
        diskStamp = FileIO.stamp(url)
        diskProblem = nil
        clearConflict()
        onDirtyChange?()
        onSave?()
        EditorEvents.notifySaved(self)
        return true
    }

    private func showSaveError(_ error: Error) {
        saveErrorShown = true
        let name = url.lastPathComponent
        let saveAs: (String, () -> Void) = ("Save As…", { [weak self] in if let self { self.onSaveAs?(self) } })
        switch error as? FileIOError {
        case .readOnly:
            pane.showBanner("“\(name)” is read-only on disk. Overwrite it?", actions: [
                ("Overwrite", { [weak self] in self?.save(overwriteReadOnly: true) }), saveAs])
        case .isDirectory:
            pane.showBanner("Can’t save: “\(name)” is now a directory.", actions: [saveAs])
        case .cannotEncode(let encodingName):
            pane.showBanner("Can’t save as \(encodingName): the text has characters it cannot represent.", actions: [
                ("Save as UTF-8", { [weak self] in if let self, self.setSaveEncoding(.utf8) { self.saveErrorShown = false; self.save() } }),
                ("Dismiss", { [weak self] in self?.clearConflict() })])
        default:
            pane.showBanner("Couldn’t save “\(name)”: \(error.localizedDescription)", actions: [
                ("Retry", { [weak self] in self?.save() }), saveAs])
        }
    }

    // MARK: Auto-save

    /// Saves a modified buffer on app/window focus loss, tab switch or idle. Never overwrites a newer disk version (the
    /// dirty-vs-disk banner is shown instead), never saves mid-IME composition, lossy-decoded, read-only, large or vanished files.
    @discardableResult
    func autoSave(_ trigger: AutoSave.Trigger) -> AutoSave.Outcome {
        guard AutoSave.enabled(for: trigger) else { return .skipped("disabled") }
        guard isDirty else { return .skipped("clean") }
        guard !isReadOnly else { return .skipped("read-only") }
        guard !isLossyDecoded else { return .skipped("lossy encoding") }
        guard !isLargeFile else { return .skipped("large file") }
        guard textView.hasMarkedText() == false else { return .skipped("composing") }
        guard FileIO.kind(url) == .file else { reloadIfChangedOnDisk(); return .skipped("missing on disk") }
        guard !hasDiskConflict else { return .skipped("disk conflict") }
        if hasNewerDiskVersion { reloadIfChangedOnDisk(); return .skipped("disk newer") }
        guard !saveErrorShown else { return .skipped("save error pending") }
        guard !saveInFlight || Date().timeIntervalSince(saveStarted) >= 15 else { return .skipped("busy") }
        var done = false
        let ok = runSave(auto: true, allowNewer: false, overwriteReadOnly: false) { _ in done = true }
        if ok { return .saved }
        return done ? .skipped("not saved") : .pending
    }

    var hasPendingIdleSave: Bool { idleWork != nil }

    private func scheduleIdleSave() {
        idleWork?.cancel()
        idleWork = nil
        let seconds = AutoSave.idleSeconds
        guard seconds > 0 else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.idleWork = nil
            if self.textView.hasMarkedText() { self.scheduleIdleSave(); return }
            self.autoSave(.idle)
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

/// Translucent bands over freshly reloaded lines; never takes events.
final class FlashOverlay: NSView {
    var bands: [NSRect] = []
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemYellow.withAlphaComponent(Theme.isDark ? 0.22 : 0.38).setFill()
        for band in bands where band.intersects(dirtyRect) { band.fill() }
    }
}
