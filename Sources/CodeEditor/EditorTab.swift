import AppKit

/// One open file: scroll view + text view + highlighter.
final class EditorTab: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
    let url: URL
    let scrollView = NSScrollView()
    private(set) var view: NSView!
    let textView: CodeTextView
    private var highlighter: Highlighter?
    private let storage: NSTextStorage
    private(set) var isDirty = false
    var onDirtyChange: (() -> Void)?
    var onSave: (() -> Void)?
    private var diskDate: Date?
    private(set) var indent = IndentSettings.standard
    private var paragraph: NSParagraphStyle = .default

    init?(url: URL) {
        self.url = url
        guard let data = try? Data(contentsOf: url), data.count < 5_000_000,
              let text = String(data: data, encoding: .utf8) else { return nil }
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
        textView.commentStyle = CodeTextView.commentStyle(forExtension: url.pathExtension)
        diskDate = Self.modificationDate(url)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.background
        view = EditorContainer(scrollView: scrollView, gutter: GutterView(textView: textView, scrollView: scrollView))

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

    var lineEnding: String { textView.string.contains("\r\n") ? "CRLF" : "LF" }

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
        highlighter?.apply()
    }

    /// Picks up edits made outside the app (agents, git). Clean buffers reload in place; dirty ones are left alone.
    func reloadIfChangedOnDisk() {
        guard !isDirty, let date = Self.modificationDate(url), date != diskDate,
              let data = try? Data(contentsOf: url), data.count < 5_000_000,
              let text = String(data: data, encoding: .utf8) else { return }
        diskDate = date
        guard text != textView.string else { return }
        let selection = textView.selectedRange()
        let origin = scrollView.contentView.bounds.origin
        textView.string = text
        textView.textStorage?.setAttributes(textView.typingAttributes,
                                            range: NSRange(location: 0, length: (text as NSString).length))
        textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        scrollView.contentView.scroll(to: origin)
        highlighter?.reparse()
        textView.undoManager?.removeAllActions()
    }

    func save() {
        do {
            try textView.string.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            diskDate = Self.modificationDate(url)
            onDirtyChange?()
            onSave?()
            EditorEvents.notifySaved(self)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
