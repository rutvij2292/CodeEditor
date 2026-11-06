import AppKit

/// The Git menu's dialog-driven actions: Merge, Rebase, Reset HEAD, Tag, Remotes, Worktrees, Patches, Clone.
/// Dialogs are sheets over the project window; the git work runs through `BranchController.work` (background queue,
/// busy label, conflict notice). Nothing here keeps state or timers.
enum GitMenuDialog {
    enum Row {
        case text(label: String, value: String, placeholder: String)
        case popup(label: String, items: [String], selected: String?)
    }

    /// A small form sheet. `done` receives one string per row (text value or selected popup title).
    static func form(over window: NSWindow?, title: String, info: String, rows: [Row], button: String, destructive: Bool = false,
                     validate: (([String]) -> String?)? = nil, done: @escaping ([String]) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
        var controls: [NSControl] = []
        for r in rows {
            let label = NSTextField(labelWithString: ""), field: NSControl
            switch r {
            case .text(let l, let v, let ph):
                label.stringValue = l
                let t = NSTextField(string: v); t.placeholderString = ph
                t.widthAnchor.constraint(equalToConstant: 320).isActive = true
                field = t
            case .popup(let l, let items, let sel):
                label.stringValue = l
                let p = NSPopUpButton(frame: .zero, pullsDown: false); p.addItems(withTitles: items)
                if let sel, items.contains(sel) { p.selectItem(withTitle: sel) }
                p.widthAnchor.constraint(equalToConstant: 320).isActive = true
                field = p
            }
            label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label); stack.addArrangedSubview(field)
            controls.append(field)
        }
        stack.setFrameSize(stack.fittingSize)
        alert.accessoryView = stack
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = destructive
        if let first = controls.first(where: { $0 is NSTextField }) { alert.window.initialFirstResponder = first }
        func values() -> [String] { controls.map { ($0 as? NSPopUpButton)?.titleOfSelectedItem ?? ($0 as? NSTextField)?.stringValue.trimmingCharacters(in: .whitespaces) ?? "" } }
        func handle(_ resp: NSApplication.ModalResponse) {
            guard resp == .alertFirstButtonReturn else { return }
            let v = values()
            if let msg = validate?(v) {
                let e = NSAlert(); e.messageText = msg; e.addButton(withTitle: "OK")
                if let window { e.beginSheetModal(for: window) { _ in form(over: window, title: title, info: info, rows: zip(rows, v).map(rebuilt), button: button, destructive: destructive, validate: validate, done: done) } }
                else { _ = e.runModal() }
                return
            }
            done(v)
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
    }

    private static func rebuilt(_ r: Row, _ value: String) -> Row {
        switch r {
        case .text(let l, _, let p): return .text(label: l, value: value, placeholder: p)
        case .popup(let l, let items, _): return .popup(label: l, items: items, selected: value)
        }
    }
}

extension BranchController {
    private func gitRepoOrNotice() -> GitRepo? {
        if let r = repo { return r }
        project?.statusBar.flash("Not a Git repository", seconds: 4)
        return nil
    }

    private func refs(_ r: GitRepo, includeCurrent: Bool = false) -> (current: String, items: [String]) {
        let l = (try? r.branchList()) ?? BranchList()
        let cur = l.detached ? "HEAD" : l.current
        var items = l.local.map(\.name) + l.remote.map(\.name)
        if !includeCurrent { items.removeAll { $0 == cur } }
        return (cur, items)
    }

    // MARK: merge / rebase

    func menuMerge() {
        guard let r = gitRepoOrNotice() else { return }
        let (cur, items) = refs(r)
        guard !items.isEmpty else { project?.statusBar.flash("No other branch to merge", seconds: 4); return }
        GitMenuDialog.form(over: project?.window, title: "Merge into “\(cur)”", info: "Merge the chosen branch into the current branch.",
                           rows: [.popup(label: "Branch to merge", items: items, selected: nil)], button: "Merge") { [weak self] v in
            let name = v[0]
            self?.work("Merging \(name)…", { try $0.mergeIntoCurrent(name) }, ok: { self?.flash("Merged \(name) into \(cur)") })
        }
    }

    func menuRebase() {
        guard let r = gitRepoOrNotice() else { return }
        let (cur, items) = refs(r)
        guard !items.isEmpty else { project?.statusBar.flash("No other branch to rebase onto", seconds: 4); return }
        GitMenuDialog.form(over: project?.window, title: "Rebase “\(cur)”", info: "Replay the current branch's commits on top of the chosen branch.",
                           rows: [.popup(label: "Rebase onto", items: items, selected: nil)], button: "Rebase") { [weak self] v in
            let name = v[0]
            self?.work("Rebasing onto \(name)…", { try $0.rebaseCurrent(onto: name) }, ok: { self?.flash("Rebased onto \(name)") })
        }
    }

    /// Continue / abort a merge, rebase, cherry-pick or revert that stopped on conflicts.
    func menuContinueOrAbort(abort: Bool) {
        guard let r = gitRepoOrNotice() else { return }
        guard let op = r.operationInProgress() else { project?.statusBar.flash("No merge, rebase or cherry-pick in progress", seconds: 4); return }
        work(abort ? "Aborting…" : "Continuing…", { abort ? try $0.abortOperation(op) : try $0.continueOperation(op) },
             ok: { [weak self] in self?.flash(abort ? "\(op.rawValue.capitalized) aborted" : "\(op.rawValue.capitalized) continued") })
    }

    // MARK: reset

    func menuReset() {
        guard let r = gitRepoOrNotice() else { return }
        let hasChanges = r.hasLocalChanges()
        GitMenuDialog.form(over: project?.window, title: "Reset HEAD",
                           info: "Move the current branch to another commit.\nSoft keeps changes staged, Mixed keeps them unstaged, Hard discards them" + (hasChanges ? " (you have uncommitted changes)." : "."),
                           rows: [.text(label: "Reset to (commit, branch or tag)", value: "HEAD~1", placeholder: "HEAD~1"),
                                  .popup(label: "Mode", items: ["Mixed", "Soft", "Hard"], selected: "Mixed")],
                           button: "Reset", destructive: true,
                           validate: { v in v[0].isEmpty ? "Enter a commit, branch or tag" : (r.resolves(v[0]) ? nil : "“\(v[0])” does not resolve to a commit") }) { [weak self] v in
            let mode = GitResetMode(rawValue: v[1].lowercased()) ?? .mixed
            let go = { self?.work("Resetting…", { try $0.reset(to: v[0], mode: mode) }, ok: { self?.flash("Reset (\(mode.rawValue)) to \(v[0])") }) }
            if mode == .hard, let w = self?.project?.window {
                let a = GitDialogs.confirmAlert(title: "Discard all uncommitted changes?", info: "A hard reset to \(v[0]) throws away every uncommitted change and cannot be undone.", button: "Hard Reset", destructive: true)
                a.beginSheetModal(for: w) { if $0 == .alertFirstButtonReturn { go() } }
            } else { go() }
        }
    }

    // MARK: tags

    func menuTag() {
        guard let r = gitRepoOrNotice() else { return }
        let existing = Set((try? r.tags()) ?? [])
        GitMenuDialog.form(over: project?.window, title: "New Tag", info: "Tag a commit. Add a message to make it an annotated tag.",
                           rows: [.text(label: "Tag name", value: "", placeholder: "v1.0.0"),
                                  .text(label: "Commit (blank = HEAD)", value: "", placeholder: "HEAD"),
                                  .text(label: "Message (optional)", value: "", placeholder: "")],
                           button: "Create Tag",
                           validate: { v in
                               if let m = GitRefName.validate(v[0]) { return m }
                               if existing.contains(v[0]) { return "Tag “\(v[0])” already exists" }
                               if !v[1].isEmpty, !r.resolves(v[1]) { return "“\(v[1])” does not resolve to a commit" }
                               return nil
                           }) { [weak self] v in
            self?.work("Tagging…", { try $0.createTag(v[0], at: v[1].isEmpty ? nil : v[1], message: v[2]) }, ok: { self?.flash("Created tag \(v[0])") })
        }
    }

    // MARK: remotes

    func menuRemotes() {
        guard let r = gitRepoOrNotice(), let window = project?.window else { return }
        let list = (try? r.remoteList()) ?? []
        let alert = NSAlert()
        alert.messageText = "Remotes"
        alert.informativeText = list.isEmpty ? "This repository has no remotes." : list.map { "\($0.name)\t\($0.url)" }.joined(separator: "\n")
        alert.addButton(withTitle: "Add…")
        if !list.isEmpty { alert.addButton(withTitle: "Edit URL…"); alert.addButton(withTitle: "Remove…") }
        alert.addButton(withTitle: "Close")
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard let self else { return }
            let idx = resp.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            let names = list.map(\.name)
            switch (idx, list.isEmpty) {
            case (0, _):
                GitMenuDialog.form(over: window, title: "Add Remote", info: "", rows: [.text(label: "Name", value: "origin", placeholder: "origin"),
                                                                               .text(label: "URL", value: "", placeholder: "git@host:org/repo.git")],
                                   button: "Add", validate: { v in v[0].isEmpty || v[1].isEmpty ? "Enter a name and a URL" : (names.contains(v[0]) ? "Remote “\(v[0])” already exists" : GitRefName.validate(v[0])) }) { v in
                    self.work("Adding remote…", { try $0.addRemote(v[0], url: v[1]) }, ok: { self.flash("Added remote \(v[0])") })
                }
            case (1, false):
                GitMenuDialog.form(over: window, title: "Edit Remote URL", info: "", rows: [.popup(label: "Remote", items: names, selected: nil),
                                                                                  .text(label: "New URL", value: "", placeholder: "")],
                                   button: "Save", validate: { v in v[1].isEmpty ? "Enter a URL" : nil }) { v in
                    self.work("Updating remote…", { try $0.setRemoteURL(v[0], url: v[1]) }, ok: { self.flash("Updated \(v[0])") })
                }
            case (2, false):
                GitMenuDialog.form(over: window, title: "Remove Remote", info: "Its remote-tracking branches are deleted too.", rows: [.popup(label: "Remote", items: names, selected: nil)],
                                   button: "Remove", destructive: true) { v in
                    self.work("Removing remote…", { try $0.removeRemote(v[0]) }, ok: { self.flash("Removed remote \(v[0])") })
                }
            default: break
            }
        }
    }

    // MARK: worktrees

    func menuAddWorktree() {
        guard let r = gitRepoOrNotice(), let window = project?.window else { return }
        let (cur, items) = refs(r, includeCurrent: true)
        GitMenuDialog.form(over: window, title: "Add Worktree", info: "Check out a new branch into a separate folder, so you can work on two branches at once.",
                           rows: [.text(label: "New branch name", value: "", placeholder: "feature/x"),
                                  .popup(label: "Start from", items: items, selected: cur)], button: "Choose Folder…",
                           validate: { v in GitRefName.validate(v[0]) ?? (r.localBranchExists(v[0]) ? "Branch “\(v[0])” already exists" : nil) }) { [weak self] v in
            let panel = NSSavePanel()
            panel.title = "New Worktree"; panel.prompt = "Create Worktree"
            panel.directoryURL = r.root.deletingLastPathComponent()
            panel.nameFieldStringValue = r.root.lastPathComponent + "-" + v[0].replacingOccurrences(of: "/", with: "-")
            panel.beginSheetModal(for: window) { resp in
                guard resp == .OK, let url = panel.url else { return }
                self?.work("Adding worktree…", { try $0.addWorktree(at: url.path, newBranch: v[0], start: v[1]) },
                           ok: { self?.flash("Worktree created at \(url.path)") })
            }
        }
    }

    func menuOpenWorktree() {
        guard let r = gitRepoOrNotice() else { return }
        let others = ((try? r.worktreeList()) ?? []).filter { !$0.isMain }
        guard !others.isEmpty else { project?.statusBar.flash("No linked worktrees. Use Add Worktree…", seconds: 4); return }
        let titles = others.map { "\($0.branch ?? "detached") — \($0.path)" }
        GitMenuDialog.form(over: project?.window, title: "Open Worktree", info: "Opens the worktree in its own window.",
                           rows: [.popup(label: "Worktree", items: titles, selected: nil)], button: "Open") { v in
            guard let i = titles.firstIndex(of: v[0]) else { return }
            (NSApp.delegate as? AppDelegate)?.openProjectRouted(URL(fileURLWithPath: others[i].path))
        }
    }

    // MARK: patches

    func menuCreatePatch() {
        guard let r = gitRepoOrNotice(), let window = project?.window else { return }
        let panel = NSSavePanel()
        panel.title = "Create Patch from Local Changes"; panel.prompt = "Save Patch"
        panel.nameFieldStringValue = r.root.lastPathComponent + ".patch"
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            self?.work("Creating patch…", { repo -> Int in
                let p = try repo.patchOfLocalChanges()
                guard !p.isEmpty else { throw GitError(message: "There are no local changes to put in a patch.") }
                try p.write(to: url, atomically: true, encoding: .utf8)
                return p.utf8.count
            }, ok: { _ in self?.flash("Saved patch to \(url.lastPathComponent)") })
        }
    }

    func menuApplyPatch() {
        guard let r = gitRepoOrNotice(), let window = project?.window else { return }
        let panel = NSOpenPanel()
        panel.title = "Apply Patch"; panel.prompt = "Apply"
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            _ = r
            self?.work("Applying patch…", { repo in try repo.applyPatch(url, checkOnly: true); try repo.applyPatch(url, checkOnly: false) },
                       ok: { self?.flash("Applied \(url.lastPathComponent)") })
        }
    }
}

// MARK: clone

enum GitClone {
    /// Asks for a URL and a parent folder, clones off the main thread, then opens the new project.
    static func present(over window: NSWindow?, app: AppDelegate) {
        GitMenuDialog.form(over: window, title: "Clone Repository", info: "Clone a Git repository and open it as a project.",
                           rows: [.text(label: "Repository URL", value: "", placeholder: "https://github.com/org/repo.git")], button: "Choose Folder…",
                           validate: { v in v[0].isEmpty ? "Enter a repository URL" : nil }) { v in
            let url = v[0]
            let panel = NSOpenPanel()
            panel.title = "Clone Into"; panel.prompt = "Clone Here"
            panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
            let go: (NSApplication.ModalResponse) -> Void = { resp in
                guard resp == .OK, let parent = panel.url else { return }
                var name = (url as NSString).lastPathComponent
                if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
                if name.isEmpty { name = "repository" }
                let dest = parent.appendingPathComponent(name)
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result { try GitRepo.clone(url: url, into: dest) }
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let d): app.openProjectRouted(d)
                        case .failure(let e):
                            let a = NSAlert(); a.messageText = "Clone failed"; a.informativeText = (e as? GitError)?.message ?? "\(e)"; a.addButton(withTitle: "OK")
                            if let window { a.beginSheetModal(for: window) } else { _ = a.runModal() }
                        }
                    }
                }
            }
            if let window { panel.beginSheetModal(for: window, completionHandler: go) } else { go(panel.runModal()) }
        }
    }
}
