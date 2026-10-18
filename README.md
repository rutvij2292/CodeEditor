# Kode

A light, native macOS code editor (Swift/AppKit) built as a low-memory alternative to PhpStorm for Laravel/PHP, Blade, JS/TS, Vue/React, HTML and CSS work. Runs next to CLI AI tools such as Claude Code or Gemini.

## Features
- tree-sitter syntax highlighting (PHP, Blade, JS/TS/TSX, HTML, CSS/SCSS, JSON, YAML, Markdown, Bash, XML), bracket pair colouring, code folding, breadcrumbs, inline Git blame
- Language servers (lazy, per project): Intelephense, TypeScript, HTML/CSS/JSON, Tailwind, Volar; ⌃Space completion, hover, go-to-definition, rename, diagnostics
- Laravel ⌘-click navigation (views, routes, config, env, lang, components, Livewire)
- Git: ⌘K Commit window with line-by-line picking, side-by-side diff and merge, log, stash, push
- Fast fuzzy file/class/symbol search (⌘⇧O, ⌘O, ⇧⇧), find in files, docked terminal (⌥F12)
- PhpStorm-style keymap, IntelliJ Light / Darcula themes, JetBrains Mono

## Build and install
```sh
./build-app.sh          # dist/Kode.app (ad-hoc signed)
./scripts/make-dmg.sh   # dist/Kode-<version>.dmg
```
Requires the Swift toolchain (`swift build --build-system native` is used). On another Mac, first launch of an ad-hoc signed app needs right-click → Open.

## Checks
`CE_SELFTEST=1 dist/Kode.app/Contents/MacOS/Kode` runs the logic self-tests; `CE_SNAPSHOT=1` renders headless screenshots.

The app name lives in `Sources/CodeEditor/Brand.swift`.
