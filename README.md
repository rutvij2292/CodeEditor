<p align="center"><img src="docs/images/icon.png" width="128" alt="Kode icon"></p>

# Kode

A light, native macOS code editor (Swift/AppKit) built as a low-memory alternative to PhpStorm for Laravel/PHP, Blade, JS/TS, Vue/React, HTML and CSS work. It sits next to CLI AI tools such as Claude Code or Gemini, and talks to Claude Code directly.

![Kode editing a Laravel controller](docs/images/editor.png)

## Highlights
- **Fast and small:** native Swift, TextKit, tree-sitter syntax highlighting (PHP, Blade, JS/TS/TSX, HTML, CSS/SCSS, JSON, YAML, Markdown, Bash, XML), bracket pair colouring, code folding, breadcrumbs, inline Git blame, JetBrains Mono, IntelliJ Light / Darcula themes. A power-saver mode follows Low Power Mode, battery and thermal state.
- **Code intelligence:** a built-in fast tier for Laravel and PHP (routes, views, config, env, translations, Eloquent columns and relations, class imports), plus language servers started lazily per project: Intelephense, TypeScript, HTML/CSS/JSON, Tailwind and Volar. ⌃Space completion, hover, go to definition, rename, diagnostics.
- **Laravel navigation:** ⌘-click on views, routes, config, env, lang keys, components and Livewire.
- **PhpStorm-style Git:** ⌘K Commit window with line-by-line picking, a branch widget and popup in the title bar, side-by-side diff and 3-way merge, log, stash, push.
- **Search:** fuzzy file, class and symbol search (⌘⇧O, ⌘O, ⇧⇧), find in files, docked terminal (⌥F12).
- **Viewers:** live Markdown preview with synced scrolling, JSON and YAML tree viewers with diagnostics, and Compose / GitHub Actions / `package.json` suggestions.
- **Claude Code integration:** Kode is an IDE for the `claude` CLI. It shares your selection, opens Claude's proposed edits in a diff you accept or reject, and shows diagnostics. See [docs/claude-code-bridge.md](docs/claude-code-bridge.md).

## Screenshots

### Commit window (⌘K)
![Commit window](docs/images/commit-window.png)

### Branches, the PhpStorm way
![Branch popup](docs/images/branch-popup.png)

### Pull request conflict resolver
Enter a PR number (or URL), resolve the conflicts in a 3-way merge, then commit and push.

![Pull request conflict resolver](docs/images/pr-conflict-resolver.png)

### Markdown preview with synced scrolling
![Markdown split view](docs/images/markdown-preview.png)

## Build and install
```sh
./build-app.sh          # dist/Kode.app (ad-hoc signed)
./scripts/make-dmg.sh   # dist/Kode-<version>.dmg
```
Requires the Swift toolchain (`swift build --build-system native` is used). On another Mac, the first launch of an ad-hoc signed app needs right-click → Open.

## Checks
`CE_SELFTEST=1 dist/Kode.app/Contents/MacOS/Kode` runs the logic self-tests, and `CE_SNAPSHOT=1` renders headless screenshots (the images above come from it, using a throwaway sample project).

The app name lives in `Sources/CodeEditor/Brand.swift`.
