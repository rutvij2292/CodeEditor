import Foundation

/// Builds the vendor class table from Composer metadata (classmap + PSR-4 directory walk). Files are never
/// parsed unless a package is not described by any metadata; then tree-sitter extracts type declarations only.
enum VendorBuilder {
    struct Source { let dir: String; let vendorDir: String }
    struct Pkg { var name: String; var version: String; var root: String; var sig: UInt64 }

    // MARK: discovery

    private static let skipDirs: Set<String> = ["node_modules", "vendor", ".git", "storage", ".build", "dist", "public", "bootstrap", "build"]

    static func isDir(_ path: String) -> Bool {
        var st = stat(); return stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }
    static func exists(_ path: String) -> Bool { access(path, F_OK) == 0 }

    static func mtimeSize(_ path: String) -> (Int, Int) {
        var st = stat()
        guard stat(path, &st) == 0 else { return (0, 0) }
        return (Int(st.st_mtimespec.tv_sec) &* 1_000_000_007 &+ Int(st.st_mtimespec.tv_nsec), Int(st.st_size))
    }

    /// Project root plus up to two levels of sub-projects (monorepo) that have a Composer vendor directory.
    static func discoverSources(root: String) -> [Source] {
        var out: [Source] = []
        func consider(_ dir: String) {
            let v = dir + "/vendor"
            if isDir(v + "/composer") { out.append(Source(dir: dir, vendorDir: v)) }
        }
        consider(root)
        func descend(_ dir: String, depth: Int) {
            guard depth > 0, out.count < 12, let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
            for n in names.sorted() where !n.hasPrefix(".") && !skipDirs.contains(n) {
                let p = dir + "/" + n
                guard isDir(p) else { continue }
                if exists(p + "/composer.json") { consider(p) }
                descend(p, depth: depth - 1)
            }
        }
        descend(root, depth: 2)
        return out
    }

    /// Cheap fingerprint: composer.lock content hash + installed.json / classmap mtimes + format version.
    static func currentKey(_ sources: [Source]) -> UInt64 {
        var h = VendorFormat.fnv("v\(VendorFormat.version)")
        for s in sources {
            h = VendorFormat.fnv(s.dir, seed: h)
            if let d = try? Data(contentsOf: URL(fileURLWithPath: s.dir + "/composer.lock"), options: .alwaysMapped) {
                h = d.withUnsafeBytes { VendorFormat.fnv($0, seed: h) }
            }
            for f in ["/composer/installed.json", "/composer/autoload_classmap.php", "/composer/autoload_psr4.php"] {
                let (m, sz) = mtimeSize(s.vendorDir + f)
                h = VendorFormat.fnv("\(m):\(sz)", seed: h)
            }
        }
        return h
    }

    // MARK: path helpers

    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for c in path.split(separator: "/", omittingEmptySubsequences: true) {
            if c == "." { continue }
            if c == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(c)
        }
        return "/" + parts.joined(separator: "/")
    }

    // MARK: PHP array file parsing (autoload_classmap.php / autoload_psr4.php)

    struct MapLine { let key: String; let paths: [String] }

    /// Parses lines like `'A\\B' => $vendorDir . '/x/y.php',` and `'A\\' => array($vendorDir . '/a', $baseDir . '/b'),`.
    /// Works on bytes (CRLF safe) and normalises Windows separators in paths.
    static func parseMap(_ bytes: [UInt8], vendorDir: String, baseDir: String) -> [MapLine] {
        var out: [MapLine] = []
        var i = 0
        let n = bytes.count
        func readQuoted(_ start: Int) -> (String, Int)? {
            let q = bytes[start]
            var j = start + 1
            var buf = [UInt8]()
            while j < n {
                let c = bytes[j]
                if c == 92, j + 1 < n, bytes[j + 1] == 92 || bytes[j + 1] == q { buf.append(bytes[j + 1]); j += 2; continue }
                if c == q { return (String(decoding: buf, as: UTF8.self), j + 1) }
                if c == 10 { return nil }
                buf.append(c); j += 1
            }
            return nil
        }
        while i < n {
            var lineEnd = i
            while lineEnd < n, bytes[lineEnd] != 10 { lineEnd += 1 }
            var p = i
            while p < lineEnd, bytes[p] == 32 || bytes[p] == 9 { p += 1 }
            if p < lineEnd, bytes[p] == 39 || bytes[p] == 34, let (key, after) = readQuoted(p) {
                var k = after
                while k + 1 < lineEnd, !(bytes[k] == 61 && bytes[k + 1] == 62) { k += 1 }
                k += 2
                var paths: [String] = []
                var base: String? = nil
                var sawBase = false
                while k < lineEnd {
                    let c = bytes[k]
                    if c == 36 { // $vendorDir / $baseDir
                        var e = k + 1
                        while e < lineEnd, bytes[e] == 95 || (bytes[e] >= 65 && bytes[e] <= 90) || (bytes[e] >= 97 && bytes[e] <= 122) { e += 1 }
                        let name = String(decoding: bytes[(k + 1)..<e], as: UTF8.self)
                        base = name == "vendorDir" ? vendorDir : (name == "baseDir" ? baseDir : nil)
                        sawBase = true
                        k = e
                    } else if c == 39 || c == 34, let (s, e) = readQuoted(k) {
                        var path = s.replacingOccurrences(of: "\\", with: "/")
                        if sawBase, let b = base { path = b + (path.hasPrefix("/") || path.isEmpty ? "" : "/") + path; paths.append(normalize(path)) }
                        else if !sawBase, path.hasPrefix("/") || path.dropFirst().hasPrefix(":/") { paths.append(path) }
                        base = nil; sawBase = false
                        k = e
                    } else { k += 1 }
                }
                if !paths.isEmpty { out.append(MapLine(key: key, paths: paths)) }
            }
            i = lineEnd + 1
        }
        return out
    }

    // MARK: installed.json

    static func readPackages(_ s: Source) -> [Pkg] {
        var out: [Pkg] = []
        if let data = try? Data(contentsOf: URL(fileURLWithPath: s.vendorDir + "/composer/installed.json")),
           let json = try? JSONSerialization.jsonObject(with: data) {
            let list = (json as? [String: Any])?["packages"] as? [[String: Any]] ?? (json as? [[String: Any]]) ?? []
            for p in list {
                guard let name = p["name"] as? String else { continue }
                let version = p["version"] as? String ?? ""
                let root: String
                if let ip = p["install-path"] as? String { root = normalize(ip.hasPrefix("/") ? ip : s.vendorDir + "/composer/" + ip) }
                else { root = s.vendorDir + "/" + name }
                var ref = ""
                for k in ["dist", "source"] { if let r = (p[k] as? [String: Any])?["reference"] as? String { ref = r; break } }
                let sig = VendorFormat.fnv("\(name)|\(version)|\(ref)|\(root)|\(mtimeSize(root).0)")
                out.append(Pkg(name: name, version: version, root: root, sig: sig))
            }
        }
        if out.isEmpty, let vendors = try? FileManager.default.contentsOfDirectory(atPath: s.vendorDir) {
            for v in vendors.sorted() where !v.hasPrefix(".") && v != "composer" && v != "bin" {
                let vp = s.vendorDir + "/" + v
                guard isDir(vp), let subs = try? FileManager.default.contentsOfDirectory(atPath: vp) else { continue }
                for sub in subs.sorted() where !sub.hasPrefix(".") && isDir(vp + "/" + sub) {
                    let root = vp + "/" + sub
                    out.append(Pkg(name: "\(v)/\(sub)", version: "", root: root,
                                   sig: VendorFormat.fnv("\(v)/\(sub)||\(mtimeSize(root).0)")))
                }
            }
        }
        return out
    }

    // MARK: directory walking

    /// Recursive readdir; follows symlinked directories (path repositories) once, guarding cycles.
    static func walkPHP(_ dir: String, skip: (String) -> Bool, limit: Int = .max, _ visit: (_ rel: String) -> Void) {
        var seen = Set<UInt64>()
        var st = stat()
        if stat(dir, &st) == 0 { seen.insert(UInt64(st.st_dev) << 40 ^ UInt64(st.st_ino)) }
        var count = 0
        func go(_ abs: String, _ rel: String, _ depth: Int) {
            guard depth < 24, let d = opendir(abs) else { return }
            defer { closedir(d) }
            var subdirs: [(String, String)] = []
            while let e = readdir(d) {
                let name = withUnsafePointer(to: &e.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
                if name.hasPrefix(".") { continue }
                var type = e.pointee.d_type
                if type == UInt8(DT_LNK) || type == UInt8(DT_UNKNOWN) {
                    var s2 = stat()
                    guard stat(abs + "/" + name, &s2) == 0 else { continue }
                    type = (s2.st_mode & S_IFMT) == S_IFDIR ? UInt8(DT_DIR) : UInt8(DT_REG)
                    if type == UInt8(DT_DIR) {
                        let id = UInt64(s2.st_dev) << 40 ^ UInt64(s2.st_ino)
                        if !seen.insert(id).inserted { continue }
                    }
                }
                if type == UInt8(DT_DIR) { if !skip(name) { subdirs.append((abs + "/" + name, rel.isEmpty ? name : rel + "/" + name)) } }
                else if type == UInt8(DT_REG), name.hasSuffix(".php") {
                    count += 1
                    if count > limit { return }
                    visit(rel.isEmpty ? name : rel + "/" + name)
                }
            }
            for (a, r) in subdirs { go(a, r, depth + 1); if count > limit { return } }
        }
        go(dir, "", 0)
    }

    /// Lazy file listing for Go to File (all files, any extension, relative to `dir`).
    static func walkAll(_ dir: String, skip: (String) -> Bool, limit: Int = .max, _ visit: (_ rel: String) -> Void) {
        var seen = Set<UInt64>()
        var count = 0
        func go(_ abs: String, _ rel: String, _ depth: Int) {
            guard depth < 24, count <= limit, let d = opendir(abs) else { return }
            defer { closedir(d) }
            while let e = readdir(d) {
                let name = withUnsafePointer(to: &e.pointee.d_name) { $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) } }
                if name.hasPrefix(".") { continue }
                var type = e.pointee.d_type
                if type == UInt8(DT_LNK) || type == UInt8(DT_UNKNOWN) {
                    var s2 = stat()
                    guard stat(abs + "/" + name, &s2) == 0 else { continue }
                    type = (s2.st_mode & S_IFMT) == S_IFDIR ? UInt8(DT_DIR) : UInt8(DT_REG)
                    if type == UInt8(DT_DIR), !seen.insert(UInt64(s2.st_dev) << 40 ^ UInt64(s2.st_ino)).inserted { continue }
                }
                let r = rel.isEmpty ? name : rel + "/" + name
                if type == UInt8(DT_DIR) { if !skip(name) { go(abs + "/" + name, r, depth + 1) } }
                else if type == UInt8(DT_REG) { count += 1; visit(r) }
            }
        }
        go(dir, "", 0)
    }

    // MARK: build

    private static let fallbackSkip: Set<String> = ["tests", "test", "docs", "doc", "examples", "example", "vendor",
                                                    "node_modules", "fixtures", "stubs", "bin", "benchmarks"]

    /// `old` supplies entries for packages whose signature is unchanged (incremental rebuild).
    static func build(root: String, sources: [Source], old: VendorTable?) -> (key: UInt64, packages: [VendorFormat.RawPackage]) {
        SymbolExtractor.prime()
        var oldByKey: [String: (sig: UInt64, index: Int)] = [:]
        var oldEntries: [Int: [VendorFormat.RawEntry]] = [:]
        if let old {
            for i in 0..<old.packageCount { let p = old.package(i); oldByKey[p.name + "\n" + p.root] = (p.sig, i) }
            for i in 0..<old.count { if let r = old.row(i) { oldEntries[r.pkg, default: []].append(.init(fqn: r.fqn, rel: r.rel, kind: r.kind, flags: r.flags)) } }
        }
        var result: [VendorFormat.RawPackage] = []
        for source in sources {
            let baseDir = (source.vendorDir as NSString).deletingLastPathComponent
            let pkgs = readPackages(source)
            var entries = [[VendorFormat.RawEntry]](repeating: [], count: pkgs.count)
            var fresh = [Bool](repeating: true, count: pkgs.count)
            for (i, p) in pkgs.enumerated() {
                if let o = oldByKey[p.name + "\n" + p.root], o.sig == p.sig, o.sig != 0 {
                    fresh[i] = false
                    entries[i] = oldEntries[o.index] ?? []
                }
            }
            var byRoot: [String: Int] = [:]
            for (i, p) in pkgs.enumerated() { byRoot[p.root] = i }
            func package(forPath path: String) -> Int? {
                if path.hasPrefix(source.vendorDir + "/") {
                    let rest = path.dropFirst(source.vendorDir.count + 1).split(separator: "/", maxSplits: 2)
                    if rest.count >= 2, let i = byRoot[source.vendorDir + "/" + rest[0] + "/" + rest[1]] { return i }
                }
                var best: Int? = nil
                for (i, p) in pkgs.enumerated() where path == p.root || path.hasPrefix(p.root + "/") {
                    if best == nil || p.root.count > pkgs[best!].root.count { best = i }
                }
                return best
            }
            func rel(_ path: String, _ pi: Int) -> String { path.count > pkgs[pi].root.count ? String(path.dropFirst(pkgs[pi].root.count + 1)) : "" }

            // 1. exact classmap
            var covered = Set<Int>()
            if let d = try? Data(contentsOf: URL(fileURLWithPath: source.vendorDir + "/composer/autoload_classmap.php")) {
                for line in parseMap([UInt8](d), vendorDir: source.vendorDir, baseDir: baseDir) {
                    guard let path = line.paths.first, let pi = package(forPath: path), path.hasSuffix(".php") || path.hasSuffix(".inc") else { continue }
                    covered.insert(pi)
                    if fresh[pi] { entries[pi].append(.init(fqn: line.key, rel: rel(path, pi), kind: 0, flags: 0)) }
                }
            }
            // 2. PSR-4: class names come from the directory layout, no file is opened
            struct Task { let prefix: String; let dir: String; let pi: Int }
            var tasks: [Task] = []
            if let d = try? Data(contentsOf: URL(fileURLWithPath: source.vendorDir + "/composer/autoload_psr4.php")) {
                for line in parseMap([UInt8](d), vendorDir: source.vendorDir, baseDir: baseDir) {
                    for dir in line.paths {
                        guard let pi = package(forPath: dir) else { continue }
                        covered.insert(pi)
                        if fresh[pi] { tasks.append(Task(prefix: line.key, dir: dir, pi: pi)) }
                    }
                }
            }
            var taskOut = [[VendorFormat.RawEntry]](repeating: [], count: tasks.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: tasks.count) { ti in
                let t = tasks[ti]
                var prefix = t.prefix
                if !prefix.isEmpty, !prefix.hasSuffix("\\") { prefix += "\\" }
                var local: [VendorFormat.RawEntry] = []
                walkPHP(t.dir, skip: { _ in false }) { relFile in
                    let comps = relFile.split(separator: "/")
                    guard let last = comps.last else { return }
                    let base = last.dropLast(4)
                    guard let f = base.utf8.first, !(f >= 97 && f <= 122), !base.contains(".") else { return }
                    let fqn = prefix + comps.dropLast().joined(separator: "\\") + (comps.count > 1 ? "\\" : "") + base
                    let full = t.dir + "/" + relFile
                    local.append(.init(fqn: fqn, rel: rel(full, t.pi), kind: 0, flags: 0))
                }
                lock.lock(); taskOut[ti] = local; lock.unlock()
            }
            for (ti, t) in tasks.enumerated() { entries[t.pi].append(contentsOf: taskOut[ti]) }

            // 3. packages that no metadata covers: tree-sitter, types only
            let uncovered = pkgs.indices.filter { fresh[$0] && !covered.contains($0) && entries[$0].isEmpty }
            var fbOut = [[VendorFormat.RawEntry]](repeating: [], count: uncovered.count)
            DispatchQueue.concurrentPerform(iterations: uncovered.count) { ui in
                let pi = uncovered[ui]
                var local: [VendorFormat.RawEntry] = []
                walkPHP(pkgs[pi].root, skip: { fallbackSkip.contains($0.lowercased()) }, limit: 3000) { relFile in
                    let path = pkgs[pi].root + "/" + relFile
                    guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)), d.count <= SymbolIndex.maxFileSize else { return }
                    autoreleasepool {
                        guard let text = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) else { return }
                        for s in SymbolExtractor.symbols(in: text, fileExtension: "php", typesOnly: true) where s.isType {
                            let kind: UInt8 = s.kind == .interface ? 2 : s.kind == .trait ? 3 : s.kind == .enum ? 4 : 1
                            let fqn = (s.container.map { $0 + "\\" } ?? "") + s.name
                            local.append(.init(fqn: fqn, rel: relFile, kind: kind, flags: 0))
                        }
                    }
                }
                lock.lock(); fbOut[ui] = local; lock.unlock()
            }
            for (ui, pi) in uncovered.enumerated() { entries[pi] = fbOut[ui] }

            for (i, p) in pkgs.enumerated() {
                var seen = Set<String>()
                let unique = entries[i].filter { seen.insert($0.fqn.lowercased() + "|" + $0.rel).inserted }
                result.append(.init(name: p.name, version: p.version, root: relativeToProject(p.root, root), sig: p.sig, entries: unique))
            }
        }
        result.sort { ($0.name, $0.root) < ($1.name, $1.root) }
        return (currentKey(sources), result)
    }

    /// Package roots inside the project are stored relative to it (so tabs/pickers get project-relative paths).
    static func relativeToProject(_ path: String, _ root: String) -> String {
        path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }
}
