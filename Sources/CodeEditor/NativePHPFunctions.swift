import Foundation

// Global functions and constants defined in a project's autoloaded helper files (composer `autoload.files`, i.e.
// app/helpers.php and vendor helpers such as Laravel's Foundation/helpers.php). Only names + offsets are kept (built lazily
// on the first function lookup, rebuilt when composer's autoload_files.php changes); signatures and docblocks are read from
// the file at lookup time.

/// One growable byte buffer per concurrently running thread (keyed by thread), for repeated file reads without an allocation each.
final class NPReadBuffers {
    private let lock = NSLock()
    private var free: [[UInt8]] = []
    func withBuffer<T>(_ body: (inout [UInt8]) -> T) -> T {
        lock.lock(); var buf = free.popLast() ?? []; lock.unlock()
        defer { lock.lock(); if free.count < 16 { free.append(buf) }; lock.unlock() }
        return body(&buf)
    }
}

/// Lock-protected counter handing out work indices to concurrent workers.
final class NPCounter {
    private let lock = NSLock()
    private var n = -1
    func next() -> Int { lock.lock(); n += 1; let v = n; lock.unlock(); return v }
}

final class NPFuncIndex {
    struct Entry { var file: Int32; var loc: Int32; var declStart: Int32 }

    private static let lock = NSLock()
    private static var byRoot: [String: NPFuncIndex] = [:]
    private static var order: [String] = []

    static func shared(root: String) -> NPFuncIndex {
        lock.lock(); defer { lock.unlock() }
        if let i = byRoot[root] { return i }
        let i = NPFuncIndex(root: root)
        byRoot[root] = i
        order.append(root)
        while order.count > 3 { byRoot[order.removeFirst()] = nil }
        return i
    }

    let root: String
    private var files: [String] = []
    private var functions: [String: Entry] = [:]       // lowercased name
    private var constants: [String: Entry] = [:]
    private var stamp: Int64 = .min
    private var checkedAt = Date.distantPast
    private let guardLock = NSLock()

    init(root: String) { self.root = root }

    static let maxFileBytes = 600_000
    static let maxFiles = 60

    private func autoloadFiles() -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ p: String) { if seen.insert(p).inserted, LaravelFS.isFile(p) { out.append(p) } }
        if let t = FastProject.read(root + "/vendor/composer/autoload_files.php") as String? {
            let re = NPRe.make(pattern: #"\$(vendorDir|baseDir)\s*\.\s*'([^']+)'"#)
            for m in re?.matches(in: t, range: NSRange(location: 0, length: (t as NSString).length)) ?? [] {
                let base = (t as NSString).substring(with: m.range(at: 1)) == "vendorDir" ? root + "/vendor" : root
                add(base + (t as NSString).substring(with: m.range(at: 2)))
            }
        }
        if let d = FileManager.default.contents(atPath: root + "/composer.json"),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            for key in ["autoload", "autoload-dev"] {
                for f in ((obj[key] as? [String: Any])?["files"] as? [String]) ?? [] { add(root + "/" + f) }
            }
        }
        return Array(out.prefix(Self.maxFiles))
    }

    private func currentStamp() -> Int64 {
        LaravelFS.mtime(root + "/vendor/composer/autoload_files.php") &+ LaravelFS.mtime(root + "/composer.json") &* 31
    }

    private func ensureBuilt() {
        guardLock.lock(); defer { guardLock.unlock() }
        let now = Date()
        if stamp != .min, now.timeIntervalSince(checkedAt) < 5 { return }
        checkedAt = now
        let st = currentStamp()
        if stamp == st { return }
        stamp = st
        let t0 = NPStats.now()
        defer { NPStats.funcIndexNs &+= NPStats.now() &- t0 }
        files = autoloadFiles()
        functions.removeAll(); constants.removeAll()
        // Every autoload file is scanned independently (on several threads: the first helper lookup read and scanned ~30 files serially),
        // then merged in file order so the first definition still wins.
        typealias Hit = (name: String, loc: Int, declStart: Int)
        var perFile = [(functions: [Hit], constants: [Hit])](repeating: ([], []), count: files.count)
        let fileList = files
        let counter = NPCounter()
        let workers = max(1, min(PowerState.shared.maxWorkers, 4, fileList.count))
        perFile.withUnsafeMutableBufferPointer { buf in
            let base = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: workers) { _ in
                while true {
                    let idx = counter.next()
                    if idx >= fileList.count { break }
                    base[idx] = Self.scanFile(fileList[idx])
                }
            }
        }
        for (idx, found) in perFile.enumerated() {
            for e in found.functions { let key = e.name.lowercased(); if functions[key] == nil { functions[key] = Entry(file: Int32(idx), loc: Int32(e.loc), declStart: Int32(e.declStart)) } }
            for e in found.constants where constants[e.name] == nil { constants[e.name] = Entry(file: Int32(idx), loc: Int32(e.loc), declStart: Int32(e.declStart)) }
        }
    }

    /// Functions and constants of one helper file. ASCII files are scanned as bytes (no decoding, no regex); anything else takes the regex path.
    /// Pure, so it may run on any thread.
    private static func scanFile(_ f: String) -> (functions: [(name: String, loc: Int, declStart: Int)], constants: [(name: String, loc: Int, declStart: Int)]) {
        if let data = FileManager.default.contents(atPath: f), data.count < maxFileBytes, let found = scanBytes(data) { return found }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: f))?[.size] as? NSNumber, size.intValue < maxFileBytes,
              let ns = FastProject.readRaw(f) else { return ([], []) }
        let fnRe = NPRe.make(pattern: #"(?m)(?:^|[\s;{}])function\s+&?\s*([A-Za-z_]\w*)\s*\("#)
        let defRe = NPRe.make(pattern: #"define\(\s*['"]([A-Za-z_]\w*)['"]"#)
        let constRe = NPRe.make(pattern: #"(?m)^const\s+([A-Za-z_]\w*)\s*="#)
        var fns: [(name: String, loc: Int, declStart: Int)] = [], consts: [(name: String, loc: Int, declStart: Int)] = []
        let full = NSRange(location: 0, length: ns.length)
        for m in fnRe?.matches(in: ns as String, range: full) ?? [] {
            let r = m.range(at: 1)
            // skip methods: preceded by a visibility/static keyword on the same statement
            if followsModifier(ns, m.range.location) { continue }
            fns.append((ns.substring(with: r), r.location, m.range.location))
        }
        for re in [defRe, constRe] {
            for m in re?.matches(in: ns as String, range: full) ?? [] {
                let r = m.range(at: 1)
                consts.append((ns.substring(with: r), r.location, m.range.location))
            }
        }
        return (fns, consts)
    }

    /// Byte scanner with the semantics of the regexes below (`function name(`, `define('X'`, `const X =` at a line start). Offsets are
    /// UTF-16 offsets, which equal byte offsets only for ASCII, so non-ASCII files return nil (caller uses the regex path).
    static func scanBytes(_ data: Data) -> (functions: [(name: String, loc: Int, declStart: Int)], constants: [(name: String, loc: Int, declStart: Int)])? {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> (functions: [(name: String, loc: Int, declStart: Int)], constants: [(name: String, loc: Int, declStart: Int)])? in
            let b = raw.bindMemory(to: UInt8.self)
            let n = b.count
            for c in b where c >= 0x80 { return nil }
            var fns: [(name: String, loc: Int, declStart: Int)] = [], consts: [(name: String, loc: Int, declStart: Int)] = []
            @inline(__always) func ws(_ c: UInt8) -> Bool { c == 32 || (c >= 9 && c <= 13) }
            @inline(__always) func idStart(_ c: UInt8) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 }
            @inline(__always) func idChar(_ c: UInt8) -> Bool { idStart(c) || (c >= 48 && c <= 57) }
            func word(_ at: Int, _ w: StaticString) -> Bool {
                let m = w.utf8CodeUnitCount
                guard at + m <= n else { return false }
                let p = w.utf8Start
                for i in 0..<m where b[at + i] != p[i] { return false }
                return true
            }
            func ident(_ at: Int) -> Int { var e = at; while e < n, idChar(b[e]) { e += 1 }; return e }
            var i = 0
            while i < n {
                let c = b[i]
                if c == 102, word(i, "function"), i == 0 || ws(b[i - 1]) || b[i - 1] == 59 || b[i - 1] == 123 || b[i - 1] == 125 {
                    var q = i + 8
                    let w0 = q
                    while q < n, ws(b[q]) { q += 1 }
                    if q > w0 {
                        if q < n, b[q] == 38 { q += 1 }
                        while q < n, ws(b[q]) { q += 1 }
                        if q < n, idStart(b[q]) {
                            let e = ident(q)
                            var r = e
                            while r < n, ws(b[r]) { r += 1 }
                            if r < n, b[r] == 40 {
                                let declStart = i > 0 ? i - 1 : 0
                                // skip methods: a visibility / static keyword right before `function`
                                var k = declStart
                                while k > 0, ws(b[k - 1]) { k -= 1 }
                                var isMethod = false
                                for mod in ["public", "protected", "private", "static", "abstract", "final"] as [StaticString] {
                                    let m = mod.utf8CodeUnitCount
                                    if k >= m, word(k - m, mod) { isMethod = true; break }
                                }
                                if !isMethod { fns.append((String(decoding: UnsafeBufferPointer(rebasing: b[q..<e]), as: UTF8.self), q, declStart)) }
                                i = r + 1
                                continue
                            }
                        }
                    }
                } else if c == 100, word(i, "define(") {
                    var q = i + 7
                    while q < n, ws(b[q]) { q += 1 }
                    if q < n, b[q] == 39 || b[q] == 34, q + 1 < n, idStart(b[q + 1]) {
                        let e = ident(q + 1)
                        if e < n, b[e] == 39 || b[e] == 34 { consts.append((String(decoding: UnsafeBufferPointer(rebasing: b[(q + 1)..<e]), as: UTF8.self), q + 1, i)) }
                    }
                } else if c == 99, i == 0 || b[i - 1] == 10, word(i, "const") {
                    var q = i + 5
                    let w0 = q
                    while q < n, ws(b[q]) { q += 1 }
                    if q > w0, q < n, idStart(b[q]) {
                        let e = ident(q)
                        var r = e
                        while r < n, ws(b[r]) { r += 1 }
                        if r < n, b[r] == 61 { consts.append((String(decoding: UnsafeBufferPointer(rebasing: b[q..<e]), as: UTF8.self), q, i)) }
                    }
                }
                i += 1
            }
            return (fns, consts)
        }
    }

    /// True when the text right before `loc` (ignoring whitespace) ends in a method modifier: `public function` is a method, not a helper.
    private static func followsModifier(_ ns: NSString, _ loc: Int) -> Bool {
        var e = loc
        while e > 0, [32, 9, 10, 13].contains(ns.character(at: e - 1)) { e -= 1 }
        for w in ["public", "protected", "private", "static", "abstract", "final"] {
            let n = w.utf16.count
            if e >= n, ns.substring(with: NSRange(location: e - n, length: n)) == w { return true }
        }
        return false
    }

    struct Found { var path: String; var loc: Int; var declStart: Int }

    /// Composer helper functions first; `stubs` adds PHP built-ins from the bundled stubs (PHPStubs) when nothing else matches.
    func function(_ name: String, stubs: Bool = true) -> Found? {
        ensureBuilt()
        guardLock.lock()
        if let e = functions[name.lowercased()], Int(e.file) < files.count {
            defer { guardLock.unlock() }
            return Found(path: files[Int(e.file)], loc: Int(e.loc), declStart: Int(e.declStart))
        }
        guardLock.unlock()
        guard stubs, let e = PHPStubs.functionEntry(name) else { return nil }
        return Found(path: e.path, loc: e.loc, declStart: e.declStart)
    }

    func constant(_ name: String, stubs: Bool = true) -> Found? {
        ensureBuilt()
        guardLock.lock()
        if let e = constants[name], Int(e.file) < files.count {
            defer { guardLock.unlock() }
            return Found(path: files[Int(e.file)], loc: Int(e.loc), declStart: Int(e.declStart))
        }
        guardLock.unlock()
        guard stubs, let e = PHPStubs.constantEntry(name) else { return nil }
        return Found(path: e.path, loc: e.loc, declStart: e.declStart)
    }

    var counts: (functions: Int, constants: Int, files: Int) { ensureBuilt(); return (functions.count, constants.count, files.count) }

    // MARK: Parsing a function at a known position

    /// `name(params): ret` text of the function whose name starts at `loc`.
    static func signature(_ ns: NSString, nameLoc loc: Int) -> (name: String, params: String, ret: String)? {
        guard loc < ns.length else { return nil }
        var e = loc
        while e < ns.length, CompletionLex.isIdent(ns.character(at: e)) { e += 1 }
        let name = ns.substring(with: NSRange(location: loc, length: e - loc))
        while e < ns.length, ns.character(at: e) == 32 { e += 1 }
        guard e < ns.length, ns.character(at: e) == 40 else { return nil }
        var depth = 0, q = e
        while q < ns.length, q - e < 4000 {
            let c = ns.character(at: q)
            if c == 40 { depth += 1 } else if c == 41 { depth -= 1; if depth == 0 { break } }
            q += 1
        }
        guard q < ns.length, depth == 0 else { return nil }
        let params = ns.substring(with: NSRange(location: e + 1, length: q - e - 1))
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\t" || $0 == " " }).joined(separator: " ")
        var r = q + 1
        while r < ns.length, ns.character(at: r) == 32 { r += 1 }
        var ret = ""
        if r < ns.length, ns.character(at: r) == 58 {
            r += 1
            var s = r
            while s < ns.length, ns.character(at: s) != 123, ns.character(at: s) != 59, s - r < 200 { s += 1 }
            ret = ns.substring(with: NSRange(location: r, length: s - r)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (name, params, ret)
    }
}
