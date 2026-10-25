# Native CSS / HTML / Tailwind language service

Kode answers completion, hover and go to definition for CSS, HTML and Tailwind classes itself (Sources/CodeEditor/NativeWeb*.swift,
NativeCSS*.swift, NativeHTML*.swift, NativeTailwind*.swift), the same way the native PHP engine does. No process is started, nothing polls,
and the external servers (vscode-html / vscode-css / tailwindcss language servers) stay the fallback.

## Switches (Settings > Languages > HTML / CSS / Tailwind)

* **Native HTML, CSS and Tailwind services** (default on, `web.native.enabled`): off = every call answers "no opinion", the servers behave as before.
* **Use native only (stop the external servers)** (default off, `web.nativeOnly`): the html, css and tailwind servers are not started. The Tailwind
  server alone is ~200-400 MB resident, the HTML and CSS servers ~100-160 MB each.

Order of answers: hover and Cmd-click ask native first and only ask the server when native has none. Completion lists are merged with the
servers' (kinds are aligned with the servers' so duplicates collapse). The old hard-coded HTML / CSS / Tailwind built-in providers stay silent for
files native handles (and for projects whose Tailwind setup native resolved).

## What is covered

CSS (`.css .scss .less .pcss`, `<style>` blocks, inline `style=""`):
property names (with docs), values per property (keywords from the MDN data, named colors, color functions, units after a number, colors used in
the file, `var(--x)` from the file and every project stylesheet, gradients for image properties), at-rules, pseudo classes / elements, selector
class / id names from the project, `@apply`, media features. Hover: property docs, colors, custom properties (value + where declared),
pseudo selectors, at-rules, tags, `@apply` classes (generated CSS). Go to definition: `var(--x)` -> declarations, `@import` / `@use` / `url()` -> file
(scss partials, `~pkg`), `@apply custom-class` -> its rule, `.class` / `#id` in a selector -> markup usages (explicit Cmd-B only).

HTML (`.html .htm .vue .phtml .svelte .astro .twig .blade.php`): tag names (closing tag from the open-element stack), attribute names
(per element, global, events, aria, data-*, Vue / Alpine / Livewire), enumerated attribute values, `href` / `src` path completion, `#id` / `for=`
targets, class lists (project classes + Tailwind), `style=""`, `<style>` content. PHP / Blade / Twig / `{{ }}` regions are opaque. Hover: element and
attribute docs, class tokens (generated Tailwind CSS plus the project rule). Go to definition: class -> CSS rule (project stylesheets and the
file's own `<style>`), `id` -> `#id` rule, `href` / `src` -> file, `for` / `href="#x"` -> element.

Tailwind (v3 and v4): class completion with variants, negatives, opacity steps, arbitrary-value hints; hover shows the generated CSS exactly in the
Tailwind server's format (`/*4px*/` and `/*#hex*/` annotations included); class lists are found in `class` / `className` / `:class` / `ngClass` /
`class:list`, inside `{{ }}` / `<?php ?>` string literals, in `cn()` / `clsx()` / `twMerge()` / `cva()` / `tw```, in `@apply`, and in
template literals inside `<script>`.

* v3: `tailwind.config.{js,cjs,mjs,ts}` is parsed with a tolerant JavaScript literal parser (objects, arrays, `require('tailwindcss/colors')`,
  `colors.emerald`, spreads of `defaultTheme`, `theme('colors.x')`, arrow functions returning an object, `satisfies Config`, `defineConfig()`).
  `extend` is merged, replaced keys replace, `prefix`, `important`, `darkMode`, `screens`, plugin names (typography ...) are honoured.
* v4: `@theme` variables (and their relative `@import`s), `--*-*: initial` resets, `@utility`, `@custom-variant`, `@config`; default breakpoints, radius,
  shadow, blur scales; `p-13` style open-ended spacing; output uses `var(--color-*)` etc. like the server.
* Not evaluated (needs JavaScript): `presets`, wrapper functions such as `konsta/config(...)`, plugin-registered utilities. Such configs are flagged
  `incomplete`; classes native cannot resolve are simply not answered, so the server (when running) still handles them.

## Diagnostics

Only structure errors that are certain, in plain `.css` files: unclosed block, stray `}`, unterminated comment / string
(NativeWebDiag.swift; debounced, hidden-window aware, silent while a CSS server runs because it reports the same). Semantic checks (unknown
property / class, HTML tag balance) are deliberately left to the servers.

## Resource model

* One serial utility queue per project (`NWProject`). File lists are walked lazily on the first request that needs the project and refreshed when
  FSEvents mark it dirty (`FastTier.invalidate` hook); tag / attribute completion and plain JS typing never touch it.
* Parsed stylesheets are cached per file (stamp = mtime + size), at most 160 files / 8 MB / 1.5 MB per file; a request that touches more files
  than fit never evicts its own entries. Tailwind's resolved theme is ~40-60 KB and re-built when its input files change.
* CSS / HTML knowledge is a table of immortal string literals (NativeWebDataGen.swift, generated by `scripts/make-web-data.js` from the MIT licensed
  vscode-css-languageservice / vscode-html-languageservice data) read lazily; nothing is copied until a record is needed.
* `NativeWeb.trimMemory()` drops every cache on memory pressure, when the app is hidden and in power-saver mode.

## Tools

* `CE_WEB_ONLY=1 CE_SELFTEST=1 .build/debug/CodeEditor` runs only the native web checks (SelfTestNativeWeb.swift, SelfTestNativeWebPerf.swift).
* `CE_WEB_BENCH=<project> [CE_WEB_BENCH_OUT=native.json] [CE_WEB_BENCH_ALL=1] CE_SELFTEST=1 .build/debug/CodeEditor` samples positions from a real project,
  times native answers, prints the footprint and writes the answers; `python3 scripts/bench-web-servers.py native.json out.json [--only html,css,tailwind] [--html-all]`
  replays them against the external servers (latency, RSS, answer parity). `CE_WEB_LOCATE=<file>:<line>:<col>` prints how the HTML scanner classifies a position.
