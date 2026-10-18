import AppKit

/// Preview text view for plans: click a ☐ / ☑ marker to toggle the task, Cmd-click a file reference to open it,
/// right-click for "Add Review Comment…". The logic lives in `activate` so it can be driven headlessly.
final class PlanTextView: NSTextView {
    var onToggleTask: ((Int) -> Void)?
    var onOpenReference: ((String) -> Void)?
    var onReviewComment: ((Int) -> Void)?       // rendered character index
    var sourceLine: ((Int) -> Int?)?            // rendered character index -> 0-based source line

    /// Character index under the point only when the point is really on that glyph (not the empty space after a line).
    func characterIndex(at p: NSPoint) -> Int? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let o = textContainerOrigin
        let pt = NSPoint(x: p.x - o.x, y: p.y - o.y)
        var fraction: CGFloat = 0
        let i = lm.characterIndex(for: pt, in: tc, fractionOfDistanceBetweenInsertionPoints: &fraction)
        guard i < storage.length else { return nil }
        let g = lm.glyphRange(forCharacterRange: NSRange(location: i, length: 1), actualCharacterRange: nil)
        return lm.boundingRect(forGlyphRange: g, in: tc).insetBy(dx: -3, dy: -3).contains(pt) ? i : nil
    }

    /// Handles a click on rendered character `index`; true when it was consumed.
    @discardableResult
    func activate(at index: Int, command: Bool) -> Bool {
        guard let storage = textStorage, index >= 0, index < storage.length else { return false }
        if let line = storage.attribute(.mdTaskLine, at: index, effectiveRange: nil) as? Int, onToggleTask != nil {
            onToggleTask?(line); return true
        }
        if command, let ref = storage.attribute(.planPath, at: index, effectiveRange: nil) as? String, onOpenReference != nil {
            onOpenReference?(ref); return true
        }
        return false
    }

    override func mouseDown(with event: NSEvent) {
        if let i = characterIndex(at: convert(event.locationInWindow, from: nil)),
           activate(at: i, command: event.modifierFlags.contains(.command)) { return }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let idx = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        if onReviewComment != nil, sourceLine?(idx) != nil {
            let item = NSMenuItem(title: "Add Review Comment…", action: #selector(addReviewComment(_:)), keyEquivalent: "")
            item.target = self
            item.tag = idx
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        return menu
    }

    @objc private func addReviewComment(_ sender: NSMenuItem) { onReviewComment?(sender.tag) }
}

/// Heading outline for Markdown files in the ⌘F12 File Structure popup.
enum PlanOutline {
    static func handles(_ ext: String) -> Bool { ["md", "markdown", "mkd", "mdx"].contains(ext.lowercased()) }

    static func items(text: String, currentLine: Int, goTo: @escaping (Int) -> Void) -> (items: [PickerItem], preselect: Int) {
        var preselect = 0
        var items: [PickerItem] = []
        for (i, h) in PlanText.headings(text).enumerated() {
            if h.line + 1 <= currentLine { preselect = i }
            let line = h.line + 1
            items.append(PickerItem(title: String(repeating: "    ", count: max(0, h.level - 1)) + h.text, detail: "H\(h.level)",
                                    symbol: h.level == 1 ? "number.square" : "text.alignleft", key: h.text) { goTo(line) })
        }
        return (items, preselect)
    }
}

enum PlansPicker {
    static func badge(status: PlanReview.Status, recent: Bool, modified: Date, now: Date = Date()) -> String {
        switch status {
        case .changed: return recent ? "● UPDATED  " : "CHANGED  "
        case .unseen: return now.timeIntervalSince(modified) < 86400 ? "NEW  " : ""
        case .unchanged: return ""
        }
    }

    static func progressText(_ p: PlanFile) -> String { p.total == 0 ? "no tasks" : "\(p.done)/\(p.total) done" }

    /// Rows for the Plans picker (newest first). `status` reports the review state of each plan.
    static func items(plans: [PlanFile], showAll: Bool, status: (PlanFile) -> PlanReview.Status, recent: (PlanFile) -> Bool,
                      open: @escaping (PlanFile) -> Void, showChanges: @escaping (PlanFile) -> Void,
                      toggleShowAll: @escaping () -> Void, now: Date = Date()) -> [PickerItem] {
        var rows: [PickerItem] = []
        var changes: [PickerItem] = []
        for p in plans {
            let st = status(p)
            let b = badge(status: st, recent: recent(p), modified: p.modified, now: now)
            let badgeText = b.trimmingCharacters(in: .whitespaces)
            rows.append(PickerItem(title: badgeText.isEmpty ? p.title : "\(p.title)   [\(badgeText)]", detail: "\(progressText(p)) · \(PlanStore.age(p.modified, now: now)) · \(p.display)",
                                   symbol: p.total > 0 && p.done == p.total ? "checkmark.circle" : "checklist",
                                   key: p.title + " " + p.display) { open(p) })
            if st == .changed {
                changes.append(PickerItem(title: "Changes since last viewed: \(p.title)", detail: p.display, symbol: "plusminus.circle",
                                          key: "changes diff " + p.title) { showChanges(p) })
            }
        }
        if rows.isEmpty { rows.append(PickerItem(title: "No plans found for this project", detail: "Looked in docs/plans, .claude/plans, PLAN.md, ~/.claude/plans",
                                                 symbol: "tray", key: "") { }) }
        rows += changes
        rows.append(PickerItem(title: showAll ? "Only plans for this project" : "Show all plans (including other projects)",
                               detail: "~/.claude/plans", symbol: "line.3.horizontal.decrease.circle", key: "show all toggle", run: toggleShowAll))
        return rows
    }
}

/// Menu target + wiring for plan features (viewer click handling, snapshots, review actions).
final class PlanSupport: NSObject, NSMenuItemValidation {
    static let shared = PlanSupport()
    private static var started = false
    private var showAllPlans = false

    private var window: ProjectWindow? { (NSApp.delegate as? AppDelegate)?.active }

    static func start() {
        guard !started else { return }
        started = true
        if !AppEnv.headless { PlanStore.shared.startWatching() }
        EditorEvents.onOpen { tab in
            guard ViewerKind.detect(tab.url) == .markdown, isPlan(tab.url), PlanReview.baseline(for: tab.url) == nil else { return }
            PlanReview.record(tab.textView.string, for: tab.url)
        }
        // The user's own saves are not "changes by an agent"; closing the tab counts as viewing it.
        EditorEvents.onSave { tab in if isPlan(tab.url), PlanReview.baseline(for: tab.url) != nil { PlanReview.record(tab.textView.string, for: tab.url) } }
        EditorEvents.onClose { tab in if isPlan(tab.url) { PlanReview.record(tab.textView.string, for: tab.url) } }
        NotificationCenter.default.addObserver(forName: PlanStore.didChange, object: nil, queue: .main) { note in
            guard let w = (NSApp.delegate as? AppDelegate)?.active, let path = (note.userInfo?["paths"] as? [String])?.first,
                  PlanStore.shared.isPlan(path: path, root: w.root) else { return }
            let url = URL(fileURLWithPath: path)
            if w.current?.url.standardizedFileURL == url.standardizedFileURL { return }
            w.statusBar.flash("Plan updated: \(url.deletingPathExtension().lastPathComponent)")
        }
    }

    static func isPlan(_ url: URL) -> Bool {
        PlanStore.shared.isPlan(path: url.standardizedFileURL.path, root: (NSApp.delegate as? AppDelegate)?.active?.root)
    }

    /// Hooks a Markdown preview up to its tab: task toggling, Cmd-click references, review comments.
    static func attach(_ m: MarkdownPreviewView, tab: EditorTab) {
        m.projectRoot = (NSApp.delegate as? AppDelegate)?.active?.root
        guard let tv = m.textView as? PlanTextView else { return }
        tv.onToggleTask = { [weak tab] line in
            guard let tab, !tab.isReadOnly, let text = PlanText.toggleTask(in: tab.textView.string, line: line) else { return }
            tab.replaceText(text, actionName: "Toggle Task")
        }
        tv.onOpenReference = { value in
            let r = PlanPaths.split(value)
            guard let w = (NSApp.delegate as? AppDelegate)?.active else { return }
            w.open(URL(fileURLWithPath: r.path), line: r.line)
            if let l = r.line { w.current?.textView.goToLine(l) }
        }
        tv.sourceLine = { [weak m] idx in m?.lineMap.last(where: { $0.loc <= idx })?.line }
        tv.onReviewComment = { [weak tab, weak tv] idx in
            guard let tab, let line = tv?.sourceLine?(idx) else { return }
            (NSApp.delegate as? AppDelegate)?.active?.promptReviewComment(tab: tab, sourceLine: line)
        }
    }

    // MARK: Menu

    @objc func showPlans(_ sender: Any?) { window?.showPlans(showAll: showAllPlans) }
    @objc func showPlanChanges(_ sender: Any?) { window?.current.map { window?.showPlanChanges($0.url) } }
    @objc func markReviewed(_ sender: Any?) {
        guard let tab = window?.current, Self.isPlan(tab.url) else { return }
        PlanReview.record(tab.textView.string, for: tab.url)
        window?.statusBar.flash("Plan marked as reviewed")
    }
    @objc func addReviewComment(_ sender: Any?) {
        guard let w = window, let tab = w.current else { return }
        w.promptReviewComment(tab: tab, sourceLine: tab.textView.lineAndColumn.line - 1)
    }

    /// Verification (CE_PICKER=plans|plan-diff, CE_PLAN_HOME=<fake home>, CE_PLAN_SNAPS=<dir>, CE_PLAN_OLD=<previous version file>).
    static func decorate(_ w: ProjectWindow, _ mode: String, shot: String) {
        if let home = AppEnv.value("CE_PLAN_HOME") { PlanStore.shared.home = home }
        if let snaps = AppEnv.value("CE_PLAN_SNAPS") { PlanReview.directory = URL(fileURLWithPath: snaps) }
        if let f = AppEnv.value("CE_PLAN_FILE") { w.open(URL(fileURLWithPath: f)); ViewerSystem.decorate(w, mode: "split") }
        if mode == "plans" { w.showPlans(showAll: AppEnv.value("CE_PLAN_ALL") != nil); return }
        guard let tab = w.current, let oldPath = AppEnv.value("CE_PLAN_OLD"), let old = try? String(contentsOfFile: oldPath, encoding: .utf8) else { return }
        let win = PlanDiffWindow.present(title: "Changes since last viewed: \(tab.url.lastPathComponent)", lines: PlanReview.unifiedDiff(old: old, new: tab.textView.string))
        win.window.setContentSize(NSSize(width: 760, height: 460))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let v = win.window.contentView { Verification.render(v, to: shot.replacingOccurrences(of: ".png", with: "_diff.png")) }
        }
    }

    func setShowAll(_ on: Bool) { showAllPlans = on }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let tab = window?.current
        let isMD = tab.map { ViewerKind.detect($0.url) == .markdown } ?? false
        switch item.action {
        case #selector(showPlans(_:)): return window?.root != nil
        case #selector(showPlanChanges(_:)), #selector(markReviewed(_:)): return isMD && tab.map { Self.isPlan($0.url) } == true
        case #selector(addReviewComment(_:)): return isMD && tab?.isReadOnly == false
        default: return true
        }
    }
}

extension ProjectWindow {
    func showPlans(showAll: Bool = false) {
        guard let root else { return }
        let plans = PlanStore.shared.plans(root: root, showAll: showAll)
        let items = PlansPicker.items(plans: plans, showAll: showAll,
            status: { p in
                guard let text = try? String(contentsOf: p.url, encoding: .utf8) else { return .unchanged }
                return PlanReview.status(of: p.url, currentText: text)
            },
            recent: { PlanStore.shared.recentlyChanged($0.url) },
            open: { [weak self] p in
                guard let self else { return }
                let changed = (try? String(contentsOf: p.url, encoding: .utf8)).map { PlanReview.status(of: p.url, currentText: $0) == .changed } ?? false
                self.open(p.url)
                if changed { self.statusBar.flash("Plan changed since you last viewed it: Navigate › Plan Changes Since Last Viewed…") }
            },
            showChanges: { [weak self] p in self?.showPlanChanges(p.url) },
            toggleShowAll: { [weak self] in
                PlanSupport.shared.setShowAll(!showAll)
                DispatchQueue.main.async { self?.showPlans(showAll: !showAll) }
            })
        QuickPicker.present(over: window, placeholder: showAll ? "Plans — all projects" : "Plans — this project", items: items)
    }

    func showPlanChanges(_ url: URL) {
        let new = editors[url.standardizedFileURL.path]?.textView.string ?? (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        guard let old = PlanReview.baseline(for: url) else { statusBar.flash("No earlier version of this plan to compare with"); return }
        PlanDiffWindow.present(title: "Changes since last viewed: \(url.lastPathComponent)", lines: PlanReview.unifiedDiff(old: old, new: new))
    }

    /// Asks for a comment (QuickPicker input) and inserts `> **Review:** ...` under the heading enclosing `sourceLine`.
    func promptReviewComment(tab: EditorTab, sourceLine: Int) {
        let heading = PlanText.heading(atOrBefore: sourceLine, in: PlanText.headings(tab.textView.string))
        guard let heading else { statusBar.flash("No heading above this position to attach a review comment to"); return }
        QuickPicker.present(over: window, placeholder: "Review comment under “\(heading.text)”", items: [], provider: { [weak tab] query in
            let q = query.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { return [] }
            return [PickerItem(title: "Add review: \(q)", detail: "under “\(heading.text)”", symbol: "text.bubble", key: query) {
                guard let tab, let text = PlanText.insertReview(in: tab.textView.string, headingLine: heading.line, comment: q) else { return }
                tab.replaceText(text, actionName: "Add Review Comment")
            }]
        })
    }
}
