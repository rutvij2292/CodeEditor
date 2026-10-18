import AppKit

/// CE_SELFTEST: plan discovery, progress, task toggling, path references, snapshots / diff, review comments, preview clicks.
enum SelfTestPlans {
    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) { SelfTest.check(name, ok()) }

    static func run(w: ProjectWindow) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("ce-plans-\(getpid())")
        try? fm.removeItem(at: base)
        defer { try? fm.removeItem(at: base) }
        textChecks()
        let project = base.appendingPathComponent("acme-shop")
        let home = base.appendingPathComponent("home")
        discoveryChecks(project: project, home: home)
        referenceChecks(project: project)
        snapshotChecks(dir: base.appendingPathComponent("snaps"))
        uiChecks(w: w, project: project)
        storeChecks(project: project)
    }

    private static func write(_ text: String, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
    }

    static let samplePlan = """
    # Checkout rewrite

    Touches `app/Http/Cart.php:12` and src/pay.ts.

    ## Steps

    - [x] Write the migration
    - [ ] Update `Cart.php`
      - [ ] nested task
    - not a task
    * [X] star done

    ```md
    - [ ] inside a fence
    ```

    ## Risks

    Prices may drift.
    """

    private static func textChecks() {
        let p = PlanText.progress(samplePlan)
        check("plan progress counts tasks outside fences (2/4)", p.done == 2 && p.total == 4)
        check("plan progress CRLF same", PlanText.progress(samplePlan.replacingOccurrences(of: "\n", with: "\r\n")) == (2, 4))
        check("plan title is the first H1", PlanText.title(samplePlan) == "Checkout rewrite")
        check("plan title ignores H1 in fence", PlanText.title("```\n# no\n```\n# yes\n") == "yes")
        check("task states", PlanText.taskState("- [ ] a") == false && PlanText.taskState("  * [x] b") == true
              && PlanText.taskState("- [] c") == nil && PlanText.taskState("[ ] d") == nil && PlanText.taskState("- [x]nospace") == nil)

        // The parser's item.line is what the rendered marker carries: toggling by it must hit the right line.
        var taskLines: [(Int, Bool)] = []
        func walk(_ blocks: [MDBlock]) {
            for b in blocks {
                if case .list(_, _, let items, _) = b {
                    for it in items { if let t = it.task { taskLines.append((it.line, t)) }; walk(it.blocks) }
                }
            }
        }
        walk(MarkdownParser.parse(samplePlan))
        check("parser exposes 4 task lines", taskLines.count == 4)
        if let second = taskLines.dropFirst().first, let out = PlanText.toggleTask(in: samplePlan, line: second.0) {
            check("toggle checks the right item", out.contains("- [x] Update `Cart.php`") && out.contains("- [x] Write the migration"))
            check("toggle changes only that byte", out.count == samplePlan.count && zip(out, samplePlan).filter { $0 != $1 }.count == 1)
            check("toggle again restores", PlanText.toggleTask(in: out, line: second.0) == samplePlan)
        } else { check("toggle checks the right item", false) }
        if let first = taskLines.first, let out = PlanText.toggleTask(in: samplePlan, line: first.0) {
            check("toggle unchecks [x]", out.contains("- [ ] Write the migration"))
        } else { check("toggle unchecks [x]", false) }
        let crlf = samplePlan.replacingOccurrences(of: "\n", with: "\r\n")
        if let line = taskLines.dropFirst().first?.0, let out = PlanText.toggleTask(in: crlf, line: line) {
            check("CRLF toggle keeps every CRLF", out.components(separatedBy: "\r\n").count == crlf.components(separatedBy: "\r\n").count
                  && !out.replacingOccurrences(of: "\r\n", with: "").contains("\n") && out.contains("- [x] Update `Cart.php`\r\n"))
        } else { check("CRLF toggle keeps every CRLF", false) }
        check("toggle on a non-task line is nil", PlanText.toggleTask(in: samplePlan, line: 0) == nil)
        check("toggle past the end is nil", PlanText.toggleTask(in: samplePlan, line: 999) == nil)
        check("toggle with unicode before the line", PlanText.toggleTask(in: "# é ✓ title\n- [ ] x\n", line: 1) == "# é ✓ title\n- [x] x\n")

        let hs = PlanText.headings(samplePlan)
        check("headings: 3 in order", hs.map(\.text) == ["Checkout rewrite", "Steps", "Risks"] && hs.map(\.level) == [1, 2, 2])
        check("heading at or before", PlanText.heading(atOrBefore: 8, in: hs)?.text == "Steps" && PlanText.heading(atOrBefore: 0, in: hs)?.text == "Checkout rewrite")

        // Review comments.
        let r1 = PlanText.insertReview(in: "# T\n\n## A\n\nbody\n", headingLine: 2, comment: "needs a rollback step")
        check("review inserted under heading", r1 == "# T\n\n## A\n\n> **Review:** needs a rollback step\n\nbody\n")
        let r2 = PlanText.insertReview(in: "# T\r\n## A\r\nbody\r\n", headingLine: 1, comment: "why?\nreally")
        check("review keeps CRLF and flattens newlines", r2 == "# T\r\n## A\r\n\r\n> **Review:** why? really\r\n\r\nbody\r\n")
        check("review on last heading without newline", PlanText.insertReview(in: "# T", headingLine: 0, comment: "x") == "# T\n\n> **Review:** x\n")
        check("empty review rejected", PlanText.insertReview(in: "# T\n", headingLine: 0, comment: "  ") == nil)
        let found = PlanText.reviewComments(r1 ?? "")
        check("review comments are listed with their section", found.count == 1 && found[0].heading == "A" && found[0].comment == "needs a rollback step")
    }

    private static func discoveryChecks(project: URL, home: URL) {
        write(samplePlan, to: project.appendingPathComponent("PLAN.md"))
        write("# Docs plan\n- [x] a\n- [x] b\n", to: project.appendingPathComponent("docs/plans/auth/auth.md"))
        write("# Spec\n", to: project.appendingPathComponent("docs/superpowers/specs/2026-a/design.md"))
        write("# Not a plan\n", to: project.appendingPathComponent("docs/superpowers/notes/x.md"))
        write("# Todo\n- [ ] one\n", to: project.appendingPathComponent("tasks/todo.md"))
        write("# Claude local\n", to: project.appendingPathComponent(".claude/plans/local.md"))
        write("# README\n", to: project.appendingPathComponent("README.md"))
        write("# Mentions it\nWork in \(project.path)/app\n", to: home.appendingPathComponent(".claude/plans/lazy-red-fox.md"))
        write("# By name\nthe acme-shop checkout\n", to: home.appendingPathComponent(".claude/plans/calm-blue-owl.md"))
        write("# Other project\nunrelated\n", to: home.appendingPathComponent(".claude/plans/other-thing.md"))
        // Order by modification time.
        let old = Date(timeIntervalSinceNow: -86400 * 3)
        try? FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: project.appendingPathComponent("PLAN.md").path)

        let store = PlanStore()
        store.home = home.path
        let plans = store.plans(root: project)
        let names = plans.map { $0.display }
        check("discovers PLAN.md, docs/plans, superpowers specs, tasks/todo, .claude/plans",
              ["PLAN.md", "docs/plans/auth/auth.md", "docs/superpowers/specs/2026-a/design.md", "tasks/todo.md", ".claude/plans/local.md"].allSatisfy(names.contains))
        check("ignores README and non plan/spec superpowers files", !names.contains("README.md") && !names.contains("docs/superpowers/notes/x.md"))
        check("global plans only when they mention the project (path or folder name)",
              names.contains("~/.claude/plans/lazy-red-fox.md") && names.contains("~/.claude/plans/calm-blue-owl.md") && !names.contains("~/.claude/plans/other-thing.md"))
        check("show all includes unrelated global plans", store.plans(root: project, showAll: true).contains { $0.display == "~/.claude/plans/other-thing.md" })
        check("sorted newest first", plans.map(\.modified) == plans.map(\.modified).sorted(by: >) && plans.last?.display == "PLAN.md")
        let planMD = plans.first { $0.display == "PLAN.md" }
        check("plan carries title and progress", planMD?.title == "Checkout rewrite" && planMD?.done == 2 && planMD?.total == 4)
        check("title falls back to the file name", store.plans(root: project, showAll: true).contains { $0.url.lastPathComponent == "local.md" && $0.title == "Claude local" })
        check("isPlan recognises plan locations only",
              store.isPlan(path: project.appendingPathComponent("docs/plans/x/y.md").path, root: project)
              && store.isPlan(path: home.path + "/.claude/plans/z.md", root: project)
              && !store.isPlan(path: project.appendingPathComponent("README.md").path, root: project)
              && !store.isPlan(path: project.appendingPathComponent("docs/superpowers/notes/x.md").path, root: project))
        check("age text", PlanStore.age(Date(timeIntervalSinceNow: -30)) == "just now" && PlanStore.age(Date(timeIntervalSinceNow: -300)) == "5m ago"
              && PlanStore.age(Date(timeIntervalSinceNow: -7300)) == "2h ago" && PlanStore.age(Date(timeIntervalSinceNow: -86400 * 3)) == "3d ago")
    }

    private static func referenceChecks(project: URL) {
        write("<?php\n", to: project.appendingPathComponent("app/Http/Cart.php"))
        write("export {}\n", to: project.appendingPathComponent("src/pay.ts"))
        let text = "See `app/Http/Cart.php:12` and src/pay.ts, also https://example.com/a/b.html and ./src/pay.ts:7:3 plus `missing/none.php:1`."
        let refs = PlanPaths.references(in: text)
        check("references: backticked path:line", refs.contains { $0.path == "app/Http/Cart.php" && $0.line == 12 })
        check("references: bare path", refs.contains { $0.path == "src/pay.ts" && $0.line == nil })
        check("references: path:line:col", refs.contains { $0.path == "./src/pay.ts" && $0.line == 7 })
        check("references: URLs are not file references", !refs.contains { $0.path.contains("example.com") || $0.path.hasSuffix("b.html") })
        let ns = text as NSString
        check("reference range covers path:line", refs.first.map { ns.substring(with: $0.range) } == "app/Http/Cart.php:12")
        let doc = project.appendingPathComponent("docs/plans/x.md")
        check("resolve relative to project root", PlanPaths.resolve("app/Http/Cart.php", root: project, base: doc)?.lastPathComponent == "Cart.php")
        check("resolve ./ relative", PlanPaths.resolve("./src/pay.ts", root: project, base: doc)?.lastPathComponent == "pay.ts")
        check("resolve relative to the document folder", PlanPaths.resolve("auth/auth.md", root: project, base: doc)?.lastPathComponent == "auth.md")
        check("resolve absolute", PlanPaths.resolve(project.appendingPathComponent("src/pay.ts").path, root: project, base: nil) != nil)
        check("missing files do not resolve", PlanPaths.resolve("missing/none.php", root: project, base: doc) == nil)
        check("directories do not resolve", PlanPaths.resolve("src/pay.ts/..", root: project, base: doc) == nil && PlanPaths.resolve("app", root: project, base: doc) == nil)
        let split = PlanPaths.split("/a/b.php:42")
        check("planPath value split", split.path == "/a/b.php" && split.line == 42 && PlanPaths.split("/a/b.php").line == nil)
        let marked = NSMutableAttributedString(string: text)
        PlanPaths.annotate(marked, root: project, base: doc)
        var hits = 0
        marked.enumerateAttribute(.planPath, in: NSRange(location: 0, length: marked.length)) { v, _, _ in if v != nil { hits += 1 } }
        check("annotate marks only existing references (3)", hits == 3)
    }

    private static func snapshotChecks(dir: URL) {
        PlanReview.directory = dir
        let url = URL(fileURLWithPath: "/tmp/ce-plan-\(getpid())/p.md")
        check("no baseline before first view", PlanReview.baseline(for: url) == nil && PlanReview.status(of: url, currentText: "x") == .unseen)
        let v1 = "# Plan\n\n## A\n\none\ntwo\nthree\nfour\nfive\nsix\nseven\n\n## B\n\nbeta\n"
        PlanReview.record(v1, for: url)
        check("baseline round-trips (compressed)", PlanReview.baseline(for: url) == v1)
        check("unchanged status", PlanReview.status(of: url, currentText: v1) == .unchanged)
        check("CRLF-only difference is unchanged", PlanReview.status(of: url, currentText: v1.replacingOccurrences(of: "\n", with: "\r\n")) == .unchanged)
        let v2 = v1.replacingOccurrences(of: "beta", with: "beta v2").replacingOccurrences(of: "four\n", with: "four\nfour-and-a-half\n")
        check("changed status", PlanReview.status(of: url, currentText: v2) == .changed)
        let diff = PlanReview.unifiedDiff(old: v1, new: v2)
        let headers = diff.filter { $0.kind == .header }.map(\.text)
        check("diff has two hunks with section names", headers.count == 2 && headers[0].hasSuffix("A") && headers[1].hasSuffix("B"))
        check("diff marks added and changed lines", diff.contains { $0.kind == .added && $0.text == "four-and-a-half" }
              && diff.contains { $0.kind == .removed && $0.text == "beta" } && diff.contains { $0.kind == .added && $0.text == "beta v2" })
        check("diff keeps context but not far lines", diff.contains { $0.kind == .context && $0.text == "three" } && !diff.contains { $0.text == "one" })
        check("no diff when equal", PlanReview.unifiedDiff(old: v1, new: v1).isEmpty)
        check("diff rendered with colour backgrounds", PlanReview.attributed(diff).length > 10)

        let big = String(repeating: "x", count: PlanReview.maxBytes + 10)
        let bigURL = URL(fileURLWithPath: "/tmp/ce-plan-\(getpid())/big.md")
        PlanReview.record(big, for: bigURL)
        check("oversized snapshots are not stored", PlanReview.baseline(for: bigURL) == nil)
        for i in 0..<(PlanReview.maxSnapshots + 15) { PlanReview.record("# \(i)\n", for: URL(fileURLWithPath: "/tmp/ce-plan-\(getpid())/n\(i).md")) }
        let count = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".snap") }.count
        check("snapshot count is capped", count <= PlanReview.maxSnapshots)
        PlanReview.forget(url)
        check("forget removes a snapshot", PlanReview.baseline(for: url) == nil)
    }

    private static func uiChecks(w: ProjectWindow, project: URL) {
        // Rendered preview: marker click toggles, Cmd-click opens references, plain click on text does nothing.
        let planURL = project.appendingPathComponent("PLAN.md")
        let preview = MarkdownPreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 600))
        preview.fileURL = planURL
        preview.projectRoot = project
        preview.show(blocks: MarkdownParser.parse(samplePlan))
        guard let tv = preview.textView as? PlanTextView, let storage = tv.textStorage else { check("preview uses PlanTextView", false); return }
        var markers: [(Int, Int)] = []   // (rendered index, source line)
        storage.enumerateAttribute(.mdTaskLine, in: NSRange(location: 0, length: storage.length)) { v, r, _ in if let l = v as? Int { markers.append((r.location, l)) } }
        check("rendered task markers carry source lines (4)", markers.count == 4)
        var toggled: [Int] = [], opened: [String] = []
        tv.onToggleTask = { toggled.append($0) }
        tv.onOpenReference = { opened.append($0) }
        if let m = markers.dropFirst().first {
            check("click on a task marker toggles", tv.activate(at: m.0, command: false) && toggled == [m.1])
        } else { check("click on a task marker toggles", false) }
        let textIdx = (storage.string as NSString).range(of: "Write the migration").location
        check("click on task text does not toggle", !tv.activate(at: textIdx, command: false) && toggled.count == 1)
        let refIdx = (storage.string as NSString).range(of: "app/Http/Cart.php").location
        check("plain click on a reference does not open it", refIdx != NSNotFound && !tv.activate(at: refIdx, command: false) && opened.isEmpty)
        check("Cmd-click on a reference opens path and line", tv.activate(at: refIdx, command: true) && opened.first?.hasSuffix("app/Http/Cart.php:12") == true)
        let missingIdx = (storage.string as NSString).range(of: "src/pay.ts").location
        check("Cmd-click on an existing bare path opens it", tv.activate(at: missingIdx, command: true) && opened.count == 2)
        check("source line lookup for review comments", { () -> Bool in
            tv.sourceLine = { idx in preview.lineMap.last(where: { $0.loc <= idx })?.line }
            let steps = (storage.string as NSString).range(of: "Risks").location
            return tv.sourceLine?(steps) == 16
        }())

        // End to end on a real tab: toggling goes through the buffer as an undoable edit and keeps CRLF on save.
        let file = project.appendingPathComponent("docs/e2e.md")
        write("# E2E\r\n- [ ] first\r\n- [x] second\r\n", to: file)
        w.open(file)
        guard let tab = w.current, tab.url.standardizedFileURL == file.standardizedFileURL else { check("e2e plan tab opened", false); return }
        let host = MarkdownPreviewView()
        PlanSupport.attach(host, tab: tab)
        guard let htv = host.textView as? PlanTextView else { check("attach installs callbacks", false); return }
        htv.onToggleTask?(1)
        check("toggle through the tab edits the buffer", tab.textView.string == "# E2E\r\n- [x] first\r\n- [x] second\r\n")
        tab.textView.undoManager?.undo()
        check("task toggle is undoable", tab.textView.string == "# E2E\r\n- [ ] first\r\n- [x] second\r\n")
        htv.onToggleTask?(2)
        tab.save()
        let disk = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        check("saved plan keeps CRLF line endings", disk == "# E2E\r\n- [ ] first\r\n- [ ] second\r\n")
        let heading = PlanText.heading(atOrBefore: 1, in: PlanText.headings(tab.textView.string))
        if let heading, let text = PlanText.insertReview(in: tab.textView.string, headingLine: heading.line, comment: "check this") {
            tab.replaceText(text, actionName: "Add Review Comment")
            check("review comment lands in the buffer", tab.textView.string.contains("> **Review:** check this"))
        } else { check("review comment lands in the buffer", false) }
        w.close(file.standardizedFileURL.path)

        // File Structure outline for Markdown.
        let outline = FileStructure.items(text: samplePlan, fileExtension: "md", currentLine: 9, goTo: { _ in })
        check("File Structure lists markdown headings", outline.items.count == 3 && outline.items[1].title.hasSuffix("Steps") && outline.preselect == 1)
        var jumped = 0
        FileStructure.items(text: samplePlan, fileExtension: "md", currentLine: 1, goTo: { jumped = $0 }).items[2].run()
        check("outline jump goes to the heading line", jumped == 17)

        // Picker rows and badges.
        let plans = PlanStore().plans(root: project)
        let rows = PlansPicker.items(plans: plans, showAll: false, status: { $0.display == "PLAN.md" ? .changed : .unchanged },
                                     recent: { $0.display == "PLAN.md" }, open: { _ in }, showChanges: { _ in }, toggleShowAll: {})
        check("picker row shows badge, progress, age and path", rows.contains { $0.title.hasPrefix("Checkout rewrite") && $0.title.contains("● UPDATED") && $0.detail.contains("2/4 done") && $0.detail.contains("PLAN.md") })
        check("picker offers changes row for changed plans and a show-all toggle",
              rows.contains { $0.title.hasPrefix("Changes since last viewed") } && rows.last?.title.hasPrefix("Show all") == true)
        check("badge rules", PlansPicker.badge(status: .unseen, recent: false, modified: Date(timeIntervalSinceNow: -86400 * 9)).isEmpty
              && PlansPicker.badge(status: .unseen, recent: false, modified: Date()) == "NEW  " && PlansPicker.badge(status: .changed, recent: false, modified: Date()) == "CHANGED  ")
        check("menu has Plans item with a shortcut", SelfTest.shortcut("Plans…") == "⌥⌘P")
        check("menu has plan review items", SelfTest.shortcut("Add Plan Review Comment…") != "missing" && SelfTest.shortcut("Mark Plan as Reviewed") != "missing")
    }

    private static func storeChecks(project: URL) {
        let store = PlanStore()
        var notified: [String] = []
        let token = NotificationCenter.default.addObserver(forName: PlanStore.didChange, object: store, queue: nil) { n in
            notified += (n.userInfo?["paths"] as? [String]) ?? []
        }
        let planPath = project.appendingPathComponent("docs/plans/auth/auth.md").path
        store.noteChanges([planPath, project.appendingPathComponent("README.md").path, project.appendingPathComponent("a.swift").path], root: project)
        NotificationCenter.default.removeObserver(token)
        check("noteChanges reports only plan files", notified == [planPath])
        check("recently changed badge window", store.recentlyChanged(URL(fileURLWithPath: planPath))
              && !store.recentlyChanged(URL(fileURLWithPath: planPath), now: Date(timeIntervalSinceNow: 3600)) && !store.recentlyChanged(project.appendingPathComponent("PLAN.md")))
    }
}
