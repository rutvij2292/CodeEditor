import AppKit

// Native Go to Implementation and Go to Type Declaration (phase 2a).
//
// Implementations: interface/abstract method -> methods of every (transitive) implementer / subclass; class or interface name ->
// all subclasses / implementers. No resident inheritance table: one pass over the project's PSR-4 PHP files reads each file once
// (text prefilter on `extends` / `implements`), extracts the class header names with a regex into a TRANSIENT array, then walks
// the hierarchy in memory and confirms every candidate with the fast-tier class parser (FQN-checked). Vendor packages are not
// scanned (implementers of a vendor interface that live inside vendor/ are not listed). The array is freed when the request ends.
//
// Type declaration: variable / property / call chain -> the class of its inferred type (FTEval), several targets for
// collections (the collection class and the element class).

private struct NPHeader { var path: String; var names: Set<String> }

extension NPResolver {
    static let maxScanFiles = 8000
    static let maxScanBytes = 600_000
    static let maxImplementations = 200

    // MARK: Type declaration

    func typeDefinition(at offset: Int) -> NPHit? {
        fp.beginRequest()
        guard let i = tokenAt(offset), inPHP(lex.toks[i].loc) else { return nil }
        let t = lex.toks[i]
        let range = NSRange(location: t.loc, length: t.len)
        var type: FTType?
        switch t.kind {
        case .variable:
            if tokText(i) == "$this" { type = cur.flatMap { $0.fqn.isEmpty ? nil : .instance($0.fqn) } }
            else if i > 0, lex.isPunct(i - 1, code: PHPTok.dcolon) { type = memberExprType(i) }
            else { type = ev.varType(tokText(i), at: i, depth: 0) }
        case .ident:
            if i > 0, isOpTok(i - 1) { type = memberExprType(i) }
            else if lex.isPunct(i + 1, "("), lex.match[i + 1] > i + 1 { type = ev.eval(i, lex.match[i + 1] + 1) }
            else { return lookup(at: offset) }       // a class name: its type declaration is itself
        default: return nil
        }
        guard let type else { return nil }
        var fqns: [String] = []
        switch type {
        case .instance(let f), .staticRef(let f): fqns = [f]
        case .builder(let m): fqns = [Self.eloquentBuilder, m]
        case .table: fqns = [Self.queryBuilder]
        case .collection(let m): fqns = [Self.collectionClass] + (m.map { [$0] } ?? [])
        }
        var targets: [NPTarget] = []
        var md = "```php\n\(typeDescription(type))\n```"
        for f in fqns {
            if let h = classHit(fqn: f, range) { for x in h.targets where !targets.contains(x) { targets.append(x) } }
        }
        if targets.isEmpty { md += "\n\nType declaration not found in the project index." }
        return NPHit(range: range, targets: targets, markdown: md, kind: "type")
    }

    /// Type of the member expression whose name token is `i` (`$a->b`, `$a->b()`, `Foo::bar()`).
    private func memberExprType(_ i: Int) -> FTType? {
        let op = i - 1
        let lo = ev.chainStart(before: op)
        guard lo < op else { return nil }
        var end = i + 1
        if lex.isPunct(i + 1, "("), lex.match[i + 1] > i + 1 { end = lex.match[i + 1] + 1 }
        return ev.eval(lo, end)
    }

    private func typeDescription(_ t: FTType) -> String {
        switch t {
        case .instance(let f): return f
        case .staticRef(let f): return "class-string<\(f)>"
        case .builder(let m): return "Eloquent Builder<\(m)>"
        case .table(let tbl): return "Query Builder (table \(tbl))"
        case .collection(let m): return m.map { "Collection<\($0)>" } ?? "Collection"
        }
    }

    // MARK: Go to implementation

    /// The class (and optionally method) the caret denotes, for implementation search.
    func implementationSubject(at offset: Int) -> (cls: String, method: String?)? {
        guard let i = tokenAt(offset), inPHP(lex.toks[i].loc) else { return nil }
        let t = lex.toks[i]
        if t.kind == .variable {
            let name = tokText(i)
            if name == "$this" { return cur.flatMap { $0.fqn.isEmpty ? nil : ($0.fqn, nil) } }
            switch ev.varType(name, at: i, depth: 0) {
            case .instance(let f)?, .staticRef(let f)?: return (f, nil)
            default: return nil
            }
        }
        guard t.kind == .ident else { return nil }
        let name = tokText(i)
        if let c = cur, let m = c.methods.first(where: { $0.loc == t.loc }) { return (c.fqn, m.name) }
        if let c = cur, t.loc == c.nameLoc { return (c.fqn, nil) }
        if i >= 1, isOpTok(i - 1) {
            guard lex.isPunct(i + 1, "(") else { return nil }
            let isStaticOp = lex.isPunct(i - 1, code: PHPTok.dcolon)
            let lo = ev.chainStart(before: i - 1)
            guard lo < i - 1, let recv = ev.eval(lo, i - 1) else { return nil }
            let (owners, model) = self.owners(for: recv)
            guard let mem = findMember(owners: owners, model: model, name: name, isCall: true, isStatic: isStaticOp, kindVariable: false), mem.kind == .method else { return nil }
            return (mem.owner.fqn, mem.name)
        }
        if lex.isPunct(i + 1, "("), !lex.isIdent(i - 1, "new") { return nil }          // plain function call
        if let (fqn, builtin) = resolveClassName(name), !builtin { return (fqn, nil) }
        return nil
    }

    func implementations(at offset: Int) -> NPHit? {
        fp.beginRequest()
        guard let subject = implementationSubject(at: offset), let i = tokenAt(offset) else { return nil }
        let range = NSRange(location: lex.toks[i].loc, length: lex.toks[i].len)
        let subs = subclasses(of: subject.cls)
        var targets: [NPTarget] = []
        for (k, path) in subs {
            let off: Int
            if let name = subject.method {
                guard let m = k.method(named: name) else { continue }
                off = m.loc
            } else { off = k.nameLoc }
            if let t = target(path: path, offset: off) { targets.append(t) }
        }
        guard !targets.isEmpty else { return nil }
        let what = subject.method.map { "`\(short(subject.cls))::\($0)()`" } ?? "`\(short(subject.cls))`"
        return NPHit(range: range, targets: targets, markdown: "\(targets.count) implementation\(targets.count == 1 ? "" : "s") of \(what)", kind: "implementation")
    }

    // MARK: Hierarchy scan

    /// All project classes that (transitively) extend or implement `base`, in path order. Bounded and transient.
    func subclasses(of base: String) -> [(FTClass, String)] {
        let baseShort = short(base)
        guard !baseShort.isEmpty else { return [] }
        var headers: [NPHeader] = []
        let needles = [Data("extends".utf8), Data("implements".utf8)]
        guard let re = NPRe.make(pattern: #"(?m)^[ \t]*(?:(?:abstract|final|readonly)[ \t]+)*(?:class|interface|enum)[ \t]+\w+([^{;]*)\{"#) else { return [] }
        var scanned = 0
        var seenPaths = Set<String>()
        for ref in fp.projectClasses() {
            guard scanned < Self.maxScanFiles, let p = fp.classPath(ref.fqn), seenPaths.insert(p).inserted else { continue }
            scanned += 1
            guard let data = FileManager.default.contents(atPath: p), data.count < Self.maxScanBytes,
                  needles.contains(where: { data.range(of: $0) != nil }) else { continue }
            let text = String(decoding: data, as: UTF8.self)
            var names = Set<String>()
            for m in re.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).prefix(4) {
                let tail = (text as NSString).substring(with: m.range(at: 1))
                for w in tail.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_" || $0 == "\\") }) where w != "extends" && w != "implements" {
                    names.insert(String(w.split(separator: "\\").last ?? w))
                }
            }
            if !names.isEmpty { headers.append(NPHeader(path: p, names: names)) }
        }
        var frontier: Set<String> = [baseShort]
        var accepted: Set<String> = [base]
        var found: [(FTClass, String)] = []
        var done = Set<String>()
        var changed = true
        var rounds = 0
        while changed, rounds < 10, found.count < Self.maxImplementations {
            changed = false; rounds += 1
            for h in headers where !done.contains(h.path) && !h.names.isDisjoint(with: frontier) {
                guard let k = fp.classInfo(path: h.path) else { done.insert(h.path); continue }
                let parents = (k.extends.map { [$0] } ?? []) + k.implements
                if parents.contains(where: { accepted.contains($0) }) {
                    done.insert(h.path)
                    accepted.insert(k.fqn); frontier.insert(k.name)
                    found.append((k, h.path))
                    changed = true
                    if found.count >= Self.maxImplementations { break }
                }
            }
        }
        return found.sorted { $0.1 < $1.1 }
    }
}

extension NativePHP {
    static func typeDefinition(url: URL, text: NSString, offset: Int, root: String? = nil) -> NPHit? {
        guard handles(url), let r = root ?? FastTier.root(for: url) else { return nil }
        let fp = FastProject.shared(root: URL(fileURLWithPath: r))
        return fp.queue.sync { resolver(fp: fp, url: url, text: text).typeDefinition(at: offset) }
    }

    static func implementations(url: URL, text: NSString, offset: Int, root: String? = nil) -> NPHit? {
        guard handles(url), let r = root ?? FastTier.root(for: url) else { return nil }
        let fp = FastProject.shared(root: URL(fileURLWithPath: r))
        return fp.queue.sync { resolver(fp: fp, url: url, text: text).implementations(at: offset) }
    }

    /// Runs `work` on the project's fast-tier queue and delivers its hit on the main queue.
    static func async(url: URL, text: NSString, _ work: @escaping (NPResolver) -> NPHit?, completion: @escaping (NPHit?) -> Void) {
        guard handles(url), let r = FastTier.root(for: url) else { completion(nil); return }
        let fp = FastProject.shared(root: URL(fileURLWithPath: r))
        let snapshot = NSString(string: text as String)
        fp.queue.async {
            let hit = work(resolver(fp: fp, url: url, text: snapshot))
            DispatchQueue.main.async { completion(hit) }
        }
    }
}

/// Menu targets: Navigate > Go to Implementation / Go to Type Declaration (PHP files only).
final class NativePHPNav: NSObject {
    static let shared = NativePHPNav()

    private func run(_ what: String, _ work: @escaping (NPResolver, Int) -> NPHit?) {
        guard let w = (NSApp.delegate as? AppDelegate)?.active, let tab = w.current else { return }
        guard NativePHP.handles(tab.url) else { w.statusBar.flash("\(what) works on PHP files"); return }
        let offset = tab.textView.selectedRange().location
        NativePHP.async(url: tab.url, text: tab.textView.string as NSString, { work($0, offset) }) { hit in
            guard let hit, !hit.targets.isEmpty, NativePHP.open(hit, from: tab, offset: offset) else { w.statusBar.flash("No \(what.lowercased()) found"); return }
        }
    }

    @objc func goToImplementation(_ sender: Any?) { run("Implementation") { $0.implementations(at: $1) } }
    @objc func goToTypeDeclaration(_ sender: Any?) { run("Type declaration") { $0.typeDefinition(at: $1) } }
}
