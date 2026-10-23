import AppKit

// Native PHP rename (phase 2b): plans a rename on top of NPRefs (every editable usage + declaration, member families through
// the class hierarchy), validates the new name and conflicts, and applies it as one edit set: open tabs through their text view
// (one undo group each), closed files atomically after a disk-state re-check, then the PSR-4 file rename for classes.

struct NPRenamePlan {
    var symbol: NPRefSymbol
    var newName: String
    var hits: [NPRefHit] = []                 // editable occurrences to change (declarations included)
    var skipped: [NPRefHit] = []              // unresolved member usages: not changed
    var warnings: [String] = []
    var conflict: String?                     // set => the rename must be refused
    var fileRename: (from: String, to: String)?
    var truncated = false

    var fileCount: Int { Set(hits.map(\.path)).count }
    var editCount: Int { hits.count }
}

struct NPRenameOptions {
    var includeDocblocks = true
    var includeStrings = true
    var renameFile = true
}

enum NPRename {
    private static let reservedClass: Set<String> = [
        "abstract", "and", "array", "as", "break", "callable", "case", "catch", "class", "clone", "const", "continue", "declare", "default", "do", "echo",
        "else", "elseif", "enddeclare", "endfor", "endforeach", "endif", "endswitch", "endwhile", "enum", "extends", "final", "finally", "fn", "for",
        "foreach", "function", "global", "goto", "if", "implements", "include", "include_once", "instanceof", "insteadof", "interface", "isset", "list",
        "match", "namespace", "new", "or", "print", "private", "protected", "public", "readonly", "require", "require_once", "return", "static", "switch",
        "throw", "trait", "try", "unset", "use", "var", "while", "xor", "yield", "true", "false", "null", "int", "float", "string", "bool", "mixed",
        "void", "iterable", "object", "never", "self", "parent", "array",
    ]

    /// Returns an error message, or nil when `name` is a legal new name for the symbol.
    static func validate(_ sym: NPRefSymbol, name raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespaces)
        if sym.kind == .variable || sym.kind == .property, name.hasPrefix("$") { name.removeFirst() }
        guard !name.isEmpty else { return "The new name is empty." }
        guard let f = name.unicodeScalars.first, f == "_" || CharacterSet.letters.contains(f) || f.value >= 0x80,
              name.unicodeScalars.allSatisfy({ $0 == "_" || CharacterSet.alphanumerics.contains($0) || $0.value >= 0x80 })
        else { return "\"\(name)\" is not a valid PHP identifier." }
        if sym.kind == .classLike || sym.kind == .function, reservedClass.contains(name.lowercased()) { return "\"\(name)\" is a reserved word." }
        if sym.kind == .variable, name == "this" { return "$this cannot be used as a variable name." }
        if sym.virtual == "accessor" { return "Eloquent accessors map to attribute names; rename the attribute usages by hand." }
        if sym.virtual == "scope", !(name.hasPrefix("scope") && name.count > 5) { return "A local scope method name must start with \"scope\" (for example scopeActive)." }
        let old = sym.kind == .variable ? String(sym.name.dropFirst()) : sym.name
        if name == old { return "The new name is the same as the old one." }
        return nil
    }

    static func normalizedName(_ sym: NPRefSymbol, _ raw: String) -> String {
        var n = raw.trimmingCharacters(in: .whitespaces)
        if (sym.kind == .variable || sym.kind == .property), n.hasPrefix("$") { n.removeFirst() }
        return n
    }

    // MARK: Planning

    /// Blocking: scans the project (run off the main thread in the app).
    static func plan(_ sym: NPRefSymbol, newName raw: String, options: NPRenameOptions = NPRenameOptions(), liveTexts liveIn: [String: NSString] = [:],
                     cancel: CancelToken? = nil, onProgress: ((Int, Int) -> Void)? = nil) -> NPRenamePlan {
        var liveTexts: [String: NSString] = [:]
        for (k, v) in liveIn { liveTexts[NPRefs.canon(k)] = v }
        let newName = normalizedName(sym, raw)
        var plan = NPRenamePlan(symbol: sym, newName: newName)
        if let err = validate(sym, name: raw) { plan.conflict = err; return plan }
        let fp = FastProject.shared(root: URL(fileURLWithPath: sym.root))
        let rel = NPRelations(fp: fp)
        var opts = NPRefsOptions()
        opts.includeVendor = sym.inVendor
        opts.cap = 20_000
        opts.scan.includeDocblocks = options.includeDocblocks
        opts.scan.includeStrings = options.includeStrings
        if sym.kind == .classLike { opts.scan.newName = newName }
        if sym.isMember { opts.scan.roots = fp.queue.sync { fp.beginRequest(); return familyRoots(sym, fp, rel) } }

        var result = NPRefs.collect(sym, options: opts, liveTexts: liveTexts, cancel: cancel) { _, d, t in onProgress?(d, t) }
        if result.cancelled { plan.conflict = "Cancelled."; return plan }

        // a promoted constructor property is also a local variable inside the constructor
        if let ctor = sym.ctorFnLoc {
            var v = NPRefSymbol(kind: .variable, name: "$" + sym.name, declPath: sym.declPath, declOffset: sym.declOffset, searchNames: [], url: sym.url, root: sym.root)
            v.scopeFn = ctor
            let extra = NPRefs.collect(v, options: opts, liveTexts: liveTexts, cancel: cancel)
            var seen = Set(result.hits.filter { $0.path == sym.declPath }.map { $0.range.location })
            for h in extra.hits where seen.insert(h.range.location).inserted { result.hits.append(h) }
        }
        plan.truncated = result.truncated
        if result.truncated { plan.conflict = "Too many occurrences to rename safely (over \(opts.cap))."; return plan }
        if let c = result.conflicts.first { plan.conflict = c; return plan }
        plan.hits = result.hits.filter { $0.editable && $0.role != .unresolved }
        plan.skipped = result.hits.filter { $0.role == .unresolved }
        guard plan.hits.contains(where: { $0.role == .declaration }) || sym.kind == .variable || sym.kind == .globalConstant else {
            plan.conflict = "The declaration of \(sym.name) was not found in the scanned files."
            return plan
        }
        if let c = conflict(for: sym, newName: newName, hits: plan.hits, fp: fp, rel: rel, liveTexts: liveTexts) { plan.conflict = c; return plan }

        if sym.inVendor { plan.warnings.append("\(sym.name) is declared in vendor/ (\((sym.declPath as NSString).lastPathComponent)). Renaming edits third-party code that composer will overwrite.") }
        if !plan.skipped.isEmpty {
            plan.warnings.append("\(plan.skipped.count) possible usage\(plan.skipped.count == 1 ? "" : "s") with an unknown receiver type will not be changed.")
        }
        if sym.kind == .classLike, options.renameFile {
            let base = (sym.declPath as NSString).lastPathComponent
            let dir = (sym.declPath as NSString).deletingLastPathComponent
            if base == sym.name + ".php", fp.queue.sync(execute: { fp.classPath(sym.fqn) }).map(NPRefs.canon) == sym.declPath {
                let dest = dir + "/" + newName + ".php"
                if FileManager.default.fileExists(atPath: dest), dest.lowercased() != sym.declPath.lowercased() {
                    plan.conflict = "\(newName).php already exists next to \(base)."
                    return plan
                }
                plan.fileRename = (sym.declPath, dest)
            }
        }
        if sym.kind == .globalConstant, plan.hits.contains(where: { $0.role == .declaration }) == false {
            plan.warnings.append("The constant is defined dynamically; only the usages are renamed.")
        }
        return plan
    }

    /// Topmost classes (in the target's hierarchy) that declare the member: every class below them is part of the family.
    private static func familyRoots(_ sym: NPRefSymbol, _ fp: FastProject, _ rel: NPRelations) -> Set<String> {
        let anc = rel.ancestors(sym.fqn)
        var declaring: [String] = []
        for a in anc {
            guard let k = fp.classInfo(rel.names[a] ?? a) else { continue }
            if declares(k, sym, name: sym.name) { declaring.append(NPRelations.norm(k.fqn)) }
        }
        if declaring.isEmpty { return [NPRelations.norm(sym.fqn)] }
        var roots = Set<String>()
        for d in declaring {
            var higher = rel.ancestors(d)
            higher.remove(d)
            if higher.isDisjoint(with: declaring) { roots.insert(d) }
        }
        return roots.isEmpty ? [NPRelations.norm(sym.fqn)] : roots
    }

    private static func declares(_ k: FTClass, _ sym: NPRefSymbol, name: String) -> Bool {
        switch sym.kind {
        case .method: return k.methods.contains { $0.name.lowercased() == name.lowercased() }
        case .property: return k.props.contains { $0.name == name }
        case .constant: return k.declLocs["const:" + name] != nil
        case .enumCase: return k.declLocs["case:" + name] != nil
        default: return false
        }
    }

    private static func conflict(for sym: NPRefSymbol, newName: String, hits: [NPRefHit], fp: FastProject, rel: NPRelations, liveTexts: [String: NSString]) -> String? {
        switch sym.kind {
        case .classLike:
            let ns = sym.fqn.contains("\\") ? String(sym.fqn[..<sym.fqn.lastIndex(of: "\\")!]) : ""
            let newFqn = ns.isEmpty ? newName : ns + "\\" + newName
            if newFqn.lowercased() != sym.fqn.lowercased(), let p = fp.queue.sync(execute: { fp.beginRequest(); return fp.classPath(newFqn) }) {
                return "A class named \(newFqn) already exists (\(((p as NSString).lastPathComponent)))."
            }
            return nil
        case .method, .property, .constant, .enumCase:
            return fp.queue.sync { () -> String? in
                fp.beginRequest()
                var owners = Set<String>()
                for h in hits where h.role == .declaration {
                    let k: FTClass? = h.path == sym.declPath ? (liveTexts[h.path].flatMap { FTParser.parse($0) } ?? fp.classInfo(path: h.path)) : fp.classInfo(path: h.path)
                    if let k { owners.insert(k.fqn) }
                }
                for o in owners {
                    for a in rel.ancestors(o) {
                        guard let k = fp.classInfo(rel.names[a] ?? a) else { continue }
                        if declares(k, sym, name: newName) {
                            let kindWord = sym.kind == .enumCase ? "enum case" : sym.kind.rawValue
                            return "\(k.name.isEmpty ? k.fqn : k.name) already has a \(kindWord) named \(newName)."
                        }
                    }
                }
                return nil
            }
        case .function:
            return fp.queue.sync { () -> String? in
                if NPFuncIndex.shared(root: sym.root).function(newName) != nil { return "A function named \(newName)() already exists." }
                if let t = FastProject.read(sym.declPath) {
                    let lex = PHPLex(t)
                    for j in 0..<max(0, lex.count - 1) where lex.isIdent(j, "function") && lex.toks[j + 1].kind == .ident && lex.text(j + 1).lowercased() == newName.lowercased() {
                        return "A function named \(newName)() already exists in \((sym.declPath as NSString).lastPathComponent)."
                    }
                }
                return nil
            }
        case .globalConstant:
            return NPFuncIndex.shared(root: sym.root).constant(newName) != nil ? "A constant named \(newName) already exists." : nil
        case .variable:
            var v = sym
            v.name = "$" + newName
            let text = liveTexts[sym.declPath] ?? FastProject.read(sym.declPath)
            guard let text else { return nil }
            let s = fp.queue.sync { NPRefs.scanFile(v, path: sym.declPath, fp: fp, rel: rel, text: text, opts: NPScanOptions(includeUnresolved: false, includeDocblocks: false, includeStrings: false)) }
            return s.hits.isEmpty ? nil : "A variable named $\(newName) already exists in this scope."
        }
    }

    // MARK: Edits

    struct PreparedFile {
        var path: String
        var ranges: [(range: NSRange, text: String)]     // descending by location
        var length: Int                                  // text length the offsets refer to
        var snapshot: (size: Int, date: Date?)?          // closed files only
    }

    static func replacement(for h: NPRefHit, _ plan: NPRenamePlan) -> String {
        switch h.form {
        case .plain: return plan.newName
        case .dollar: return "$" + plan.newName
        case .scopeShort: return plan.newName.hasPrefix("scope") ? plan.newName.prefix(6).dropFirst(5).lowercased() + plan.newName.dropFirst(6) : plan.newName
        }
    }

    /// Edits grouped per file, ascending by path; the Preview rows use the same data.
    static func prepare(_ plan: NPRenamePlan, liveTexts: [String: NSString], tabLength: (String) -> Int?) -> (files: [PreparedFile], error: String?) {
        var byPath: [String: [NPRefHit]] = [:]
        for h in plan.hits { byPath[h.path, default: []].append(h) }
        var out: [PreparedFile] = []
        for path in byPath.keys.sorted() {
            let hits = byPath[path]!
            let tabLen = tabLength(path)
            let text: NSString
            var snap: (size: Int, date: Date?)?
            if let live = liveTexts[path] { text = live }
            else if let d = try? Data(contentsOf: URL(fileURLWithPath: path)), let s = String(data: d, encoding: .utf8) {
                text = s as NSString
                if tabLen == nil { snap = state(path) }
            } else { return ([], "cannot read \((path as NSString).lastPathComponent)") }
            if let tl = tabLen, tl != text.length { return ([], "\((path as NSString).lastPathComponent) changed while the rename was prepared") }
            var ranges: [(range: NSRange, text: String)] = []
            for h in hits.sorted(by: { $0.range.location > $1.range.location }) {
                guard NSMaxRange(h.range) <= text.length else { return ([], "stale occurrence in \((path as NSString).lastPathComponent)") }
                if let l = ranges.last, NSMaxRange(h.range) > l.range.location { return ([], "overlapping edits in \((path as NSString).lastPathComponent)") }
                ranges.append((h.range, replacement(for: h, plan)))
            }
            out.append(PreparedFile(path: path, ranges: ranges, length: text.length, snapshot: snap))
        }
        return (out, nil)
    }

    private static func state(_ path: String) -> (size: Int, date: Date?)? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return ((a[.size] as? NSNumber)?.intValue ?? -1, a[.modificationDate] as? Date)
    }

    struct ApplyResult {
        var applied = false
        var failure: String?
        var files = 0
        var edits = 0
        var written: [URL] = []
        var movedFile: (from: URL, to: URL)?
    }

    /// Main thread. Open tabs are edited through their text view (undoable), the others are rewritten atomically.
    @discardableResult
    static func apply(_ plan: NPRenamePlan, liveTexts liveIn: [String: NSString] = [:], tabFor: (String) -> EditorTab?) -> ApplyResult {
        var res = ApplyResult()
        var liveTexts: [String: NSString] = [:]
        for (k, v) in liveIn { liveTexts[NPRefs.canon(k)] = v }
        if let c = plan.conflict { res.failure = c; return res }
        let prep = prepare(plan, liveTexts: liveTexts, tabLength: { tabFor($0).map { ($0.textView.string as NSString).length } })
        if let e = prep.error { res.failure = e; return res }
        // validate closed files again just before touching anything
        var contents: [String: String] = [:]
        for f in prep.files where tabFor(f.path) == nil {
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: f.path)), let s = String(data: d, encoding: .utf8) else { res.failure = "cannot read \((f.path as NSString).lastPathComponent)"; return res }
            let now = state(f.path)
            if now?.size != f.snapshot?.size || now?.date != f.snapshot?.date { res.failure = "\((f.path as NSString).lastPathComponent) changed on disk while the rename was prepared"; return res }
            let m = NSMutableString(string: s)
            for r in f.ranges { m.replaceCharacters(in: r.range, with: r.text) }
            contents[f.path] = m as String
        }
        for f in prep.files { if let tab = tabFor(f.path) { LSPEdits.applyToBuffer(tab.textView, f.ranges, actionName: "Rename") } }
        for f in prep.files where tabFor(f.path) == nil {
            do { try contents[f.path]!.write(toFile: f.path, atomically: true, encoding: .utf8); res.written.append(URL(fileURLWithPath: f.path)) }
            catch { res.failure = "cannot write \((f.path as NSString).lastPathComponent): \(error.localizedDescription)"; break }
        }
        if res.failure == nil, let fr = plan.fileRename {
            do {
                let to = try FileOperations.rename(URL(fileURLWithPath: fr.from), to: (fr.to as NSString).lastPathComponent)
                res.movedFile = (URL(fileURLWithPath: fr.from), to)
            } catch { res.failure = "edits applied, but the file could not be renamed: \(error.localizedDescription)" }
        }
        if !res.written.isEmpty { LanguageServers.fileEvents(res.written.map { ($0, 2) }) }
        NPFiles.clear()
        FastProject.existing(root: URL(fileURLWithPath: plan.symbol.root))?.markDirty()
        res.files = prep.files.count
        res.edits = prep.files.reduce(0) { $0 + $1.ranges.count }
        res.applied = res.failure == nil
        return res
    }
}
