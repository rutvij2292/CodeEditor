import Foundation

/// Project-wide symbol table, built lazily in the background and refreshed incrementally by mtime.
final class SymbolIndex {
    struct Entry { let symbol: CodeSymbol; let relativePath: String }

    static let maxFileSize = 1_000_000
    static let maxFiles = 30_000
    private static let extensions: Set<String> = ["php", "phtml", "js", "jsx", "mjs", "cjs"]

    private struct FileSymbols { let mtime: Date; let symbols: [CodeSymbol] }

    let root: URL
    private let files: () -> [String]
    private let queue = DispatchQueue(label: "symbol-index", qos: .utility)
    private let lock = NSLock()
    private var perFile: [String: FileSymbols] = [:]
    private var flat: [Entry]?

    init(root: URL, files: @escaping () -> [String]) {
        self.root = root
        self.files = files
    }

    var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        if let flat { return flat }
        var all: [Entry] = []
        for (path, f) in perFile { for s in f.symbols { all.append(Entry(symbol: s, relativePath: path)) } }
        all.sort { ($0.relativePath, $0.symbol.line) < ($1.relativePath, $1.symbol.line) }
        flat = all
        return all
    }

    private func parse(_ path: String, known: FileSymbols?) -> FileSymbols? {
        let url = root.appendingPathComponent(path)
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let size = values.fileSize, size <= Self.maxFileSize else { return nil }
        let mtime = values.contentModificationDate ?? .distantPast
        if let known, known.mtime == mtime { return known }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = (path as NSString).pathExtension
        let syms = autoreleasepool { () -> [CodeSymbol] in
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return [] }
            return SymbolExtractor.symbols(in: text, fileExtension: ext)
        }
        return FileSymbols(mtime: mtime, symbols: syms)
    }

    func rebuild(completion: (() -> Void)? = nil) {
        SymbolExtractor.prime()
        let candidates = files().filter { Self.extensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .prefix(Self.maxFiles)
        let paths = Array(candidates)
        queue.async { [self] in
            lock.lock(); let old = perFile; lock.unlock()
            var results = [FileSymbols?](repeating: nil, count: paths.count)
            let resultLock = NSLock()
            let chunk = 64
            let chunks = (paths.count + chunk - 1) / chunk
            DispatchQueue.concurrentPerform(iterations: chunks) { c in
                var local: [(Int, FileSymbols)] = []
                for i in (c * chunk)..<min(paths.count, (c + 1) * chunk) {
                    if let r = autoreleasepool(invoking: { parse(paths[i], known: old[paths[i]]) }) { local.append((i, r)) }
                }
                resultLock.lock()
                for (i, r) in local { results[i] = r }
                resultLock.unlock()
            }
            var fresh: [String: FileSymbols] = [:]
            fresh.reserveCapacity(paths.count)
            for (i, r) in results.enumerated() { if let r { fresh[paths[i]] = r } }
            lock.lock(); perFile = fresh; flat = nil; lock.unlock()
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    func update(file relativePath: String) {
        guard Self.extensions.contains((relativePath as NSString).pathExtension.lowercased()) else { return }
        SymbolExtractor.prime()
        queue.async { [self] in
            let r = parse(relativePath, known: nil)
            lock.lock()
            perFile[relativePath] = r
            flat = nil
            lock.unlock()
        }
    }
}
