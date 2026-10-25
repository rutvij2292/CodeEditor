# Native engines: registry and the future plugin seam

Design note. Step 1 (done): one protocol and one registry, every dispatch point routed through it, no behaviour change.
Step 2 (not started): an `EditorKit` module boundary so an engine can live in its own SwiftPM target / plugin bundle.

## What exists today

| File | Role |
| --- | --- |
| `NativeEngine.swift` | `protocol NativeEngine` plus the engine-neutral value types (`NativeSigOutcome`, `NativeRenameOutcome`, `NativeSettingsSection`, ...) |
| `NativeEngines.swift` | the registry. ONE list (`builtin`) holds the engines; `register(_:)` appends (plugin loader); dispatch and fan-out live here |
| `NativeEngineAdapters.swift` | `PHPEngine`, `PythonEngine`, `WebEngine` (HTML / CSS / Tailwind), `JSEngine`, `VueEngine`: thin structs that forward to `NativePHP`, `NativePy`, `NativeWeb`, `NativeJS`, `NativeVue` (engine internals untouched) |

Adding or removing an engine is one line in `NativeEngines.builtin`. Nothing else in the editor names an engine any more:
hover, Cmd-hover underline, Cmd-B, find usages, rename, signature help, completion registration, diagnostics start, memory hooks,
FSEvents invalidation, server suppression, hover diagnostics, Settings > Languages rows and "Restore defaults" all go through `NativeEngines`.

### Ordering

`priority` decides who is asked first (lower first, ties keep list order): Vue 10, JS 20, PHP 30, Python 30, Web 40. A lookup asks
the engines that `handles(url)` one after the other; the first hit that passes the caller's `accept` wins and the rest are not asked;
when none answers the caller asks the external language server. So `.vue` is Vue, JS, Web, Volar; `.blade.php` is PHP, Web, server;
`.ts` is JS, Web (Tailwind class strings), server.

List order is Settings order and fan-out order. `completionRank` only exists so PHP's FastTier provider registers last (it wins
score ties when completion results are de-duplicated).

Per-engine switches that exist only to keep old behaviour exact: `emptyHoverIsAnswer` (PHP, Python), `underlinesHitRange` (Vue),
`providesSessionUI` (Python: needs the LSP session UI although it has no server), `supportsSignatureHelp` (PHP, JS).

## What a plugin would implement

A plugin is one `NativeEngine` value. The required members are `id`, `displayName`, `priority`, `handles(_:)` and `lookup(url:text:offset:completion:)`;
everything else has a no-op default:

- `goToDefinition(in:at:)`, `findUsages(_:tab:)`, `rename(_:)`, `signatureHelp(url:text:caret:completion:)`
- `hoverDiagnostics(for:)`, `startDiagnostics()`, `registerCompletion()`
- `invalidate(root:)`, `trimMemory()`, `installMemoryHooks()` (event driven, never timers)
- `settingsSections` (declarative toggles / pop-ups with label, accessibility label, help text, getter and setter), `resetPrefs()`
- `suppressesServer(_:root:)` (which external servers it replaces) and `suppressesBuiltinCompletion(_:for:)`

The plugin loader would build the engine (statically linked, or from a bundle's principal class) and call `NativeEngines.register`.
Registering a second engine with the same id replaces the first, so a plugin can supersede a built-in.

## The `EditorKit` boundary (not built)

The protocol's signatures mention host types. A plugin target can only compile if those live in a module both sides import
(`EditorKit`), or are replaced by plain value types. Needed on the boundary:

| Host type | Used for | Notes |
| --- | --- | --- |
| `NPHit`, `NPTarget` | every lookup result (hover markdown, targets, range, `inferred`) | born in `NativePHPResolve.swift`; already plain structs, move as-is. Rename to `EKHit` / `EKTarget` |
| `CompletionItem`, `CompletionContext`, `CompletionRegistry`, `CompletionProvider` | completion | `CompletionRegistry.register(_:forExtensions:)` is the only entry the engines use |
| `LSPDiagnostic` | hover diagnostics and the diagnostics controllers | plain struct (range, severity, message, source) |
| `EditorTab` accessors | go to definition / find usages / rename need: `url`, `textView.string`, `selectedRange`, `setSelectedRange`, `window`, `projectRoot`, `onOpenURL` | expose a small `EditorBuffer` protocol (text, selection, url, window, open(url, line, column)) instead of the class |
| `ProjectWindow` | find usages and rename take it | replace by a `ProjectHost` protocol: current buffer, root, `window`, show-results panel, quick picker |
| quick-picker items (`PickerItem`) | find usages result list, "Go to ..." chooser | plain struct; the picker itself stays in the host behind `ProjectHost.showResults` |
| `LanguageServers` (`openLocation`, `report`, `rename`) | engines open locations and report problems | `HostServices` protocol: `open(url, line, column)`, `report(message)` |
| `LanguageServerManager.serverPreferenceChanged(_:)` | `setNativeOnly` toggles a server | `HostServices.serverPreferenceChanged(id)` |
| `NativeSettingsSection` / `Toggle` / `Choice` | settings | already host-neutral value types (`NativeEngine.swift`) |
| `NativeSigOutcome`, `NativeRenameOutcome`, `NativeBuiltinCompletionTopic` | protocol results | already host-neutral |
| `AppEnv.headless`, `PowerState` | memory hooks trim on saver / hidden | `HostServices.isHeadless`, `HostServices.onLowPower` |

## What blocks static SwiftPM targets today

Everything is one executable target (`CodeEditor`, 341 files); Swift has no per-file visibility between modules, so an engine
can only move out once its dependencies are in a library target. Measured on the 88 `Native*.swift` files (27.7k lines):

- Shared host types referenced from engine files (files / references): `NPHit` 18 / 133, `FastProject` 30 / 101, `EditorTab` 16 / 49, `CompletionItem` 10 / 74,
  `CompletionContext` 7 / 10, `ProjectWindow` 7 / 28, `LSPDiagnostic` 6 / 15, `PickerItem` 6 / 18, `LanguageServers` 12 / 23,
  `LaravelFS` 18 / 54, `AppEnv` 13 / 31, `PowerState` 12 / 22, `CompletionRegistry` 4 / 4, `LSPSession` 3 / 4.
- The engines are not fully independent: Vue calls into the JS and Web resolvers (3 and 2 Vue files), and `NativeJS`, `NativeVue`, `NativeWeb`
  and `NativePy` all open their targets with `NativePHP.open(hit, from:, offset:)`, which is really host code (opens a tab or shows a
  chooser) and must become a host service first. JS, Web and Python do not reference each other.
- The PHP engine is welded to the Laravel layer: `FastProject`, `FTClass`, `LaravelFS`, `FastTier.root(for:)`, `PhpStubs`, plus `FastTierRules` and
  `LSPProblems` (`NativePHPDiag.merged`) and `Menu.swift` (`NativePHPNav` selectors) which still name PHP directly (see below).
- Tree-sitter: 28 engine files import `SwiftTreeSitter` and five import grammar products (`TreeSitterJavaScript/TypeScript/TSX/Python` for
  the engines). Grammars are already separate packages, so this only needs the target dependency lines.
- UI inside engine files: `NativePHPRefsUI`, `NativeJSRename`, `NativePyRefs`, `NativeVueRefs` build result lists and rename sheets with AppKit
  (`LSPSession.promptSheet`, `LanguageServers.report`); they need the `ProjectHost` / `HostServices` protocols above.
- Test hooks: ~12 self-test files reach into engine internals (`NativeJS.trimMemory`, `NWProject.shared`, ...). Those tests move with their engine.
- `SelfTest*` and `Settings*` still use concrete engine types for engine-specific checks (intended, they move with the engine).

Suggested order for step 2: (1) move `NPHit` and friends, `CompletionItem` family, `LSPDiagnostic`, `PickerItem` into a library target `EditorKit`
with `EditorBuffer` / `ProjectHost` / `HostServices` protocols; (2) make `NativePHP.open` a host service; (3) split engines in dependency order
(Python has the fewest ties, then Web, then JS, then Vue, then PHP with Laravel last); (4) the executable lists engines in `NativeEngines.builtin`
or loads them from bundles.

## Remaining hand-written references to engines outside the engine files

These are not dispatch chains; each is tied to one engine's own feature:

- `FastTierRules.swift`: `NativePHP.resolver(...)` (Laravel completion rules use the PHP resolver).
- `LSPProblems.swift`: `NativePHPDiag.merged(...)` (de-duplicates PHP native and Intelephense problems).
- `Menu.swift`: `NativePHPNav` selectors (Go to Implementation / Type Declaration, PHP only).
- `SymbolExtractor.swift`: `NativeJS.documentSymbols(...)` (file structure for TS / Vue).
- `SettingsSupport`/`SettingsPanesMore`: none left; both render from `NativeEngines`.

A future engine-neutral hook for each (`documentSymbols`, `mergeProblems`, `menuItems`) would remove them; they were left because they
are single call sites with no chain and no merge conflicts so far.
