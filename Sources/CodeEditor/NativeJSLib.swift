import Foundation
import SwiftTreeSitter

/// The TypeScript standard library (lib.*.d.ts) for the native JS / TS service.
///
/// Which lib files make up a program is decided exactly like tsc: `compilerOptions.lib` names them one by one; without it the default
/// lib of `target` is used (`lib.es2025.full.d.ts` when there is no target, the `.full` file of an ES version, `lib.es6.d.ts` for
/// ES2015 and ES5), and `/// <reference lib="..." />` lines pull in the rest. The directory is the one the TypeScript server would use:
/// the native TypeScript 7 platform package (project, then global), else a project / global `typescript/lib`, else the copy bundled in
/// `TsLib/` (Apache-2.0, Contents/Resources in the app). Files are memory mapped and never read as a whole: a byte level scan finds the
/// top-level declarations of every file once (name, kind, byte range, doc comment), and a lookup parses only the declaration it needs.
final class NJSLibFile {
    let path: String
    let data: Data                       // memory mapped
    private var checkpoints: [(byte: Int, u16: Int)] = [(0, 0)]       // every 4 KB: UTF-16 offset of the byte
    let ascii: Bool

    init?(path: String) {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return nil }
        var u16 = 0, nonASCII = false
        var cps: [(byte: Int, u16: Int)] = [(0, 0)]
        d.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            for i in 0..<b.count {
                if i > 0, i % 4096 == 0 { cps.append((i, u16)) }
                let c = b[i]
                if c < 0x80 { u16 += 1 } else { nonASCII = true; if c >= 0xF0 { u16 += 2 } else if c >= 0xC0 { u16 += 1 } }
            }
        }
        self.path = path; data = d; checkpoints = cps
        ascii = !nonASCII
    }

    var utf16Length: Int { utf16(atByte: data.count) }

    func utf16(atByte target: Int) -> Int {
        if ascii { return target }
        var lo = 0, hi = checkpoints.count - 1
        while lo < hi { let m = (lo + hi + 1) / 2; if checkpoints[m].byte <= target { lo = m } else { hi = m - 1 } }
        var (byte, u16) = checkpoints[lo]
        data.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            while byte < target, byte < b.count { let c = b[byte]; if c < 0x80 { u16 += 1 } else if c >= 0xF0 { u16 += 2 } else if c >= 0xC0 { u16 += 1 }; byte += 1 }
        }
        return u16
    }

    func byte(atUTF16 target: Int) -> Int {
        if ascii { return min(target, data.count) }
        var lo = 0, hi = checkpoints.count - 1
        while lo < hi { let m = (lo + hi + 1) / 2; if checkpoints[m].u16 <= target { lo = m } else { hi = m - 1 } }
        var (byte, u16) = checkpoints[lo]
        data.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            while u16 < target, byte < b.count { let c = b[byte]; if c < 0x80 { u16 += 1 } else if c >= 0xF0 { u16 += 2 } else if c >= 0xC0 { u16 += 1 }; byte += 1 }
        }
        return byte
    }

    func string(utf16 a: Int, _ b: Int) -> String {
        let x = byte(atUTF16: a), y = byte(atUTF16: b)
        guard y > x, y <= data.count else { return "" }
        return String(decoding: data[x..<y], as: UTF8.self)
    }

    func string(bytes a: Int, _ b: Int) -> String { b > a && b <= data.count ? String(decoding: data[a..<b], as: UTF8.self) : "" }

    func lineCol(utf16 offset: Int) -> (line: Int, col: Int) {
        let end = byte(atUTF16: offset)
        var line = 1, lineStart = 0
        data.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            for i in 0..<min(end, b.count) where b[i] == 10 { line += 1; lineStart = i + 1 }
        }
        return (line, utf16(atByte: end) - utf16(atByte: lineStart) + 1)
    }
}

struct NJSLibEntry {
    var file: Int
    var isValue: Bool
    var start: Int                       // byte offset of the doc comment (or the declaration)
    var end: Int
}

final class NJSLibIndex {
    let dir: String
    let rootNames: [String]
    private(set) var files: [NJSLibFile] = []
    private(set) var fileNames: [String] = []
    private(set) var byName: [String: [NJSLibEntry]] = [:]
    private let lock = NSLock()
    private var parsed: [String: [NJSSym]] = [:]
    private var parsedCost = 0

    init(dir: String, roots: [String]) {
        self.dir = dir; rootNames = roots
        var order: [String] = []
        var seen = Set<String>()
        func visit(_ name: String) {
            guard seen.insert(name).inserted else { return }
            let p = dir + "/" + name
            guard let f = NJSLibFile(path: p) else { return }
            for ref in NJSLibIndex.references(in: f) { visit(ref) }
            order.append(name)
            fileNames.append(name)
            files.append(f)
        }
        for r in roots { visit(r) }
        for (i, f) in files.enumerated() { NJSLibIndex.scan(f, index: i, into: &byName) }
    }

    /// `/// <reference lib="es2015" />` lines of the file header.
    static func references(in f: NJSLibFile) -> [String] {
        let head = f.string(bytes: 0, min(f.data.count, 2500))
        var out: [String] = []
        for line in head.split(separator: "\n") {
            guard line.hasPrefix("/// <reference lib=\""), let q = line.dropFirst(20).firstIndex(of: "\"") else { continue }
            out.append("lib." + line.dropFirst(20)[..<q].lowercased() + ".d.ts")
        }
        return out
    }

    /// Top-level declarations of a lib file: they start in column 0, `interface X {` ends at the matching `}`, `declare var X: ...;` at `;`.
    static func scan(_ f: NJSLibFile, index: Int, into table: inout [String: [NJSLibEntry]]) {
        f.data.withUnsafeBytes { raw in
            let b = raw.bindMemory(to: UInt8.self)
            let n = b.count
            @inline(__always) func isIdent(_ c: UInt8) -> Bool { (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 }
            func has(_ i: Int, _ w: StaticString) -> Bool {
                let k = w.utf8CodeUnitCount
                guard i + k <= n else { return false }
                let p = w.utf8Start
                for j in 0..<k where b[i + j] != p[j] { return false }
                return true
            }
            var i = 0
            while i < n {
                // at a line start
                let lineStart = i
                var j = i
                var isValue = true, closesWithBrace = false
                if has(j, "declare ") {
                    j += 8
                    if has(j, "var ") { j += 4 } else if has(j, "let ") { j += 4 } else if has(j, "const ") { j += 6 } else if has(j, "function ") { j += 9 }
                    else if has(j, "abstract class ") { j += 15; closesWithBrace = true } else if has(j, "class ") { j += 6; closesWithBrace = true }
                    else if has(j, "namespace ") { j += 10; closesWithBrace = true } else { j = -1 }
                } else if has(j, "interface ") { j += 10; isValue = false; closesWithBrace = true }
                else if has(j, "type ") { j += 5; isValue = false } else { j = -1 }
                if j > 0 {
                    let ns = j
                    while j < n, isIdent(b[j]) { j += 1 }
                    if j > ns {
                        let name = String(decoding: UnsafeBufferPointer(rebasing: b[ns..<j]), as: UTF8.self)
                        // end of the declaration
                        var depth = 0, k = j
                        var end = n
                        while k < n {
                            let c = b[k]
                            if c == 47, k + 1 < n, b[k + 1] == 47 { while k < n, b[k] != 10 { k += 1 }; continue }
                            if c == 47, k + 1 < n, b[k + 1] == 42 { k += 2; while k + 1 < n, !(b[k] == 42 && b[k + 1] == 47) { k += 1 }; k += 2; continue }
                            if c == 34 || c == 39 || c == 96 { k += 1; while k < n, b[k] != c, b[k] != 10 { if b[k] == 92 { k += 1 }; k += 1 }; k += 1; continue }
                            if c == 123 || c == 40 || c == 91 { depth += 1 }
                            else if c == 125 || c == 41 || c == 93 {
                                depth -= 1
                                if depth <= 0, c == 125, closesWithBrace { end = k + 1; break }
                            } else if c == 59, depth <= 0 { end = k + 1; break }
                            k += 1
                        }
                        // the JSDoc block right above
                        var start = lineStart
                        var p = lineStart - 1
                        while p >= 0, b[p] == 10 || b[p] == 32 { p -= 1 }
                        if p >= 1, b[p] == 47, b[p - 1] == 42 {
                            var q = p - 2
                            while q >= 2, !(b[q] == 42 && b[q - 1] == 42 && b[q - 2] == 47) { q -= 1; if lineStart - q > 120_000 { q = -1; break } }
                            if q >= 2, !(q >= 3 && b[q - 3] != 10 && b[q - 3] != 32) { start = q - 2 }
                        }
                        if end > lineStart { table[name, default: []].append(NJSLibEntry(file: index, isValue: isValue, start: start, end: end)) }
                        i = max(end, lineStart + 1)
                        continue
                    }
                }
                // next line
                while i < n, b[i] != 10 { i += 1 }
                i += 1
            }
        }
    }

    // MARK: declarations

    /// Every declaration of `name` in the program's libs, parsed (and cached) one slice at a time.
    func declarations(_ name: String) -> [NJSRes] {
        guard let entries = byName[name] else { return [] }
        var out: [NJSRes] = []
        for e in entries {
            let f = files[e.file]
            let key = "\(e.file):\(e.start)"
            lock.lock(); var syms = parsed[key]; lock.unlock()
            if syms == nil {
                let text = f.string(bytes: e.start, e.end) as NSString
                let base = f.utf16(atByte: e.start)
                var made: [NJSSym] = []
                if let d = NJSDoc(path: f.path, text: text) {
                    made = d.summary.order.filter { $0.name == name }
                    for s in made { NJSLibIndex.shift(s, by: base) }
                    withExtendedLifetime(d) {}
                }
                lock.lock()
                if parsedCost > 1_500_000 { parsed.removeAll(); parsedCost = 0 }
                parsed[key] = made; parsedCost += made.reduce(0) { $0 + 300 + $1.members.count * 160 }
                lock.unlock()
                syms = made
            }
            for s in syms ?? [] { out.append(NJSRes(path: f.path, sym: s)) }
        }
        return out
    }

    static func shift(_ s: NJSSym, by d: Int) {
        guard d != 0 else { return }
        s.loc += d; s.declStart += d; s.sigEnd += d
        if s.docStart >= 0 { s.docStart += d; s.docEnd += d }
        func fix(_ ms: [NJSMember]) -> [NJSMember] {
            ms.map { m in
                var m = m
                m.loc += d; m.declStart += d; m.sigEnd += d
                if m.docStart >= 0 { m.docStart += d; m.docEnd += d }
                if let sub = m.sub { m.sub = fix(sub) }
                return m
            }
        }
        s.members = fix(s.members)
        s.returnMembers = fix(s.returnMembers)
        s.valueMembers = fix(s.valueMembers)
    }

    func file(forPath p: String) -> NJSLibFile? { files.first { $0.path == p } }
    func trim() { lock.lock(); parsed.removeAll(); parsedCost = 0; lock.unlock() }
}

enum NJSLib {
    private static let lock = NSLock()
    private static var indexes: [String: NJSLibIndex] = [:]          // dir + roots -> index
    private static var dirs: Set<String> = []
    private static var dirCache: [String: String] = [:]               // project root -> lib dir ("" none)

    static let bundledName = "TsLib"

    static func bundledDirectory() -> String? {
        let fm = FileManager.default
        func ok(_ u: URL) -> Bool { fm.fileExists(atPath: u.appendingPathComponent("lib.es5.d.ts").path) }
        if let env = ProcessInfo.processInfo.environment["CE_TS_LIB"], ok(URL(fileURLWithPath: env)) { return env }
        if let res = Bundle.main.resourceURL?.appendingPathComponent(bundledName), ok(res) { return res.path }
        var url = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<7 {
            guard let u = url else { break }
            let c = u.appendingPathComponent(bundledName)
            if ok(c) { return c.path }
            url = u.deletingLastPathComponent()
        }
        return nil
    }

    private static var platform: String {
        #if arch(arm64)
        return "typescript-darwin-arm64"
        #else
        return "typescript-darwin-x64"
        #endif
    }

    private static func globalModuleDirs() -> [String] {
        let nvm = NSHomeDirectory() + "/.nvm/versions/node"
        var dirs = ((try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? []).sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { nvm + "/" + $0 + "/lib/node_modules" }
        dirs += ["/opt/homebrew/lib/node_modules", "/usr/local/lib/node_modules", NSHomeDirectory() + "/.volta/tools/image/packages",
                 NSHomeDirectory() + "/Library/Application Support/CodeEditor/servers/node_modules"]
        return dirs
    }

    /// The lib directory the TypeScript server would use for a project at `root` (see the type comment).
    static var directoryOverride: String?              // tests: a fixed lib directory

    static func directory(forRoot root: String) -> String? {
        if let o = directoryOverride { return o }
        lock.lock(); if let c = dirCache[root] { lock.unlock(); return c.isEmpty ? nil : c }; lock.unlock()
        let fm = FileManager.default
        func ok(_ d: String) -> Bool { fm.fileExists(atPath: d + "/lib.es5.d.ts") }
        var ancestors: [String] = []
        var d = root
        while d != "/", !d.isEmpty, d != NSHomeDirectory() { ancestors.append(d + "/node_modules"); d = (d as NSString).deletingLastPathComponent }
        let globals = globalModuleDirs()
        var found: String?
        outer: for nm in ancestors + globals {                        // 1. native TypeScript 7 platform package
            for c in [nm + "/@typescript/" + platform + "/lib", nm + "/typescript/node_modules/@typescript/" + platform + "/lib"] where ok(c) { found = c; break outer }
        }
        if found == nil { for nm in ancestors + globals where ok(nm + "/typescript/lib") { found = nm + "/typescript/lib"; break } }
        if found == nil { found = bundledDirectory() }
        lock.lock(); dirCache[root] = found ?? ""; lock.unlock()
        return found
    }

    /// Root lib file names for a config (nil config = no tsconfig: the default target).
    static func rootNames(dir: String, config: NJSConfig?) -> [String] {
        if config?.noLib == true { return [] }
        let modern = FileManager.default.fileExists(atPath: dir + "/lib.es2025.d.ts")           // TypeScript 7 style lib set
        if let libs = config?.libs, !libs.isEmpty {
            return libs.map { l in
                let n = l.lowercased()
                return "lib." + (n.hasPrefix("lib.") ? String(n.dropFirst(4)) : n) + ".d.ts"
            }
        }
        let target = (config?.target ?? "").lowercased()
        switch target {
        case "": return [modern ? "lib.es2025.full.d.ts" : "lib.d.ts"]
        case "es3", "es5": return [modern ? "lib.es6.d.ts" : "lib.d.ts"]          // TypeScript 7 loads the ES2015 libraries for an ES5 target (observed)
        case "es6", "es2015": return ["lib.es6.d.ts"]
        case "esnext": return ["lib.esnext.full.d.ts"]
        default: return ["lib." + target + ".full.d.ts"]
        }
    }

    static func index(forRoot root: String, config: NJSConfig?) -> NJSLibIndex? {
        guard let dir = directory(forRoot: root) else { return nil }
        let roots = rootNames(dir: dir, config: config)
        let key = dir + "|" + roots.joined(separator: ",")
        lock.lock(); if let i = indexes[key] { lock.unlock(); return i }; lock.unlock()
        let idx = NJSLibIndex(dir: dir, roots: roots)
        lock.lock(); indexes[key] = idx; dirs.insert(dir); lock.unlock()
        return idx
    }

    /// A standard lib file: memory mapped and indexed rather than parsed as a whole (@types files are ordinary, smaller files).
    static func isLibPath(_ p: String) -> Bool {
        guard !p.contains("#"), p.hasSuffix(".d.ts"), (p as NSString).lastPathComponent.hasPrefix("lib.") else { return false }
        lock.lock(); defer { lock.unlock() }
        return dirs.contains((p as NSString).deletingLastPathComponent)
    }

    static func file(forPath p: String) -> NJSLibFile? {
        let r = NJSTypes.realPath(p)
        lock.lock(); let all = Array(indexes.values); lock.unlock()
        for i in all { if let f = i.file(forPath: r) { return f } }
        return NJSTypes.file(forPath: r)
    }

    static func trim() {
        lock.lock(); let all = Array(indexes.values); indexes.removeAll(); dirCache.removeAll(); lock.unlock()
        for i in all { i.trim() }
        NJSTypes.trim()
    }

    static var indexCount: Int { lock.lock(); defer { lock.unlock() }; return indexes.count }
}

extension NJSEnv {
    /// Global declarations of `name` from the program's libs (merged interfaces give one result per declaration).
    func libTop(_ name: String) -> [NJSRes] {
        guard NativeJS.libsEnabled else { return [] }
        var out = NJSLib.index(forRoot: proj.root, config: proj.modules.config(for: path))?.declarations(name) ?? []
        out += typesIndex()?.declarations(name) ?? []                         // globals of the @types packages (process, Buffer, require, ...)
        return out
    }
}
