import AppKit

enum BlameLineInfo: Equatable {
    case commit(Int)       // index into BlameData.commits
    case uncommitted       // modified in the buffer or the working tree
    case none              // no blame for this line
}

/// Per-tab blame state: loads blame off-main, maps buffer lines through unsaved edits and drives the inline annotation
/// and the annotate column.
final class BlameController {
    /// "Open in Git Log": the integrator wires this to the Commit window's Log tab (hash, file shown in the editor).
    static var onShowCommit: ((String, URL) -> Void)?

    struct Loaded {
        var data: BlameData
        var base: String                 // file text blame was computed for
        var stamp: FileStamp
        var root: URL
        var rel: String
        var you: (name: String, email: String)
    }

    private(set) weak var tab: EditorTab?
    private(set) weak var textView: CodeTextView?
    private(set) weak var scrollView: NSScrollView?
    private(set) var loaded: Loaded?
    /// File is untracked / ignored / outside a repo / binary / has no commit.
    private(set) var isUnavailable = false
    private var loading = false
    private var loadGen = 0
    private var textRevision = 0
    private var lineMap: [Int32]?
    private(set) var mapValid = false
    private var mapGen = 0
    private var mapLineCount = 0
    private var mapDebounce: DispatchWorkItem?
    private var inlineTimer: DispatchWorkItem?
    private var inlineLine = -1

    // line start cache
    private var lineStartsRev = -1
    private var lineStarts: [Int] = [0]

    // views
    private(set) var chip: BlameChip?
    private(set) var strip: BlameAnnotateView?
    private var wantAnnotate = false
    private var savedLeadingConstant: CGFloat = 0
    private var leadingConstraint: NSLayoutConstraint?
    private var popover: NSPopover?
    /// The last popover content (tests render it; popovers are never shown while headless).
    private(set) var popoverContent: NSView?
    private var hoverTimer: Timer?
    /// Called on the main thread after data or the line mapping changed (tests).
    var onUpdate: (() -> Void)?

    private static var rootCache: [String: URL?] = [:]
    private static let rootLock = NSLock()

    init(tab: EditorTab) {
        self.tab = tab
        textView = tab.textView
        scrollView = tab.scrollView
    }

    var isAnnotating: Bool { strip != nil }
    var url: URL? { tab?.url }

    // MARK: lifecycle

    func begin() {
        guard let tv = textView, let sv = scrollView else { return }
        sv.contentView.postsBoundsChangedNotifications = true
        tv.postsFrameChangedNotifications = true
        let nc = NotificationCenter.default
        if let storage = tv.textStorage {
            nc.addObserver(self, selector: #selector(storageProcessed(_:)), name: NSTextStorage.didProcessEditingNotification, object: storage)
        }
        nc.addObserver(self, selector: #selector(selectionChanged), name: NSTextView.didChangeSelectionNotification, object: tv)
        nc.addObserver(self, selector: #selector(layoutChanged), name: NSView.frameDidChangeNotification, object: tv)
        nc.addObserver(self, selector: #selector(prefsChanged(_:)), name: Prefs.didChange, object: nil)
        nc.addObserver(self, selector: #selector(themeChanged), name: Theme.didChange, object: nil)
        nc.addObserver(self, selector: #selector(gitStateChanged), name: GitGutter.statusChanged, object: nil)
        nc.addObserver(self, selector: #selector(appActivated), name: NSApplication.didBecomeActiveNotification, object: nil)
        if Prefs.inlineBlame { reload() }
    }

    func end() {
        NotificationCenter.default.removeObserver(self)
        mapDebounce?.cancel(); inlineTimer?.cancel(); hoverTimer?.invalidate()
        loadGen += 1; mapGen += 1
        popover?.close(); popover = nil
        setAnnotate(false)
        chip?.removeFromSuperview(); chip = nil
        if let u = url { BlameCache.shared.drop(file: u.resolvingSymlinksInPath().path) }
        loaded = nil; lineMap = nil
    }

    // MARK: loading

    @objc private func gitStateChanged() {
        Self.rootLock.lock(); Self.rootCache.removeAll(); Self.rootLock.unlock()
        BlameCache.shared.removeAll()
        GitRepo.forgetCaches()
        reload()
    }

    @objc private func appActivated() { if loaded != nil || wantAnnotate { checkStale() } }

    /// Reloads when the file changed on disk since the blame was computed.
    func checkStale() {
        guard let url, let loaded else { return }
        if FileIO.stamp(url) != loaded.stamp { reload() }
    }

    private static func resolve(_ url: URL) -> (root: URL, rel: String)? {
        let key = url.deletingLastPathComponent().path
        rootLock.lock(); let cached = rootCache[key]; rootLock.unlock()
        let root: URL?
        if let cached { root = cached } else {
            root = GitRepo.repoRoot(for: url)
            rootLock.lock(); rootCache[key] = .some(root); rootLock.unlock()
        }
        guard let root else { return nil }
        let file = url.resolvingSymlinksInPath().path, base = root.resolvingSymlinksInPath().path
        guard file.hasPrefix(base + "/") else { return nil }
        return (root, String(file.dropFirst(base.count + 1)))
    }

    /// Computes (or fetches from the cache) the blame of the file on disk, in the background.
    func reload() {
        guard let url = tab?.url, tab?.isLargeFile == false else { return }
        loadGen += 1
        let gen = loadGen
        loading = true
        Blame.gitQueue.async { [weak self] in
            var result: Loaded?
            for _ in 0..<2 {
                guard let (root, rel) = Self.resolve(url), let stamp = FileIO.stamp(url),
                      let raw = try? Data(contentsOf: url), !raw.prefix(8000).contains(0) else { break }
                let repo = GitRepo(root: root)
                let head = repo.headOID()
                guard !head.isEmpty else { break }
                let key = BlameCache.key(file: url.resolvingSymlinksInPath().path, head: head, stamp: stamp)
                var data = BlameCache.shared.get(key)
                if data == nil {
                    guard let fresh = try? repo.blameData(path: rel), fresh.lineCount <= 200_000 else { break }
                    data = fresh
                    BlameCache.shared.put(key, file: url.resolvingSymlinksInPath().path, fresh)
                }
                if FileIO.stamp(url) != stamp { continue }          // the file moved on while blaming: once more
                var bytes = raw
                if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
                result = Loaded(data: data!, base: String(decoding: bytes, as: UTF8.self), stamp: stamp, root: root, rel: rel,
                                you: repo.userIdentity())
                break
            }
            DispatchQueue.main.async {
                guard let self, self.loadGen == gen else { return }
                self.loading = false
                self.loaded = result
                self.isUnavailable = result == nil
                if result == nil, self.wantAnnotate { self.wantAnnotate = false }
                if result != nil, self.wantAnnotate, self.strip == nil { self.install() }
                self.recomputeMap()
                NotificationCenter.default.post(name: Blame.didUpdate, object: nil)
            }
        }
    }

    // MARK: edits and line mapping

    @objc private func storageProcessed(_ n: Notification) {
        guard let storage = n.object as? NSTextStorage, storage.editedMask.contains(.editedCharacters) else { return }
        textRevision += 1
        mapValid = false
        hideChip()
        strip?.needsDisplay = true
        mapDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.recomputeMap() }
        mapDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (isAnnotating ? 0.12 : 0.25), execute: work)
    }

    private func recomputeMap() {
        guard let loaded, let tv = textView else { mapValid = false; publish(); return }
        let rev = textRevision
        let text = tv.string
        let base = loaded.base
        Blame.mapQueue.async { [weak self] in
            let map = Blame.lineMap(base: base, buffer: text)
            DispatchQueue.main.async {
                guard let self, self.textRevision == rev else { return }
                self.lineMap = map
                self.mapValid = true
                self.ensureLineStarts()
                self.mapLineCount = self.lineStarts.count
                self.publish()
            }
        }
    }

    private func publish() {
        strip?.needsDisplay = true
        updateInline()
        onUpdate?()
    }

    /// Blame classification of a buffer line (0-based). Lines past the end of the file have none.
    func info(forBufferLine line: Int) -> BlameLineInfo {
        guard let loaded, line >= 0 else { return .none }
        var baseLine = line
        if let map = lineMap {
            guard line < map.count else { return .none }
            if map[line] < 0 { return .uncommitted }
            baseLine = Int(map[line])
        }
        guard let ci = loaded.data.commitIndex(atLine: baseLine) else { return .none }
        return loaded.data.commits[ci].isUncommitted ? .uncommitted : .commit(ci)
    }

    /// The line mapping is current, or (while typing) still valid because no line was added or removed.
    var canDrawStrip: Bool {
        guard loaded != nil else { return false }
        if mapValid { return true }
        ensureLineStarts()
        return mapLineCount == lineStarts.count && mapLineCount > 0
    }

    func commit(at index: Int) -> BlameCommit? {
        guard let loaded, index >= 0, index < loaded.data.commits.count else { return nil }
        return loaded.data.commits[index]
    }

    // MARK: line index helpers

    func ensureLineStarts() {
        guard lineStartsRev != textRevision, let s = textView?.string as NSString? else { return }
        var starts = [0]
        let len = s.length
        var buf = [unichar](repeating: 0, count: 8192)
        var pos = 0
        while pos < len {
            let chunk = min(buf.count, len - pos)
            s.getCharacters(&buf, range: NSRange(location: pos, length: chunk))
            for i in 0..<chunk where buf[i] == 10 { starts.append(pos + i + 1) }
            pos += chunk
        }
        lineStarts = starts
        lineStartsRev = textRevision
    }

    /// 0-based line of a character offset.
    func lineIndex(ofChar c: Int) -> Int {
        ensureLineStarts()
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= c { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    var lineCount: Int { ensureLineStarts(); return lineStarts.count }

    // MARK: inline annotation

    @objc private func selectionChanged() {
        guard Prefs.inlineBlame || chip != nil, let tv = textView else { return }
        let sel = tv.selectedRange()
        let line = lineIndex(ofChar: sel.location)
        if line == inlineLine, chip?.isHidden == false, sel.length == 0 { return }
        hideChip()
        scheduleInline()
    }

    @objc private func layoutChanged() { if chip?.isHidden == false { placeChip() } }

    @objc private func themeChanged() {
        chip?.restyle(font: annotationFont())
        strip?.restyle()
        if chip?.isHidden == false { placeChip() }
    }

    @objc private func prefsChanged(_ n: Notification) {
        let key = n.userInfo?["key"] as? String
        if key == "inlineBlame" {
            if Prefs.inlineBlame {
                if loaded == nil, !loading { reload() } else { scheduleInline(delay: 0) }
            } else { hideChip() }
        } else if key == "editorFontName" || key == "editorFontSize" || key == "lineHeightMultiple" {
            chip?.restyle(font: annotationFont())
            strip?.restyle()
            if isAnnotating { applyStripWidth() }
            if chip?.isHidden == false { placeChip() }
        }
    }

    func scheduleInline(delay: TimeInterval = 0.25) {
        inlineTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateInline() }
        inlineTimer = work
        if delay == 0 { DispatchQueue.main.async(execute: work) }
        else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }
    }

    func hideChip() {
        chip?.isHidden = true
        hoverTimer?.invalidate()
    }

    func annotationFont() -> NSFont {
        let base = textView?.font ?? Theme.font
        let size = max(8, base.pointSize - 1)
        let f = NSFont(name: base.fontName, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let italic = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask)
        return italic
    }

    /// Current inline text (nil while hidden).
    private(set) var inlineText: String?
    private var inlineCommitIndex: Int?

    func updateInline() {
        inlineTimer = nil
        guard Prefs.inlineBlame, let tab, !tab.isLargeFile, let tv = textView, let loaded, mapValid, !isUnavailable else {
            if chip != nil { hideChip() }
            inlineText = nil
            return
        }
        let text = tv.string as NSString
        let sel = tv.selectedRange()
        let loc = min(sel.location, text.length)
        let isLast = loc == text.length && (text.length == 0 || text.character(at: text.length - 1) == 10)
        let line = lineIndex(ofChar: loc)
        if isLast || (sel.length > 0 && lineIndex(ofChar: min(NSMaxRange(sel), text.length)) != line) {
            hideChip(); inlineText = nil; return
        }
        let lineRange = text.lineRange(for: NSRange(location: loc, length: 0))
        if Blame.suppressInline?(tab, lineRange) == true { hideChip(); inlineText = nil; return }
        let state = info(forBufferLine: line)
        let string: String
        switch state {
        case .none: hideChip(); inlineText = nil; return
        case .uncommitted: string = Blame.uncommittedText; inlineCommitIndex = nil
        case .commit(let i): string = Blame.annotation(for: loaded.data.commits[i], you: loaded.you); inlineCommitIndex = i
        }
        inlineLine = line
        inlineText = string
        if chip == nil {
            let c = BlameChip()
            c.onClick = { [weak self] in self?.showInlinePopover() }
            c.onHover = { [weak self] inside in self?.chipHover(inside) }
            tv.addSubview(c)
            chip = c
        }
        chip?.set(text: string, font: annotationFont(), clickable: inlineCommitIndex != nil)
        placeChip()
    }

    /// Positions the chip after the end of the caret line (last fragment when soft-wrapped). Hides it when the line is folded
    /// away or there is no room.
    func placeChip() {
        guard let tv = textView, let chip, let lm = tv.layoutManager, tv.textContainer != nil, inlineText != nil else { return }
        let text = tv.string as NSString
        let loc = min(tv.selectedRange().location, text.length)
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: loc, length: 0))
        let lineRange = NSRange(location: start, length: end - start)
        lm.ensureLayout(forCharacterRange: lineRange)
        let hasContent = contentsEnd > start
        let glyphChar = hasContent ? contentsEnd - 1 : start
        guard glyphChar < text.length else { chip.isHidden = true; return }
        let glyph = lm.glyphIndexForCharacter(at: glyphChar)
        if hasContent, lm.notShownAttribute(forGlyphAt: lm.glyphIndexForCharacter(at: start)), text.character(at: start) > 32 {
            chip.isHidden = true; return
        }
        let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let used = lm.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        guard frag.height >= 2 else { chip.isHidden = true; return }
        let origin = tv.textContainerOrigin
        let baseline = lm.location(forGlyphAt: glyph).y
        let space = (" " as NSString).size(withAttributes: [.font: chip.font]).width
        var x = origin.x + (hasContent ? used.maxX : 0) + space * 4
        let visible = tv.visibleRect
        x = max(x, visible.minX + 8)
        let limit = visible.maxX - 6
        let natural = chip.naturalWidth
        guard limit - x >= 60 else { chip.isHidden = true; return }
        let width = min(natural, limit - x)
        chip.baseline = baseline
        chip.frame = NSRect(x: x, y: frag.minY + origin.y, width: width, height: frag.height)
        chip.isHidden = false
    }

    // MARK: popover

    private func chipHover(_ inside: Bool) {
        hoverTimer?.invalidate()
        guard inside, !AppEnv.headless else { return }
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in self?.showInlinePopover() }
    }

    func showInlinePopover() {
        guard let i = inlineCommitIndex, let chip, !chip.isHidden else { return }
        showPopover(commitIndex: i, anchor: chip.bounds, of: chip)
    }

    /// Builds (and, outside headless runs, shows) the commit popover for a commit of the loaded blame.
    @discardableResult
    func showPopover(commitIndex: Int, anchor: NSRect, of view: NSView) -> BlamePopoverView? {
        guard let commit = commit(at: commitIndex), let loaded, !commit.isUncommitted else { return nil }
        popover?.close()
        hoverTimer?.invalidate()
        let content = BlamePopoverView(commit: commit, you: loaded.you)
        content.onCopyHash = { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(commit.hash, forType: .string) }
        content.onCopyMessage = { [weak content] in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content?.messageText ?? commit.summary, forType: .string)
        }
        content.onOpenLog = { [weak self] in
            guard let self, let url = self.url else { return }
            self.popover?.close()
            Self.onShowCommit?(commit.hash, url)
        }
        content.onShowDiff = { [weak self] in self?.showDiff(for: commit) }
        let root = loaded.root
        Blame.gitQueue.async {
            let info = try? GitRepo(root: root).commitInfo(hash: commit.hash)
            DispatchQueue.main.async { if let info { content.apply(info: info) } }
        }
        let vc = NSViewController()
        vc.view = content
        let p = NSPopover()
        p.contentViewController = vc
        p.behavior = .transient
        p.animates = false
        popover = p
        popoverContent = content
        if !AppEnv.headless { p.show(relativeTo: anchor, of: view, preferredEdge: .maxY) }
        return content
    }

    /// Replaces the popover content with the commit's diff of this file (side by side).
    func showDiff(for commit: BlameCommit) {
        guard let loaded else { return }
        let root = loaded.root
        let path = commit.filename.isEmpty ? loaded.rel : commit.filename
        let change = GitFileChange(status: "M", path: path, oldPath: commit.previousPath ?? path)
        let ext = (path as NSString).pathExtension
        Blame.gitQueue.async { [weak self] in
            let sides = try? GitRepo(root: root).commitDiffSides(rev: commit.hash, file: change)
            DispatchQueue.main.async {
                guard let self else { return }
                let diff = BlameDiffView(title: "\(commit.shortHash)  \(commit.summary)")
                diff.show(old: sides?.old ?? "", new: sides?.new ?? "", oldTitle: "Before", newTitle: path, fileExtension: ext)
                diff.onBack = { [weak self] in
                    guard let self, let i = loaded.data.commits.firstIndex(where: { $0.hash == commit.hash }),
                          let c = self.chip else { return }
                    self.popover?.close()
                    self.showPopover(commitIndex: i, anchor: c.bounds, of: c)
                }
                self.popoverContent = diff
                if let p = self.popover {
                    p.contentViewController?.view = diff
                    p.contentSize = diff.frame.size
                }
            }
        }
    }

    // MARK: annotate column

    /// Toggles "Annotate with Git Blame" for a tab. Returns the new state (true = on / pending until blame loads).
    @discardableResult
    static func toggleAnnotate(for tab: EditorTab) -> Bool {
        guard let c = Blame.controller(for: tab) else { return false }
        c.setAnnotate(!(c.isAnnotating || c.wantAnnotate))
        return c.isAnnotating || c.wantAnnotate
    }

    func setAnnotate(_ on: Bool) {
        if on {
            wantAnnotate = true
            if loaded == nil {
                if !loading { reload() }
                return   // the strip appears once blame arrived (see `reload`)
            }
            guard strip == nil else { return }
            install()
        } else {
            wantAnnotate = false
            guard let strip else { return }
            strip.removeFromSuperview()
            self.strip = nil
            leadingConstraint?.constant = savedLeadingConstant
            leadingConstraint = nil
            tab?.scrollView.superview?.needsLayout = true
        }
    }

    private func install() {
        guard let sv = scrollView, let container = sv.superview as? EditorContainer else { wantAnnotate = false; return }
        guard let lead = container.constraints.first(where: {
            ($0.firstItem as? NSScrollView) === sv && $0.firstAttribute == .leading
        }) else { wantAnnotate = false; return }
        let view = BlameAnnotateView(controller: self)
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        savedLeadingConstant = lead.constant
        leadingConstraint = lead
        let w = view.preferredWidth
        lead.constant = savedLeadingConstant + w
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.gutter.trailingAnchor),
            view.widthAnchor.constraint(equalToConstant: w),
            view.topAnchor.constraint(equalTo: sv.topAnchor),
            view.bottomAnchor.constraint(equalTo: sv.bottomAnchor),
        ])
        strip = view
        view.needsDisplay = true
        container.needsLayout = true
        recomputeMapIfNeeded()
    }

    private func recomputeMapIfNeeded() { if !mapValid { recomputeMap() } }

    func applyStripWidth() {
        guard let strip, let lead = leadingConstraint else { return }
        let w = strip.preferredWidth
        lead.constant = savedLeadingConstant + w
        for c in strip.constraints where c.firstAttribute == .width { c.constant = w }
        for c in strip.superview?.constraints ?? [] where c.firstItem === strip && c.firstAttribute == .width { c.constant = w }
        strip.superview?.needsLayout = true
        strip.needsDisplay = true
    }
}
