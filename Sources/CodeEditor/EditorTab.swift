import AppKit

/// One open file: scroll view + text view + highlighter.
final class EditorTab: NSObject, NSTextViewDelegate {
    let url: URL
    let scrollView = NSScrollView()
    private(set) var view: NSView!
    let textView: CodeTextView
    private var highlighter: Highlighter?
    private var reparseWork: DispatchWorkItem?
    private(set) var isDirty = false
    var onDirtyChange: (() -> Void)?
    var onSave: (() -> Void)?
    private var diskDate: Date?

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
        textView.typingAttributes = [.font: Theme.font, .foregroundColor: Theme.foreground]
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

        highlighter = Highlighter(textView: textView, extension: url.pathExtension)
        EditorEvents.notifyOpened(self)
    }

    func textDidChange(_ notification: Notification) {
        if !isDirty { isDirty = true; onDirtyChange?() }
        reparseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.highlighter?.reparse() }
        reparseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private static func modificationDate(_ url: URL) -> Date? {
        // URL caches resource values, so ask the file system directly.
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    @objc private func themeChanged() {
        textView.textColor = Theme.foreground
        textView.backgroundColor = Theme.background
        textView.insertionPointColor = Theme.foreground
        textView.typingAttributes = [.font: Theme.font, .foregroundColor: Theme.foreground]
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
