import Foundation

/// CE_SELFTEST: Rules & Skills (scan of a fake ~/.claude and project, first-open seeding, new/changed badges, diff, create, disable, move, trash).
enum SelfTestRulesSkills {
    static func run() {
        func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("ce-rules-\(ProcessInfo.processInfo.processIdentifier)")
        try? fm.removeItem(at: base)
        defer { try? fm.removeItem(at: base) }
        let savedHome = ClaudeData.home, savedTrasher = ClaudeData.trasher, savedState = RulesSkills.stateFile
        defer { ClaudeData.home = savedHome; ClaudeData.trasher = savedTrasher; RulesSkills.stateFile = savedState }
        ClaudeData.home = base.appendingPathComponent("home/.claude")
        RulesSkills.stateFile = base.appendingPathComponent("state/rules-review.json")
        let trash = base.appendingPathComponent("trash")
        try? fm.createDirectory(at: trash, withIntermediateDirectories: true)
        ClaudeData.trasher = { try fm.moveItem(at: $0, to: trash.appendingPathComponent(UUID().uuidString)) }

        let project = base.appendingPathComponent("demo-shop")
        func write(_ path: String, _ text: String) {
            let u = path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
            try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: u, atomically: true, encoding: .utf8)
        }
        write("demo-shop/CLAUDE.md", "# Shop\nUse Pint.\n")
        write("demo-shop/.claude/rules/api-style.md", "# API style\nReturn resources.\n")
        write("demo-shop/.claude/rules/sub/deep.md", "deep\n")
        write("demo-shop/.claude/skills/deploy/SKILL.md", "---\nname: deploy\n---\nShip it.\n")
        write("demo-shop/.claude/commands/fix.md", "fix\n")
        write("home/.claude/CLAUDE.md", "global\n")
        write("home/.claude/skills/graphify/SKILL.md", "g\n")
        let mem = "home/.claude/projects/\(ClaudeData.projectDirName(for: project.path))/memory"
        write(mem + "/MEMORY.md", "- note\n")
        write(mem + "/user.md", "user\n")

        var items = RulesSkills.scan(projectRoot: project)
        let titles = { (s: RulesSkills.Scope) in items.filter { $0.scope == s }.map(\.title) }
        check("rules: project lists CLAUDE.md, nested rules, skills and commands", titles(.project) == ["CLAUDE.md", "rules/api-style.md", "rules/sub/deep.md", "skills/deploy", "commands/fix.md"])
        check("rules: global and memory are listed apart", titles(.global) == ["CLAUDE.md", "skills/graphify"] && titles(.memory) == ["MEMORY.md", "user.md"])
        check("rules: a skill edits its SKILL.md and moves as a folder", items.first { $0.title == "skills/deploy" }.map { $0.file.lastPathComponent == "SKILL.md" && $0.container.lastPathComponent == "deploy" } == true)

        var store = RulesSkills.loadStore()
        check("rules: nothing is known on a fresh state", RulesSkills.counts(items, in: store).isEmpty == false)
        RulesSkills.seedIfNeeded(projectRoot: project, items: items, store: &store)
        check("rules: first open takes everything already on disk as seen", RulesSkills.counts(items, in: store).isEmpty)
        RulesSkills.saveStore(store)
        check("rules: the store survives a reload", RulesSkills.loadStore().files.count == store.files.count && RulesSkills.loadStore().projects.count == 1)

        // Claude adds a rule and edits another
        _ = try? RulesSkills.create(.rule, named: "Testing Rules!", scope: .project, projectRoot: project)
        let api = project.appendingPathComponent(".claude/rules/api-style.md")
        try? "# API style\nReturn resources.\nAlways paginate.\n".write(to: api, atomically: true, encoding: .utf8)
        items = RulesSkills.scan(projectRoot: project)
        store = RulesSkills.loadStore()
        let created = items.first { $0.title == "rules/testing-rules.md" }
        check("rules: create slugs the name into .claude/rules", created != nil)
        check("rules: an added file is new", created.map { RulesSkills.status($0, in: store) == .new } == true)
        let edited = items.first { $0.title == "rules/api-style.md" }!
        check("rules: an edited file is changed", RulesSkills.status(edited, in: store) == .changed)
        check("rules: counts group by scope", RulesSkills.counts(items, in: store) == [.project: 2])
        let d = RulesSkills.diff(old: store.files[edited.key]?.text ?? "", new: (try? String(contentsOf: api, encoding: .utf8)) ?? "")
        check("rules: the diff marks the added line", d.contains(RulesSkills.DiffLine(kind: .added, text: "Always paginate.")) && !d.contains { $0.kind == .removed })
        RulesSkills.markSeen(edited, in: &store)
        check("rules: marking seen clears the badge", RulesSkills.status(edited, in: store) == .seen)
        check("rules: creating the same name again is refused", (try? RulesSkills.create(.rule, named: "testing rules", scope: .project, projectRoot: project)) == nil)
        check("rules: an empty name is refused", (try? RulesSkills.create(.skill, named: "  ! ", scope: .project, projectRoot: project)) == nil)

        // skills, disable, move, trash
        let skill = try? RulesSkills.create(.skill, named: "Release Notes", scope: .project, projectRoot: project)
        check("rules: a new skill has frontmatter in its own folder", (try? String(contentsOf: skill!, encoding: .utf8))?.hasPrefix("---\nname: release-notes") == true && skill?.deletingLastPathComponent().lastPathComponent == "release-notes")
        items = RulesSkills.scan(projectRoot: project)
        let rule = items.first { $0.title == "rules/api-style.md" }!
        let off = try? RulesSkills.setDisabled(rule, true)
        check("rules: disabling renames to .md.disabled", off?.lastPathComponent == "api-style.md.disabled" && !fm.fileExists(atPath: api.path))
        items = RulesSkills.scan(projectRoot: project)
        let dis = items.first { $0.title == "rules/api-style.md" }
        check("rules: a disabled rule is listed under its normal name, flagged", dis?.disabled == true)
        _ = try? RulesSkills.setDisabled(dis!, false)
        check("rules: enabling restores it", fm.fileExists(atPath: api.path))

        let skillItem = RulesSkills.scan(projectRoot: project).first { $0.title == "skills/release-notes" }!
        let moved = try? RulesSkills.move(skillItem, to: .global, projectRoot: project)
        check("rules: a skill moves to global as a folder", moved.map { fm.fileExists(atPath: $0.path) && $0.path.contains("home/.claude/skills/release-notes/SKILL.md") } == true && !fm.fileExists(atPath: skillItem.container.path))
        let ruleItem = RulesSkills.scan(projectRoot: project).first { $0.title == "rules/sub/deep.md" }!
        let moved2 = try? RulesSkills.move(ruleItem, to: .global, projectRoot: project)
        check("rules: a nested rule keeps its path when moved", moved2?.path.hasSuffix("home/.claude/rules/sub/deep.md") == true)
        let claudeMd = RulesSkills.scan(projectRoot: project).first { $0.title == "CLAUDE.md" && $0.scope == .project }!
        check("rules: CLAUDE.md and memory cannot be moved", (try? RulesSkills.move(claudeMd, to: .global, projectRoot: project)) == nil)
        let cmd = RulesSkills.scan(projectRoot: project).first { $0.title == "commands/fix.md" }!
        try? RulesSkills.trash(cmd)
        check("rules: trash goes through the trasher", !fm.fileExists(atPath: cmd.file.path) && (try? fm.contentsOfDirectory(atPath: trash.path).count) == 1)

        // the menu dot: unseeded project -> 0, seeded -> counts additions, title carries the count
        let other = base.appendingPathComponent("other-proj")
        write("other-proj/.claude/rules/a.md", "a\n")
        check("rules: a never-seeded project shows no dot", RulesSkills.pendingCount(projectRoot: other) == 0)
        var st2 = RulesSkills.loadStore()
        RulesSkills.seedIfNeeded(projectRoot: other, items: RulesSkills.scan(projectRoot: other), store: &st2)
        RulesSkills.saveStore(st2)
        check("rules: a seeded, untouched project shows no dot", RulesSkills.pendingCount(projectRoot: other) == 0)
        write("other-proj/.claude/rules/b.md", "b\n")
        check("rules: an addition after seeding counts", RulesSkills.pendingCount(projectRoot: other) == 1)
        check("rules: menu title carries the count", RulesSkills.menuTitle(pending: 0) == "Rules & Skills…" && RulesSkills.menuTitle(pending: 2).hasSuffix("● 2 new"))

        if let out = AppEnv.value("CE_RULES_PNG") {
            // a fresh project state so the badges show: seen state, then Claude's additions
            try? fm.removeItem(at: RulesSkills.stateFile)
            var st = RulesSkills.Store()
            let cur = RulesSkills.scan(projectRoot: project)
            RulesSkills.seedIfNeeded(projectRoot: project, items: cur, store: &st)
            RulesSkills.saveStore(st)
            _ = try? RulesSkills.create(.rule, named: "queue-jobs", scope: .project, projectRoot: project)
            try? "# Shop\nUse Pint.\nNever commit .env.\n".write(to: project.appendingPathComponent("CLAUDE.md"), atomically: true, encoding: .utf8)
            RulesSkillsWindowController.render(root: project, to: out)
        }
    }
}
