import AppKit

/// Orchestrates the branch workflow of one project window: the title-bar widget, the popup, background fetch, and every
/// branch action. Git work runs on a utility queue; results come back as non-modal notices (BranchNotice) and status-bar flashes.
final class BranchController: NSObject {
    private(set) weak var project: ProjectWindow?
    let widget = BranchWidget()
    private var accessory: NSTitlebarAccessoryViewController?
    private let host = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 28))
    private(set) var lastList = BranchList()
    private var busy = 0
    /// Verification / test hooks.
    var onIdle: (() -> Void)?
    private(set) var lastMessage = ""
    nonisolated(unsafe) static var allowFetchInHeadless = false

    init(project: ProjectWindow) {
        self.project = project
        super.init()
        widget.onClick = { [weak self] in self?.showPopup() }
        widget.onResize = { [weak self] in self?.layoutHost() }
        host.addSubview(widget)
    }

    var repo: GitRepo? { project?.gitRoot.map { GitRepo(root: $0) } }
    private var window: NSWindow? { project?.window }

    // MARK: widget

    /// Shows or hides the title-bar widget for a status snapshot (nil info = not a Git repository).
    func apply(info: GitRepo.BranchInfo?, changes: Int) {
        guard let info else { setWidgetVisible(false); return }
        installAccessoryIfNeeded()
        widget.update(branch: info.name, detached: info.detached, ahead: info.ahead, behind: info.behind, dirty: changes > 0)
        setWidgetVisible(true)
    }

    private func installAccessoryIfNeeded() {
        guard accessory == nil, let window else { return }
        let vc = NSTitlebarAccessoryViewController()
        vc.view = host
        vc.layoutAttribute = .leading
        window.addTitlebarAccessoryViewController(vc)
        accessory = vc
    }

    private func setWidgetVisible(_ on: Bool) { accessory?.isHidden = !on; widget.isHidden = !on }
    var widgetVisible: Bool { accessory != nil && accessory?.isHidden == false }

    private func layoutHost() {
        host.setFrameSize(NSSize(width: widget.frame.width + 14, height: 28))
        widget.setFrameOrigin(NSPoint(x: 4, y: (28 - widget.frame.height) / 2))
        accessory?.view.needsLayout = true
    }

    private var noticeAnchor: NSView? { widgetVisible && widget.window != nil ? widget : window?.contentView }

    // MARK: popup

    func showPopup(over host: NSWindow? = nil) {
        guard let window = host ?? window, repo != nil else { return }
        BranchNotice.dismiss()
        BranchPopup.present(over: window, controller: self, anchor: host == nil && widgetVisible ? widget : nil)
    }

    func favorites() -> Set<String> { project?.gitRoot.map { BranchFavorites.all(for: $0) } ?? [] }
    func toggleFavorite(_ name: String) { if let r = project?.gitRoot { BranchFavorites.toggle(name, for: r) } }

    func loadBranchList(done: @escaping (Result<BranchList, Error>) -> Void) {
        guard let repo else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try repo.branchList() }
            DispatchQueue.main.async { [weak self] in
                if case .success(let l) = result { self?.lastList = l }
                done(result)
            }
        }
    }

    func backgroundFetch(force: Bool = false, done: @escaping (Bool, String?) -> Void) {
        guard let repo, !AppEnv.headless || Self.allowFetchInHeadless else { DispatchQueue.main.async { done(false, nil) }; return }
        repo.fetchThrottled(force: force) { [weak self] fetched, err in
            if fetched, err == nil { self?.project?.gitStateChanged(reloadEditors: false) }
            done(fetched, err)
        }
    }

    // MARK: running work

    private func describe(_ e: Error) -> String {
        if let c = e as? CheckoutFailure { return c.message }
        return (e as? GitError)?.message ?? e.localizedDescription
    }

    /// Runs `job` off the main thread with a busy label in the widget, then `ok` / `fail` on main.
    private func work<T>(_ label: String, _ job: @escaping (GitRepo) throws -> T, ok: @escaping (T) -> Void, fail: ((Error) -> Void)? = nil) {
        guard let repo else { return }
        busy += 1
        widget.setBusy(label)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try job(repo) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy -= 1
                if self.busy == 0 { self.widget.setBusy(nil) }
                self.project?.gitStateChanged(reloadEditors: true)
                switch result {
                case .success(let v): ok(v)
                case .failure(let e): if let fail { fail(e) } else { self.report(error: e) }
                }
                if self.busy == 0 { self.onIdle?() }
            }
        }
    }

    private func flash(_ text: String) {
        lastMessage = text
        project?.statusBar.flash(text, seconds: 6)
    }

    func report(error: Error, title: String = "Git operation failed") {
        let msg = describe(error)
        lastMessage = msg
        // merge / rebase stopped on conflicts: say so and offer the way forward
        if let r = repo, let op = r.operationInProgress() {
            let files = ((try? r.status()) ?? []).filter(\.isConflict).map(\.path)
            let name = op.rawValue
            BranchNotice.show(title: "\(name.capitalized) stopped with conflicts",
                              message: files.isEmpty ? msg : "Resolve the conflicts in these files, then continue from the Commit window (⌘K).",
                              files: files,
                              buttons: [.init(title: "Open Commit Window", style: .primary) { [weak self] in self?.project?.showCommitWindow() },
                                        .init(title: "Abort \(name.capitalized)", style: .destructive) { [weak self] in
                                            self?.work("Aborting…", { try $0.abortOperation(op) }, ok: { _ in self?.flash("\(name.capitalized) aborted") })
                                        }],
                              over: noticeAnchor)
            return
        }
        BranchNotice.show(title: title, message: msg, buttons: [.init(title: "OK", style: .primary) {}], over: noticeAnchor)
    }

    // MARK: actions

    func run(_ action: BranchAction, entry: BranchEntry?) {
        switch action {
        case .newBranch: newBranch(from: nil)
        case .checkoutRevision: checkoutRevision(nil)
        case .fetchUpdate: fetchAndUpdate()
        case .favorite: if let e = entry { toggleFavorite(e.name) }
        default:
            guard let e = entry else { return }
            switch action {
            case .checkout: checkout(e.name)
            case .newFrom: newBranch(from: e.name)
            case .checkoutAndRebase: checkoutAndRebase(e)
            case .rebaseOnto: rebaseCurrent(onto: e)
            case .merge: merge(e)
            case .compare: compare(e)
            case .pullMerge: pull(e, rebase: false)
            case .pullRebase: pull(e, rebase: true)
            case .push: push(e)
            case .rename: rename(e)
            case .delete: confirmDelete(e)
            case .deleteRemote: confirmDeleteRemote(e)
            default: break
            }
        }
    }

    // checkout (with smart / force)

    func checkout(_ target: String) {
        work("Checking out \(target)…", { try $0.checkoutTarget(target) }, ok: { [weak self] in self?.flash("Checked out \(target)") },
             fail: { [weak self] e in self?.handleCheckoutFailure(e, target: target) })
    }

    private func handleCheckoutFailure(_ e: Error, target: String) {
        guard let failure = e as? CheckoutFailure, case .localChanges(let files, _) = failure else { report(error: e, title: "Cannot check out \(target)"); return }
        lastMessage = failure.message
        BranchNotice.show(title: "Cannot check out “\(target)”",
                          message: "Local changes to these files would be overwritten by the checkout:",
                          files: files,
                          buttons: [.init(title: "Smart Checkout", style: .primary) { [weak self] in self?.smartCheckout(target) },
                                    .init(title: "Force Checkout", style: .destructive) { [weak self] in self?.forceCheckout(target) },
                                    .init(title: "Cancel") {}],
                          over: noticeAnchor)
    }

    func smartCheckout(_ target: String) {
        work("Smart checkout \(target)…", { try $0.smartCheckout(target) }, ok: { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .clean: self.flash("Checked out \(target); your local changes were carried over")
            case .conflicts(let files):
                self.lastMessage = "conflicts"
                BranchNotice.show(title: "Checked out “\(target)” with conflicts",
                                  message: "Re-applying your local changes conflicted in these files. Resolve them in the Commit window (⌘K); your original changes are kept in the stash until then.",
                                  files: files,
                                  buttons: [.init(title: "Open Commit Window", style: .primary) { [weak self] in self?.project?.showCommitWindow() },
                                            .init(title: "Close") {}],
                                  over: self.noticeAnchor)
            }
        })
    }

    func forceCheckout(_ target: String) {
        work("Checking out \(target)…", { try $0.checkoutTarget(target, force: true) }, ok: { [weak self] in self?.flash("Checked out \(target) (local changes discarded)") })
    }

    // revision / tag

    func checkoutRevision(_ rev: String?) {
        guard let rev else {
            promptText(title: "Checkout Tag or Revision", message: "Tag, commit hash, or any revision. HEAD will be detached.", placeholder: "v1.0.0 or a1b2c3d") { [weak self] in
                self?.checkoutRevision($0)
            }
            return
        }
        let r = rev.trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty else { return }
        work("Checking out \(r)…", { repo in
            guard repo.resolves(r) else { throw GitError(message: "“\(r)” is not a known branch, tag or commit.") }
            try repo.checkoutTarget(r)
        }, ok: { [weak self] in self?.flash("Checked out \(r) (detached HEAD)") },
             fail: { [weak self] e in self?.handleCheckoutFailure(e, target: r) })
    }

    private func promptText(title: String, message: String, placeholder: String, ok: @escaping (String) -> Void) {
        guard let window, !AppEnv.headless else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: "Checkout")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { resp in
            if resp == .alertFirstButtonReturn { ok(field.stringValue) }
        }
    }

    // new branch

    func newBranch(from start: String?) {
        guard let window, let repo else { return }
        let list = lastList
        let curLabel = list.detached ? "HEAD" : list.current
        let startDefault = start ?? curLabel
        var items: [String] = []
        if !curLabel.isEmpty { items.append(curLabel) }
        for n in list.local.map(\.name) + list.remote.map(\.name) + list.tags where !items.contains(n) { items.append(n) }
        NewBranchSheet.presentNew(over: window, startItems: items, defaultStart: startDefault, startLabel: curLabel,
                                  existing: Set(list.local.map(\.name))) { [weak self] r, done in
            guard let self else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                var needsSmart = false
                var failure: String?
                do {
                    if let s = r.start, !repo.resolves(s) { throw GitError(message: "Start point “\(s)” is not a branch, tag or commit.") }
                    do { try repo.createBranch(named: r.name, from: r.start, checkout: r.checkout, overwrite: r.overwrite) }
                    catch let e as GitError {
                        if r.checkout, case .localChanges = GitRepo.classifyCheckoutFailure(e.message) {
                            // branch creation is fine; only the switch collides with local changes -> offer Smart Checkout
                            try repo.createBranch(named: r.name, from: r.start, checkout: false, overwrite: r.overwrite)
                            needsSmart = true
                        } else { throw e }
                    }
                } catch { failure = (error as? GitError)?.message ?? "\(error)" }
                DispatchQueue.main.async {
                    done(failure)
                    guard failure == nil else { return }
                    self.project?.gitStateChanged(reloadEditors: true)
                    if needsSmart { self.handleCheckoutFailure(CheckoutFailure.localChanges(files: [], message: "would be overwritten"), target: r.name) }
                    else { self.flash(r.checkout ? "Created and checked out \(r.name)" : "Created branch \(r.name)") }
                    self.onIdle?()
                }
            }
        }
    }

    // rebase / merge / pull / push

    private func checkoutAndRebase(_ e: BranchEntry) {
        work("Rebasing \(e.name)…", { try $0.checkoutAndRebase(e.name) }, ok: { [weak self] in self?.flash("Checked out \(e.name) and rebased onto previous branch") },
             fail: { [weak self] err in
                if let f = err as? CheckoutFailure, case .localChanges = f { self?.handleCheckoutFailure(err, target: e.name) } else { self?.report(error: err, title: "Rebase failed") }
             })
    }

    private func rebaseCurrent(onto e: BranchEntry) {
        work("Rebasing onto \(e.name)…", { try $0.rebaseCurrent(onto: e.name) }, ok: { [weak self] in self?.flash("Rebased onto \(e.name)") })
    }

    private func merge(_ e: BranchEntry) {
        work("Merging \(e.name)…", { try $0.mergeIntoCurrent(e.name) }, ok: { [weak self] in self?.flash("Merged \(e.name) into current branch") })
    }

    private func pull(_ e: BranchEntry, rebase: Bool) {
        work("Pulling…", { repo in
            if e.isCurrent { try repo.git(["pull", rebase ? "--rebase" : "--no-rebase", "--no-edit"]) }
            else { try repo.pullIntoCurrent(e, rebase: rebase) }
        }, ok: { [weak self] in self?.flash("Pulled \(e.name) using \(rebase ? "rebase" : "merge")") })
    }

    private func push(_ e: BranchEntry) {
        work("Pushing \(e.name)…", { try $0.pushBranch(e) }, ok: { [weak self] in self?.flash("Pushed \(e.name)") })
    }

    // fetch / update

    func fetchAndUpdate() {
        work("Updating…", { repo -> String in
            try repo.fetch()
            let info = try repo.branchInfo()
            guard info.upstream != nil, !info.detached else { return "fetched" }
            if info.behind == 0 { return "uptodate" }
            if info.ahead == 0 { try repo.git(["merge", "--ff-only", "@{u}"]); return "updated" }
            return "diverged"
        }, ok: { [weak self] state in
            guard let self else { return }
            switch state {
            case "diverged":
                BranchNotice.show(title: "Branch has diverged from its upstream",
                                  message: "It has local commits and the remote has new ones. How should they be combined?",
                                  buttons: [.init(title: "Merge", style: .primary) { [weak self] in self?.updateDiverged(rebase: false) },
                                            .init(title: "Rebase") { [weak self] in self?.updateDiverged(rebase: true) },
                                            .init(title: "Cancel") {}],
                                  over: self.noticeAnchor)
            case "updated": self.flash("Project updated")
            case "uptodate": self.flash("Already up to date")
            default: self.flash("Fetched all remotes")
            }
        })
    }

    private func updateDiverged(rebase: Bool) {
        work("Updating…", { try $0.git(["pull", rebase ? "--rebase" : "--no-rebase", "--no-edit"]) },
             ok: { [weak self] _ in self?.flash("Project updated (\(rebase ? "rebase" : "merge"))") })
    }

    // compare

    private var compareWindows: [BranchCompareWindow] = []

    private func compare(_ e: BranchEntry) {
        work("Comparing…", { try ($0.compare(with: e.name), (try? $0.branchInfo().name) ?? "HEAD") }, ok: { [weak self] pair in
            guard let self, let repo = self.repo else { return }
            let w = BranchCompareWindow(repo: repo, comparison: pair.0, current: pair.1)
            self.compareWindows.append(w)
            if !AppEnv.headless { w.show() }
        })
    }

    // rename / delete

    private func rename(_ e: BranchEntry) {
        guard let window, let repo else { return }
        NewBranchSheet.presentRename(over: window, old: e.name, existing: Set(lastList.local.map(\.name))) { [weak self] newName, done in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Result { try repo.renameBranch(e.name, to: newName) }
                DispatchQueue.main.async {
                    switch result {
                    case .success: done(nil); self?.project?.gitStateChanged(reloadEditors: false); self?.flash("Renamed \(e.name) to \(newName)")
                    case .failure(let err): done((err as? GitError)?.message ?? "\(err)")
                    }
                    self?.onIdle?()
                }
            }
        }
    }

    private func confirmDelete(_ e: BranchEntry) {
        var buttons: [BranchNotice.Button] = [.init(title: "Delete", style: .destructive) { [weak self] in self?.deleteLocal(e, alsoRemote: false, force: false) }]
        var message = "The local branch will be removed. Unmerged commits are protected."
        if let up = e.upstream, lastList.remote.contains(where: { $0.name == up }) {
            buttons.append(.init(title: "Delete Local and Remote", style: .destructive) { [weak self] in self?.deleteLocal(e, alsoRemote: true, force: false) })
            message = "The local branch will be removed. You can also delete \(up) on the remote."
        }
        buttons.append(.init(title: "Cancel") {})
        BranchNotice.show(title: "Delete branch “\(e.name)”?", message: message, buttons: buttons, over: noticeAnchor)
    }

    func deleteLocal(_ e: BranchEntry, alsoRemote: Bool, force: Bool) {
        let remoteEntry = e.upstream.flatMap { up in lastList.remote.first { $0.name == up } }
        work("Deleting \(e.name)…", { repo in
            try repo.deleteLocalBranch(e.name, force: force)
            if alsoRemote, let r = remoteEntry { try repo.deleteRemoteBranch(r) }
        }, ok: { [weak self] in self?.flash(alsoRemote ? "Deleted \(e.name) locally and on the remote" : "Deleted branch \(e.name)") },
             fail: { [weak self] err in
                guard let self else { return }
                if GitRepo.isUnmergedRefusal(err) {
                    BranchNotice.show(title: "“\(e.name)” is not fully merged",
                                      message: "Deleting it will lose commits that exist nowhere else.",
                                      buttons: [.init(title: "Force Delete", style: .destructive) { [weak self] in self?.deleteLocal(e, alsoRemote: alsoRemote, force: true) },
                                                .init(title: "Cancel", style: .primary) {}],
                                      over: self.noticeAnchor)
                } else { self.report(error: err, title: "Cannot delete “\(e.name)”") }
             })
    }

    private func confirmDeleteRemote(_ e: BranchEntry) {
        BranchNotice.show(title: "Delete remote branch “\(e.name)”?", message: "This deletes the branch on \(e.remote ?? "the remote") for everyone.",
                          buttons: [.init(title: "Delete Remote Branch", style: .destructive) { [weak self] in
                                        self?.work("Deleting \(e.name)…", { try $0.deleteRemoteBranch(e) }, ok: { [weak self] in self?.flash("Deleted remote branch \(e.name)") })
                                    },
                                    .init(title: "Cancel", style: .primary) {}],
                          over: noticeAnchor)
    }
}
