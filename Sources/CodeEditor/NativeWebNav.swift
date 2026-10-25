import Foundation

/// Navigation helpers shared by the CSS and HTML services: targets, file resolution, class / id usage search.
enum NWNav {
    static func target(path: String, offset: Int, text: NSString? = nil) -> NPTarget {
        guard let t = text ?? FastProject.readRaw(path) else { return NPTarget(path: path, offset: offset, line: 1, column: 1) }
        let pos = NPLineStarts(t).position(of: offset)
        return NPTarget(path: path, offset: offset, line: pos.line, column: pos.col)
    }

    /// Resolves `ref` (href / src / @import / url()) to an existing file: relative to `dir`, root-relative to the project (and its public/ dir),
    /// scss partials (`_name.scss`) and `~pkg` / bare node_modules imports.
    static func resolveFile(_ ref: String, from dir: String, root: String) -> String? {
        var r = ref.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t\n"))
        if let q = r.firstIndex(where: { $0 == "?" || $0 == "#" }) { r = String(r[r.startIndex..<q]) }
        guard !r.isEmpty, !r.hasPrefix("http:"), !r.hasPrefix("https:"), !r.hasPrefix("data:"), !r.hasPrefix("//"), !r.hasPrefix("mailto:"), !r.hasPrefix("tel:"),
              !r.contains("{{"), !r.contains("<?"), !r.contains("$") else { return nil }
        var candidates: [String] = []
        func add(_ base: String) {
            let std = (base as NSString).standardizingPath
            candidates.append(std)
            let name = (std as NSString).lastPathComponent
            let d = (std as NSString).deletingLastPathComponent
            if (name as NSString).pathExtension.isEmpty {
                for ext in ["css", "scss", "less", "sass"] { candidates.append(std + "." + ext); candidates.append(d + "/_" + name + "." + ext) }
                for ext in ["css", "scss"] { candidates.append(std + "/index." + ext); candidates.append(std + "/_index." + ext) }
            } else { candidates.append(d + "/_" + name) }
        }
        if r.hasPrefix("~") { add(root + "/node_modules/" + r.dropFirst()) }
        else if r.hasPrefix("/") { add(root + r); add(root + "/public" + r); add(root + "/resources" + r); add(r) }
        else { add(dir + "/" + r); add(root + "/" + r); add(root + "/public/" + r); add(root + "/node_modules/" + r) }
        for c in candidates where LaravelFS.isFile(c) { return c }
        return nil
    }

    /// Usages of a class / id token across the project's markup (and the current buffer), found by text prefilter + attribute scan.
    static func usages(of name: String, isId: Bool, in p: NWProject, current: (path: String, buf: NWBuf)?, limit: Int = 60) -> [NPTarget] {
        var out: [NPTarget] = []
        let needle = Array(name.utf8)
        func scan(_ b: NWBuf, path: String) {
            NWHtml.eachAttribute(b) { _, attr, _, value, quote in
                guard out.count < limit else { return }
                let a = attr.lowercased()
                if isId {
                    guard a == "id" || a == "for" && false else { return }
                    if b.str(value.location, NSMaxRange(value)) == name { out.append(NWNav.target(path: path, offset: value.location, text: b.ns)) }
                    return
                }
                guard NWService.isClassAttribute(a) else { return }
                let bound = a != "class" && a != "classname" && a != "classlist" || quote == 123
                var spans: [NSRange] = [value]
                if bound {                                                       // string literals inside the expression
                    spans = []
                    var i = value.location
                    let end = NSMaxRange(value)
                    while i < end {
                        let c = b[i]
                        if c == 34 || c == 39 || c == 96 {
                            var j = i + 1
                            while j < end, b[j] != c { if b[j] == 92 { j += 1 }; j += 1 }
                            spans.append(NSRange(location: i + 1, length: max(0, min(j, end) - i - 1)))
                            i = j + 1
                        } else { i += 1 }
                    }
                }
                for s in spans {
                    for t in NWHtml.classTokens(b, in: s) where t.name == name { out.append(NWNav.target(path: path, offset: t.range.location, text: b.ns)); return }
                }
            }
        }
        var seenCurrent = ""
        if let c = current { seenCurrent = c.path; scan(c.buf, path: c.path) }
        var examined = 0
        for path in p.allMarkupFiles where out.count < limit && path != seenCurrent && examined < 3500 {
            examined += 1
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe), d.count <= 600_000, !needle.isEmpty else { continue }
            let found = d.withUnsafeBytes { raw -> Bool in
                guard let base = raw.baseAddress else { return false }
                return memmem(base, d.count, needle, needle.count) != nil
            }
            guard found, let text = NSString(data: d, encoding: String.Encoding.utf8.rawValue) else { continue }
            scan(NWBuf(text), path: path)
        }
        return out
    }
}
