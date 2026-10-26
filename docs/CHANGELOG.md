# Changelog

Version is `0.<commit count>` (see build-app.sh); the installer is `dist/Kode-<version>.dmg`.

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
