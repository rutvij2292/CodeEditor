import AppKit

/// Bookmarks of one project (file + line), persisted as a short string list; lines are gutter markers and a tool-panel list.
final class BookmarkStore {
    struct Mark: Equatable { var path: String; var line: Int }
    private let root: URL
    private(set) var marks: [Mark] = []
    var onChange: (() -> Void)?
    private static var memory: [String: [String]] = [:]   // headless runs never touch UserDefaults

    private var key: String { "bookmarks:" + root.standardizedFileURL.path }

    init(root: URL) {
        self.root = root
        let raw = AppEnv.headless ? (Self.memory[key] ?? []) : (UserDefaults.standard.stringArray(forKey: key) ?? [])
        marks = raw.compactMap { s in
            guard let i = s.lastIndex(of: "\t"), let line = Int(s[s.index(after: i)...]) else { return nil }
            return Mark(path: String(s[..<i]), line: line)
        }
    }

    func lines(in path: String) -> Set<Int> { Set(marks.filter { $0.path == path }.map(\.line)) }

    @discardableResult
    func toggle(path: String, line: Int) -> Bool {
        let m = Mark(path: path, line: line)
        let on = !marks.contains(m)
        if on { marks.append(m) } else { marks.removeAll { $0 == m } }
        save()
        onChange?()
        return on
    }

    func remove(_ m: Mark) { marks.removeAll { $0 == m }; save(); onChange?() }

    /// Next / previous bookmark after (path, line) in file-then-line order, wrapping around.
    func neighbour(of path: String, line: Int, forward: Bool) -> Mark? {
        let sorted = marks.sorted { ($0.path, $0.line) < ($1.path, $1.line) }
        guard !sorted.isEmpty else { return nil }
        if forward { return sorted.first { ($0.path, $0.line) > (path, line) } ?? sorted.first }
        return sorted.last { ($0.path, $0.line) < (path, line) } ?? sorted.last
    }

    private func save() {
        let raw = marks.map { "\($0.path)\t\($0.line)" }
        if AppEnv.headless { Self.memory[key] = raw } else { UserDefaults.standard.set(raw, forKey: key) }
    }
}

/// Scans the project for TODO / FIXME / HACK / XXX comments with the streaming search engine, only when asked (panel shown
/// or Refresh); keeps at most `cap` rows and cancels the walk once it has them.
final class TodoScanner {
    static let cap = 1000
    static let pattern = #"\b(TODO|FIXME|HACK|XXX)\b"#
    private let engine: FindEngine
    private let root: URL
    private var token: CancelToken?

    init(root: URL, files: @escaping () -> [String]) {
        self.root = root
        engine = FindEngine(root: root, files: files)
    }

    func cancel() { token?.cancel(); token = nil }

    /// Panel rows for search matches (tag = the keyword found, path shown relative to `base`).
    static func rows<S: Sequence>(from matches: S, base: String) -> [LineListPanel.Row] where S.Element == FindMatch {
        matches.map { m in
            let text = m.lineText.trimmingCharacters(in: .whitespaces)
            let tag = ["TODO", "FIXME", "HACK", "XXX"].first { text.contains($0) } ?? ""
            var rel = m.url.path
            if rel.hasPrefix(base + "/") { rel = String(rel.dropFirst(base.count + 1)) }
            return LineListPanel.Row(tag: tag, primary: String(text.prefix(200)), secondary: "\(rel):\(m.line)", path: m.url.path, line: m.line)
        }
    }

    /// `done` runs on the main queue with the rows (sorted by file, line) and whether the list was cut at the cap.
    func scan(done: @escaping ([LineListPanel.Row], Bool) -> Void) {
        cancel()
        var opts = FindOptions(query: Self.pattern)
        opts.isRegex = true
        opts.caseSensitive = true
        var rows: [LineListPanel.Row] = []
        var cut = false
        let base = (root.path as NSString).standardizingPath
        let tok = engine.search(opts, batch: { [weak self] matches in
            let room = Self.cap - rows.count
            if matches.count > room { cut = true; self?.token?.cancel() }
            rows += Self.rows(from: matches.prefix(max(0, room)), base: base)
        }, done: { _ in
            rows.sort { ($0.path, $0.line) < ($1.path, $1.line) }
            done(rows, cut)
        })
        token = tok
    }
}

extension ProjectWindow {
    func installTodoAndBookmarks(root: URL) {
        guard !hasToolPanel("todo") else { return }
        // TODO panel
        let todo = LineListPanel(emptyMessage: "Press ⌘8 or Refresh to scan for TODO / FIXME comments", showsRefresh: true)
        let scanner = TodoScanner(root: root, files: { [weak self] in self?.projectFiles ?? [] })
        todo.setTags(["TODO", "FIXME", "HACK", "XXX"])
        let open: (LineListPanel.Row) -> Void = { [weak self] r in
            let url = URL(fileURLWithPath: r.path)
            self?.open(url, line: r.line)
            self?.current?.textView.goToLine(r.line)
        }
        todo.onOpen = open
        let rescan: () -> Void = {
            todo.setStatus("Scanning…")
            scanner.scan { rows, cut in
                todo.setRows(rows, status: rows.isEmpty ? "No TODO / FIXME comments" : "\(rows.count) item\(rows.count == 1 ? "" : "s")" + (cut ? " (first \(TodoScanner.cap))" : ""))
            }
        }
        todo.onRefresh = rescan
        todoRescan = rescan
        registerToolPanel(id: "todo", title: "TODO", view: todo.view)

        // Bookmarks
        let store = BookmarkStore(root: root)
        bookmarks = store
        let panel = LineListPanel(emptyMessage: "No bookmarks — press F3 on a line to add one", showsRefresh: false)
        panel.onOpen = open
        let rebuild: () -> Void = { [weak self, weak panel] in
            guard let self, let panel else { return }
            let base = (root.path as NSString).standardizingPath
            let rows = store.marks.sorted { ($0.path, $0.line) < ($1.path, $1.line) }.map { m -> LineListPanel.Row in
                var rel = m.path
                if rel.hasPrefix(base + "/") { rel = String(rel.dropFirst(base.count + 1)) }
                return LineListPanel.Row(tag: "", primary: Self.lineText(path: m.path, line: m.line), secondary: "\(rel):\(m.line)", path: m.path, line: m.line)
            }
            panel.setRows(rows, status: rows.isEmpty ? "No bookmarks — press F3 on a line to add one" : "\(rows.count) bookmark\(rows.count == 1 ? "" : "s")")
            self.syncBookmarkGutters()
        }
        store.onChange = rebuild
        bookmarkPanelRebuild = rebuild
        registerToolPanel(id: "bookmarks", title: "Bookmarks", view: panel.view)
        rebuild()
    }

    /// First 160 characters of a line, read from an open buffer or, failing that, the file.
    private static func lineText(path: String, line: Int) -> String {
        guard let data = FileManager.default.contents(atPath: path), data.count < 2_000_000 else { return "" }
        var n = 1
        for part in data.split(separator: 10, omittingEmptySubsequences: false) {
            if n == line { return String(decoding: part.prefix(400), as: UTF8.self).trimmingCharacters(in: .whitespaces).prefix(160).description }
            n += 1
        }
        return ""
    }

    func syncBookmarkGutters() {
        guard let store = bookmarks else { return }
        for (path, tab) in editors {
            (tab.view.subviews.first as? EditorContainer)?.gutter.bookmarkLines = store.lines(in: path)
        }
    }

    func toggleBookmark() {
        guard let tab = current, let store = bookmarks else { NSSound.beep(); return }
        let ns = tab.textView.string as NSString
        let caret = min(tab.textView.selectedRange().location, ns.length)
        var line = 1, i = 0
        while i < caret { if ns.character(at: i) == 10 { line += 1 }; i += 1 }
        store.toggle(path: tab.url.standardizedFileURL.path, line: line)
    }

    func jumpToBookmark(forward: Bool) {
        guard let store = bookmarks else { return }
        var path = "", line = 0
        if let tab = current {
            path = tab.url.standardizedFileURL.path
            let ns = tab.textView.string as NSString
            let caret = min(tab.textView.selectedRange().location, ns.length)
            line = 1; var i = 0
            while i < caret { if ns.character(at: i) == 10 { line += 1 }; i += 1 }
        }
        guard let m = store.neighbour(of: path, line: line, forward: forward) else { NSSound.beep(); return }
        open(URL(fileURLWithPath: m.path), line: m.line)
        current?.textView.goToLine(m.line)
    }

    func showTodo() { showToolPanel("todo") { [weak self] in self?.todoRescan?() } }
    func showBookmarks() { showToolPanel("bookmarks") }
}
