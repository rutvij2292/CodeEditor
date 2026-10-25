import Foundation

/// Members that exist only in docblocks: `@method` / `@property` tags of IDE-helper annotated classes, Carbon (`subDay`, `addMonths`
/// ... are `@method` lines), and Laravel facades (`Cache::store`, `Inertia::render`, `Auth::setUser`). Nothing is cached: the class
/// docblock (a few KB, up to ~100 KB for Carbon) is scanned for lines whose name matches the typed prefix, so RAM stays flat.
extension FTEval {
    private static let methodRx = NPRe.make(pattern: #"@method\s+(static\s+)?(?:([^\s(][^(]*?)\s+)?(\w+)\s*\(([^)]*)\)"#)
    private static let propRx = NPRe.make(pattern: #"@property(?:-read|-write)?\s+(?:([^\s$]+)\s+)?\$(\w+)"#)

    /// Items for the `@method` / `@property` tags on the class chain of `f` whose name starts with `prefix` (case-insensitive).
    /// `instance`: members of an object (`->`), else of the class (`::`, only `static` @method lines).
    func docMemberItems(_ f: String, prefix: String, instance: Bool, seen: inout Set<String>, priority: Int = 3, limit: Int = 400) -> [CompletionItem] {
        var out: [CompletionItem] = []
        let pl = prefix.lowercased()
        for k in hierarchy(f).prefix(6) {
            guard let t = fileText(of: k), let d = NPDoc.leading(t, before: k.declStart), d.text.utf8.count < 400_000,
                  d.text.contains("@method") || d.text.contains("@property") else { continue }
            let doc = d.text as NSString
            if let rx = Self.methodRx {
                rx.enumerateMatches(in: d.text, range: NSRange(location: 0, length: doc.length)) { m, _, stop in
                    guard let m, out.count < limit else { stop.pointee = true; return }
                    let isStatic = m.range(at: 1).location != NSNotFound
                    if !instance, !isStatic { return }
                    let name = doc.substring(with: m.range(at: 3))
                    if !pl.isEmpty, !name.lowercased().hasPrefix(pl) { return }
                    guard seen.insert("method:" + name).inserted else { return }
                    let ret = m.range(at: 2).location != NSNotFound ? doc.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces) : ""
                    let params = doc.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespaces)
                    let detail = "(" + params + ")" + (ret.isEmpty ? "" : ": " + ret)
                    var it = CI.make(name, .method, detail: detail, insert: params.isEmpty ? name + "()" : CI.callInsert(name, params: params), snippet: !params.isEmpty,
                                     doc: "```php\n\(name)\(detail)\n```\n\(k.fqn)")
                    it.priority = priority
                    out.append(it)
                }
            }
            if instance, let rx = Self.propRx {
                rx.enumerateMatches(in: d.text, range: NSRange(location: 0, length: doc.length)) { m, _, stop in
                    guard let m, out.count < limit else { stop.pointee = true; return }
                    let name = doc.substring(with: m.range(at: 2))
                    if !pl.isEmpty, !name.lowercased().hasPrefix(pl) { return }
                    guard seen.insert("property:" + name).inserted else { return }
                    let type = m.range(at: 1).location != NSNotFound ? doc.substring(with: m.range(at: 1)) : ""
                    var it = CI.make(name, .property, detail: type, doc: k.fqn)
                    it.priority = priority
                    out.append(it)
                }
            }
        }
        return out
    }

    /// `Cache::`, `Inertia::` ...: the facade's own `@method static` tags, then the public methods of the real class behind it
    /// (`getFacadeAccessor`), then the facade base class statics (`shouldReceive`, `swap` ...) last.
    func facadeItems(_ f: String, prefix: String) -> [CompletionItem] {
        var seen = Set<String>()
        var items = docMemberItems(f, prefix: prefix, instance: false, seen: &seen, priority: 0)
        if let root = facadeRoot(f) {
            for var it in members(of: .instance(root), via: nil, fromSameClass: false, staticDollar: false, onlyNames: &seen) { it.priority = 2; items.append(it) }
            items += docMemberItems(root, prefix: prefix, instance: true, seen: &seen, priority: 3)
        }
        for var it in members(of: .staticRef(f), via: nil, fromSameClass: false, staticDollar: false, onlyNames: &seen) { it.priority = 30; items.append(it) }
        return items
    }
}


// MARK: Deprecation and lazily loaded documentation

extension FTEval {
    /// Names of the methods of `k` whose docblock carries `@deprecated` (shown struck through). Computed once per class per request,
    /// and only when the class file mentions the tag at all.
    func deprecatedMethods(of k: FTClass) -> Set<String> {
        let id = ObjectIdentifier(k)
        if let c = deprecatedCache[id] { return c }
        var out = Set<String>()
        defer { deprecatedCache[id] = out }
        guard let t = fileText(of: k), t.length < 600_000 else { return out }
        var from = 0
        var hits = 0
        while hits < 200 {
            let r = t.range(of: "@deprecated", options: .literal, range: NSRange(location: from, length: t.length - from))
            if r.location == NSNotFound { break }
            hits += 1
            let end = t.range(of: "*/", options: .literal, range: NSRange(location: r.location, length: t.length - r.location))
            if end.location == NSNotFound { break }
            from = end.location + 2
            // the declaration right after the docblock: [attributes] [modifiers] function name
            let tail = t.substring(with: NSRange(location: from, length: min(400, t.length - from)))
            if let rx = NPRe.make(pattern: #"^\s*(?:#\[[^\]]*\]\s*)*(?:(?:public|protected|private|static|final|abstract)\s+)*function\s+&?(\w+)"#),
               let m = rx.firstMatch(in: tail, range: NSRange(location: 0, length: (tail as NSString).length)) {
                out.insert((tail as NSString).substring(with: m.range(at: 1)))
            }
        }
        return out
    }

    /// `resolve` for a member item: the docblock of the declaration (summary, @param, @return, @deprecated) read on the project queue when
    /// the row is highlighted. Nothing is read for rows nobody looks at.
    func lazyDoc(owner: String, declStart: Int, header: String) -> (@escaping (CompletionItem) -> Void) -> Void {
        let fp = self.fp
        return { done in
            fp.queue.async {
                var it = CompletionItem(label: "", insertText: "", kind: .method)
                var md = ""
                if let path = fp.classPath(owner), let t = NPFiles.text(path), let d = NPDoc.leading(t, before: declStart) {
                    md = NPDoc.parse(d.text, start: d.start, query: .core).markdown(maxChars: 900)
                }
                it.documentation = md.isEmpty ? header : header + "\n\n" + md
                done(it)
            }
        }
    }
}
