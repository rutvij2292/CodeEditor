# Native PHP language service

Goal: progressively replace Intelephense (free tier, 160-600 MB RAM) with a native Swift service built on the fast tier
(`FastTierIndex`, `FastTierPHP`, `FastTierTypes`/`FTEval`, `VendorIndex`, `PHPLex`). Footprint rule: lazy, capped, no
polling, nothing big resident.

## Switch

Settings > Languages > PHP > "Use native PHP engine only (stop Intelephense)" (pref `php.nativeOnly`, default OFF).
When ON, `LanguageServerPrefs.isEnabled("intelephense")` is false, so the server is never started (or is stopped through
`serverPreferenceChanged`). When OFF, native answers first and Intelephense (if running) is the fallback.

## Architecture (phase 1)

| File | Role |
| --- | --- |
| `NativePHP.swift` | Public API: `lookup` (sync), `lookupAsync` (hover / link underline), `goToDefinition(in:at:)`, pref, picker for multiple targets. Memoises the last lex/parse of the live buffer. |
| `NativePHPResolve.swift` | `NPResolver`: token classification (class, member, function, constant, variable, string, docblock), member search over the type hierarchy + Eloquent virtual members + facades (`@see`, `@method`), hover markdown. One instance per request on the project's fast-tier queue. |
| `NativePHPDocs.swift` | `NPFiles` (last 6 PHP texts, 6 MB cap), `NPDoc` (docblock locate/parse/render), line/column helpers. |
| `NativePHPFunctions.swift` | `NPFuncIndex`: global functions/constants from composer autoload files (app helpers + vendor `helpers.php`); names and offsets only, max 3 projects. |
| `NativePHPBuiltins.swift` | Doc-only tables: ~180 PHP functions, ~50 constants, core classes. |
| `FastTierPHP.swift` (extended) | `FTMethod/FTProp/FTClass` now carry declaration offsets (`loc`, `declStart`, `nameLoc`, `declLocs`). |

Wiring (all additive): `AppDelegate` `beforeDefinition` calls `NativePHP.goToDefinition` after the Laravel navigator;
`LSPSession.showHover` and `updateLinkHighlight` ask native first; `LanguageServerPrefs.isEnabled`; Languages settings pane.

Adding a feature (phase 2+) means a new method on `NPResolver` / a new `NativePHP*.swift` file that reuses
`NativePHP.resolver(...)`, `NPResolver.tokenAt`, `findMember`, `memberHit`, `NPFiles`.

## Intelephense features vs native

| Feature | Native status |
| --- | --- |
| Go to definition: classes/interfaces/traits/enums (code, `use`, type hints, extends/implements, new, static, catch, docblock types, class-name strings) | done |
| Go to definition: methods/properties/constants/enum cases via `$this`, `$var`, chains, `Foo::`, `self/static/parent` | done |
| Go to definition: Eloquent relations, scopes, accessors, columns (migration line), `with('a.b')`, `where('col')` | done |
| Go to definition: facades (`Cache::get` -> manager via `@see`, `@method` tags), `@property`/`@method` docblock members | done |
| Go to definition: user + vendor global functions (composer autoload files), user constants | done |
| Go to definition: variable -> declaration | done (param / assignment / foreach) |
| Hover: signature, return type, docblock summary, `@param`/`@return`/`@throws`/deprecated, origin file:line | done |
| Hover: built-in functions/constants/classes (doc only) | done (curated subset) |
| Blade-embedded PHP (`{{ }}`, `{!! !!}`, `@php`, directive arguments) | done |
| Cmd-hover link underline | done |
| Completion | done earlier (fast tier) |
| Signature help | planned (phase 2: reuse `findMember` + param split; trigger on `(` and `,`) |
| Find usages | planned (phase 2: token scan over project files that mention the name, filtered by resolve) |
| Rename | planned (phase 2, on top of usages; Intelephense needs a licence for it) |
| Diagnostics (undefined symbol/method, unused import, syntax) | planned (phase 3; tree-sitter syntax errors first) |
| Document / workspace symbols | partly (SymbolIndex / Go to Symbol exist) |
| Go to implementation, type definition | planned |
| Code actions / formatting | exist separately (PHP import quick fix, Pint) |
| Inlay hints, semantic tokens, folding via LSP | not planned (tree-sitter highlighting exists) |

## Accuracy limits

* Only the first type in a file is parsed (one class per file, PSR-4 style).
* Types come from FTEval: declared types, `new`, assignments, `@var`, params, foreach, Eloquent chains. Docblock-only return
  types (`@return Foo`) are not used for inference yet, so `auth()->user()->` has no type.
* No generics, no flow analysis, no union/intersection narrowing beyond the first class name.
* Overloads: `__call`/`__get` magic only for Eloquent builder forwarding, facades and `@method`/`@property` tags.
* Dynamic names (`$obj->$name`, `$class::make()` with variable class) are not resolved.
* Built-in function/constant/class docs are a curated subset; unknown built-ins give no hover.
