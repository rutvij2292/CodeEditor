import Foundation

// Global functions and constants defined in a project's autoloaded helper files (composer `autoload.files`, i.e.
// app/helpers.php and vendor helpers such as Laravel's Foundation/helpers.php). Only names + offsets are kept (built lazily
// on the first function lookup, rebuilt when composer's autoload_files.php changes); signatures and docblocks are read from
// the file at lookup time.

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
            let re = try? NSRegularExpression(pattern: #"\$(vendorDir|baseDir)\s*\.\s*'([^']+)'"#)
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
        files = autoloadFiles()
        functions.removeAll(); constants.removeAll()
        let fnRe = try? NSRegularExpression(pattern: #"(?m)(?:^|[\s;{}])function\s+&?\s*([A-Za-z_]\w*)\s*\("#)
        let defRe = try? NSRegularExpression(pattern: #"define\(\s*['"]([A-Za-z_]\w*)['"]"#)
        let constRe = try? NSRegularExpression(pattern: #"(?m)^const\s+([A-Za-z_]\w*)\s*="#)
        for (idx, f) in files.enumerated() {
            guard let size = (try? FileManager.default.attributesOfItem(atPath: f))?[.size] as? NSNumber, size.intValue < Self.maxFileBytes,
                  let ns = FastProject.read(f) else { continue }
            let full = NSRange(location: 0, length: ns.length)
            for m in fnRe?.matches(in: ns as String, range: full) ?? [] {
                let r = m.range(at: 1)
                // skip methods: preceded by a visibility/static keyword on the same statement
                let ctx = ns.substring(with: NSRange(location: max(0, m.range.location - 24), length: min(24, m.range.location)))
                if ctx.range(of: #"(public|protected|private|static|abstract|final)\s*$"#, options: .regularExpression) != nil { continue }
                let key = ns.substring(with: r).lowercased()
                if functions[key] == nil { functions[key] = Entry(file: Int32(idx), loc: Int32(r.location), declStart: Int32(m.range.location)) }
            }
            for (re, group) in [(defRe, 1), (constRe, 1)] {
                for m in re?.matches(in: ns as String, range: full) ?? [] {
                    let r = m.range(at: group)
                    let key = ns.substring(with: r)
                    if constants[key] == nil { constants[key] = Entry(file: Int32(idx), loc: Int32(r.location), declStart: Int32(m.range.location)) }
                }
            }
        }
    }

    struct Found { var path: String; var loc: Int; var declStart: Int }

    func function(_ name: String) -> Found? {
        ensureBuilt()
        guardLock.lock(); defer { guardLock.unlock() }
        guard let e = functions[name.lowercased()], Int(e.file) < files.count else { return nil }
        return Found(path: files[Int(e.file)], loc: Int(e.loc), declStart: Int(e.declStart))
    }

    func constant(_ name: String) -> Found? {
        ensureBuilt()
        guardLock.lock(); defer { guardLock.unlock() }
        guard let e = constants[name], Int(e.file) < files.count else { return nil }
        return Found(path: files[Int(e.file)], loc: Int(e.loc), declStart: Int(e.declStart))
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
