import AppKit
import SwiftTreeSitter

/// Native JS / TS completion limited to lists that are provably complete and correct:
/// module specifiers in import / export-from / require strings (directory listings, tsconfig `paths`, node_modules), the names a
/// module really exports inside `import { | } from '...'`, and members of a receiver whose class chain resolves. Everything else is
/// left to the other providers (the language server, words, snippets).
extension NJSEnv {
    /// Names exported by `file` (ES exports, `export =` namespace members, `export *` chains, ambient script globals).
    func exportNames(_ file: String, depth: Int = 0, into out: inout [(name: String, kind: NJSKind?)]) {
        steps += 1
        guard depth < 6, steps < 300, let s = summary(file) else { return }
        for (k, _) in s.exports where k != "default" && k != "=" { out.append((k, s.top[k]?.first?.kind)) }
        if let eq = s.exportEquals { for b in resolveTop(file, eq, depth: depth + 1) { for m in b.members { out.append((m.name, m.kind)) } } }
        for star in s.stars { if let t = proj.modules.resolve(star, from: file), NJSEnv.isCode(t) { exportNames(t, depth: depth + 1, into: &out) } }
        if !s.isModule && !s.commonJS { for sym in s.order where sym.kind != .import { out.append((sym.name, sym.kind)) } }
    }

    /// All members visible on a value of type `t` (declared members of the class chain), with kinds and type names.
    func memberList(_ t: NJSTV) -> [NJSMember] {
        var out: [NJSMember] = []
        var seen = Set<String>()
        func walk(_ r: NJSRes, depth: Int) {
            guard depth < 10 else { return }
            steps += 1
            for m in r.members where (r.kind != .class || m.isStatic == t.isStatic) && m.name != "constructor" {
                if seen.insert(m.name).inserted { out.append(m) }
            }
            for h in r.heritage { for base in resolveTypeRef(h, in: r.path, siblings: r.siblings) where !(base.path == r.path && base.loc == r.loc) { walk(base, depth: depth + 1) } }
        }
        for r in t.res { walk(r, depth: 0) }
        if let m = t.module { var names: [(name: String, kind: NJSKind?)] = []; exportNames(m, into: &names); for n in names where seen.insert(n.name).inserted {
            out.append(NJSMember(name: n.name, kind: n.kind ?? .variable, loc: 0, len: 0, declStart: 0, sigEnd: 0)) } }
        return out
    }
}

enum NativeJSCompletion {
    static let extensions = ["js", "jsx", "ts", "tsx", "mjs", "cjs", "mts", "cts", "vue"]

    static func register() { CompletionRegistry.register(NativeJSCompletionProvider(), forExtensions: extensions) }

    static func kind(_ k: NJSKind?) -> CompletionKind {
        switch k {
        case .function?: return .function
        case .class?: return .class
        case .interface?, .typeAlias?: return .interface
        case .enum?: return .enum
        case .namespace?: return .module
        case .method?: return .method
        case .property?, .getter?, .setter?: return .property
        case .enumMember?: return .enumMember
        case .constant?: return .constant
        default: return .variable
        }
    }

    // MARK: module specifiers

    /// (opening quote offset, specifier typed so far) when the caret is inside the string of an import / export-from / require.
    static func specifierContext(_ ns: NSString, _ caret: Int) -> (quote: Int, typed: String)? {
        let ls = max(CompletionLex.lineStart(ns, caret), caret - 300)
        var j = caret - 1
        while j >= ls {
            let c = ns.character(at: j)
            if c == 39 || c == 34 || c == 96 {
                let before = ns.substring(with: NSRange(location: ls, length: j - ls))
                guard let re = NPRe.make(pattern: #"(?:\bfrom|\bimport|\brequire)\s*\(?\s*$"#), re.firstMatch(in: before, range: NSRange(location: 0, length: (before as NSString).length)) != nil else { return nil }
                return (j, ns.substring(with: NSRange(location: j + 1, length: caret - j - 1)))
            }
            j -= 1
        }
        return nil
    }

    static func specifierItems(env: NJSProject, file: String, typed: String, caretReplaceStart: Int, caret: Int) -> [CompletionItem] {
        var items: [CompletionItem] = []
        let fm = FileManager.default
        func listDir(_ dir: String, prefixTyped: String, allowFiles: Bool = true) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            var seen = Set<String>()
            for n in names.sorted().prefix(2000) where !n.hasPrefix(".") && n != "node_modules" {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: dir + "/" + n, isDirectory: &isDir)
                if isDir.boolValue {
                    if seen.insert(n).inserted { items.append(CompletionItem(label: n + "/", insertText: n + "/", kind: .folder)) }
                    continue
                }
                guard allowFiles else { continue }
                let ext = (n as NSString).pathExtension.lowercased()
                var label = n
                if NJSModules.codeExts.contains(ext), ext != "vue" {
                    if n.hasSuffix(".d.ts") { label = String(n.dropLast(5)) } else { label = (n as NSString).deletingPathExtension }
                    if label == "index" { items.append(CompletionItem(label: "index", insertText: "index", kind: .file)) }
                }
                if seen.insert(label).inserted { items.append(CompletionItem(label: label, insertText: label, kind: .file)) }
            }
        }
        let dirPart: String, base: String
        if let slash = typed.lastIndex(of: "/") { dirPart = String(typed[...slash]); base = String(typed[typed.index(after: slash)...]) } else { dirPart = ""; base = typed }
        _ = base
        let fileDir = (file as NSString).deletingLastPathComponent
        if typed.hasPrefix("./") || typed.hasPrefix("../") || typed == "." || typed == ".." {
            if typed == "." || typed == ".." { return [CompletionItem(label: typed + "/", insertText: typed + "/", kind: .folder)] }
            listDir(NJSModules.join(fileDir, dirPart), prefixTyped: base)
        } else if typed.hasPrefix("/") {
            listDir(NJSModules.join("/", dirPart), prefixTyped: base)
        } else {
            // tsconfig `paths` / baseUrl
            if let cfg = env.modules.config(for: file) {
                for r in cfg.rules where r.star && typed.hasPrefix(r.prefix) && !r.targets.isEmpty {
                    let rest = String(typed.dropFirst(r.prefix.count))
                    let sub: String, tail: String
                    if let slash = rest.lastIndex(of: "/") { sub = String(rest[...slash]); tail = String(rest[rest.index(after: slash)...]) } else { sub = ""; tail = rest }
                    _ = tail
                    for t in r.targets {
                        guard let star = t.firstIndex(of: "*") else { continue }
                        let tdir = String(t[..<star]) + sub
                        listDir(NJSModules.join(cfg.pathsBase, tdir), prefixTyped: tail)
                    }
                }
                for r in cfg.rules where r.prefix.hasPrefix(typed) { items.append(CompletionItem(label: r.prefix + (r.star ? "" : ""), insertText: r.prefix, kind: .module)) }
                if let b = cfg.baseUrl, !typed.hasPrefix("@") { listDir(NJSModules.join(b, dirPart), prefixTyped: base) }
            }
            // packages in the nearest node_modules (only the segment being typed)
            if !typed.contains("/") || typed.hasPrefix("@") && typed.split(separator: "/").count <= 1 {
                var d = fileDir
                for _ in 0..<12 {
                    let nm = d + "/node_modules"
                    if let names = try? fm.contentsOfDirectory(atPath: nm) {
                        for n in names.sorted() where !n.hasPrefix(".") && n != ".bin" {
                            if n.hasPrefix("@") {
                                if let scoped = try? fm.contentsOfDirectory(atPath: nm + "/" + n) { for s in scoped.sorted().prefix(500) where !s.hasPrefix(".") { items.append(CompletionItem(label: n + "/" + s, insertText: n + "/" + s, kind: .module)) } }
                            } else if !n.hasPrefix("@") { items.append(CompletionItem(label: n, insertText: n, kind: .module)) }
                        }
                        break
                    }
                    if d == "/" || d.isEmpty { break }
                    d = (d as NSString).deletingLastPathComponent
                }
            } else if let slash = typed.firstIndex(of: "/") {
                // subpath of a package: `pkg/` -> its directory listing
                let name = typed.hasPrefix("@") ? typed.split(separator: "/").prefix(2).joined(separator: "/") : String(typed[..<slash])
                var d = fileDir
                for _ in 0..<12 {
                    let pk = d + "/node_modules/" + name
                    if fm.fileExists(atPath: pk) {
                        let afterName = typed.dropFirst(name.count)
                        let sub = afterName.hasPrefix("/") ? String(afterName.dropFirst()) : ""
                        let subDir = sub.lastIndex(of: "/").map { String(sub[...$0]) } ?? ""
                        listDir(pk + "/" + subDir, prefixTyped: "")
                        break
                    }
                    if d == "/" || d.isEmpty { break }
                    d = (d as NSString).deletingLastPathComponent
                }
            }
        }
        // replace only the last path segment
        let segStart = caretReplaceStart + (typed.lastIndex(of: "/").map { typed.distance(from: typed.startIndex, to: $0) + 1 } ?? 0)
        let seg = NSRange(location: segStart, length: max(0, caret - segStart))
        for i in items.indices { items[i].replaceRange = seg }
        return items
    }

    // MARK: import { | } from 'x'

    /// Module specifier when the caret is inside the braces of `import { ... } from '...'` / `export { ... } from '...'`.
    static func namedImportSpecifier(_ ns: NSString, _ caret: Int) -> String? {
        let from = max(0, caret - 3000)
        var j = caret - 1
        var brace = -1
        while j >= from {
            let c = ns.character(at: j)
            if c == 125 || c == 59 || c == 40 || c == 41 { return nil }
            if c == 123 { brace = j; break }
            j -= 1
        }
        guard brace >= 0 else { return nil }
        let head = ns.substring(with: NSRange(location: max(0, brace - 120), length: min(120, brace)))
        guard let re = NPRe.make(pattern: #"(?:^|[\n;])\s*(?:import|export)\s+(?:type\s+)?(?:[A-Za-z_$][\w$]*\s*,\s*)?$"#),
              re.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length)) != nil else { return nil }
        let tailStart = caret
        let tailLen = min(3000, ns.length - tailStart)
        let tail = ns.substring(with: NSRange(location: tailStart, length: tailLen))
        guard let re2 = NPRe.make(pattern: #"^[^{}]*\}\s*from\s*['"]([^'"\n]+)['"]"#),
              let m = re2.firstMatch(in: tail, range: NSRange(location: 0, length: (tail as NSString).length)) else { return nil }
        return (tail as NSString).substring(with: m.range(at: 1))
    }
}

final class NativeJSCompletionProvider: CompletionProvider {
    let triggerCharacters = ["'", "\"", "/", ".", "{", ","]
    private var token = 0

    func cancel() { token += 1 }

    func complete(_ context: CompletionContext, deliver: @escaping ([CompletionItem], Bool) -> Void) {
        token += 1
        let mine = token
        guard NativeJS.enabled, NativeJS.extensions.contains(context.fileExtension.lowercased()) else { deliver([], false); return }
        let ns = context.text as NSString
        let caret = min(context.caret, ns.length)
        let url = context.fileURL
        let proj = NJSProject.shared(root: NativeJS.root(for: url))
        let file = (url.standardizedFileURL.path as NSString).standardizingPath
        let prefix = context.prefixRange
        let snapshot = NSString(string: context.text)
        proj.queue.async { [weak self] in
            guard let self, self.token == mine else { return }
            proj.modules.beginRequest()
            var items: [CompletionItem] = []
            if let (quote, typed) = NativeJSCompletion.specifierContext(snapshot, caret) {
                items = NativeJSCompletion.specifierItems(env: proj, file: file, typed: typed, caretReplaceStart: quote + 1, caret: caret)
            } else if let spec = NativeJSCompletion.namedImportSpecifier(snapshot, caret), let target = proj.modules.resolve(spec, from: file), NJSEnv.isCode(target) {
                guard let d = NativeJS.document(path: file, text: snapshot) else { deliver([], false); return }
                let env = NJSEnv(proj: proj, doc: d)
                var names: [(name: String, kind: NJSKind?)] = []
                env.exportNames(target, into: &names)
                var seen = Set<String>()
                items = names.filter { seen.insert($0.name).inserted }.map { CompletionItem(label: $0.name, insertText: $0.name, kind: NativeJSCompletion.kind($0.kind), detail: $0.kind?.label ?? "") }
            } else if prefix.location > 0, let dot = NativeJSProviderSupport.memberReceiver(snapshot, prefix) {
                items = NativeJSProviderSupport.memberItems(proj: proj, file: file, text: snapshot, prefix: prefix, receiverEnd: dot)
            }
            guard self.token == mine else { return }
            deliver(items, false)
        }
    }
}

enum NativeJSProviderSupport {
    /// Offset of the `.` (or `?.`) right before the identifier prefix, if any.
    static func memberReceiver(_ ns: NSString, _ prefix: NSRange) -> Int? {
        var i = prefix.location - 1
        guard i >= 0 else { return nil }
        if ns.character(at: i) != 46 { return nil }
        if i > 0, ns.character(at: i - 1) == 46 { return nil }          // spread / range
        i -= 1
        if i >= 0, ns.character(at: i) == 63 { i -= 1 }                  // ?.
        return i + 1
    }

    static func memberItems(proj: NJSProject, file: String, text: NSString, prefix: NSRange, receiverEnd: Int) -> [CompletionItem] {
        // Parse a copy where the (possibly empty) prefix is a complete identifier, so `foo.` is a valid member expression.
        let placeholder = "__ce_x__"
        let masked = text.replacingCharacters(in: prefix, with: placeholder) as NSString
        guard let doc = NJSDoc(path: file, text: masked), doc.inScript(prefix.location) else { return [] }
        let env = NJSEnv(proj: proj, doc: doc)
        guard let leaf = doc.leaf(at: prefix.location), leaf.kind == "property_identifier", let p = leaf.parent, p.kind == "member_expression",
              let o = p.field("object"), let t = env.typeOf(o) else { return [] }
        var items: [CompletionItem] = []
        for m in env.memberList(t) {
            var kind: CompletionKind = .property
            switch m.kind {
            case .method: kind = .method
            case .function: kind = .function
            case .class: kind = .class
            case .interface, .typeAlias: kind = .interface
            case .enum: kind = .enum
            case .enumMember: kind = .enumMember
            case .namespace: kind = .module
            case .constant: kind = .constant
            case .variable: kind = .variable
            default: kind = .property
            }
            items.append(CompletionItem(label: m.name, insertText: m.name, kind: kind, detail: m.typeName ?? ""))
        }
        return items
    }
}
