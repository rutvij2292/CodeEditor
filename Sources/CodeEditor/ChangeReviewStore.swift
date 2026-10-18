import AppKit

/// Timeline of what coding agents changed in a project window, with the baseline text each touched file had before the
/// agent changed it (so hunks can be accepted / rejected later). Driven by FS-watcher batches (`noteChanges`, only while an
/// agent terminal tab is active) and by the Claude bridge's diff flow (`recordBridgeEdit`). No timers, no polling.
///
/// Baselines are kept only for touched files and are capped (per file, per total, files per session, sessions); a file that
/// does not fit is still listed, without a baseline (no reject for it).
final class ChangeReviewStore {
    // MARK: Caps (tests lower them)
    static var maxFileBytes = 512 * 1024
    static var maxTotalBytes = 24 * 1024 * 1024
    static var maxFilesPerSession = 200
    static var maxSessions = 12

    enum Source: String {
        case preimage = "buffer before the change"
        case bridge = "Claude IDE diff"
        case head = "git HEAD"
    }
    enum State { case pending, accepted, rejected }

    final class Entry {
        let path: String
        var rel: String
        var baseline: String?
        var source: Source?
        var state: State = .pending
        var added = 0, removed = 0
        let first: Date
        var last: Date
        /// Why there is no baseline / what the user should know.
        var note: String?
        /// Hash of the text a reject restored: the FS event of our own write must not re-list the file.
        var settledHash: Int?
        init(path: String, rel: String, at: Date) { self.path = path; self.rel = rel; first = at; last = at }
        var url: URL { URL(fileURLWithPath: path) }
    }

    final class Session {
        let id: Int
        var title: String
        let started: Date
        var entries: [Entry] = []
        init(id: Int, title: String, started: Date) { self.id = id; self.title = title; self.started = started }
        var pending: [Entry] { entries.filter { $0.state == .pending } }
    }

    /// Session id used for edits that came through the IDE bridge while no agent terminal tab was active.
    static let bridgeSessionID = -1

    let root: URL
    private(set) var sessions: [Session] = []
    var onChange: (() -> Void)?

    /// The agent terminal tab that is active now (id, title), nil when the active tab is a plain shell.
    var activeAgent: () -> (id: Int, title: String)? = { nil }
    /// Buffer text of a file open and clean in an editor, i.e. what was on disk before the change (nil otherwise).
    var preimage: (String) -> String? = { _ in nil }
    /// Git HEAD content of a file (called off the main thread).
    var headProvider: (URL) -> String?
    /// Restores a whole file; the window routes this through an open editor (undoable) when there is one.
    var restore: (URL, String) -> Bool = { HunkActions.writeDisk($1, to: $0) }
    var now: () -> Date = Date.init

    private let queue = DispatchQueue(label: "ChangeReview", qos: .utility)

    init(root: URL) {
        self.root = URL(fileURLWithPath: VCSKind.canonical(root.standardizedFileURL.path))
        headProvider = { url in
            guard let repo = GitRepo.repoRoot(for: url) else { return nil }
            let file = url.resolvingSymlinksInPath().path, base = repo.resolvingSymlinksInPath().path
            guard file.hasPrefix(base + "/") else { return nil }
            return (try? GitRepo(root: repo).headContent(of: String(file.dropFirst(base.count + 1)))) ?? nil
        }
    }

    // MARK: Queries

    var pendingEntries: [(session: Session, entry: Entry)] { sessions.flatMap { s in s.pending.map { (s, $0) } } }
    var pendingFileCount: Int { Set(pendingEntries.map { $0.entry.path }).count }
    var totalBaselineBytes: Int { sessions.reduce(0) { $0 + $1.entries.reduce(0) { $0 + ($1.baseline?.utf8.count ?? 0) } } }

    /// Pending entry for a path (newest session first).
    func pendingEntry(_ path: String) -> Entry? {
        for s in sessions.reversed() { if let e = s.entries.first(where: { $0.path == path && $0.state == .pending }) { return e } }
        return nil
    }

    private func changed() { onChange?() }

    private func session(id: Int, title: String) -> Session {
        if let s = sessions.first(where: { $0.id == id }) { s.title = title; return s }
        let s = Session(id: id, title: title, started: now())
        sessions.append(s)
        if sessions.count > Self.maxSessions {
            // Drop the oldest session without pending work first, else the oldest.
            let victim = sessions.dropLast().first { $0.pending.isEmpty } ?? sessions[0]
            sessions.removeAll { $0 === victim }
        }
        return s
    }

    /// True when a baseline of `bytes` still fits under the total cap.
    private func fits(_ bytes: Int) -> Bool {
        bytes <= Self.maxFileBytes && totalBaselineBytes + bytes <= Self.maxTotalBytes
    }

    // MARK: Recording

    /// Core update, main thread. `baseline` is only used when the file has no pending entry in the session yet.
    func record(path: String, current: String?, baseline: String?, source: Source?, agent: (id: Int, title: String)) {
        let s = session(id: agent.id, title: agent.title)
        let t = now()
        if let e = s.entries.first(where: { $0.path == path && $0.state == .pending }) {
            guard let current else { changed(); return }
            e.last = t
            if let base = e.baseline {
                let c = HunkActions.counts(baseline: base, current: current)
                if c.added == 0 && c.removed == 0 { s.entries.removeAll { $0 === e } } else { e.added = c.added; e.removed = c.removed }
            }
            changed()
            return
        }
        if let current, s.entries.contains(where: { $0.path == path && $0.settledHash == current.hashValue }) { return }
        guard s.entries.count < Self.maxFilesPerSession || s.entries.contains(where: { $0.path == path }) else { return }
        s.entries.removeAll { $0.path == path }          // a resolved entry starts over
        let e = Entry(path: path, rel: Self.relative(path, root: root), at: t)
        if let baseline, let current {
            if baseline == current { return }
            if fits(baseline.utf8.count) {
                e.baseline = baseline; e.source = source
                let c = HunkActions.counts(baseline: baseline, current: current)
                e.added = c.added; e.removed = c.removed
            } else {
                e.note = "Too large to keep a baseline"
                e.added = (current as NSString).length > 0 ? DiffEngine.splitLines(current).count : 0
            }
        } else {
            e.note = "No baseline (new or untracked file)"
            if let current { e.added = DiffEngine.splitLines(current).count }
        }
        s.entries.append(e)
        changed()
    }

    /// Edit that went through the bridge's diff flow: `original` is the exact text before it.
    func recordBridgeEdit(url: URL, original: String, new: String) {
        let agent = activeAgent() ?? (Self.bridgeSessionID, "Claude Code (IDE)")
        record(path: url.standardizedFileURL.path, current: new, baseline: original, source: .bridge, agent: agent)
    }

    /// FS-watcher batch (main thread; call BEFORE open editors reload so clean buffers still hold the previous text).
    /// Files are attributed to the active agent tab; files already under review are refreshed regardless. `completion` runs on
    /// the main thread when every path has been applied.
    func noteChanges(_ paths: [String], completion: (() -> Void)? = nil) {
        let agent = activeAgent()
        let group = DispatchGroup()
        var seen = Set<String>()
        for raw in paths {
            let path = VCSKind.canonical(URL(fileURLWithPath: raw).standardizedFileURL.path)
            guard seen.insert(path).inserted, !path.contains("/.git/"), path.hasPrefix(root.path + "/") else { continue }
            let tracked = pendingEntry(path)
            guard agent != nil || tracked != nil else { continue }
            guard let who = agent ?? sessions.first(where: { $0.pending.contains { $0.path == path } }).map({ ($0.id, $0.title) }) else { continue }
            let pre = tracked == nil ? preimage(path) : nil
            let url = URL(fileURLWithPath: path)
            let head = headProvider
            group.enter()
            queue.async {
                var isFile = false
                var current: String?
                if FileIO.kind(url) == .file, (FileIO.stamp(url)?.size ?? 0) <= Int64(4 * Self.maxFileBytes) {
                    isFile = true
                    current = HunkActions.readDisk(url)?.text
                }
                let wantHead = tracked == nil && pre == nil && current != nil
                let base = wantHead ? head(url) : nil
                DispatchQueue.main.async {
                    defer { group.leave() }
                    guard isFile else {
                        // Deleted by the agent: keep tracking only what is already tracked.
                        if tracked != nil { self.record(path: path, current: nil, baseline: nil, source: nil, agent: who) }
                        return
                    }
                    guard let current else { return }
                    self.record(path: path, current: current, baseline: pre ?? base, source: pre != nil ? .preimage : (base != nil ? .head : nil), agent: who)
                }
            }
        }
        group.notify(queue: .main) { completion?() }
    }

    // MARK: Actions

    /// Marks one hunk of a file as reviewed: the baseline advances over it. `current` is the text the hunk was shown against.
    @discardableResult
    func acceptHunk(path: String, old: Range<Int>, current: String) -> Bool {
        guard let e = pendingEntry(path), let base = e.baseline, let next = HunkActions.accepting(old: old, baseline: base, current: current) else { return false }
        e.baseline = next
        let c = HunkActions.counts(baseline: next, current: current)
        e.added = c.added; e.removed = c.removed
        if c.added == 0 && c.removed == 0 { e.state = .accepted; e.baseline = nil }
        changed()
        return true
    }

    func acceptFile(_ e: Entry) {
        guard e.state == .pending else { return }
        e.state = .accepted
        e.baseline = nil
        changed()
    }

    /// Restores the file to its baseline. False when there is none or the restore failed (the entry stays pending).
    @discardableResult
    func rejectFile(_ e: Entry) -> Bool {
        guard e.state == .pending, let base = e.baseline, restore(e.url, base) else { return false }
        e.state = .rejected
        e.settledHash = base.hashValue
        e.baseline = nil
        e.added = 0; e.removed = 0
        changed()
        return true
    }

    func acceptAll(in s: Session) { for e in s.pending { acceptFile(e) } }
    func acceptAll() { for s in sessions { acceptAll(in: s) } }

    /// Returns how many files could not be rejected (no baseline or write failure).
    @discardableResult
    func rejectAll(in s: Session) -> Int { s.pending.reduce(0) { $0 + (rejectFile($1) ? 0 : 1) } }
    @discardableResult
    func rejectAll() -> Int { sessions.reduce(0) { $0 + rejectAll(in: $1) } }

    /// Forgets resolved entries and empty sessions.
    func clearResolved() {
        for s in sessions { s.entries.removeAll { $0.state != .pending } }
        sessions.removeAll { $0.entries.isEmpty }
        changed()
    }

    static func relative(_ path: String, root: URL) -> String {
        path.hasPrefix(root.path + "/") ? String(path.dropFirst(root.path.count + 1)) : path
    }
}
