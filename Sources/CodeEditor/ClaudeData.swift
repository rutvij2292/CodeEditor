import Foundation

/// What Claude Code keeps on disk for one project (~/.claude/projects/<encoded path>): session transcripts with their side data,
/// the durable memory notes, and the project's own `.claude` folder. Read on demand (metadata only, titles from the head of each
/// transcript), never watched. Removal goes to the Trash.
enum ClaudeData {
    /// Overridable so tests never touch the real ~/.claude.
    static var home = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude")
    static var trasher: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    /// A transcript touched this recently may belong to a live session: it cannot be ticked.
    static let activeWindow: TimeInterval = 600

    struct Session: Equatable {
        let id: String
        var title: String
        var modified: Date
        var bytes: Int64                 // transcript + its subfolder + file-history + session-env
        var urls: [URL]
        var isActive: Bool
    }

    struct Item: Equatable {
        let name: String
        let url: URL
        var bytes: Int64
        var modified: Date
    }

    struct Snapshot {
        var projectDir: URL?
        var sessions: [Session] = []
        var memory: [Item] = []
        var local: [Item] = []           // <project>/.claude contents
        var otherBytes: Int64 = 0        // everything else under the project folder (not offered for removal)
        var totalBytes: Int64 { sessions.reduce(0) { $0 + $1.bytes } + memory.reduce(0) { $0 + $1.bytes } + otherBytes }
    }

    /// Claude's folder name for a project path: every character that is not a letter or digit becomes `-`.
    static func projectDirName(for path: String) -> String {
        String(path.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
    }

    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        if !isDir.boolValue {
            let v = try? url.resourceValues(forKeys: Set(keys))
            return Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
        }
        var total: Int64 = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let f as URL in e {
                let v = try? f.resourceValues(forKeys: Set(keys))
                total += Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
            }
        }
        return total
    }

    /// The first real prompt of a transcript (head of the file only), single line, clipped.
    static func title(ofTranscript url: URL) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "Untitled session" }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: 256 * 1024)) ?? Data()
        for line in data.split(separator: 10) where line.range(of: Data("\"type\":\"user\"".utf8)) != nil {
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let msg = obj["message"] as? [String: Any] else { continue }
            var text = ""
            if let s = msg["content"] as? String { text = s }
            else if let parts = msg["content"] as? [[String: Any]] { text = parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: " ") }
            let t = text.split(whereSeparator: { $0.isNewline }).first(where: { !$0.hasPrefix("<") && !$0.hasPrefix("Caveat:") }).map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if !t.isEmpty { return t.count > 90 ? String(t.prefix(90)) + "…" : t }
        }
        return "Untitled session"
    }

    static func scan(projectRoot: URL, now: Date = Date()) -> Snapshot {
        let fm = FileManager.default
        var snap = Snapshot()
        let dir = home.appendingPathComponent("projects").appendingPathComponent(projectDirName(for: projectRoot.standardizedFileURL.path))
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        if !names.isEmpty { snap.projectDir = dir }
        for n in names.sorted() {
            let u = dir.appendingPathComponent(n)
            if n.hasSuffix(".jsonl") {
                let id = String(n.dropLast(6))
                var urls = [u]
                for extra in [dir.appendingPathComponent(id), home.appendingPathComponent("file-history/\(id)"), home.appendingPathComponent("session-env/\(id)")]
                where fm.fileExists(atPath: extra.path) { urls.append(extra) }
                let mod = ((try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
                snap.sessions.append(Session(id: id, title: title(ofTranscript: u), modified: mod, bytes: urls.reduce(0) { $0 + size(of: $1) }, urls: urls,
                                             isActive: now.timeIntervalSince(mod) < activeWindow))
            } else if n == "memory" {
                for f in ((try? fm.contentsOfDirectory(atPath: u.path)) ?? []).sorted() where !f.hasPrefix(".") {
                    let fu = u.appendingPathComponent(f)
                    snap.memory.append(Item(name: f, url: fu, bytes: size(of: fu), modified: ((try? fu.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast))
                }
            } else if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true, snap.sessions.contains(where: { $0.id == n }) || fm.fileExists(atPath: dir.appendingPathComponent(n + ".jsonl").path) {
                continue                                           // a session's subfolder: counted with its transcript
            } else {
                snap.otherBytes += size(of: u)
            }
        }
        snap.sessions.sort { $0.modified > $1.modified }
        let local = projectRoot.appendingPathComponent(".claude")
        for f in ((try? fm.contentsOfDirectory(atPath: local.path)) ?? []).sorted() where !f.hasPrefix(".DS_Store") {
            let fu = local.appendingPathComponent(f)
            snap.local.append(Item(name: f, url: fu, bytes: size(of: fu), modified: ((try? fu.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast))
        }
        return snap
    }

    /// Moves the chosen sessions' files (and chosen memory files) to the Trash. Returns the bytes freed and the paths that failed.
    @discardableResult
    static func remove(sessions: [Session], memory: [Item] = []) -> (freed: Int64, failed: [String]) {
        var freed: Int64 = 0
        var failed: [String] = []
        for u in sessions.flatMap(\.urls) + memory.map(\.url) {
            let b = size(of: u)
            do { try trasher(u); freed += b } catch { failed.append(u.path) }
        }
        return (freed, failed)
    }

    // MARK: Smart selections

    static func olderThan(_ days: Int, in s: [Session], now: Date = Date()) -> Set<String> {
        Set(s.filter { !$0.isActive && now.timeIntervalSince($0.modified) > Double(days) * 86400 }.map(\.id))
    }
    static func largerThan(_ mb: Int, in s: [Session]) -> Set<String> { Set(s.filter { !$0.isActive && $0.bytes > Int64(mb) * 1_048_576 }.map(\.id)) }
    /// Everything except the newest `n` (list is newest first).
    static func allButNewest(_ n: Int, in s: [Session]) -> Set<String> { Set(s.dropFirst(n).filter { !$0.isActive }.map(\.id)) }

    static func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
