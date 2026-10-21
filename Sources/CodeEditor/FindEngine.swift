import AppKit

// Project-wide Find / Replace in Files engine. Streams files through mmap, never holds project text.

struct FindOptions {
    var query: String
    var isRegex = false
    var caseSensitive = false
    var wholeWord = false
    /// Comma separated globs, e.g. "*.php, *.blade.php, !*.min.js". Empty = all text files.
    var fileMask = ""
    /// Also search skipNames directories (vendor, node_modules, ...) by walking the filesystem. `.git` is always skipped.
    var includeIgnored = false
    /// Replace: keep the matched text's casing style (ALL CAPS / Capitalised / lower) on the replacement.
    var preserveCase = false
    /// nil = project root.
    var directory: URL?
}

struct FindMatch {
    let url: URL
    let line: Int           // 1-based
    let column: Int         // 1-based, UTF-16
    let length: Int         // UTF-16
    let lineText: String    // untrimmed; very long lines are cut to a window around the match (with ellipses)
    /// UTF-16 offset of the match inside `lineText` (differs from column-1 when the line was windowed).
    var textOffset = 0
}

struct FindKey: Hashable { let path: String; let line: Int; let column: Int }
extension FindMatch { var key: FindKey { FindKey(path: url.path, line: line, column: column) } }

struct FindStats {
    var filesScanned = 0
    var filesMatched = 0
    var matches = 0
    var milliseconds = 0.0
    var truncated = false
    var error: String?
}

final class CancelToken {
    private let lock = NSLock()
    private var flag = false
    func cancel() { lock.lock(); flag = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

struct FindReplaceReport {
    var replaced = Set<FindKey>()
    var filesChanged = 0
    var buffersEdited = 0
    var skipped: [(url: URL, reason: String)] = []
    var error: String?
}

// MARK: - Glob mask

struct FindGlobMask {
    private struct Pat { let text: String; let hasSlash: Bool }
    private var includes: [Pat] = []
    private var excludes: [Pat] = []

    init(_ s: String) {
        for raw in s.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            var t = raw.trimmingCharacters(in: .whitespaces)
            var neg = false
            if t.hasPrefix("!") { neg = true; t = String(t.dropFirst()).trimmingCharacters(in: .whitespaces) }
            while t.hasPrefix("./") { t = String(t.dropFirst(2)) }
            while t.hasSuffix("/") { t.removeLast() }
            guard !t.isEmpty else { continue }
            let p = Pat(text: t, hasSlash: t.contains("/"))
            if neg { excludes.append(p) } else { includes.append(p) }
        }
    }

    var isEmpty: Bool { includes.isEmpty && excludes.isEmpty }

    private static func fn(_ pattern: String, _ s: String) -> Bool { fnmatch(pattern, s, FNM_CASEFOLD) == 0 }

    func allows(_ rel: String) -> Bool {
        let base = rel.lastIndex(of: "/").map { String(rel[rel.index(after: $0)...]) } ?? rel
        if !includes.isEmpty {
            var ok = false
            for p in includes {
                if p.hasSlash {
                    if Self.fn(p.text, rel) || Self.fn("*/" + p.text, rel) || Self.fn(p.text + "/*", rel) || Self.fn("*/" + p.text + "/*", rel) { ok = true; break }
                } else if Self.fn(p.text, base) { ok = true; break }
            }
            if !ok { return false }
        }
        for p in excludes {
            if p.hasSlash {
                if Self.fn(p.text, rel) || Self.fn("*/" + p.text, rel) || Self.fn(p.text + "/*", rel) || Self.fn("*/" + p.text + "/*", rel) { return false }
            } else {
                if Self.fn(p.text, base) { return false }
                if rel.contains("/") { for comp in rel.split(separator: "/").dropLast() where Self.fn(p.text, String(comp)) { return false } }
            }
        }
        return true
    }
}

// MARK: - Compiled query

enum FindError: Error { case message(String) }

final class FindMatcher {
    let opts: FindOptions
    let needle: UnsafeMutablePointer<UInt8>   // literal bytes (already lowercased when case-insensitive)
    let needleCount: Int
    let needleUnits: Int                      // UTF-16 length of the literal
    let regex: NSRegularExpression?           // set for regex mode and for non-ASCII case-insensitive literals
    let regexSemantics: Bool                  // true = user regex (templates apply)

    init(_ o: FindOptions) throws {
        opts = o
        let q = o.query
        let ascii = q.utf8.allSatisfy { $0 < 0x80 }
        var bytes = Array(q.utf8)
        needleUnits = q.utf16.count
        regexSemantics = o.isRegex
        if o.isRegex || (!o.caseSensitive && !ascii) {
            var pattern = o.isRegex ? q : NSRegularExpression.escapedPattern(for: q)
            if o.wholeWord { pattern = "\\b(?:" + pattern + ")\\b" }
            var ro: NSRegularExpression.Options = [.anchorsMatchLines]
            if !o.caseSensitive { ro.insert(.caseInsensitive) }
            do { regex = try NSRegularExpression(pattern: pattern, options: ro) }
            catch { throw FindError.message(Self.cleanMessage(error)) }
        } else {
            regex = nil
            if !o.caseSensitive { bytes = bytes.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 } }
        }
        needleCount = bytes.count
        needle = UnsafeMutablePointer<UInt8>.allocate(capacity: max(1, bytes.count))
        needle.initialize(from: bytes, count: bytes.count)
    }
    deinit { needle.deallocate() }

    static func cleanMessage(_ e: Error) -> String {
        let d = (e as NSError).userInfo[NSDebugDescriptionErrorKey] as? String
        return d ?? e.localizedDescription
    }

    /// Template for NSRegularExpression.replacementString: `$1` kept, `\n \t \r` expanded; literal mode is escaped.
    func template(for replacement: String) -> String {
        guard regexSemantics else { return NSRegularExpression.escapedTemplate(for: replacement) }
        var out = ""
        var it = replacement.makeIterator()
        while let ch = it.next() {
            if ch == "\\" {
                guard let nx = it.next() else { out.append("\\\\"); break }
                switch nx {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                default: out.append("\\"); out.append(nx)
                }
            } else { out.append(ch) }
        }
        return out
    }
}

// MARK: - Byte helpers

@inline(__always) private func utf16Len(_ p: UnsafePointer<UInt8>, _ a: Int, _ b: Int) -> Int {
    var c = 0, i = a
    while i < b {
        let x = p[i]
        if x & 0xC0 != 0x80 { c += x >= 0xF0 ? 2 : 1 }
        i += 1
    }
    return c
}

private func isValidUTF8(_ p: UnsafePointer<UInt8>, _ n: Int) -> Bool {
    var i = 0
    while i < n {
        let b = p[i]
        if b < 0x80 { i += 1; continue }
        var need = 0
        if b >= 0xC2 && b <= 0xDF { need = 1 } else if b >= 0xE0 && b <= 0xEF { need = 2 } else if b >= 0xF0 && b <= 0xF4 { need = 3 } else { return false }
        if i + need >= n { return false }
        for k in 1...need where p[i + k] & 0xC0 != 0x80 { return false }
        i += need + 1
    }
    return true
}

@inline(__always) private func isWordByte(_ b: UInt8) -> Bool {
    (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95 || b >= 0x80
}

private func decodeLine(_ p: UnsafePointer<UInt8>, _ a: Int, _ b: Int, latin1: Bool) -> String {
    let buf = UnsafeBufferPointer(start: p + a, count: b - a)
    if latin1 { return String(String.UnicodeScalarView(buf.map { Unicode.Scalar($0) })) }
    return String(decoding: buf, as: UTF8.self)
}

// MARK: - Per-file scanning

struct FindSnapshot { let mtime: Double; let size: Int }

private let maxFileBytes = 2_000_000
private let maxLineDisplay = 300

private func readFile(_ path: String) -> (data: Data, snap: FindSnapshot)? {
    var st = stat()
    guard stat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size > 0, st.st_size <= maxFileBytes else { return nil }
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return nil }
    let mt = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
    return (data, FindSnapshot(mtime: mt, size: Int(st.st_size)))
}

private func snapshot(of path: String) -> FindSnapshot? {
    var st = stat()
    guard stat(path, &st) == 0 else { return nil }
    return FindSnapshot(mtime: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9, size: Int(st.st_size))
}

private func looksBinary(_ p: UnsafePointer<UInt8>, _ n: Int) -> Bool {
    memchr(p, 0, min(8192, n)) != nil
}

/// Scans one file's bytes; appends matches until `out.count` reaches `cap`.
private func scanBuffer(_ p: UnsafePointer<UInt8>, _ n: Int, url: URL, m: FindMatcher, cap: Int, out: inout [FindMatch]) {
    if looksBinary(p, n) { return }
    if m.regex != nil { scanRegex(p, n, url: url, m: m, cap: cap, out: &out) } else { scanLiteral(p, n, url: url, m: m, cap: cap, out: &out) }
}

private func scanLiteral(_ p: UnsafePointer<UInt8>, _ n: Int, url: URL, m: FindMatcher, cap: Int, out: inout [FindMatch]) {
    let nl = m.needleCount
    guard nl > 0, n >= nl else { return }
    let needle = UnsafePointer(m.needle)
    let sensitive = m.opts.caseSensitive
    let whole = m.opts.wholeWord
    let lo = needle[0]
    let hi: UInt8 = (lo >= 97 && lo <= 122) ? lo - 32 : lo
    var candA = -1, candB = -1
    let startWord = isWordByte(needle[0]), endWord = isWordByte(needle[nl - 1])

    var lineNo = 1, lineStart = 0, scanned = 0, lineEnd = -1, colPos = 0, colUnits = 0
    var latin1: Bool?
    var pos = 0

    @inline(__always) func find(_ from: Int) -> Int? {
        if sensitive {
            guard let r = memmem(p + from, n - from, needle, nl) else { return nil }
            return p.distance(to: r.assumingMemoryBound(to: UInt8.self))
        }
        var i = from
        let limit = n - nl
        while i <= limit {
            if candA < i { candA = memchr(p + i, Int32(lo), n - i).map { p.distance(to: $0.assumingMemoryBound(to: UInt8.self)) } ?? Int.max }
            if hi != lo, candB < i { candB = memchr(p + i, Int32(hi), n - i).map { p.distance(to: $0.assumingMemoryBound(to: UInt8.self)) } ?? Int.max }
            let c = hi == lo ? candA : min(candA, candB)
            if c > limit { return nil }
            var k = 1
            while k < nl {
                let b = p[c + k]
                if (b >= 65 && b <= 90 ? b + 32 : b) != needle[k] { break }
                k += 1
            }
            if k == nl { return c }
            i = c + 1
        }
        return nil
    }

    while pos + nl <= n, out.count < cap {
        guard let s = find(pos) else { break }
        let e = s + nl
        if whole {
            if startWord, s > 0, isWordByte(p[s - 1]) { pos = s + 1; continue }
            if endWord, e < n, isWordByte(p[e]) { pos = s + 1; continue }
        }
        pos = e
        if latin1 == nil { latin1 = !isValidUTF8(p, n) }
        let l1 = latin1!
        // advance line tracking to s
        while scanned < s {
            guard let r = memchr(p + scanned, 10, s - scanned) else { scanned = s; break }
            let idx = p.distance(to: r.assumingMemoryBound(to: UInt8.self))
            lineNo += 1; lineStart = idx + 1; lineEnd = -1; colPos = lineStart; colUnits = 0
            scanned = idx + 1
        }
        scanned = max(scanned, s)
        if lineEnd < s {
            if let r = memchr(p + s, 10, n - s) { lineEnd = p.distance(to: r.assumingMemoryBound(to: UInt8.self)) } else { lineEnd = n }
        }
        let units = l1 ? s - colPos : utf16Len(p, colPos, s)
        colUnits += units; colPos = s
        var le = lineEnd
        if le > lineStart, p[le - 1] == 13 { le -= 1 }
        le = max(le, min(e, n))
        var a = lineStart, b = le
        var prefix = false, suffix = false
        if b - a > maxLineDisplay {
            a = max(lineStart, s - 50)
            b = min(le, e + 250)
            if !l1 {
                while a < s, p[a] & 0xC0 == 0x80 { a += 1 }
                while b < le, p[b] & 0xC0 == 0x80 { b += 1 }
            }
            prefix = a > lineStart; suffix = b < le
        }
        var text = decodeLine(p, a, b, latin1: l1)
        var off = l1 ? s - a : utf16Len(p, a, s)
        if prefix { text = "…" + text; off += 1 }
        if suffix { text += "…" }
        out.append(FindMatch(url: url, line: lineNo, column: colUnits + 1, length: m.needleUnits, lineText: text, textOffset: off))
    }
}

private func decodeText(_ p: UnsafePointer<UInt8>, _ n: Int) -> String {
    if isValidUTF8(p, n) { return String(decoding: UnsafeBufferPointer(start: p, count: n), as: UTF8.self) }
    return decodeLine(p, 0, n, latin1: true)
}

private func scanRegex(_ p: UnsafePointer<UInt8>, _ n: Int, url: URL, m: FindMatcher, cap: Int, out: inout [FindMatch]) {
    guard let re = m.regex else { return }
    let text = decodeText(p, n)
    let u16 = Array(text.utf16)
    let len = u16.count
    let startCount = out.count
    var sawMultiline = false

    func emitAll(ranges: [NSRange]) {
        var lineNo = 1, lineStart = 0, scanned = 0
        u16.withUnsafeBufferPointer { buf in
            for r in ranges {
                if out.count >= cap { return }
                while scanned < r.location {
                    if buf[scanned] == 10 { lineNo += 1; lineStart = scanned + 1 }
                    scanned += 1
                }
                var le = r.location
                while le < len, buf[le] != 10 { le += 1 }
                var lineEndTrim = le
                if lineEndTrim > lineStart, buf[lineEndTrim - 1] == 13 { lineEndTrim -= 1 }
                lineEndTrim = max(lineEndTrim, min(NSMaxRange(r), len))
                var a = lineStart, b = lineEndTrim
                var prefix = false, suffix = false
                if b - a > maxLineDisplay {
                    a = max(lineStart, r.location - 50)
                    b = min(lineEndTrim, NSMaxRange(r) + 250)
                    if a < r.location, UTF16.isTrailSurrogate(buf[a]) { a += 1 }
                    if b < lineEndTrim, UTF16.isTrailSurrogate(buf[b]) { b += 1 }
                    prefix = a > lineStart; suffix = b < lineEndTrim
                }
                var s = String(decoding: UnsafeBufferPointer(rebasing: buf[a..<b]), as: UTF16.self)
                var off = r.location - a
                if prefix { s = "…" + s; off += 1 }
                if suffix { s += "…" }
                out.append(FindMatch(url: url, line: lineNo, column: r.location - lineStart + 1, length: r.length, lineText: s, textOffset: off))
            }
        }
    }

    var ranges: [NSRange] = []
    re.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: len)) { res, _, stop in
        guard let r = res?.range, r.length > 0 else { return }
        var hasNL = false
        u16.withUnsafeBufferPointer { buf in for i in r.location..<NSMaxRange(r) where buf[i] == 10 { hasNL = true; break } }
        if hasNL { sawMultiline = true; stop.pointee = true; return }
        ranges.append(r)
        if startCount + ranges.count >= cap { stop.pointee = true }
    }
    if sawMultiline {
        // Multi-line matching is off: redo line by line so patterns like `\s` cannot cross newlines.
        ranges.removeAll()
        var ls = 0
        while ls <= len, startCount + ranges.count < cap {
            var le = ls
            while le < len, u16[le] != 10 { le += 1 }
            var end = le
            if end > ls, u16[end - 1] == 13 { end -= 1 }
            if end > ls {
                re.enumerateMatches(in: text, options: [.withTransparentBounds], range: NSRange(location: ls, length: end - ls)) { res, _, stop in
                    guard let r = res?.range, r.length > 0 else { return }
                    ranges.append(r)
                    if startCount + ranges.count >= cap { stop.pointee = true }
                }
            }
            ls = le + 1
        }
    }
    emitAll(ranges: ranges)
}

// MARK: - Engine

final class FindEngine {
    static let maxMatches = 10_000

    private let root: URL
    private let files: () -> [String]
    private let lock = NSLock()
    private var snapshots: [String: FindSnapshot] = [:]
    private let spillDir: URL
    private var lastReplace: [BackupEntry] = []
    private var backupBytes = 0
    static let memoryBackupCap = 16 * 1024 * 1024

    private struct BackupEntry {
        let url: URL
        let mem: Data?
        let spill: URL?
        let writtenMTime: Double
        let writtenSize: Int
    }

    init(root: URL, files: @escaping () -> [String]) {
        self.root = root
        self.files = files
        spillDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodeEditorFindBackup/\(UUID().uuidString)")
    }

    deinit { releaseBackups() }

    /// Drops the in-memory/Caches backup used by `undoLastReplace`.
    func releaseBackups() {
        lock.lock()
        let entries = lastReplace
        lastReplace = []; backupBytes = 0; snapshots = [:]
        lock.unlock()
        if entries.contains(where: { $0.spill != nil }) { try? FileManager.default.removeItem(at: spillDir) }
    }

    var canUndoReplace: Bool { lock.lock(); defer { lock.unlock() }; return !lastReplace.isEmpty }

    /// Returns an error message when the options cannot be compiled (bad regex), nil otherwise.
    static func validate(_ o: FindOptions) -> String? {
        guard !o.query.isEmpty else { return nil }
        do { _ = try FindMatcher(o); return nil } catch FindError.message(let m) { return m } catch { return "\(error)" }
    }

    // MARK: file listing

    private func canonical(_ p: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        return realpath(p, &buf) != nil ? String(cString: buf) : p
    }

    /// (absolute path, mask-relative path) pairs, sorted by path.
    func listFiles(_ o: FindOptions) -> [(path: String, rel: String)] {
        let rootPath = root.path
        let rootCanon = canonical(rootPath)
        let dirPath = o.directory?.path ?? rootPath
        let dirCanon = canonical(dirPath)
        let inRoot = dirCanon == rootCanon || dirCanon.hasPrefix(rootCanon + "/")
        var result: [(String, String)] = []
        let useIndex = !o.includeIgnored && inRoot
        let indexed = useIndex ? files() : []
        if useIndex && !indexed.isEmpty {
            let relDir = dirCanon == rootCanon ? "" : String(dirCanon.dropFirst(rootCanon.count + 1)) + "/"
            for rel in indexed where relDir.isEmpty || rel.hasPrefix(relDir) {
                result.append((rootPath + "/" + rel, rel))
            }
            return result
        }
        let base = inRoot ? rootCanon : dirCanon
        walk(dirCanon, base: base, skipAll: !o.includeIgnored, into: &result)
        result.sort { $0.0 < $1.0 }
        return result
    }

    private func walk(_ dir: String, base: String, skipAll: Bool, into out: inout [(String, String)]) {
        guard out.count < 300_000, let d = opendir(dir) else { return }
        defer { closedir(d) }
        var subdirs: [String] = []
        while let e = readdir(d) {
            let name = withUnsafePointer(to: &e.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: Int(e.pointee.d_namlen) + 1) { String(cString: $0) } }
            if name == "." || name == ".." { continue }
            if name == ".git" || name == ".DS_Store" { continue }
            if skipAll && ProjectIndex.skipNames.contains(name) { continue }
            let full = dir + "/" + name
            var type = e.pointee.d_type
            if type == UInt8(DT_UNKNOWN) {
                var st = stat()
                if lstat(full, &st) == 0 { type = (st.st_mode & S_IFMT) == S_IFDIR ? UInt8(DT_DIR) : (st.st_mode & S_IFMT) == S_IFLNK ? UInt8(DT_LNK) : UInt8(DT_REG) }
            }
            if type == UInt8(DT_DIR) { subdirs.append(full) }          // symlinked dirs are DT_LNK: never followed, so no loops
            else if type == UInt8(DT_REG) || type == UInt8(DT_LNK) {
                let rel = full.count > base.count + 1 && full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : full
                out.append((full, rel))
            }
        }
        for s in subdirs { walk(s, base: base, skipAll: skipAll, into: &out) }
    }

    // MARK: search

    @discardableResult
    func search(_ o: FindOptions, batch: @escaping ([FindMatch]) -> Void, done: @escaping (FindStats) -> Void) -> CancelToken {
        let token = CancelToken()
        guard !o.query.isEmpty else {
            DispatchQueue.main.async { if !token.isCancelled { done(FindStats()) } }
            return token
        }
        let matcher: FindMatcher
        do { matcher = try FindMatcher(o) } catch {
            var s = FindStats()
            if case FindError.message(let m) = error { s.error = m } else { s.error = "\(error)" }
            DispatchQueue.main.async { if !token.isCancelled { done(s) } }
            return token
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let t0 = DispatchTime.now()
            let mask = FindGlobMask(o.fileMask)
            var list = self.listFiles(o)
            if !mask.isEmpty { list = list.filter { mask.allows($0.rel) } }
            let sink = FindSink(token: token, batch: batch)
            let counter = FindCounter()
            let workers = PowerState.shared.maxWorkers
            let total = list.count
            let statsLock = NSLock()
            var scannedTotal = 0, matchedTotal = 0
            var snaps: [String: FindSnapshot] = [:]
            list.withUnsafeBufferPointer { files in
                DispatchQueue.concurrentPerform(iterations: workers) { _ in
                    var scanned = 0, matched = 0
                    var local: [String: FindSnapshot] = [:]
                    var buf: [FindMatch] = []
                    while !token.isCancelled, !sink.full {
                        let i = counter.next()
                        if i >= total { break }
                        let path = files[i].path
                        guard let (data, snap) = readFile(path) else { continue }
                        scanned += 1
                        buf.removeAll(keepingCapacity: true)
                        let url = URL(fileURLWithPath: path)
                        data.withUnsafeBytes { raw in
                            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                            scanBuffer(base, data.count, url: url, m: matcher, cap: FindEngine.maxMatches, out: &buf)
                        }
                        if !buf.isEmpty {
                            matched += 1
                            local[path] = snap
                            sink.add(buf)
                        } else { sink.tick() }
                    }
                    statsLock.lock()
                    scannedTotal += scanned; matchedTotal += matched
                    snaps.merge(local) { a, _ in a }
                    statsLock.unlock()
                }
            }
            self.lock.lock(); self.snapshots = snaps; self.lock.unlock()
            let (count, truncated) = sink.finish()
            var stats = FindStats(filesScanned: scannedTotal, filesMatched: matchedTotal, matches: count,
                                  milliseconds: Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6,
                                  truncated: truncated)
            stats.error = nil
            DispatchQueue.main.async { if !token.isCancelled { done(stats) } }
        }
        return token
    }

    // MARK: replace

    /// Applies `replacement` to the given (non-excluded) matches. Must run on the main thread.
    /// Open files go through `openBuffer` (one undo group per file); closed files are rewritten atomically after
    /// verifying they still match the scanned snapshot.
    func replace(_ matches: [FindMatch], with replacement: String, options: FindOptions,
                 openBuffer: (URL) -> EditorTab?) -> FindReplaceReport {
        var report = FindReplaceReport()
        let matcher: FindMatcher
        do { matcher = try FindMatcher(options) } catch {
            if case FindError.message(let m) = error { report.error = m } else { report.error = "\(error)" }
            return report
        }
        var byFile: [String: [FindMatch]] = [:]
        var order: [String] = []
        for m in matches { if byFile[m.url.path] == nil { order.append(m.url.path) }; byFile[m.url.path, default: []].append(m) }
        lock.lock(); let snaps = snapshots; lock.unlock()
        var newBackups: [BackupEntry] = []

        for path in order {
            let sel = byFile[path]!
            let url = sel[0].url
            if let tab = openBuffer(url) {
                let text = tab.textView.string
                let r = resolveEdits(text: text, sel: sel, m: matcher, replacement: replacement)
                for s in r.skipped { report.skipped.append((url, "line \(s.line) changed since the search")) }
                guard !r.edits.isEmpty else { continue }
                applyToBuffer(tab, edits: r.edits)
                for e in r.edits { report.replaced.insert(e.key) }
                report.buffersEdited += 1
                continue
            }
            // closed file: verify snapshot, re-read, edit, write atomically
            guard let snap = snaps[path], let now = snapshot(of: path), now.size == snap.size, abs(now.mtime - snap.mtime) < 0.001 else {
                report.skipped.append((url, "file changed since the search")); continue
            }
            guard let data = try? Data(contentsOf: url), data.count == snap.size else {
                report.skipped.append((url, "could not read file")); continue
            }
            var bom = false
            var body = data
            if data.starts(with: [0xEF, 0xBB, 0xBF]) { bom = true; body = data.dropFirst(3) }
            let latin1 = !body.withUnsafeBytes { raw in isValidUTF8(raw.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(bitPattern: 1)!, body.count) }
            guard let text = String(data: body, encoding: latin1 ? .isoLatin1 : .utf8) else {
                report.skipped.append((url, "unsupported encoding")); continue
            }
            let r = resolveEdits(text: text, sel: sel, m: matcher, replacement: replacement)
            for s in r.skipped { report.skipped.append((url, "line \(s.line) changed since the search")) }
            guard !r.edits.isEmpty else { continue }
            let mutable = NSMutableString(string: text)
            for e in r.edits.sorted(by: { $0.range.location > $1.range.location }) { mutable.replaceCharacters(in: e.range, with: e.new) }
            guard var out = (mutable as String).data(using: latin1 ? .isoLatin1 : .utf8) else {
                report.skipped.append((url, "replacement not representable in file encoding")); continue
            }
            if bom { out = Data([0xEF, 0xBB, 0xBF]) + out }
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            do { try out.write(to: url, options: .atomic) } catch {
                report.skipped.append((url, "write failed")); continue
            }
            if let perms = attrs?[.posixPermissions] { try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: path) }
            let written = snapshot(of: path) ?? snap
            newBackups.append(makeBackup(url: url, original: data, written: written))
            for e in r.edits { report.replaced.insert(e.key) }
            report.filesChanged += 1
        }
        if !newBackups.isEmpty {
            lock.lock(); lastReplace = newBackups; lock.unlock()
        }
        // refresh snapshots for rewritten files so a follow-up replace on remaining matches still works
        lock.lock()
        for b in newBackups { snapshots[b.url.path] = FindSnapshot(mtime: b.writtenMTime, size: b.writtenSize) }
        lock.unlock()
        return report
    }

    private func makeBackup(url: URL, original: Data, written: FindSnapshot) -> BackupEntry {
        lock.lock(); defer { lock.unlock() }
        if backupBytes + original.count <= Self.memoryBackupCap {
            backupBytes += original.count
            return BackupEntry(url: url, mem: original, spill: nil, writtenMTime: written.mtime, writtenSize: written.size)
        }
        try? FileManager.default.createDirectory(at: spillDir, withIntermediateDirectories: true)
        let f = spillDir.appendingPathComponent(UUID().uuidString)
        try? original.write(to: f)
        return BackupEntry(url: url, mem: nil, spill: f, writtenMTime: written.mtime, writtenSize: written.size)
    }

    /// Restores disk files written by the last replace (skips files modified since). Returns (restored, skipped).
    func undoLastReplace() -> (restored: Int, skipped: [(url: URL, reason: String)]) {
        lock.lock(); let entries = lastReplace; lastReplace = []; backupBytes = 0; lock.unlock()
        var restored = 0
        var skipped: [(URL, String)] = []
        for e in entries {
            guard let now = snapshot(of: e.url.path), now.size == e.writtenSize, abs(now.mtime - e.writtenMTime) < 0.001 else {
                skipped.append((e.url, "file modified since the replace")); continue
            }
            let data = e.mem ?? e.spill.flatMap { try? Data(contentsOf: $0) }
            guard let data else { skipped.append((e.url, "backup unavailable")); continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: e.url.path)
            do { try data.write(to: e.url, options: .atomic); restored += 1 } catch { skipped.append((e.url, "write failed")) }
            if let perms = attrs?[.posixPermissions] { try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: e.url.path) }
        }
        if entries.contains(where: { $0.spill != nil }) { try? FileManager.default.removeItem(at: spillDir) }
        return (restored, skipped)
    }

    // MARK: replace internals

    private struct Edit { let range: NSRange; let new: String; let key: FindKey }

    /// Re-validates each selected match against `text` and computes its replacement.
    private func resolveEdits(text: String, sel: [FindMatch], m: FindMatcher, replacement: String) -> (edits: [Edit], skipped: [FindMatch]) {
        let ns = text as NSString
        let len = ns.length
        var u16 = [unichar](repeating: 0, count: len)
        ns.getCharacters(&u16, range: NSRange(location: 0, length: len))
        let maxLine = sel.map(\.line).max() ?? 1
        var lineStarts = [0]
        if maxLine > 1 { for i in 0..<len where u16[i] == 10 { lineStarts.append(i + 1); if lineStarts.count >= maxLine { break } } }
        let tmpl = m.regex != nil ? m.template(for: replacement) : replacement
        var edits: [Edit] = []
        var skipped: [FindMatch] = []
        for mt in sel.sorted(by: { ($0.line, $0.column) < ($1.line, $1.column) }) {
            guard mt.line - 1 < lineStarts.count else { skipped.append(mt); continue }
            let ls = lineStarts[mt.line - 1]
            var le = ls
            while le < len, u16[le] != 10 { le += 1 }
            if le > ls, u16[le - 1] == 13 { le -= 1 }
            let loc = ls + mt.column - 1
            guard loc >= ls, loc + mt.length <= len else { skipped.append(mt); continue }
            let range = NSRange(location: loc, length: mt.length)
            if let last = edits.last, NSMaxRange(last.range) > loc { skipped.append(mt); continue }
            if let re = m.regex {
                guard loc + mt.length <= le,
                      let r = re.firstMatch(in: text, options: [.anchored, .withTransparentBounds, .withoutAnchoringBounds],
                                            range: NSRange(location: loc, length: le - loc)),
                      r.range == range else { skipped.append(mt); continue }
                let new = re.replacementString(for: r, in: text, offset: 0, template: tmpl)
                edits.append(Edit(range: range, new: m.opts.preserveCase ? Self.adaptCase(new, to: ns.substring(with: range)) : new, key: mt.key))
            } else {
                let sub = ns.substring(with: range)
                let same = m.opts.caseSensitive ? sub == m.opts.query : sub.compare(m.opts.query, options: .caseInsensitive) == .orderedSame
                guard same else { skipped.append(mt); continue }
                if m.opts.wholeWord {
                    func word(_ c: unichar) -> Bool { c == 95 || (c < 128 ? (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) : true) }
                    if loc > 0, word(u16[loc - 1]), word(u16[loc]) { skipped.append(mt); continue }
                    if loc + mt.length < len, word(u16[loc + mt.length]), word(u16[loc + mt.length - 1]) { skipped.append(mt); continue }
                }
                edits.append(Edit(range: range, new: m.opts.preserveCase ? Self.adaptCase(replacement, to: sub) : replacement, key: mt.key))
            }
        }
        return (edits, skipped)
    }

    /// "Preserve case": FOO -> BAR, Foo -> Bar, foo -> bar-as-typed.
    static func adaptCase(_ replacement: String, to matched: String) -> String {
        let letters = matched.filter(\.isLetter)
        guard !letters.isEmpty, !replacement.isEmpty else { return replacement }
        if letters.count > 1, letters == letters.uppercased() { return replacement.uppercased() }
        if letters == letters.lowercased() { return replacement.lowercased() }
        if let f = letters.first, f.isUppercase, letters.dropFirst() == letters.dropFirst().lowercased() {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }

    private func applyToBuffer(_ tab: EditorTab, edits: [Edit]) {
        let tv = tab.textView
        let asc = edits.sorted { $0.range.location < $1.range.location }
        guard tv.shouldChangeText(inRanges: asc.map { NSValue(range: $0.range) }, replacementStrings: asc.map(\.new)) else { return }
        let um = tv.undoManager
        um?.beginUndoGrouping()
        tv.textStorage?.beginEditing()
        for e in asc.reversed() { tv.textStorage?.replaceCharacters(in: e.range, with: e.new) }
        tv.textStorage?.endEditing()
        tv.didChangeText()
        um?.setActionName("Replace in Files")
        um?.endUndoGrouping()
    }
}

// MARK: - Concurrency helpers

private final class FindCounter {
    private let lock = NSLock()
    private var n = -1
    func next() -> Int { lock.lock(); n += 1; let v = n; lock.unlock(); return v }
}

/// Collects matches from workers and flushes them to the main thread every ~50 ms / 200 matches.
private final class FindSink {
    private let lock = NSLock()
    private var pending: [FindMatch] = []
    private var total = 0
    private var truncated = false
    private var lastFlush = DispatchTime.now()
    private let token: CancelToken
    private let batch: ([FindMatch]) -> Void

    init(token: CancelToken, batch: @escaping ([FindMatch]) -> Void) { self.token = token; self.batch = batch }

    var full: Bool { lock.lock(); defer { lock.unlock() }; return truncated }

    func add(_ ms: [FindMatch]) {
        lock.lock()
        let room = FindEngine.maxMatches - total
        let take = ms.count > room ? Array(ms.prefix(max(0, room))) : ms
        pending.append(contentsOf: take); total += take.count
        if total >= FindEngine.maxMatches { truncated = true }
        flushIfDue()
        lock.unlock()
    }

    func tick() {
        lock.lock()
        if !pending.isEmpty { flushIfDue() }
        lock.unlock()
    }

    private func flushIfDue() {
        let now = DispatchTime.now()
        if pending.count >= 200 || now.uptimeNanoseconds - lastFlush.uptimeNanoseconds >= 50_000_000 {
            send()
        }
    }

    private func send() {
        guard !pending.isEmpty else { return }
        let out = pending; pending = []; lastFlush = DispatchTime.now()
        let token = self.token, batch = self.batch
        DispatchQueue.main.async { if !token.isCancelled { batch(out) } }
    }

    func finish() -> (Int, Bool) {
        lock.lock(); send(); let r = (total, truncated); lock.unlock()
        return r
    }
}
