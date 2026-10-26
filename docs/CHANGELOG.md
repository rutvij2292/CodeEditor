# Changelog

Version is `0.<commit count>` (see build-app.sh); the installer is `dist/Kode-<version>.dmg`.

## 0.258
- Native engines are the default for PHP, JS/TS, Vue, HTML/CSS and Tailwind. The TypeScript server and Volar are off; Python is opt-in.
- Engine registry: each language engine has its own switches in Settings.
- PHP completion v2: expected-type ranking, Smart Completion (Ctrl-Shift-Space), Complete Current Statement (Ctrl-Shift-Return), postfix templates, better auto-import, Eloquent `where<Column>` and `$casts`, richer popup rows.
- Cmd-hover link highlight is skipped on plain JS/TS files (Cmd-click still navigates).

## 0.260
- Inline Git blame is off by default; toggle with Ctrl-Option-B (Git menu). It is hidden on blank lines, where it used to cover the caret.
- Backspace on a whitespace-only line clears its indentation in one press.
- File picker: the directory column keeps its width, so paths are no longer cut to "…tes".
