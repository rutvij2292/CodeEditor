import AppKit

extension NSAttributedString.Key {
    /// On the ☐ / ☑ marker of a rendered task item: the 0-based source line of the item (click toggles it).
    static let mdTaskLine = NSAttributedString.Key("kode.mdTaskLine")
    /// On a rendered file reference: "absolute-path" or "absolute-path:line" (Cmd-click opens it).
    static let planPath = NSAttributedString.Key("kode.planPath")
}

/// One plan document (Claude Code plan mode, PLAN.md, docs/plans, ...).
struct PlanFile: Equatable {
    var url: URL
    var title: String
    var modified: Date
    var done: Int
    var total: Int
    var isGlobal: Bool
    /// Path relative to the project root (or `~/.claude/plans/name.md` for global plans).
    var display: String
}

/// Text-level plan logic: progress counting, title, headings, task toggling, review comments. Pure functions over strings.
enum PlanText {
    private static func fenceMarker(_ line: Substring) -> Character? {
        let t = line.drop(while: { $0 == " " })
        guard line.count - t.count <= 3, let c = t.first, c == "`" || c == "~" else { return nil }
        return t.prefix(3).allSatisfy { $0 == c } && t.count >= 3 ? c : nil
    }

    /// (checked?) when `line` is a GFM task list item.
    static func taskState(_ line: Substring) -> Bool? {
        var i = line.startIndex
        while i < line.endIndex, line[i] == " " || line[i] == "\t" { i = line.index(after: i) }
        guard i < line.endIndex, "-*+".contains(line[i]) else { return nil }
        i = line.index(after: i)
        guard i < line.endIndex, line[i] == " " else { return nil }
        while i < line.endIndex, line[i] == " " { i = line.index(after: i) }
        let rest = line[i...]
        guard rest.count >= 3, rest.first == "[" else { return nil }
        let mid = rest[rest.index(after: rest.startIndex)]
        guard rest[rest.index(rest.startIndex, offsetBy: 2)] == "]", mid == " " || mid == "x" || mid == "X" else { return nil }
        let after = rest.index(rest.startIndex, offsetBy: 3)
        guard after == rest.endIndex || rest[after] == " " || rest[after] == "\t" else { return nil }
        return mid != " "
    }

    /// Done / total task items outside fenced code.
    static func progress(_ text: String) -> (done: Int, total: Int) {
        var done = 0, total = 0
        var fence: Character?
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            if let f = fenceMarker(raw) { fence = fence == nil ? f : (fence == f ? nil : fence); continue }
            if fence != nil { continue }
            if let checked = taskState(raw) { total += 1; if checked { done += 1 } }
        }
        return (done, total)
    }

    /// First H1 (outside fences and front matter), else nil.
    static func title(_ text: String) -> String? {
        headings(text).first { $0.level == 1 }?.text
    }

    struct Heading: Equatable { var level: Int; var text: String; var line: Int }

    /// ATX / setext headings of the document (via the Markdown parser, so fences and front matter are handled), in source order.
    static func headings(_ text: String) -> [Heading] {
        var out: [Heading] = []
        for b in MarkdownParser.parse(text) {
            if case .heading(let level, let t, let line) = b { out.append(Heading(level: level, text: t, line: line)) }
        }
        return out
    }

    /// Flips the `[ ]` / `[x]` of the task item on 0-based `line`. Nothing else changes (line endings included). nil when the line is not a task.
    static func toggleTask(in text: String, line: Int) -> String? {
        let u = Array(text.utf8)
        var start = 0, n = 0
        while n < line {
            guard let nl = u[start...].firstIndex(of: 10) else { return nil }
            start = nl + 1; n += 1
        }
        let end = u[start...].firstIndex(of: 10) ?? u.count
        let lineText = String(decoding: u[start..<end], as: UTF8.self)
        guard taskState(Substring(lineText)) != nil, let open = u[start..<end].firstIndex(of: 91) else { return nil }
        var out = u
        out[open + 1] = u[open + 1] == 32 ? 120 : 32
        return String(decoding: out, as: UTF8.self)
    }

    /// Nearest heading at or before 0-based `line` (nil before the first heading).
    static func heading(atOrBefore line: Int, in headings: [Heading]) -> Heading? {
        headings.last { $0.line <= line }
    }

    static let reviewPrefix = "> **Review:** "

    /// Inserts `> **Review:** comment` as its own block directly under the heading on `headingLine` (0-based).
    /// The file's line-ending style is kept. Newlines inside the comment collapse to spaces.
    static func insertReview(in text: String, headingLine: Int, comment: String) -> String? {
        let flat = comment.split(whereSeparator: { $0.isNewline }).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !flat.isEmpty else { return nil }
        let eol = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = DiffEngine.splitLines(text)
        guard headingLine >= 0, headingLine < lines.count else { return nil }
        if lines[headingLine].utf8.last != 10 { lines[headingLine] += eol }
        let review = reviewPrefix + flat + eol
        let nextBlank = headingLine + 1 < lines.count && lines[headingLine + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var insert = [eol, review]
        if headingLine + 1 < lines.count, !nextBlank { insert.append(eol) }
        lines.insert(contentsOf: insert, at: headingLine + 1)
        return lines.joined()
    }

    /// All `> **Review:** ...` comments with their section heading (what an agent should address).
    static func reviewComments(_ text: String) -> [(heading: String, comment: String, line: Int)] {
        let hs = headings(text)
        var out: [(String, String, Int)] = []
        for (i, raw) in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }).enumerated() {
            let l = raw.drop(while: { $0 == " " })
            if l.hasPrefix(reviewPrefix) {
                out.append((heading(atOrBefore: i, in: hs)?.text ?? "", String(l.dropFirst(reviewPrefix.count)), i))
            }
        }
        return out
    }
}

/// File references (`path`, `path:line`, backticked or bare) inside rendered plan text.
enum PlanPaths {
    struct Ref: Equatable { var range: NSRange; var path: String; var line: Int? }

    // path chars with an extension, optional :line[:col]; not part of a longer word / URL.
    private static let regex = try! NSRegularExpression(
        pattern: #"(?<![\w/.\-@:~])((?:~/|/|\.{1,2}/)?[\w.\-@]+(?:/[\w.\-@\[\]()]+)*\.[A-Za-z][A-Za-z0-9]{0,7})(?::(\d+)(?::\d+)?)?(?![\w/])"#)

    static func references(in text: String) -> [Ref] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            let line = m.range(at: 2).location != NSNotFound ? Int(ns.substring(with: m.range(at: 2))) : nil
            return Ref(range: m.range, path: ns.substring(with: m.range(at: 1)), line: line)
        }
    }

    /// Resolves to an existing regular file: absolute / `~`, then relative to the project root, then to the document's folder.
    static func resolve(_ path: String, root: URL?, base: URL?) -> URL? {
        let fm = FileManager.default
        func exists(_ u: URL) -> URL? {
            var dir: ObjCBool = false
            return fm.fileExists(atPath: u.path, isDirectory: &dir) && !dir.boolValue ? u.standardizedFileURL : nil
        }
        if path.hasPrefix("~/") { return exists(URL(fileURLWithPath: NSHomeDirectory() + String(path.dropFirst(1)))) }
        if path.hasPrefix("/") {
            return exists(URL(fileURLWithPath: path))
        }
        if let root, let u = exists(root.appendingPathComponent(path)) { return u }
        if let base, let u = exists(base.deletingLastPathComponent().appendingPathComponent(path)) { return u }
        return nil
    }

    /// Marks existing file references in a rendered document with `.planPath` (and a dotted underline). Bounded work.
    static func annotate(_ storage: NSMutableAttributedString, root: URL?, base: URL?, maxStats: Int = 400) {
        guard storage.length <= 600_000 else { return }
        var stats = 0
        var cache: [String: URL?] = [:]
        for ref in references(in: storage.string) {
            if storage.attribute(.link, at: ref.range.location, effectiveRange: nil) != nil { continue }
            let target: URL?
            if let hit = cache[ref.path] { target = hit }
            else {
                guard stats < maxStats else { break }
                stats += 1
                target = resolve(ref.path, root: root, base: base)
                cache[ref.path] = target
            }
            guard let url = target else { continue }
            let value = ref.line.map { "\(url.path):\($0)" } ?? url.path
            storage.addAttributes([.planPath: value,
                                   .underlineStyle: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue], range: ref.range)
        }
    }

    /// Splits a `.planPath` value back into (path, line).
    static func split(_ value: String) -> (path: String, line: Int?) {
        if let i = value.lastIndex(of: ":"), let n = Int(value[value.index(after: i)...]) { return (String(value[..<i]), n) }
        return (value, nil)
    }
}

/// Finds plan files for a project and keeps the list live (one cheap FSEvents stream on ~/.claude/plans; project plan
/// files arrive through the project window's existing watcher via `noteChanges`).
final class PlanStore {
    static let shared = PlanStore()
    static let didChange = Notification.Name("PlanStoreDidChange")
    /// Overridable for tests.
    var home = NSHomeDirectory()
    private var watcher: FSWatcher?
    private var mentionCache: [String: Bool] = [:]
    /// Paths of plan files whose change we saw (path -> time); drives the "updated by an agent" badge.
    private(set) var recentChanges: [String: Date] = [:]

    static let projectPlanDirs = ["docs/plans", "docs/superpowers", ".claude/plans", "tasks"]
    static let projectPlanFiles = ["plan.md", "plans.md", "tasks/todo.md"]   // matched case-insensitively

    var globalDir: String { home + "/.claude/plans" }

    /// Starts the single global watcher (no-op when ~/.claude/plans does not exist or in tests).
    func startWatching() {
        guard watcher == nil, FileManager.default.fileExists(atPath: globalDir) else { return }
        watcher = FSWatcher(path: globalDir, latency: 0.8, filter: { $0.filter { $0.hasSuffix(".md") } }) { [weak self] paths in
            self?.record(paths)
        }
    }

    /// Called with changed paths from any watcher: keeps only plan-like markdown files.
    func noteChanges(_ paths: [String], root: URL?) {
        let hits = paths.filter { $0.hasSuffix(".md") && isPlan(path: $0, root: root) }
        if !hits.isEmpty { record(hits) }
    }

    private func record(_ paths: [String]) {
        let now = Date()
        for p in paths { recentChanges[p] = now }
        if recentChanges.count > 200 { recentChanges = recentChanges.filter { now.timeIntervalSince($0.value) < 3600 } }
        NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["paths": paths])
    }

    func recentlyChanged(_ url: URL, within: TimeInterval = 900, now: Date = Date()) -> Bool {
        recentChanges[url.path].map { now.timeIntervalSince($0) < within } ?? false
    }

    /// Whether `path` is somewhere plans live for `root` (no disk access).
    func isPlan(path: String, root: URL?) -> Bool {
        if path.hasPrefix(globalDir + "/") { return true }
        guard let root else { return false }
        let base = VCSKind.canonical(root.path) + "/"
        let p = VCSKind.canonical(path)
        guard p.hasPrefix(base) else { return false }
        let rel = String(p.dropFirst(base.count))
        if Self.projectPlanFiles.contains(rel.lowercased()) { return true }
        if rel.hasPrefix("docs/plans/") || rel.hasPrefix(".claude/plans/") { return true }
        if rel.hasPrefix("docs/superpowers/") {
            let parts = rel.split(separator: "/")
            return parts.dropLast().contains { $0 == "plans" || $0 == "specs" }
        }
        return false
    }

    private func markdownFiles(in dir: URL, maxDepth: Int, filter: (URL) -> Bool = { _ in true }) -> [URL] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for case let u as URL in en {
            if en.level > maxDepth { en.skipDescendants(); continue }
            if ["md", "markdown"].contains(u.pathExtension.lowercased()), filter(u) { out.append(u) }
            if out.count > 400 { break }
        }
        return out
    }

    private func mentionsProject(_ url: URL, modified: Date, root: URL) -> Bool {
        let key = "\(url.path)|\(modified.timeIntervalSince1970)|\(root.path)"
        if let hit = mentionCache[key] { return hit }
        var result = false
        if let h = try? FileHandle(forReadingFrom: url) {
            let data = (try? h.read(upToCount: 400_000)) ?? Data()
            try? h.close()
            let s = String(decoding: data, as: UTF8.self)
            result = s.contains(root.path) || s.contains(root.lastPathComponent)
        }
        if mentionCache.count > 2000 { mentionCache.removeAll() }
        mentionCache[key] = result
        return result
    }

    /// Plans for `root`, newest first. Global plans appear only when they mention the project (or `showAll`).
    func plans(root: URL?, showAll: Bool = false) -> [PlanFile] {
        let fm = FileManager.default
        var urls: [(URL, Bool)] = []
        if let root {
            for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where ["plan.md", "plans.md"].contains(name.lowercased()) {
                urls.append((root.appendingPathComponent(name), false))
            }
            if fm.fileExists(atPath: root.appendingPathComponent("tasks/todo.md").path) { urls.append((root.appendingPathComponent("tasks/todo.md"), false)) }
            urls += markdownFiles(in: root.appendingPathComponent("docs/plans"), maxDepth: 3).map { ($0, false) }
            urls += markdownFiles(in: root.appendingPathComponent(".claude/plans"), maxDepth: 2).map { ($0, false) }
            urls += markdownFiles(in: root.appendingPathComponent("docs/superpowers"), maxDepth: 5) {
                $0.deletingLastPathComponent().pathComponents.contains { $0 == "plans" || $0 == "specs" }
            }.map { ($0, false) }
        }
        urls += markdownFiles(in: URL(fileURLWithPath: globalDir), maxDepth: 1).map { ($0, true) }

        var seen = Set<String>()
        var out: [PlanFile] = []
        for (url, global) in urls {
            let std = url.standardizedFileURL
            guard seen.insert(std.path).inserted,
                  let attrs = try? fm.attributesOfItem(atPath: std.path), let mod = attrs[.modificationDate] as? Date,
                  (attrs[.size] as? Int ?? 0) <= 2_000_000 else { continue }
            if global, !showAll, let root, !mentionsProject(std, modified: mod, root: root) { continue }
            guard let data = fm.contents(atPath: std.path) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            let p = PlanText.progress(text)
            let title = PlanText.title(text) ?? std.deletingPathExtension().lastPathComponent
            let display: String
            if global { display = "~/.claude/plans/" + std.lastPathComponent }
            else if let root, VCSKind.canonical(std.path).hasPrefix(VCSKind.canonical(root.path) + "/") {
                display = String(VCSKind.canonical(std.path).dropFirst(VCSKind.canonical(root.path).count + 1))
            } else { display = std.path }
            out.append(PlanFile(url: std, title: title, modified: mod, done: p.done, total: p.total, isGlobal: global, display: display))
        }
        return out.sorted { $0.modified > $1.modified }
    }

    static func age(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        if s < 86400 * 14 { return "\(s / 86400)d ago" }
        return "\(s / (86400 * 7))w ago"
    }
}
