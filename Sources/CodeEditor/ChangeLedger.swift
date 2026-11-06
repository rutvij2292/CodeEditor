import Foundation
import CryptoKit

/// One changed method / function / class (or a whole new file) of an accepted agent change.
struct LedgerSymbol: Codable, Equatable {
    var name: String
    var kind: String?
    var line: Int
    var added: Int
    var removed: Int
    var isNewFile: Bool
}

struct LedgerFile: Codable, Equatable {
    var rel: String
    var added: Int
    var removed: Int
    var symbols: [LedgerSymbol]
}

/// An agent session whose changes the user reviewed and accepted, with the user's own note on what it does.
struct LedgerSession: Codable, Equatable {
    var id: String
    var started: Date
    var updated: Date
    var title: String
    var note: String
    var files: [LedgerFile]

    var symbolCount: Int { files.reduce(0) { $0 + $1.symbols.count } }
    /// Lowercased text the Ledger's type-to-search matches: title, note, file paths and symbol names.
    var searchText: String {
        ([title, note] + files.map { $0.rel } + files.flatMap { $0.symbols.map { $0.name } }).joined(separator: "\n").lowercased()
    }
}

/// The user's memory of what agents changed in one project: small, capped, persisted as one JSON file per project under
/// Application Support. Loaded lazily on first access; no timers, no polling, no AI.
final class ChangeLedger {
    /// Headless runs (self-tests, snapshots) never touch the real Application Support folder.
    static var directory: URL = AppEnv.headless
        ? FileManager.default.temporaryDirectory.appendingPathComponent("kode-ledger-headless")
        : URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Kode/ledger")
    static var maxSessions = 300
    static var maxBytes = 256 * 1024
    static var maxFilesPerSession = 200
    static var maxSymbolsPerFile = 40
    static var maxNoteChars = 2000
    static var maxTitleChars = 200
    private static let version = 1

    private struct Payload: Codable { var version: Int; var sessions: [LedgerSession] }

    let root: URL
    var onChange: (() -> Void)?
    private var loaded: [LedgerSession]?

    init(root: URL) { self.root = root }

    var fileURL: URL {
        let key = VCSKind.canonical(root.standardizedFileURL.path)
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return Self.directory.appendingPathComponent(hash + ".json")
    }

    /// Newest updated first.
    private(set) var sessions: [LedgerSession] {
        get { if loaded == nil { reload(notify: false) }; return loaded ?? [] }
        set { loaded = newValue }
    }

    func reload() { reload(notify: true) }

    private func reload(notify: Bool) {
        loaded = []
        if let data = try? Data(contentsOf: fileURL) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            if let p = try? dec.decode(Payload.self, from: data), p.version == Self.version {
                loaded = p.sessions
            } else {
                // Unreadable or from a newer Kode: keep the bytes aside, start empty.
                let bak = URL(fileURLWithPath: fileURL.path + ".bak")
                try? FileManager.default.removeItem(at: bak)
                try? FileManager.default.moveItem(at: fileURL, to: bak)
            }
        }
        if notify { onChange?() }
    }

    // MARK: Mutations

    /// Adds `files` to the session `id` (created when new). A file already in the session is replaced; a non-empty `note` is appended.
    func record(id: String, title: String, started: Date, files: [LedgerFile], note: String, now: Date) {
        var list = sessions
        let cleanFiles = files.map { f -> LedgerFile in var f = f; f.symbols = Array(f.symbols.prefix(Self.maxSymbolsPerFile)); return f }
        let cleanTitle = String(title.prefix(Self.maxTitleChars))
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = list.firstIndex(where: { $0.id == id }) {
            var s = list[i]
            for f in cleanFiles {
                if let j = s.files.firstIndex(where: { $0.rel == f.rel }) { s.files[j] = f } else { s.files.append(f) }
            }
            s.files = Array(s.files.prefix(Self.maxFilesPerSession))
            if !trimmed.isEmpty { s.note = String((s.note.isEmpty ? trimmed : s.note + "\n" + trimmed).prefix(Self.maxNoteChars)) }
            if !cleanTitle.isEmpty { s.title = cleanTitle }
            s.updated = now
            list[i] = s
        } else {
            list.append(LedgerSession(id: id, started: started, updated: now, title: cleanTitle, note: String(trimmed.prefix(Self.maxNoteChars)),
                                      files: Array(cleanFiles.prefix(Self.maxFilesPerSession))))
        }
        commit(list)
    }

    func setNote(_ note: String, for id: String) {
        var list = sessions
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].note = String(note.prefix(Self.maxNoteChars))
        commit(list)
    }

    func remove(id: String) { commit(sessions.filter { $0.id != id }) }

    private func commit(_ list: [LedgerSession]) {
        sessions = Array(list.sorted { $0.updated > $1.updated }.prefix(Self.maxSessions))
        save()
        onChange?()
    }

    // MARK: Persistence

    private func encoded() -> Data? {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys]
        return try? enc.encode(Payload(version: Self.version, sessions: sessions))
    }

    /// Writes the file after trimming (oldest sessions first, then the last files of a lone session) to fit `maxBytes`.
    @discardableResult
    func save() -> Bool {
        var data = encoded()
        while let d = data, d.count > Self.maxBytes {
            if sessions.count > 1 { sessions.removeLast() }
            else if var s = sessions.first, s.files.count > 1 { s.files.removeLast(); sessions = [s] }
            else { break }
            data = encoded()
        }
        guard let data else { return false }
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch { return false }
    }
}
