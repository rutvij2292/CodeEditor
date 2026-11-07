import Foundation
import CryptoKit

/// One thing the project does, in the owner's words: what it is, how a user reaches it, and which files hold it.
struct Feature: Codable, Equatable {
    enum Status: String, Codable { case draft, confirmed }
    enum Origin: String, Codable { case you, agent }

    var id: String
    var name: String
    var area: String
    var summary: String
    /// "Route POST /invoices/send", "Scheduler: daily 08:00", "Menu: Git > Commit (⌘K)".
    var entryPoints: [String]
    /// Project-relative file, folder (trailing "/") or glob ("Sources/CodeEditor/NativePHP*").
    var files: [String]
    var notes: String
    var status: Status
    var confirmedAt: Date?
    var origin: Origin

    static func make(name: String, area: String = "", summary: String = "", entryPoints: [String] = [], files: [String] = [],
                     status: Status = .draft, origin: Origin = .you) -> Feature {
        Feature(id: UUID().uuidString.lowercased().prefix(8).description, name: name, area: area, summary: summary, entryPoints: entryPoints,
                files: files, notes: "", status: status, confirmedAt: nil, origin: origin)
    }

    /// Does this feature claim the project-relative path `rel`?
    func claims(_ rel: String) -> Bool { files.contains { FeatureMap.pattern($0, matches: rel) } }

    /// Lowercased text the type-to-search matches.
    var searchText: String {
        ([name, area, summary, notes] + entryPoints + files).joined(separator: "\n").lowercased()
    }
}

/// Why a feature wants the owner's attention.
struct FeatureAttention: Equatable {
    var isDraft = false
    /// Accepted agent sessions that touched the feature's files after it was last confirmed.
    var changedSince: [LedgerSession] = []
    var missingFiles: [String] = []
    var needsReview: Bool { !changedSince.isEmpty }
    var isClean: Bool { !isDraft && changedSince.isEmpty && missingFiles.isEmpty }
}

/// The owner's map of what the project does and where it lives: one small JSON file per project under Application Support (never
/// inside the project: work repos are shared with teammates). Loaded lazily on first access; no timers, no polling, no AI
/// (drafting with Claude only happens when the user asks).
final class FeatureMap {
    static let version = 1
    static var maxFeatures = 500
    static var maxFilesPerFeature = 200
    static var maxSummaryChars = 2000
    static var maxBytes = 512 * 1024

    private struct Payload: Codable { var version: Int; var ignore: [String]; var features: [Feature] }

    let root: URL
    var onChange: (() -> Void)?
    private var loaded: Payload?
    private var loadFailed = false

    init(root: URL) { self.root = root }

    /// Headless runs (self-tests, snapshots) never touch the real Application Support folder.
    static var directory: URL = AppEnv.headless
        ? FileManager.default.temporaryDirectory.appendingPathComponent("kode-features-headless")
        : URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Kode/features")

    var fileURL: URL {
        let key = VCSKind.canonical(root.standardizedFileURL.path)
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return Self.directory.appendingPathComponent(hash + ".json")
    }
    var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    private var payload: Payload {
        get { if loaded == nil { reload(notify: false) }; return loaded ?? Payload(version: Self.version, ignore: [], features: []) }
        set { loaded = newValue }
    }

    private(set) var features: [Feature] {
        get { payload.features }
        set { var p = payload; p.features = newValue; payload = p }
    }

    /// Globs for files that need no feature (generated code, assets).
    var ignore: [String] {
        get { payload.ignore }
        set { var p = payload; p.ignore = newValue; payload = p; commit() }
    }

    func reload() { reload(notify: true) }

    private func reload(notify: Bool) {
        loaded = Payload(version: Self.version, ignore: [], features: [])
        loadFailed = false
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL) {
                let dec = JSONDecoder()
                dec.dateDecodingStrategy = .iso8601
                if let p = try? dec.decode(Payload.self, from: data), p.version == Self.version { loaded = p }
                else { loadFailed = true }      // not ours or from a newer Kode: never write over it
            } else { loadFailed = true }
        }
        if notify { onChange?() }
    }

    var isReadOnly: Bool { _ = payload; return loadFailed }

    // MARK: Matching

    /// Exact file, folder prefix (pattern ends in "/"), or `*` glob.
    static func pattern(_ p: String, matches rel: String) -> Bool {
        let p = p.trimmingCharacters(in: .whitespaces)
        if p.isEmpty { return false }
        if p == rel { return true }
        if p.hasSuffix("/") { return rel.hasPrefix(p) }
        if p.contains("*") { return fnmatch(p, rel, 0) == 0 }
        return false
    }

    func features(claiming rel: String) -> [Feature] { features.filter { $0.claims(rel) } }

    /// Features that claim at least one of `rels`, in map order.
    func features(touching rels: [String]) -> [Feature] { features.filter { f in rels.contains { f.claims($0) } } }

    func isIgnored(_ rel: String) -> Bool { payload.ignore.contains { Self.pattern($0, matches: rel) } }

    /// Project files no feature claims and the ignore list does not cover. `files` are project-relative paths.
    func unmapped(in files: [String]) -> [String] {
        let all = features
        let ign = payload.ignore
        return files.filter { rel in
            !Self.isNoise(rel) && !all.contains { $0.claims(rel) } && !ign.contains { Self.pattern($0, matches: rel) }
        }
    }

    /// Lock files, images, fonts and the like are never worth a feature.
    static func isNoise(_ rel: String) -> Bool {
        let name = (rel as NSString).lastPathComponent.lowercased()
        if name.hasPrefix(".") { return true }
        let ext = (name as NSString).pathExtension
        return ["png", "jpg", "jpeg", "gif", "icns", "ico", "svg", "woff", "woff2", "ttf", "otf", "lock", "map", "dmg", "zip", "pdf"].contains(ext)
            || name == "package-lock.json" || name == "composer.lock"
    }

    // MARK: Attention

    /// Draft / changed-since-confirmed / missing-files state of `f`. `sessions` are the ledger's accepted agent sessions.
    func attention(of f: Feature, sessions: [LedgerSession]) -> FeatureAttention {
        var a = FeatureAttention()
        a.isDraft = f.status == .draft
        if let since = f.confirmedAt, f.status == .confirmed {
            a.changedSince = sessions.filter { s in s.updated > since && s.files.contains { f.claims($0.rel) } }
        }
        let fm = FileManager.default
        a.missingFiles = f.files.filter { p in
            !p.contains("*") && !fm.fileExists(atPath: root.appendingPathComponent(p).path)
        }
        return a
    }

    /// Accepted agent sessions that touched `f`'s files, newest first.
    func history(of f: Feature, sessions: [LedgerSession], limit: Int = 20) -> [LedgerSession] {
        Array(sessions.filter { s in s.files.contains { f.claims($0.rel) } }.sorted { $0.updated > $1.updated }.prefix(limit))
    }

    func needsReviewCount(sessions: [LedgerSession]) -> Int {
        features.filter { attention(of: $0, sessions: sessions).needsReview }.count
    }

    static func filter(_ list: [Feature], query: String) -> [Feature] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return q.isEmpty ? list : list.filter { $0.searchText.contains(q) }
    }

    // MARK: Mutations

    @discardableResult
    func add(_ f: Feature) -> Feature {
        var list = features
        var f = clean(f)
        while list.contains(where: { $0.id == f.id }) { f.id = UUID().uuidString.lowercased().prefix(8).description }
        guard list.count < Self.maxFeatures else { return f }
        list.append(f)
        features = list
        commit()
        return f
    }

    func update(_ f: Feature) {
        var list = features
        guard let i = list.firstIndex(where: { $0.id == f.id }) else { return }
        list[i] = clean(f)
        features = list
        commit()
    }

    func remove(id: String) { features = features.filter { $0.id != id }; commit() }

    /// "I read this and it is right." Needs a summary: an empty one cannot be confirmed.
    @discardableResult
    func confirm(id: String, now: Date = Date()) -> Bool {
        guard var f = features.first(where: { $0.id == id }), !f.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        f.status = .confirmed
        f.confirmedAt = now
        update(f)
        return true
    }

    /// Adds `rels` to feature `id` (skipping paths it already claims).
    func assign(_ rels: [String], to id: String) {
        guard var f = features.first(where: { $0.id == id }) else { return }
        for r in rels where !f.claims(r) { f.files.append(r) }
        update(f)
    }

    /// Adds drafted features (status draft, origin agent); a name that already exists is skipped. Returns how many were added.
    @discardableResult
    func addDrafts(_ drafts: [Feature]) -> Int {
        var n = 0
        for d in drafts {
            var d = d
            d.status = .draft; d.origin = .agent; d.confirmedAt = nil
            if features.contains(where: { $0.name.lowercased() == d.name.lowercased() }) { continue }
            add(d); n += 1
        }
        return n
    }

    private func clean(_ f: Feature) -> Feature {
        var f = f
        f.name = String(f.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        f.area = String(f.area.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        f.summary = String(f.summary.prefix(Self.maxSummaryChars))
        f.notes = String(f.notes.prefix(Self.maxSummaryChars))
        f.entryPoints = f.entryPoints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(40).map { String($0.prefix(200)) }
        f.files = Array(f.files.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(Self.maxFilesPerFeature))
        return f
    }

    private func commit() { save(); onChange?() }

    // MARK: Persistence

    @discardableResult
    func save() -> Bool {
        guard !loadFailed else { return false }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var p = payload
        p.features.sort { ($0.area.lowercased(), $0.name.lowercased()) < ($1.area.lowercased(), $1.name.lowercased()) }
        guard let data = try? enc.encode(p), data.count <= Self.maxBytes else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            loaded = p
            return true
        } catch { return false }
    }

    // MARK: Draft with Claude

    /// Prompt asking for features that cover `files` (unmapped), told what already exists so it does not repeat it.
    static func draftPrompt(projectName: String, files: [String], existing: [Feature]) -> String {
        let shown = files.prefix(600).joined(separator: "\n")
        let have = existing.isEmpty ? "(none yet)" : existing.map { "- \($0.name)" }.joined(separator: "\n")
        return """
        You are helping the owner of the project "\(projectName)" keep a map of what the project does and where it lives.
        Below are project files that no feature covers yet. Group them into user-visible features (something the owner could be asked about, \
        like "email sending", "invoice export", "git commit window"), not into technical layers. Use only what the paths tell you; if unsure, say so in the summary.

        Existing features (do not repeat them):
        \(have)

        Files:
        \(shown)

        Reply with ONLY a JSON array, no prose, no code fence. Each item:
        {"name": "short feature name", "area": "broad group", "summary": "one or two plain sentences", "entryPoints": ["how a user or the system reaches it, if the paths show it"], "files": ["relative file, folder ending in /, or glob like Sources/X/Foo*"]}
        Prefer folders or globs over long file lists. Every file above should land in exactly one feature.
        """
    }

    /// Features parsed from Claude's reply (tolerates a code fence or surrounding prose). Empty when nothing usable.
    static func parseDrafts(_ reply: String) -> [Feature] {
        guard let a = reply.firstIndex(of: "["), let b = reply.lastIndex(of: "]"), a < b,
              let data = String(reply[a...b]).data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return raw.compactMap { d in
            guard let name = (d["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            let files = (d["files"] as? [String]) ?? []
            guard !files.isEmpty else { return nil }
            return Feature.make(name: name, area: (d["area"] as? String) ?? "", summary: (d["summary"] as? String) ?? "",
                                entryPoints: (d["entryPoints"] as? [String]) ?? [], files: files, status: .draft, origin: .agent)
        }
    }
}
