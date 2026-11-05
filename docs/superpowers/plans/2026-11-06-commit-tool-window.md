# Commit Tool Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cmd+K swaps a PhpStorm-style Commit panel (Commit / Stash tabs) into the left sidebar slot; clicking a file opens its diff in a reused preview tab in the editor area; the standalone commit window is removed.

**Architecture:** `GitPanelController` (GitPanel.swift) gains a `Layout` so one class serves two hosts: `.sidebar` (toolbar, changes tree, commit box; diff detached) in the left slot, and `.log` (Log view and its toolbar only) in the bottom Git tool window (⌘9). The detached `diffHost` view is re-parented into an editor-area tab (`tabs.add(id:title:view:)` already accepts arbitrary views). `ProjectWindow` owns a `CommitSidebar` that swaps the commit panel and `tree.panel` inside the existing sidebar split item.

**Tech Stack:** Swift/AppKit, SwiftPM (`swift build`), in-app self-tests (`CE_SELFTEST=1`, `SelfTest.check(_:_:)`).

**Spec:** `docs/superpowers/specs/2026-11-06-commit-tool-window-design.md`

## Global Constraints
- Native Swift/AppKit; reuse `GitPanelController`, `GitStashView`, `SideBySideDiffView`; no duplicated tree/commit code.
- Commit/Stash tabs only. No Shelf. No Git menu additions (separate later project).
- Log stays in the bottom Git panel (⌘9); the bottom panel has no Changes/commit UI after this change.
- Panel swaps into the left slot shared with the file tree (no second column). Sidebar width limits stay 180–500 pt (`ProjectWindow.swift:131-132`).
- Cmd+K again or Esc hides it, restoring the file tree and focus to the previous editor. Opening focuses the message box. ⌘9 and ⌥⌘K (Commit and Push) unchanged; ⇧⌘K/⌘T/Fetch entry points keep working.
- RAM first: panel built lazily on first Cmd+K, no timers/polling, content released when hidden is NOT required but nothing may run while hidden.
- Diff = one reused preview tab, replaced on each file click; refreshes after stage/commit/revert; closes when its file has no changes.
- Verify headless (`AppEnv.headless`): never open visible windows. Build green + `CE_SELFTEST=1` green before pushing to main (pre-authorised).

## Review Focus
- Not a git repo: Cmd+K shows the existing "not a Git repository" alert, sidebar unchanged.
- Sidebar collapsed (Cmd+\) when Cmd+K pressed: it expands for the panel and re-collapses on hide.
- Terminal maximized: Cmd+K must not break layout (`isTerminalMaximized` guard as in `toggleSidebar`).
- Committing the file whose diff is open: preview tab closes/clears, no stale diff or crash.
- Clicking a conflicted file: merge UI (`MergeView`) still works inside the diff tab.
- Untracked/binary/deleted file click: diff tab shows the existing message ("Select a file…"/binary text), not blank.
- Rapid clicks across files: only one preview tab exists; selecting the tab and the tree stay in sync.
- Project window closes with panel open: no leak, no callback into a dead window.

---

### Task 1: Layout modes in GitPanelController

**Files:**
- Modify: `Sources/CodeEditor/GitPanel.swift` (init at :387, `build()` :402-700, `modeChanged` :1113, toolbar :403-422)
- Modify: `Sources/CodeEditor/ProjectWindow.swift:1228` (`ensureGitPanel`)

**Interfaces:**
- Produces: `enum GitPanelController.Layout { case sidebar, log }`; `init(root: URL, layout: Layout = .log, openFile: @escaping (URL) -> Void)`; `let diffHost: NSView` (made non-private, the existing view); `var onShowDiff: (() -> Void)?` fired when a tree selection should show its diff; `func hasDiff(for path: String) -> Bool`.

- [ ] **Step 1:** Self-test in `SelfTestProject.swift` next to the existing "commit panel dividers" block: build `GitPanelController(root: tmpRepo, layout: .sidebar) { _ in }`; check `gp.view.subviews` contains no `NSSegmentedControl` with "Log", `gp.diffHost.superview == nil`, and `.log` layout contains the log view but no commit message view.
- [ ] **Step 2:** Run `swift build && CE_SELFTEST=1 .build/debug/CodeEditor` → new checks FAIL (compile error counts).
- [ ] **Step 3:** Implement layouts in `build()`: `.sidebar` = toolbar row (icons only: refresh, rollback, expand all, collapse all, stash-tab control) / banners / `outlineScroll` / `commitBox` stacked vertically in `panel` (no `panel.split`/`panel.right` splits; `diffHost` not added to any parent). `.log` = existing toolbar (Fetch/Pull/Push/branch/op buttons) + `logView` only; drop `modeControl` and force `mode = .log`.
- [ ] **Step 4:** `outlineViewSelectionDidChange` (:935): in `.sidebar` layout call `onShowDiff?()` after loading the diff into `diffView` (existing logic); keep existing behaviour in `.log`.
- [ ] **Step 5:** Change `ensureGitPanel` to pass `layout: .log`. Build + self-test pass. Commit `refactor: GitPanelController layouts (sidebar/log)`.

### Task 2: CommitSidebar swap + Cmd+K

**Files:**
- Create: `Sources/CodeEditor/CommitSidebar.swift`
- Modify: `Sources/CodeEditor/ProjectWindow.swift` (sidebar setup :110-148, near `toggleSidebar` :999), `Sources/CodeEditor/CommitWindow.swift` (becomes the `ProjectWindow` extension only, then deleted in Task 5)

**Interfaces:**
- Consumes: Task 1 `GitPanelController(root:layout:openFile:)`.
- Produces: `final class CommitSidebar { init(project: ProjectWindow, host: NSViewController); func show(then: ((GitPanelController) -> Void)?); func hide(restoreFocus: Bool); var isShowing: Bool }`; `ProjectWindow.showCommitPanel(then:)`, `ProjectWindow.toggleCommitPanel()`.
- `sidebarVC.view` becomes a container holding both `tree.panel` and the commit panel view (one hidden at a time).

- [ ] **Step 1:** Self-test (new `SelfTestCommitPanel.swift`, registered where other SelfTest* are called): headless project window over a temp git repo; `w.toggleCommitPanel()` → `w.commitSidebar.isShowing`, tree panel hidden; toggle again → tree visible, `isShowing == false`. Second test: with `isSidebarVisible == false`, show expands it, hide re-collapses.
- [ ] **Step 2:** Run self-test → FAIL.
- [ ] **Step 3:** Implement. `show` resolves repo via `GitRepo.repoRoot(for:)` (alert if nil, as `CommitWindow.swift:22-28`), lazily creates the panel once, remembers `wasCollapsed` and previous first responder, calls `panel.reload()` and `focusCommitMessage()`. `hide` restores tree, collapse state, and focus. Respect `isTerminalMaximized`.
- [ ] **Step 4:** Wire panel callbacks: `onRequestClose`/Esc → `hide`; `onCommitted(andPush)` → hide when `!andPush`; `onPushed` hides when `panel.committedAndPushing`; `onShowBranches` → `branches.showPopup(over: window)`; `onStatusChange` → `refreshGitStatus(); tree.refresh()`; `onSummaryChange` badge as in `ensureGitPanel`.
- [ ] **Step 5:** Self-test pass; commit `feat: commit panel swaps into the left sidebar`.

### Task 3: Diff preview tab in the editor area

**Files:**
- Modify: `Sources/CodeEditor/CommitSidebar.swift`, `Sources/CodeEditor/ProjectWindow.swift` (tab close/select hooks at :93-94; `didSelect`)

**Interfaces:**
- Consumes: Task 1 `diffHost`, `onShowDiff`, `hasDiff(for:)`; `TabBar.add(id:title:view:)`, `remove(_:)`, `select(_:)`, `setTitle(_:for:)`.
- Produces: tab id constant `CommitSidebar.diffTabID = "git-diff:preview"`; `CommitSidebar.showDiffTab(title: String)`; `closeDiffTab()`.

- [ ] **Step 1:** Self-test: simulate selecting a changed file in the panel → exactly one tab with id `git-diff:preview` exists and its title is `"<file name> (diff)"`; select a second file → still one, title updated; commit/clear changes → tab removed.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** `onShowDiff` → `showDiffTab`: add the tab on first use (re-parenting `diffHost` into the tab view), otherwise `setTitle` + `select`. Tab id must not collide with the file-keyed `editors` dictionary: make `didSelect`/`close`/`captureSession` ignore ids with the `git-diff:` prefix (session must not persist it).
- [ ] **Step 4:** Closing the tab via its ✕ detaches `diffHost`; the next click re-adds it. After panel `reload()`, if `hasDiff(for:)` is false for the previewed path call `closeDiffTab()`.
- [ ] **Step 5:** Self-test pass; commit `feat: file diffs open in an editor-area preview tab`.

### Task 4: Commit / Stash tabs and toolbar

**Files:**
- Modify: `Sources/CodeEditor/GitPanel.swift` (`stashTapped` :1083, `makeStashView` :1066, toolbar), `Sources/CodeEditor/GitStashView.swift`

**Interfaces:**
- Consumes: Task 1 `.sidebar` layout. Produces: `enum GitPanelController.SidebarTab { case commit, stash }`, `func showTab(_ t: SidebarTab)`, `@objc refreshTapped()`, `expandAllTapped()`, `collapseAllTapped()`.

- [ ] **Step 1:** Self-test: `showTab(.stash)` hides the commit box + tree and shows a `GitStashView`; `showTab(.commit)` reverses; `collapseAllTapped()` collapses every `GitGroup`, `expandAllTapped()` expands them.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement the tab control (`Commit | Stash`) at the top of `.sidebar`; embed the existing `makeStashView()` content inline instead of in the popover (popover code path stays for `.log`/menu users only if still referenced, otherwise delete). Refresh calls `reload()`; rollback keeps `rollbackTapped` (⌥⌘Z).
- [ ] **Step 4:** Self-test pass; commit `feat: Commit/Stash tabs and tree toolbar in the commit panel`.

### Task 5: Remove the commit window; rewire entry points

**Files:**
- Delete: `Sources/CodeEditor/CommitWindow.swift` (keep nothing but the `showCommitWindow` shim removed)
- Modify: `AppDelegate.swift:82,301-304`, `BranchController.swift:153,223` (button title "Open Commit Panel"), `ToolStrip.swift:223`, `Verification.swift:42`, `Menu.swift:195` (selector unchanged), `ProjectWindow.swift` (remove `"CommitWindow"` frame default use)

**Interfaces:** Consumes `ProjectWindow.showCommitPanel(then:)` / `toggleCommitPanel()` from Task 2. Cmd+K and the tool-strip Commit button call `toggleCommitPanel()`; Push/Update/Fetch/blame-history call `showCommitPanel { $0.push() }` etc. `showHistory(for:)` must open the bottom Git panel's Log (use `showFileHistory()`), not the commit panel.

- [ ] **Step 1:** Replace every `showCommitWindow` reference; `grep -rn "showCommitWindow\|CommitWindowController" Sources` must return nothing.
- [ ] **Step 2:** Verification hook `case "commit"` calls `w.toggleCommitPanel()`; add a `CE_SNAPSHOT` render of panel + diff tab for headless visual check.
- [ ] **Step 3:** Run `swift build` and `CE_SELFTEST=1` → all pass; `CE_SNAPSHOT=1` commit screenshot reviewed (headless only).
- [ ] **Step 4:** Update README keymap/feature line if it mentions the Commit window. Commit `feat: Cmd+K opens the left Commit panel; remove standalone commit window`, then push main (pre-authorised once green).
