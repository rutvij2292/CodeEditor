import Foundation
import CryptoKit

/// Cheap safety net: previous versions of a file are copied to ~/Library/Caches/CodeEditor/history/<hash of real path>/
/// before every save, external reload and discard. Content-hash deduped; per-file (50 revisions / 5 MB) and total (200 MB,
/// least recently used first) caps; files over 2 MB are not tracked.
///
/// Restore policy (simplest robust path): `ProjectWindow.restoreRevision` replaces the buffer with the revision as ONE
/// undoable edit after a confirmation; nothing is written to disk until the user saves.
enum LocalHistory {
    struct Revision: Equatable {
        let url: URL          // the stored copy
        let date: Date
        let size: Int
        let hash: String
    }

    static var root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/CodeEditor/history", isDirectory: true)
    static var maxRevisionsPerFile = 50
    static var maxBytesPerFile = 5_000_000
    static var maxTotalBytes = 200_000_000
    static var maxTrackedFileSize = 2_000_000
    private static var snapshotCount = 0

    private static func hex(_ data: Data) -> String { SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined() }

    static func directory(for file: URL) -> URL {
        let key = hex(Data(FileIO.resolve(file).path.utf8))
        return root.appendingPathComponent(key, isDirectory: true)
    }

    /// Stores `data` as the newest revision of `file` (no-op when over the size cap or already the newest/any stored content).
    @discardableResult
    static func snapshot(_ data: Data, of file: URL, now: Date = Date()) -> Bool {
        guard data.count <= maxTrackedFileSize else { return false }
        let fm = FileManager.default
        let dir = directory(for: file)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { return false }
        let h = hex(data)
        let existing = revisions(for: file)
        if let dup = existing.first(where: { $0.hash == h }) {
            // Same content already kept: just move it to "now" so LRU eviction treats it as fresh.
            let renamed = dir.appendingPathComponent(name(now, h))
            if dup.url != renamed, dup.date < now { try? fm.moveItem(at: dup.url, to: renamed) }
            return false
        }
        let meta = dir.appendingPathComponent("path.txt")
        if !fm.fileExists(atPath: meta.path) { try? Data(FileIO.resolve(file).path.utf8).write(to: meta) }
        guard (try? data.write(to: dir.appendingPathComponent(name(now, h)), options: .atomic)) != nil else { return false }
        trim(dir)
        snapshotCount += 1
        if snapshotCount % 25 == 1 { evict() }
        return true
    }

    /// Snapshots whatever is on disk at `file` now (before it is overwritten or replaced).
    static func snapshotDisk(of file: URL) {
        let real = FileIO.resolve(file)
        guard let stamp = FileIO.stamp(real), stamp.size <= Int64(maxTrackedFileSize), stamp.size > 0,
              let data = try? Data(contentsOf: real) else { return }
        snapshot(data, of: file)
    }

    private static func name(_ date: Date, _ hash: String) -> String { String(format: "%013d-%@.rev", Int(date.timeIntervalSince1970 * 1000), hash) }

    /// Newest first.
    static func revisions(for file: URL) -> [Revision] {
        let dir = directory(for: file)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        var result: [Revision] = []
        for n in names where n.hasSuffix(".rev") {
            let parts = n.dropLast(4).split(separator: "-", maxSplits: 1)
            guard parts.count == 2, let ms = Double(parts[0]) else { continue }
            let url = dir.appendingPathComponent(n)
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
            result.append(Revision(url: url, date: Date(timeIntervalSince1970: ms / 1000), size: size, hash: String(parts[1])))
        }
        return result.sorted { $0.date > $1.date }
    }

    static func data(of revision: Revision) -> Data? { try? Data(contentsOf: revision.url) }

    /// The revision decoded like the file was (a byte-order mark wins over `encoding`).
    static func text(of revision: Revision, encoding: String.Encoding = .utf8) -> String? {
        guard let bytes = data(of: revision) else { return nil }
        if let (sniffed, length) = TextEncodings.sniffBOM(bytes) { return String(data: bytes.dropFirst(length), encoding: sniffed) }
        return String(data: bytes, encoding: encoding)
    }

    private static func trim(_ dir: URL) {
        let fm = FileManager.default
        var list = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".rev") }.sorted(by: >)
        var bytes = 0
        var kept = 0
        for n in list {
            let size = ((try? fm.attributesOfItem(atPath: dir.appendingPathComponent(n).path))?[.size] as? NSNumber)?.intValue ?? 0
            // Always keep the newest revision, however big.
            if kept >= 1, kept >= maxRevisionsPerFile || bytes + size > maxBytesPerFile {
                try? fm.removeItem(at: dir.appendingPathComponent(n))
            } else { bytes += size; kept += 1 }
        }
        list.removeAll()
    }

    /// Total cap: removes the least recently used revisions (oldest timestamp) across all files.
    static func evict(totalLimit: Int? = nil) {
        let limit = totalLimit ?? maxTotalBytes
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return }
        var all: [(url: URL, ms: String, size: Int)] = []
        var total = 0
        for d in dirs {
            for n in (try? fm.contentsOfDirectory(atPath: d.path)) ?? [] where n.hasSuffix(".rev") {
                let u = d.appendingPathComponent(n)
                let size = ((try? fm.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.intValue ?? 0
                all.append((u, String(n.prefix(13)), size)); total += size
            }
        }
        guard total > limit else { return }
        for item in all.sorted(by: { $0.ms < $1.ms }) {
            if total <= limit { break }
            try? fm.removeItem(at: item.url)
            total -= item.size
        }
        // Drop directories left empty.
        for d in dirs where ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).filter({ $0.hasSuffix(".rev") }).isEmpty {
            try? fm.removeItem(at: d)
        }
    }

    static func describe(_ revision: Revision, relativeTo now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDate(revision.date, inSameDayAs: now) ? "HH:mm:ss" : "MMM d, HH:mm"
        let kb = Double(revision.size) / 1000
        return "\(f.string(from: revision.date))  ·  " + (kb < 1000 ? String(format: "%.1f KB", kb) : String(format: "%.1f MB", kb / 1000))
    }
}
