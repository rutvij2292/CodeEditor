# Changelog

Version is `0.<commit count>` (see build-app.sh); the installer is `dist/Kode-<version>.dmg`.

## 0.258
- Native engines are the default for PHP, JS/TS, Vue, HTML/CSS and Tailwind. The TypeScript server and Volar are off; Python is opt-in.
- Engine registry: each language engine has its own switches in Settings.
- PHP completion v2: expected-type ranking, Smart Completion (Ctrl-Shift-Space), Complete Current Statement (Ctrl-Shift-Return), postfix templates, better auto-import, Eloquent `where<Column>` and `$casts`, richer popup rows.
- Cmd-hover link highlight is skipped on plain JS/TS files (Cmd-click still navigates).
