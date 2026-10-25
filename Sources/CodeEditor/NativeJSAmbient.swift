import Foundation
import SwiftTreeSitter

/// Ambient declarations of the program: the packages of `node_modules/@types` (all of them, or the `types` of the tsconfig), found the way
/// tsc finds them (every ancestor `node_modules/@types`, entry file plus `/// <reference path|types>` closure). Like the libs they are
/// memory mapped and indexed by a byte scan: `declare module "x" { }` blocks (ambient modules), `declare global { }` blocks and the
/// top-level `declare` / `interface` / `type` declarations of script files. A lookup parses the one declaration (or module body) it
/// needs. Ambient modules appear to the resolver as pseudo files `<real path>#<module name>` so that imports, `export =`, namespaces and
/// type references inside them work with the same code as for real files.
struct NJSAmbientEntry {
    var file: Int
    var start: Int                       // byte offset (doc comment included)
    var end: Int
    var bodyStart: Int = -1              // module / global blocks: first byte after `{`
    var bodyEnd: Int = -1                // the matching `}`
}

final class NJSTypesIndex {
    let roots: [String]
    private(set) var files: [NJSLibFile] = []
    private(set) var globals: [String: [NJSAmbientEntry]] = [:]
    private(set) var modules: [String: [NJSAmbientEntry]] = [:]
    private let lock = NSLock()
    private var parsed: [String: [NJSSym]] = [:]
    private var moduleSummaries: [String: NJSSummary] = [:]
    private var cost = 0

    init(typeRoots: [String], only: [String]?) {
        roots = typeRoots
        var seen = Set<String>()
        var queue: [String] = []
        func enqueue(_ p: String) { if seen.insert(p).inserted { queue.append(p) } }
        let fm = FileManager.default
        for tr in typeRoots {
            for pkg in ((try? fm.contentsOfDirectory(atPath: tr)) ?? []).sorted() where !pkg.hasPrefix(".") {
                if let only, !only.contains(pkg) { continue }
                let dir = tr + "/" + pkg
                var entry = dir + "/index.d.ts"
                if let d = try? Data(contentsOf: URL(fileURLWithPath: dir + "/package.json")), case .o(let pairs)? = NJSOJ.parse(d) {
                    for k in ["types", "typings"] { if case .s(let t)? = pairs.first(where: { $0.0 == k })?.1 { entry = NJSModules.join(dir, t); break } }
                }
                if fm.fileExists(atPath: entry) { enqueue(entry) }
            }
        }
        var i = 0
        while i < queue.count, files.count < 400 {
            let p = queue[i]; i += 1
            guard let f = NJSLibFile(path: p), f.data.count < 4_000_000 else { continue }
            let idx = files.count
            files.append(f)
            for ref in NJSTypesIndex.references(f) {
                let dir = (p as NSString).deletingLastPathComponent
                if ref.isPath { enqueue(NJSModules.join(dir, ref.value)) }
                else {
                    for tr in typeRoots { for c in [tr + "/" + ref.value + "/index.d.ts"] where fm.fileExists(atPath: c) { enqueue(c) } }
                }
            }
            NJSTypesIndex.scan(f, index: idx, globals: &globals, modules: &modules)
        }
    }

    static func references(_ f: NJSLibFile) -> [(isPath: Bool, value: String)] {
        let head = f.string(bytes: 0, min(f.data.count, 6000))
        var out: [(Bool, String)] = []
        for line in head.split(separator: "\n") {
            if line.hasPrefix("/// <reference path=\""), let q = line.dropFirst(21).firstIndex(of: "\"") { out.append((true, String(line.dropFirst(21)[..<q]))) }
            else if line.hasPrefix("/// <reference types=\""), let q = line.dropFirst(22).firstIndex(of: "\"") { out.append((false, String(line.dropFirst(22)[..<q]))) }
        }
        return out
    }

    /// End of the declaration starting at `from`: the matching `}` for blocks, `;` otherwise.
    static func declarationEnd(_ b: UnsafeBufferPointer<UInt8>, from j: Int, blocky: Bool) -> (end: Int, open: Int) {
        let n = b.count
        var depth = 0, k = j, open = -1
        while k < n {
            let c = b[k]
            if c == 47, k + 1 < n, b[k + 1] == 47 { while k < n, b[k] != 10 { k += 1 }; continue }
            if c == 47, k + 1 < n, b[k + 1] == 42 { k += 2; while k + 1 < n, !(b[k] == 42 && b[k + 1] == 47) { k += 1 }; k += 2; continue }
            if c == 34 || c == 39 || c == 96 { k += 1; while k < n, b[k] != c, b[k] != 10 { if b[k] == 92 { k += 1 }; k += 1 }; k += 1; continue }
            if c == 123 || c == 40 || c == 91 { if c == 123, open < 0 { open = k }; depth += 1 }
            else if c == 125 || c == 41 || c == 93 {
                depth -= 1
                if depth <= 0, c == 125, blocky { return (k + 1, open) }
            } else if c == 59, depth <= 0 { return (k + 1, open) }
            k += 1
        }
        return (n, open)
    }

    static func docStart(_ b: UnsafeBufferPointer<UInt8>, lineStart: Int) -> Int {
        var p = lineStart - 1
        while p >= 0, b[p] == 10 || b[p] == 32 { p -= 1 }
        if p >= 1, b[p] == 47, b[p - 1] == 42 {
            var q = p - 2
            while q >= 2, !(b[q] == 42 && b[q - 1] == 42 && b[q - 2] == 47) { q -= 1; if lineStart - q > 120_000 { return lineStart } }
            if q >= 2 { return q - 2 }
        }
        return lineStart
    }

    static func scan(_ f: NJSLibFile, index: Int, globals: inout [String: [NJSAmbientEntry]], modules: inout [String: [NJSAmbientEntry]]) {
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
            func ident(_ j: inout Int) -> String? {
                let st = j
                while j < n, isIdent(b[j]) { j += 1 }
                return j > st ? String(decoding: UnsafeBufferPointer(rebasing: b[st..<j]), as: UTF8.self) : nil
            }
            // does the file have col-0 `import` / `export` (an ES module): then its declarations are not global
            var isModule = false
            var li = 0
            while li < n { if has(li, "import ") || has(li, "export ") { isModule = true; break }; while li < n, b[li] != 10 { li += 1 }; li += 1 }
            // declaration keywords after optional `declare `: kind
            func declKeyword(_ at: Int) -> (len: Int, blocky: Bool)? {
                var j = at
                var declared = false
                if has(j, "declare ") { j += 8; declared = true }
                if has(j, "var ") { return (j + 4 - at, false) }
                if has(j, "let ") { return (j + 4 - at, false) }
                if has(j, "const ") { return (j + 6 - at, false) }
                if has(j, "function ") { return (j + 9 - at, false) }
                if has(j, "abstract class ") { return (j + 15 - at, true) }
                if has(j, "class ") { return (j + 6 - at, true) }
                if has(j, "namespace ") { return (j + 10 - at, true) }
                if has(j, "enum ") { return (j + 5 - at, true) }
                if !declared || true, has(j, "interface ") { return (j + 10 - at, true) }
                if has(j, "type ") { return (j + 5 - at, false) }
                return nil
            }
            var i = 0
            while i < n {
                let lineStart = i
                if has(i, "declare module ") {
                    var j = i + 15
                    if j < n, b[j] == 34 || b[j] == 39 {
                        let q = b[j]; let st = j + 1; j += 1
                        while j < n, b[j] != q, b[j] != 10 { j += 1 }
                        let name = String(decoding: UnsafeBufferPointer(rebasing: b[st..<j]), as: UTF8.self)
                        let (end, open) = declarationEnd(b, from: j + 1, blocky: true)          // after the closing quote
                        if open >= 0, !name.contains("*") {
                            modules[name, default: []].append(NJSAmbientEntry(file: index, start: lineStart, end: end, bodyStart: open + 1, bodyEnd: max(open + 1, end - 1)))
                        }
                        i = max(end, lineStart + 1); continue
                    }
                } else if has(i, "declare global") {
                    let (end, open) = declarationEnd(b, from: i + 14, blocky: true)
                    if open >= 0 {
                        // names declared directly inside the block (one indentation level)
                        var k = open + 1
                        var depth = 0
                        while k < end - 1 {
                            let ls = k
                            while k < end - 1, b[k] != 10 { k += 1 }
                            k += 1
                            // only lines at the block's top level (indented by 2 or 4 spaces)
                            var ind = 0
                            while ls + ind < end, b[ls + ind] == 32 { ind += 1 }
                            if depth == 0, ind >= 2, ind <= 4, let kw = declKeyword(ls + ind) {
                                var j = ls + ind + kw.len
                                if let name = ident(&j) {
                                    let (e2, _) = declarationEnd(b, from: j, blocky: kw.blocky)
                                    globals[name, default: []].append(NJSAmbientEntry(file: index, start: docStart(b, lineStart: ls), end: e2))
                                    k = max(k, e2); continue
                                }
                            }
                        }
                        i = max(end, lineStart + 1); continue
                    }
                } else if !isModule, let kw = declKeyword(i) {
                    var j = i + kw.len
                    if let name = ident(&j) {
                        let (end, _) = declarationEnd(b, from: j, blocky: kw.blocky)
                        globals[name, default: []].append(NJSAmbientEntry(file: index, start: docStart(b, lineStart: lineStart), end: end))
                        i = max(end, lineStart + 1); continue
                    }
                }
                while i < n, b[i] != 10 { i += 1 }
                i += 1
            }
        }
    }

    // MARK: lookups

    private func parse(file f: NJSLibFile, start: Int, end: Int, key: String, filter: String?) -> [NJSSym] {
        lock.lock(); let c = parsed[key]; lock.unlock()
        if let c { return c }
        let text = f.string(bytes: start, end) as NSString
        let base = f.utf16(atByte: start)
        var made: [NJSSym] = []
        if let d = NJSDoc(path: f.path, text: text) {
            made = filter.map { n in d.summary.order.filter { $0.name == n } } ?? d.summary.order
            for s in made { NJSLibIndex.shift(s, by: base) }
            withExtendedLifetime(d) {}
        }
        lock.lock()
        if cost > 2_500_000 { parsed.removeAll(); moduleSummaries.removeAll(); cost = 0 }
        parsed[key] = made; cost += made.reduce(0) { $0 + 300 + $1.members.count * 160 }
        lock.unlock()
        return made
    }

    func declarations(_ name: String) -> [NJSRes] {
        guard let entries = globals[name] else { return [] }
        var out: [NJSRes] = []
        for e in entries {
            let f = files[e.file]
            for s in parse(file: f, start: e.start, end: e.end, key: "g\(e.file):\(e.start):\(name)", filter: name) { out.append(NJSRes(path: f.path, sym: s)) }
        }
        return out
    }

    func hasModule(_ spec: String) -> Bool { modules[spec] != nil }

    /// The merged summary of every `declare module "spec"` body (augmentations of the same name merge), offsets in the real files.
    func moduleSummary(_ spec: String) -> NJSSummary? {
        lock.lock(); if let s = moduleSummaries[spec] { lock.unlock(); return s }; lock.unlock()
        guard let entries = modules[spec] else { return nil }
        let merged = NJSSummary()
        merged.isModule = true
        for e in entries {
            let f = files[e.file]
            let text = f.string(bytes: e.bodyStart, e.bodyEnd) as NSString
            let base = f.utf16(atByte: e.bodyStart)
            guard let d = NJSDoc(path: f.path, text: text) else { continue }
            let s = d.summary
            for sym in s.order { NJSLibIndex.shift(sym, by: base); merged.add(sym) }
            for (k, v) in s.exports {
                var ex = v
                if case .anon(let l, let n, let ds, let se, let dc, let de) = v { ex = .anon(loc: l + base, len: n, declStart: ds + base, sigEnd: se + base, docStart: dc >= 0 ? dc + base : -1, docEnd: de >= 0 ? de + base : -1) }
                merged.exports[k] = ex
            }
            merged.stars += s.stars
            if let eq = s.exportEquals { merged.exportEquals = eq }
            withExtendedLifetime(d) {}
        }
        lock.lock(); moduleSummaries[spec] = merged; cost += 400 + merged.cost; lock.unlock()
        return merged
    }

    func file(forPath p: String) -> NJSLibFile? { files.first { $0.path == p } }
    func trim() { lock.lock(); parsed.removeAll(); moduleSummaries.removeAll(); cost = 0; lock.unlock() }
}

enum NJSTypes {
    private static let lock = NSLock()
    private static var indexes: [String: NJSTypesIndex] = [:]
    private static var paths: Set<String> = []

    /// `node_modules/@types` of the project and every ancestor (what tsc's default `typeRoots` are).
    static func typeRoots(forRoot root: String) -> [String] {
        var out: [String] = []
        var d = root
        while d != "/", !d.isEmpty, d != NSHomeDirectory() {
            let t = d + "/node_modules/@types"
            if FileManager.default.fileExists(atPath: t) { out.append(t) }
            d = (d as NSString).deletingLastPathComponent
        }
        return out
    }

    static func index(forRoot root: String, config: NJSConfig?) -> NJSTypesIndex? {
        let roots = typeRoots(forRoot: root)
        guard !roots.isEmpty else { return nil }
        let key = roots.joined(separator: ",") + "|" + (config?.types?.joined(separator: ",") ?? "*")
        lock.lock(); if let i = indexes[key] { lock.unlock(); return i }; lock.unlock()
        let idx = NJSTypesIndex(typeRoots: roots, only: config?.types)
        lock.lock(); indexes[key] = idx; for f in idx.files { paths.insert(f.path) }; lock.unlock()
        return idx
    }

    static func isTypesPath(_ p: String) -> Bool { lock.lock(); defer { lock.unlock() }; return paths.contains(realPath(p)) }
    static func file(forPath p: String) -> NJSLibFile? {
        lock.lock(); let all = Array(indexes.values); lock.unlock()
        let r = realPath(p)
        for i in all { if let f = i.file(forPath: r) { return f } }
        return nil
    }
    static func realPath(_ p: String) -> String { p.firstIndex(of: "#").map { String(p[..<$0]) } ?? p }
    static func trim() { lock.lock(); let all = Array(indexes.values); indexes.removeAll(); paths.removeAll(); lock.unlock(); for i in all { i.trim() } }
}

extension NJSEnv {
    func typesIndex() -> NJSTypesIndex? {
        guard NativeJS.libsEnabled else { return nil }
        return NJSTypes.index(forRoot: proj.root, config: proj.modules.config(for: path))
    }

    /// Pseudo path of the ambient module `spec` (`declare module "spec"` in the @types packages), nil when there is none.
    func ambientModule(_ spec: String) -> String? {
        guard let idx = typesIndex(), idx.hasModule(spec), let first = idx.modules[spec]?.first else { return nil }
        return idx.files[first.file].path + "#" + spec
    }

    func ambientSummary(_ pseudo: String) -> NJSSummary? {
        guard let h = pseudo.firstIndex(of: "#"), let idx = typesIndex() else { return nil }
        return idx.moduleSummary(String(pseudo[pseudo.index(after: h)...]))
    }
}
