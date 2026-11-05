# Commit tool window (PhpStorm-style Cmd+K) — design

## Intent
Cmd+K in Kode today opens a standalone 1120x780 window (`CommitWindow.swift`) hosting `GitPanelController`. The user wants PhpStorm's behaviour: a **Commit panel docked on the left beside the editor**, where clicking a file opens its diff **in the editor area**, so the diff stays visible while writing the commit message. Goal: Kode replaces PhpStorm for daily git work, staying light.

## Goals
- Cmd+K (Git > Commit…) toggles a left-side tool window with two tabs: **Commit** and **Stash**.
- Commit tab, top to bottom: small toolbar, changes tree, Amend row, message box, Commit / Commit and Push buttons.
  - Toolbar: refresh, rollback, diff preview/show-diff, expand all, collapse all (a "group by" control is optional).
  - Tree: reuse existing grouping (Conflicts, Staged, Changes, Unversioned Files), per-file checkboxes, scope colours (`GitColors`, test/generated tinting from the last commit).
  - Message box + Amend + "Draft with Claude" + Commit / Commit and Push (⌥⌘K) keep current behaviour.
- Clicking a file in the tree opens its diff as a tab in the editor area, reusing the existing side-by-side diff view (line checkboxes / partial staging, Prev/Next change, Stage Selected). Closing the panel leaves diff tabs open like any tab.
- Stash tab reuses existing stash code (`GitStashView`, `GitRepoExtras` stash push/apply) as a tab instead of a popover.
- Cmd+K again or Esc (when focus is in the panel) hides the panel. Push… (⇧⌘K) and other entry points that currently call `showCommitWindow { ... }` keep working against the new panel.
- Remove the standalone commit window once the panel works. Non-git-repo projects still get the "not a Git repository" alert.

## Non-goals
- No Shelf tab or shelve/unshelve (Kode has no shelf code; deferred).
- No Git menu additions (Merge, Rebase, Reset HEAD, Worktrees, Show Git Log, Tag, Remotes, Clone, Patch, ⌥⌘N). That is a separate, later project.
- No changes to the Log view or the branch toolbar: **Log stays in the bottom Git panel (⌘9)**. That panel keeps working as today.

## Anti-goals
- Must not regress commit, amend, partial staging, Commit and Push, merge/rebase Continue/Abort, or conflict handling.
- Must not add RAM or CPU cost when the panel is closed: build lazily on first Cmd+K, no polling, no background timers (RAM/lightweight is the project's #1 priority).

## Constraints
- Native Swift/AppKit, existing project at `Sources/CodeEditor/`. Reuse `GitPanelController` pieces (`GitPanel.swift`, ~86 KB) rather than rewriting; the tree, commit box and diff view should be split out/hosted differently, not duplicated.
- Keymap rule from project memory applies (tool-window key scheme); ⌘9 and ⌥⌘K stay as they are.
- Verify GUI headless; never pop windows on the user's screen. Build must be green and self-test (`Verification.swift` hooks) updated before pushing to main (user pre-authorised push after green build + self-test).

## Decided by the user
- Left-panel tool window, like the PhpStorm screenshot.
- Diff opens in the editor area.
- Shelf left out; Panel first, Git menu afterwards.
- The Commit panel **swaps into the left slot** shared with the project file tree (PhpStorm-style): Cmd+K shows Commit in place of the file tree; Cmd+K again/Esc restores the file tree. No second column.

## Decided by me (check these)
- Tabs are Commit and Stash only.
- Log remains in the bottom Git panel.
- Esc / Cmd+K again hides the panel.
- Lazy build, no polling.

- Diff opens in a single reused preview tab, replaced on each file click (as PhpStorm's diff preview); it refreshes after stage/commit/revert and closes if its file no longer has changes. It coexists with a normal editor tab of the same file.
- Opening the panel focuses the message box; Esc/Cmd+K hides it and returns focus to the previously focused editor. Cmd+K with the panel open but unfocused just focuses it.
- One commit UI only: the bottom Git panel (⌘9) becomes Log-only; the Changes/commit UI lives solely in the left panel, so no shared-state problem.
- The standalone commit window and its saved-frame default are removed in the same change, once the build and self-test (hooks updated) are green.

## Left to the builder
- How to split `GitPanelController` so the bottom panel (Log) and the new left panel share the tree/commit box code.
- How the left tool window plugs into the existing tool-window/sidebar system and its width persistence.
- How diff tabs integrate with the existing editor tab model.
- Exact toolbar icons and spacing; keep them consistent with current UI polish.
