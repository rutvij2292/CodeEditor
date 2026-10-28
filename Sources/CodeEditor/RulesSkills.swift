import Foundation

/// Every instruction file Claude Code reads for a project: CLAUDE.md files, `.claude/rules`, `.claude/skills`, `.claude/commands`
/// (in the project and in ~/.claude) and the project's auto-memory notes. Read on demand, never watched. "New"/"changed" badges come
/// from a small store of what the user last looked at (a fingerprint and the text, capped), kept next to the app's other state.
enum RulesSkills {
    /// Overridable so tests never touch the real ~/.claude or Application Support.
    static var home: URL { ClaudeData.home }
    static var stateFile = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/Kode/rules-review.json")
    static let disabledSuffix = ".disabled"
    static let maxStoredBytes = 64 * 1024

    enum Scope: Int, CaseIterable { case project, global, memory
        var title: String { ["Project", "Global", "Memory"][rawValue] }
    }
    enum Kind { case instructions, rule, skill, command, memory
        var label: String { switch self { case .instructions: "CLAUDE.md"; case .rule: "rule"; case .skill: "skill"; case .command: "command"; case .memory: "memory" } }
    }
    enum Status { case seen, new, changed }

    struct Item: Equatable {
        let scope: Scope
        let kind: Kind
        let title: String          // path relative to its base, as shown in the tree
        let file: URL              // the text that is edited (SKILL.md for a skill)
        let container: URL         // what moves / goes to the Trash (the skill folder, else the file)
        var disabled: Bool
        var modified: Date
        var bytes: Int64
        var key: String { file.path }
    }

    // MARK: scan

    static func scan(projectRoot: URL) -> [Item] {
        let root = projectRoot.standardizedFileURL
        var items = base(root, scope: .project, claudeDir: root.appendingPathComponent(".claude"), extraFiles: ["CLAUDE.md", "CLAUDE.local.md"])
        items += base(home.deletingLastPathComponent(), scope: .global, claudeDir: home, extraFiles: [])
        let memDir = home.appendingPathComponent("projects/\(ClaudeData.projectDirName(for: root.path))/memory")
        for f in sortedNames(memDir) where f.hasSuffix(".md") || f.hasSuffix(".md" + disabledSuffix) {
            items.append(make(.memory, .memory, f, memDir.appendingPathComponent(f), container: nil))
        }
        return items
    }

    /// `claudeDir` is `<project>/.claude` or `~/.claude`; `extraFiles` are instruction files that sit beside it.
    private static func base(_ dir: URL, scope: Scope, claudeDir: URL, extraFiles: [String]) -> [Item] {
        var out: [Item] = []
        for n in extraFiles where exists(dir.appendingPathComponent(n)) || exists(dir.appendingPathComponent(n + disabledSuffix)) {
            out.append(make(scope, .instructions, n, dir.appendingPathComponent(n), container: nil))
        }
        for n in ["CLAUDE.md"] where exists(claudeDir.appendingPathComponent(n)) || exists(claudeDir.appendingPathComponent(n + disabledSuffix)) {
            out.append(make(scope, .instructions, scope == .project ? ".claude/" + n : n, claudeDir.appendingPathComponent(n), container: nil))
        }
        let rules = claudeDir.appendingPathComponent("rules")
        if let e = FileManager.default.enumerator(at: rules, includingPropertiesForKeys: [.isRegularFileKey]) {
            var found: [URL] = []
            for case let u as URL in e where u.lastPathComponent.hasSuffix(".md") || u.lastPathComponent.hasSuffix(".md" + disabledSuffix) { found.append(u) }
            let prefix = rules.resolvingSymlinksInPath().path.count + 1       // the enumerator may report the symlink-resolved path
            for u in found.sorted(by: { $0.path < $1.path }) {
                out.append(make(scope, .rule, "rules/" + String(u.resolvingSymlinksInPath().path.dropFirst(prefix)), u, container: nil))
            }
        }
        let skills = claudeDir.appendingPathComponent("skills")
        for n in sortedNames(skills) where !n.hasPrefix(".") {
            let folder = skills.appendingPathComponent(n)
            for f in ["SKILL.md", "SKILL.md" + disabledSuffix] where exists(folder.appendingPathComponent(f)) {
                out.append(make(scope, .skill, "skills/" + n, folder.appendingPathComponent(f), container: folder)); break
            }
        }
        let commands = claudeDir.appendingPathComponent("commands")
        for n in sortedNames(commands) where n.hasSuffix(".md") || n.hasSuffix(".md" + disabledSuffix) {
            out.append(make(scope, .command, "commands/" + n, commands.appendingPathComponent(n), container: nil))
        }
        return out
    }

    private static func make(_ scope: Scope, _ kind: Kind, _ title: String, _ file: URL, container: URL?) -> Item {
        let v = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let disabled = file.lastPathComponent.hasSuffix(disabledSuffix)
        let shown = disabled && title.hasSuffix(disabledSuffix) ? String(title.dropLast(disabledSuffix.count)) : title
        return Item(scope: scope, kind: kind, title: shown, file: file, container: container ?? file, disabled: disabled,
                    modified: v?.contentModificationDate ?? .distantPast, bytes: Int64(v?.fileSize ?? 0))
    }

    private static func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }
    private static func sortedNames(_ dir: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() }

    static func fingerprint(_ item: Item) -> String { "\(Int(item.modified.timeIntervalSince1970 * 1000)):\(item.bytes)" }

    // MARK: last-reviewed store

    struct Seen: Codable { var fp: String; var text: String? }
    struct Store: Codable {
        var projects: [String: Double] = [:]       // project path -> when its existing files were taken as already seen
        var files: [String: Seen] = [:]            // file path -> what was last looked at
    }

    static func loadStore() -> Store {
        guard let d = try? Data(contentsOf: stateFile), let s = try? JSONDecoder().decode(Store.self, from: d) else { return Store() }
        return s
    }
    static func saveStore(_ s: Store) {
        try? FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(s) { try? d.write(to: stateFile, options: .atomic) }
    }

    /// Records the item as looked at (its current fingerprint and text).
    static func markSeen(_ item: Item, text: String? = nil, in store: inout Store) {
        let t = text ?? (try? String(contentsOf: item.file, encoding: .utf8))
        store.files[item.key] = Seen(fp: fingerprint(item), text: (t?.utf8.count ?? 0) <= maxStoredBytes ? t : nil)
    }

    /// First time a project is opened here everything already on disk counts as seen, so only later additions get badges.
    static func seedIfNeeded(projectRoot: URL, items: [Item], store: inout Store) {
        let key = projectRoot.standardizedFileURL.path
        guard store.projects[key] == nil else { return }
        store.projects[key] = Date().timeIntervalSince1970
        for i in items where store.files[i.key] == nil { markSeen(i, in: &store) }
    }

    static func status(_ item: Item, in store: Store) -> Status {
        guard let s = store.files[item.key] else { return .new }
        return s.fp == fingerprint(item) ? .seen : .changed
    }

    static func counts(_ items: [Item], in store: Store) -> [Scope: Int] {
        var c: [Scope: Int] = [:]
        for i in items where status(i, in: store) != .seen { c[i.scope, default: 0] += 1 }
        return c
    }

    // MARK: diff against what was last seen

    struct DiffLine: Equatable { enum Kind { case same, added, removed }; let kind: Kind; let text: String }

    /// Changed lines with up to `context` unchanged lines around them.
    static func diff(old: String, new: String, context: Int = 2) -> [DiffLine] {
        let rows = DiffEngine.rows(old: old, new: new)
        var lines: [DiffLine] = []
        for r in rows {
            switch r.kind {
            case .equal: lines.append(DiffLine(kind: .same, text: trimNL(r.right ?? "")))
            case .added: lines.append(DiffLine(kind: .added, text: trimNL(r.right ?? "")))
            case .removed: lines.append(DiffLine(kind: .removed, text: trimNL(r.left ?? "")))
            case .changed:
                if let l = r.left { lines.append(DiffLine(kind: .removed, text: trimNL(l))) }
                if let n = r.right { lines.append(DiffLine(kind: .added, text: trimNL(n))) }
            }
        }
        var keep = [Bool](repeating: false, count: lines.count)
        for (i, l) in lines.enumerated() where l.kind != .same { for j in max(0, i - context)...min(lines.count - 1, i + context) { keep[j] = true } }
        var out: [DiffLine] = []
        for (i, l) in lines.enumerated() {
            if keep[i] { out.append(l) } else if out.last?.text != "…" || out.last?.kind != .same { out.append(DiffLine(kind: .same, text: "…")) }
        }
        return out
    }
    private static func trimNL(_ s: String) -> String { s.hasSuffix("\n") ? String(s.dropLast()) : s }

    // MARK: actions

    enum Creatable { case rule, skill }

    /// Creates a rule or skill in the project or global scope. Returns the file to edit.
    static func create(_ what: Creatable, named raw: String, scope: Scope, projectRoot: URL) throws -> URL {
        let slug = raw.trimmingCharacters(in: .whitespaces).lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        guard !slug.isEmpty, scope != .memory else { throw NSError(domain: "RulesSkills", code: 1, userInfo: [NSLocalizedDescriptionKey: "Give it a name made of letters or digits."]) }
        let claude = scope == .project ? projectRoot.appendingPathComponent(".claude") : home
        let fm = FileManager.default
        let url: URL, text: String
        switch what {
        case .rule:
            url = claude.appendingPathComponent("rules/\(slug).md")
            text = "# \(raw.trimmingCharacters(in: .whitespaces))\n\n"
        case .skill:
            url = claude.appendingPathComponent("skills/\(slug)/SKILL.md")
            text = "---\nname: \(slug)\ndescription: Say when Claude should use this skill.\n---\n\n"
        }
        guard !fm.fileExists(atPath: url.path) else { throw NSError(domain: "RulesSkills", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(slug) already exists."]) }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Claude ignores a file that does not end in `.md`, so disabling renames `x.md` to `x.md.disabled` (SKILL.md inside a skill).
    static func setDisabled(_ item: Item, _ disabled: Bool) throws -> URL {
        guard item.disabled != disabled else { return item.file }
        let name = item.file.lastPathComponent
        let new = item.file.deletingLastPathComponent().appendingPathComponent(disabled ? name + disabledSuffix : String(name.dropLast(disabledSuffix.count)))
        try FileManager.default.moveItem(at: item.file, to: new)
        return new
    }

    static func trash(_ item: Item) throws { try ClaudeData.trasher(item.container) }

    /// Rules, skills and commands can move between the project and global scope. Returns the new location of the edited file.
    static func move(_ item: Item, to scope: Scope, projectRoot: URL) throws -> URL {
        guard item.scope != scope, scope != .memory, item.scope != .memory, [.rule, .skill, .command].contains(item.kind) else {
            throw NSError(domain: "RulesSkills", code: 3, userInfo: [NSLocalizedDescriptionKey: "This item cannot be moved there."])
        }
        let claude = scope == .project ? projectRoot.appendingPathComponent(".claude") : home
        let dest = claude.appendingPathComponent(item.title)          // title is rules/x.md, skills/x, commands/x.md
        let target = item.kind != .skill && item.disabled ? dest.deletingLastPathComponent().appendingPathComponent(dest.lastPathComponent + disabledSuffix) : dest
        guard !FileManager.default.fileExists(atPath: target.path) else { throw NSError(domain: "RulesSkills", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(item.title) already exists in \(scope.title)."]) }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: item.container, to: target)
        return item.kind == .skill ? target.appendingPathComponent(item.file.lastPathComponent) : target
    }
}
