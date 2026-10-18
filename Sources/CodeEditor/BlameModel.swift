import AppKit

/// Inline git blame (GitLens style) and the "Annotate with Git Blame" column.
///
/// Integrator wiring:
///  - `Blame.start()` once at launch (also done by `GitGutter.start()`, which every CodeTextView calls).
///  - Menu "Toggle Inline Blame"  -> `Blame.toggleInline()`.
///  - Menu "Annotate with Git Blame" (suggested ⌥⌘A) -> `BlameController.toggleAnnotate(for: currentTab)`; check state with `Blame.isAnnotating(tab)`.
///  - "Open in Git Log" -> set `BlameController.onShowCommit = { hash, fileURL in ... }`.
///  - Folding: set `Blame.suppressInline = { tab, lineRange in isFoldedOrHidden }` to hide the annotation on collapsed lines.
enum Blame {
    /// Posted (object: nil) after any controller published new blame data.
    static let didUpdate = Notification.Name("CodeEditor.blameDidUpdate")
    /// Return true to hide the inline annotation of the line (folded / hidden lines). Called on the main thread.
    static var suppressInline: ((EditorTab, NSRange) -> Bool)?

    static let gitQueue = DispatchQueue(label: "Blame.git", qos: .utility)
    static let mapQueue = DispatchQueue(label: "Blame.map", qos: .utility)

    private static var started = false
    fileprivate static var controllers: [ObjectIdentifier: BlameController] = [:]
    private static var escMonitor: Any?

    static func start() {
        guard !started else { return }
        started = true
        EditorEvents.onOpen { tab in
            guard !tab.isLargeFile else { return }
            let c = BlameController(tab: tab)
            controllers[ObjectIdentifier(tab)] = c
            c.begin()
        }
        EditorEvents.onClose { tab in
            controllers.removeValue(forKey: ObjectIdentifier(tab))?.end()
        }
        EditorEvents.onSave { tab in controllers[ObjectIdentifier(tab)]?.reload() }
        if !AppEnv.headless {
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                      let responder = event.window?.firstResponder, !CompletionPopup.shared.isShown else { return event }
                for c in controllers.values where c.isAnnotating && c.textView === responder {
                    if (responder as? NSTextView)?.hasMarkedText() == true { return event }
                    c.setAnnotate(false)
                    return nil
                }
                return event
            }
        }
    }

    static func controller(for tab: EditorTab) -> BlameController? { controllers[ObjectIdentifier(tab)] }
    static func isAnnotating(_ tab: EditorTab) -> Bool { controllers[ObjectIdentifier(tab)]?.isAnnotating ?? false }
    static func toggleInline() { Prefs.inlineBlame.toggle() }

    // MARK: text

    /// "just now", "5 minutes ago", "3 hours ago", "yesterday", "12 days ago", "4 months ago", "2 years ago".
    static func relativeText(from date: Date, now: Date = Date()) -> String {
        let s = max(0, now.timeIntervalSince(date))
        func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s") ago" }
        if s < 45 { return "just now" }
        let minutes = Int((s / 60).rounded())
        if minutes < 60 { return minutes <= 1 ? "a minute ago" : plural(minutes, "minute") }
        let hours = Int((s / 3600).rounded())
        if hours < 24 { return plural(hours, "hour") }
        let days = Int(s / 86400)
        if days < 2 { return "yesterday" }
        if days < 30 { return plural(days, "day") }
        if days < 365 { return plural(max(1, days / 30), "month") }
        return plural(days / 365, "year")
    }

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yy"
        return f
    }()
    private static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, d MMM yyyy HH:mm"
        return f
    }()
    static func shortDateText(_ d: Date) -> String { shortDate.string(from: d) }
    static func longDateText(_ d: Date) -> String { longDate.string(from: d) }

    static let uncommittedText = "Not committed yet"

    static func isYou(_ commit: BlameCommit, _ you: (name: String, email: String)) -> Bool {
        (!you.name.isEmpty && commit.author == you.name) || (!you.email.isEmpty && !commit.mail.isEmpty && commit.mail.lowercased() == you.email.lowercased())
    }

    /// "Author, 3 days ago · Fix cart total" ("You" for the configured user, "Not committed yet" for uncommitted lines).
    static func annotation(for commit: BlameCommit?, you: (name: String, email: String), now: Date = Date()) -> String {
        guard let commit, !commit.isUncommitted else { return uncommittedText }
        let who = isYou(commit, you) ? "You" : commit.author
        var s = "\(who), \(relativeText(from: commit.date, now: now))"
        if !commit.summary.isEmpty { s += " · \(commit.summary)" }
        return s
    }

    /// "Alice B." style short author for the annotate column.
    static func abbreviatedAuthor(_ name: String, limit: Int = 12) -> String {
        let parts = name.split(separator: " ").map(String.init)
        var s = name
        if parts.count >= 2, let last = parts.last?.first { s = parts[0] + " " + String(last).uppercased() + "." }
        return s.count > limit ? String(s.prefix(limit - 1)) + "…" : s
    }

    // MARK: lines

    /// Lines without terminators (LF and CRLF compare equal; the final newline is not an extra line).
    static func lines(of s: String) -> [String] {
        var out: [String] = []
        let bytes = Array(s.utf8)
        var start = 0
        for i in 0..<bytes.count where bytes[i] == 10 {
            var e = i
            if e > start, bytes[e - 1] == 13 { e -= 1 }
            out.append(String(decoding: bytes[start..<e], as: UTF8.self))
            start = i + 1
        }
        if start < bytes.count { out.append(String(decoding: bytes[start...], as: UTF8.self)) }
        return out
    }

    /// Maps every buffer line (0-based) to its line in `base` (the text blame was computed for); -1 for lines that only
    /// exist in the buffer. nil = identical texts (identity). Pure; safe off the main thread.
    static func lineMap(base: String, buffer: String) -> [Int32]? {
        if base == buffer { return nil }
        let a = lines(of: base), b = lines(of: buffer)
        let ids = DiffEngine.intern([a, b])
        let ops = DiffEngine.edit(ids[0], ids[1], maxD: 4000)
        var map: [Int32] = []
        map.reserveCapacity(b.count)
        var i = 0
        for op in ops {
            switch op {
            case .equal: map.append(Int32(i)); i += 1
            case .delete: i += 1
            case .insert: map.append(-1)
            }
        }
        return map
    }

    /// Stable hue (0...1) per author name.
    static func hue(for name: String) -> CGFloat {
        var h: UInt32 = 2166136261
        for b in name.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return CGFloat(h % 360) / 360
    }
}

/// Global LRU of blame results (20 files) so reopening / re-annotating the same HEAD+mtime costs nothing.
final class BlameCache {
    static let shared = BlameCache()
    static let capacity = 20
    private var entries: [(key: String, file: String, data: BlameData)] = []
    private let lock = NSLock()

    static func key(file: String, head: String, stamp: FileStamp) -> String {
        "\(file)|\(head)|\(stamp.seconds).\(stamp.nanos)|\(stamp.size)"
    }

    func get(_ key: String) -> BlameData? {
        lock.lock(); defer { lock.unlock() }
        guard let i = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let e = entries.remove(at: i)
        entries.append(e)
        return e.data
    }

    func put(_ key: String, file: String, _ data: BlameData) {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.key == key }
        entries.append((key, file, data))
        while entries.count > Self.capacity { entries.removeFirst() }
    }

    func drop(file: String) { lock.lock(); entries.removeAll { $0.file == file }; lock.unlock() }
    func removeAll() { lock.lock(); entries.removeAll(); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return entries.count }
}
