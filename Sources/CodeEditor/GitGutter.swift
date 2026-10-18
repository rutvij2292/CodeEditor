import AppKit

/// Live git change markers in the editor gutter: the buffer is diffed against HEAD (debounced, off the main thread)
/// so the bars update while typing. Call `GitGutter.start()` once at launch (also done lazily by the first CodeTextView).
enum GitGutter {
    /// Post (object: nil) when git state changed (commit, checkout, stage...). Every tab re-reads its HEAD content.
    static let statusChanged = Notification.Name("CodeEditor.gitStatusChanged")

    private static var started = false
    private static var controllers: [ObjectIdentifier: GitGutterController] = [:]

    static func start() {
        guard !started else { return }
        started = true
        EditorEvents.onOpen { tab in
            let c = GitGutterController(tab: tab)
            controllers[ObjectIdentifier(tab)] = c
            c.begin()
        }
        EditorEvents.onClose { tab in
            controllers.removeValue(forKey: ObjectIdentifier(tab))?.end()
        }
        EditorEvents.onSave { tab in controllers[ObjectIdentifier(tab)]?.reloadHead() }
    }

    /// Controller for a tab (tests / integrators).
    static func controller(for tab: EditorTab) -> GitGutterController? { controllers[ObjectIdentifier(tab)] }

    // MARK: diff

    /// One changed block: 0-based half-open line ranges in HEAD (`old`) and in the buffer (`new`).
    struct Hunk: Equatable {
        var old: Range<Int>
        var new: Range<Int>
        var markers: [GutterMarker]
    }

    /// CRLF and LF compare equal (like DiffEngine).
    private static func normalized(_ line: String) -> String {
        guard line.utf8.last == 10 else { return line }
        var u = Array(line.utf8.dropLast())
        if u.last == 13 { u.removeLast() }
        return String(decoding: u, as: UTF8.self) + "\n"
    }

    /// Hunks of `new` against `old` (HEAD). Pure; safe off the main thread.
    static func hunks(old: String, new: String) -> [Hunk] {
        let a = DiffEngine.splitLines(old), b = DiffEngine.splitLines(new)
        let ids = DiffEngine.intern([a.map(normalized), b.map(normalized)])
        let ops = DiffEngine.edit(ids[0], ids[1], maxD: 2000)
        var out: [Hunk] = []
        var i = 0, j = 0, k = 0
        while k < ops.count {
            if ops[k] == .equal { i += 1; j += 1; k += 1; continue }
            var dels = 0, ins = 0
            while k < ops.count, ops[k] != .equal {
                if ops[k] == .delete { dels += 1 } else { ins += 1 }
                k += 1
            }
            let paired = min(dels, ins)
            var markers: [GutterMarker] = []
            // Gutter lines are 1-based.
            if paired > 0 { markers.append(GutterMarker(lines: (j + 1)..<(j + paired + 1), kind: .modified)) }
            if ins > paired { markers.append(GutterMarker(lines: (j + paired + 1)..<(j + ins + 1), kind: .added)) }
            if dels > 0, ins == 0 { markers.append(GutterMarker(lines: (j + 1)..<(j + 1), kind: .deleted)) }
            out.append(Hunk(old: i..<(i + dels), new: j..<(j + ins), markers: markers))
            i += dels; j += ins
        }
        return out
    }

    // MARK: revert

    /// Range of lines [lines) in `s` as UTF-16 characters (clamped to the end of text).
    static func charRange(ofLines lines: Range<Int>, in s: NSString) -> NSRange {
        var loc = 0, n = 0
        func advance(to line: Int) {
            while n < line, loc < s.length {
                let r = s.range(of: "\n", options: .literal, range: NSRange(location: loc, length: s.length - loc))
                loc = r.location == NSNotFound ? s.length : NSMaxRange(r)
                n += 1
            }
        }
        advance(to: lines.lowerBound)
        let start = loc
        advance(to: lines.upperBound)
        return NSRange(location: start, length: loc - start)
    }

    /// Text that replaces the hunk's buffer lines when reverting: HEAD lines with the buffer's line endings.
    static func revertText(hunk: Hunk, head: String, buffer: NSString, eol: String) -> (range: NSRange, text: String) {
        let oldLines = DiffEngine.splitLines(head)
        let range = charRange(ofLines: hunk.new, in: buffer)
        func strip(_ l: String) -> String {
            var u = Array(l.utf8)
            if u.last == 10 { u.removeLast() }
            if u.last == 13 { u.removeLast() }
            return String(decoding: u, as: UTF8.self)
        }
        let body = oldLines[hunk.old].map(strip)
        var text = body.joined(separator: eol)
        let endsWithTerminator = range.length > 0 && {
            let c = buffer.character(at: NSMaxRange(range) - 1); return c == 10 || c == 13
        }()
        if !body.isEmpty, endsWithTerminator || range.length == 0 { text += eol }
        // Insert-only revert at the very end of a buffer lacking a final terminator: separate from the last line.
        if range.length == 0, !body.isEmpty, range.location == buffer.length, buffer.length > 0 {
            let c = buffer.character(at: buffer.length - 1)
            if c != 10 && c != 13 { text = eol + body.joined(separator: eol) }
        }
        return (range, text)
    }

    /// Old / new lines of a hunk for display and clipboard.
    static func oldText(hunk: Hunk, head: String) -> String {
        DiffEngine.splitLines(head)[hunk.old].joined()
    }
}

// MARK: - Per-tab controller

final class GitGutterController {
    private weak var tab: EditorTab?
    private weak var textView: CodeTextView?
    private weak var gutter: GutterView?
    private let url: URL
    private var relPath: String?
    private var root: URL?
    private(set) var head: String?
    private(set) var hunks: [GitGutter.Hunk] = []
    private var generation = 0
    private var debounce: DispatchWorkItem?
    private var popover: NSPopover?
    private static let queue = DispatchQueue(label: "GitGutter", qos: .utility)
    private static var rootCache: [String: URL?] = [:]
    private static let cacheLock = NSLock()
    /// Called on the main thread after markers were published (tests).
    var onUpdate: (() -> Void)?

    init(tab: EditorTab) {
        self.tab = tab
        self.url = tab.url
        self.textView = tab.textView
        self.gutter = (tab.view as? EditorContainer)?.gutter
    }

    func begin() {
        guard let tv = textView, let gutter else { return }
        gutter.onMarkerClick = { [weak self] m, r in self?.showPopover(for: m, rect: r) }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(textChanged), name: NSText.didChangeNotification, object: tv)
        nc.addObserver(self, selector: #selector(statusChanged), name: GitGutter.statusChanged, object: nil)
        reloadHead(resolveRoot: true)
    }

    func end() {
        NotificationCenter.default.removeObserver(self)
        debounce?.cancel()
        generation += 1
        popover?.close()
        gutter?.onMarkerClick = nil
    }

    @objc private func statusChanged() {
        Self.cacheLock.lock(); Self.rootCache.removeAll(); Self.cacheLock.unlock()
        reloadHead(resolveRoot: true)
    }
    @objc private func textChanged() { schedule(after: 0.3) }

    /// Re-reads HEAD for this file off the main thread, then recomputes markers.
    func reloadHead(resolveRoot: Bool = false) {
        let url = self.url
        let known = relPath
        Self.queue.async { [weak self] in
            var rootURL: URL?, rel = known
            if rel == nil || resolveRoot {
                let key = url.deletingLastPathComponent().path
                Self.cacheLock.lock(); let cached = Self.rootCache[key]; Self.cacheLock.unlock()
                if let cached { rootURL = cached } else {
                    rootURL = GitRepo.repoRoot(for: url)
                    Self.cacheLock.lock(); Self.rootCache[key] = .some(rootURL); Self.cacheLock.unlock()
                }
                if let r = rootURL {
                    let file = url.resolvingSymlinksInPath().path, base = r.resolvingSymlinksInPath().path
                    rel = file.hasPrefix(base + "/") ? String(file.dropFirst(base.count + 1)) : nil
                }
            } else {
                rootURL = self?.root
            }
            var content: String?
            if let r = rootURL, let rel {
                content = (try? GitRepo(root: r).headContent(of: rel)) ?? nil
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.root = rootURL; self.relPath = rel; self.head = content
                self.schedule(after: 0)
            }
        }
    }

    private func schedule(after delay: TimeInterval) {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recompute() }
        debounce = work
        if delay == 0 { DispatchQueue.main.async(execute: work) }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    }

    private func recompute() {
        guard let tv = textView, let gutter else { return }
        guard let head else {
            hunks = []
            gutter.markers = []
            onUpdate?()
            return
        }
        generation += 1
        let gen = generation
        let text = tv.string
        Self.queue.async { [weak self] in
            let hunks = GitGutter.hunks(old: head, new: text)
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                self.hunks = hunks
                self.gutter?.markers = hunks.flatMap { $0.markers }
                self.onUpdate?()
            }
        }
    }

    // MARK: popover

    private func hunk(for marker: GutterMarker) -> GitGutter.Hunk? { hunks.first { $0.markers.contains(marker) } }

    func showPopover(for marker: GutterMarker, rect: NSRect) {
        guard let head, let tv = textView, let gutter, let hunk = hunk(for: marker) else { return }
        popover?.close()
        let content = HunkPopoverView(hunk: hunk, head: head, buffer: tv.string as NSString)
        content.onRevert = { [weak self] in self?.revert(hunk) }
        content.onCopy = { [weak self] in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(GitGutter.oldText(hunk: hunk, head: head), forType: .string)
            self?.popover?.close()
        }
        let vc = NSViewController()
        vc.view = content
        let p = NSPopover()
        p.contentViewController = vc
        p.behavior = .transient
        p.animates = false
        popover = p
        if AppEnv.headless { return }   // never open windows during verification
        p.show(relativeTo: rect, of: gutter, preferredEdge: .maxX)
    }

    /// Replaces the hunk's buffer lines with the HEAD lines as one undo step. Returns false if the buffer moved on.
    @discardableResult
    func revert(_ hunk: GitGutter.Hunk) -> Bool {
        guard let head, let tv = textView else { return false }
        // Re-diff the live buffer so a stale hunk can never clobber unrelated text.
        let live = GitGutter.hunks(old: head, new: tv.string)
        guard let current = live.first(where: { $0.old == hunk.old }) else {
            recompute(); popover?.close(); return false
        }
        let edit = GitGutter.revertText(hunk: current, head: head, buffer: tv.string as NSString, eol: tv.lineEnding)
        tv.replaceUndoable(edit.range, with: edit.text)
        popover?.close()
        schedule(after: 0)
        return true
    }
}

// MARK: - Popover content

/// Old-vs-new view of one hunk with Revert / Copy old buttons.
final class HunkPopoverView: NSView {
    var onRevert: (() -> Void)?
    var onCopy: (() -> Void)?

    init(hunk: GitGutter.Hunk, head: String, buffer: NSString) {
        let width: CGFloat = 520
        let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        var oldLines = DiffEngine.splitLines(head)[hunk.old].map(Self.strip)
        let newRange = GitGutter.charRange(ofLines: hunk.new, in: buffer)
        var newLines = DiffEngine.splitLines(buffer.substring(with: newRange)).map(Self.strip)
        // Drop the indentation shared by every line so deep code stays readable.
        func indentWidth(_ l: String) -> Int? {
            let n = l.prefix { $0 == " " || $0 == "\t" }.count
            return n == l.count ? nil : n
        }
        if let common = (oldLines + newLines).compactMap(indentWidth).min(), common > 0 {
            oldLines = oldLines.map { $0.count >= common ? String($0.dropFirst(common)) : $0 }
            newLines = newLines.map { $0.count >= common ? String($0.dropFirst(common)) : $0 }
        }
        let red = NSColor(srgbRed: 0.90, green: 0.30, blue: 0.30, alpha: Theme.isDark ? 0.28 : 0.16)
        let green = NSColor(srgbRed: 0.30, green: 0.70, blue: 0.35, alpha: Theme.isDark ? 0.28 : 0.18)
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byClipping
        let text = NSMutableAttributedString()
        func add(_ lines: [String], prefix: String, bg: NSColor) {
            for l in lines.prefix(60) {
                text.append(NSAttributedString(string: prefix + l + "\n", attributes: [
                    .font: mono, .foregroundColor: Theme.foreground, .backgroundColor: bg, .paragraphStyle: para]))
            }
            if lines.count > 60 {
                text.append(NSAttributedString(string: "  ... \(lines.count - 60) more lines\n",
                                               attributes: [.font: mono, .foregroundColor: Theme.gutter]))
            }
        }
        add(oldLines, prefix: "- ", bg: red)
        add(newLines, prefix: "+ ", bg: green)

        let rows = CGFloat(min(60, oldLines.count) + min(60, newLines.count))
        let textHeight = min(260, max(34, rows * 14 + 12))
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: textHeight + 44))

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: textHeight))
        tv.isEditable = false
        tv.isRichText = true
        tv.drawsBackground = true
        tv.backgroundColor = Theme.background
        tv.textContainerInset = NSSize(width: 6, height: 4)
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude)
        tv.isHorizontallyResizable = true
        tv.textStorage?.setAttributedString(text)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 44, width: width, height: textHeight))
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.background
        addSubview(scroll)

        let revert = NSButton(title: "Revert", target: self, action: #selector(revertTapped))
        let copy = NSButton(title: "Copy old", target: self, action: #selector(copyTapped))
        for b in [revert, copy] { b.bezelStyle = .rounded; b.controlSize = .small; addSubview(b) }
        revert.frame = NSRect(x: width - 160, y: 10, width: 70, height: 24)
        copy.frame = NSRect(x: width - 84, y: 10, width: 76, height: 24)
        let title = NSTextField(labelWithString: "Lines \(hunk.new.lowerBound + 1)–\(max(hunk.new.lowerBound + 1, hunk.new.upperBound))  (HEAD \(hunk.old.count) → \(hunk.new.count))")
        title.font = .systemFont(ofSize: 11)
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: 10, y: 14, width: width - 180, height: 16)
        addSubview(title)
    }
    required init?(coder: NSCoder) { fatalError() }

    private static func strip(_ l: String) -> String {
        var u = Array(l.utf8)
        if u.last == 10 { u.removeLast() }
        if u.last == 13 { u.removeLast() }
        return String(decoding: u, as: UTF8.self)
    }

    @objc private func revertTapped() { onRevert?() }
    @objc private func copyTapped() { onCopy?() }
}
