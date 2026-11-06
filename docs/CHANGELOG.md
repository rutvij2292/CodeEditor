# Changelog

Version is `0.<commit count>` (see build-app.sh); the installer is `dist/Kode-<version>.dmg`.

## 0.330
- **Change Ledger**: when you accept agent changes in Claude Changes (a file, a session or all), Kode records them in a per-project ledger: the agent session title, date, files, and the changed methods / classes with +/- lines. Open it from the new **Ledger** tool window (⌥⌘4, tool strip, View menu).
- **Your own notes**: the Claude Changes panel has a note field ("What does this change do, in your words?"). Whatever you type is saved with the next accept (empty is fine, Accept is never blocked). In the Ledger you can edit any note later, search across title, note, files and methods, and double-click a method to jump to it.
- Stored as one small JSON file per project in Application Support (capped at 300 sessions / 256 KB, notes 2,000 characters); no AI calls, no background work. Per-hunk accepts from the editor gutter are not recorded yet.

## 0.324
- Problems panel redone PhpStorm-style: **File** (current file, with its count), **Project Errors** and **Inspections** tabs, problems grouped by category then inspection, and a detail pane with the message, code snippet and Claude's answer.
- **Project Errors** scans the whole project only when you press Scan (cancellable, one file at a time, low priority, capped at 5,000 problems). It skips `vendor`, `node_modules`, `public/build`, `.git`, `storage`, `bootstrap/cache` and other build output. Results are dropped when you leave the tab.
- **Evaluate with Claude** (right-click a problem, group or file, or the button in the detail pane): one one-shot call for up to 20 problems, answered separately per problem (real / false positive / ignorable, how hard, explanation, proposed fix). Easy fixes get **Apply fix** (one undoable edit, refused unless the text matches exactly once); harder ones get **Hand to agent**. Only runs when asked.

## 0.279
- Soft wrap: the Edit-menu toggle and Settings / View now share one preference; end-to-end wrap test.
- Markdown / viewer files: the breadcrumb bar keeps room for the Source / Split / Preview switch (no more overprinting); calmer notice banner (icon, light tint, recessed buttons, 26 pt); GitHub-style preview headings and no underline on links.

## 0.276
- Route action completion: `Route::get('x', [LoginController::class, '|'])` offers the controller's public methods (also `[$this, '|']`); verified through the real completion pipeline.
- Dev probes: `CE_COMPL_ASYNC` (typed completion), `CE_IDLE_FILE` (typing burst then idle: CPU / wakeups / energy; idle settles to ~0 within 10 s).

## 0.274
- Single-tab mode no longer shows an empty strip row: the strip collapses to zero height (it returns with several tabs or a split); the unsaved dot moves to the window's close button.
- Hot updates for the Vue / web engines: saving a file no longer rebuilds their file lists or memos (a `.js` / `.ts` save rebuilds only globals and routes); creating / deleting files refreshes the lists.

## 0.272
- One editor tab by default: only the active file's tab is shown, the other files stay open for Cmd-E / Cmd-[ ]. View > Multiple Editor Tabs brings the full strip back.

## 0.270
- Scrolling no longer jumps: files up to 6,000 lines are laid out in full on open, so the scroll bar is exact; bigger files fill in their layout in the background.
- The terminal (and Claude Code in it) no longer opens when a project opens; it starts when you ask for it. Settings keep "reopen terminal on launch" off.
- Tab after a tag name at the start of a line in Vue / HTML (`h1`, `div`) expands it to `<h1></h1>` with the caret between.
- Shift-Home / Shift-End (fn + Shift + Left / Right) select to the line start / end.
- Completion: the popup no longer closes on the first letter typed after `::` or `->`, and scattered middle-of-word fuzzy hits (`po` offering dispatchToRoute) are gone; a query that starts any word of a name (`replace` for str_replace) still matches.

## 0.268
- Hot index updates: a saved, created, deleted or moved file updates the file list, the symbol table and the PHP completion index from the changed paths only; no project rescans. Large batches (checkout, install) and Reload from Disk still do a full scan.
- Go to File no longer rescans the project every time it opens.

## 0.266
- Double Shift opens the tabbed Search Everywhere: All, Classes, Files, Symbols, Actions, Text; Tab / Shift-Tab switch tabs, "Include non-project items" adds vendor classes, files and members, the footer shows the full path, Shift-Return opens in a right split. The Text tab searches file contents.
- Return after an open tag indents one level; Return between `<div>|</div>` expands onto three lines.
- The project index no longer re-scans on a timer: only when files change.

## 0.264
- Fixed the caret being drawn at column 0 after Return on an indented line (TextKit lays out line-end blanks with zero width; the caret x is now computed from the column).

## 0.263
- Return on an empty line keeps the surrounding indent (the caret no longer jumps to column 0); after a line ending in `{`, `(` or `[` it indents one level.
- HTML / Vue: typing `>` adds the end tag with the caret between; component completion adds the end tag too.
- HTML / Vue: no auto popup while typing text between tags (Ctrl-Space still works); `{ }`, attributes and tag names still complete.
- Typing stays light in big modular Laravel apps: the project index re-walked every directory every 1.5 s while typing; now only when files change (FSEvents), with a 60 s safety net.

## 0.262
- New Window (File menu, Shift-Cmd-N, and the Dock icon menu): an empty window with the project picker.
- The native JS/TS engine is off by default (Settings > Languages); native Python stays off.

## 0.258
- Native engines are the default for PHP, JS/TS, Vue, HTML/CSS and Tailwind. The TypeScript server and Volar are off; Python is opt-in.
- Engine registry: each language engine has its own switches in Settings.
- PHP completion v2: expected-type ranking, Smart Completion (Ctrl-Shift-Space), Complete Current Statement (Ctrl-Shift-Return), postfix templates, better auto-import, Eloquent `where<Column>` and `$casts`, richer popup rows.
- Cmd-hover link highlight is skipped on plain JS/TS files (Cmd-click still navigates).

## 0.260
- Inline Git blame is off by default; toggle with Ctrl-Option-B (Git menu). It is hidden on blank lines, where it used to cover the caret.
- Backspace on a whitespace-only line clears its indentation in one press.
- File picker: the directory column keeps its width, so paths are no longer cut to "…tes".
