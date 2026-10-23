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
| `NativePHPDiag.swift` | Diagnostics entry: `NativePHPDiag.analyze(url:text:fp:groups:)`, rule groups (`php.diag.<group>` prefs), severity pref, `dedupe` / `merged` against Intelephense, line table. |
| `NativePHPDiagSyntax.swift` | Syntax errors from the vendored tree-sitter PHP grammar (top-most ERROR / MISSING nodes, one per line, max 5). |
| `NativePHPDiagLint.swift` | Optional `php -l` second opinion (only when tree-sitter already found an error): a grammar blind spot never becomes a red error. |
| `NativePHPDiagContext.swift` / `...Names.swift` | Token facts (brace kinds, imports, namespace, declared types), undefined classes, unused / duplicate imports. |
| `NativePHPDiagFlow.swift` / `...Members.swift` | Function scopes and undefined variables; undefined methods / properties and too-few-arguments checks on certain receivers. |
| `NativePHPDiagController.swift` | Per-tab driver (debounced after edits, no polling) and the squiggle / dimming overlay; feeds `NativeProblems` (Problems panel) and the hover. |
| `NativePHPDiagBuiltins.swift` | Names of PHP 8.3 + common extension classes (never reported as undefined). |
| `FastTierPHP.swift` (extended) | `FTMethod/FTProp/FTClass` now carry declaration offsets (`loc`, `declStart`, `nameLoc`, `declLocs`). |

Wiring (all additive): `AppDelegate` `beforeDefinition` calls `NativePHP.goToDefinition` after the Laravel navigator;
`LSPSession.showHover` and `updateLinkHighlight` ask native first; `LanguageServerPrefs.isEnabled`; Languages settings pane.

Adding a feature (phase 2+) means a new method on `NPResolver` / a new `NativePHP*.swift` file that reuses
`NativePHP.resolver(...)`, `NPResolver.tokenAt`, `findMember`, `memberHit`, `NPFiles`.

## Phase 2a (signature help, type inference, implementation)

| File | Role |
| --- | --- |
| `NativePHPSig.swift` | `NPResolver.signatureHelp(at:)`: backward token scan for the innermost call (skips strings/comments, nested calls, arrays; stops at `{` and `;`), callee resolution (member / static / `new` / function / closure variable), parameter splitting, active parameter, LSP-shaped payload rendered by `LSPUIParse.signature`. `LSPSession.showSignature` asks native first and only falls back to Intelephense on `.unknown`. |
| `NativePHPSigTypes.swift` | FTEval extension: docblock `@return`/`@var`/`@param` types (unions, `static`, `$this`, `Foo[]`, `array<K,V>`, `Collection<K,V>` -> `.collection(Foo)` element hint, `class-string<T>`, basic `@template` and conditional `($x is class-string<T> ? T : mixed)`), property docs, `@property`/`@method`, helper function return types (user + vendor helpers), `auth()->user()` / `Auth::user()` / `$request->user()` / guards from `config/auth.php`, `app(Foo::class)` / `app('cache')` / `app()->make(Foo::class)`, facade roots from `getFacadeAccessor` (alias table) or `@see`. Per-request caches only. |
| `NativePHPImpl.swift` | Go to Implementation / Type Declaration (`NativePHPNav` menu targets). Implementers: one pass over project PSR-4 files (text prefilter, header regex into a transient array), FQN-confirmed with the class parser, capped at 200 results / 8000 files. No resident inheritance table. |

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
| Signature help | done (phase 2a): functions, built-ins, methods, static methods, constructors, closure variables, facades, Eloquent builder forwarding/scopes; active parameter incl. named args, variadics, nested calls, strings/comments; Intelephense only as fallback when the callee is unresolved |
| Find usages (Alt-F7) | done (phase 2b): classes, members (override/interface family), props, consts, enum cases, functions, global consts, local vars/params; native first, LSP only when native finds nothing. See "Find usages and rename" |
| Rename (Shift-F6) | done (phase 2b): classes (+ PSR-4 file, `use`, `::class`, FQCN strings, docblocks), methods (family through hierarchy, array callables, scopes), props (incl. promoted), consts, enum cases, functions, variables/params; preview list, conflict refusal, vendor warning |
| Diagnostics: syntax errors (tree-sitter, confirmed by `php -l` when PHP is installed) | done |
| Diagnostics: undefined classes (type hints, new, static, extends/implements, catch, instanceof, attributes, trait use) | done (warning by default, error optional) |
| Diagnostics: unused imports (dimmed hint), duplicate imports / name clashes; quick fix = Optimize imports (PHPImports) | done |
| Diagnostics: undefined variables (function scopes only, conservative) | done |
| Diagnostics: undefined methods / properties on `$this`, `self::`, `Foo::`, typed parameters, `new` locals (certain hierarchy, no magic) | done |
| Diagnostics: too few arguments (project methods, constructors, helper and same-file functions) | done |
| Diagnostics in Problems panel + editor squiggles + hover, deduplicated against Intelephense | done |
| Document / workspace symbols | partly (SymbolIndex / Go to Symbol exist) |
| Go to implementation (Cmd-Opt-B), type declaration (Ctrl-Shift-B) | done (phase 2a): interface/abstract/concrete method -> implementers + overriders, class/interface -> transitive subclasses (project PSR-4 code only), variable/property/call -> its class |
| Code actions / formatting | exist separately (PHP import quick fix, Pint) |
| Inlay hints, semantic tokens, folding via LSP | not planned (tree-sitter highlighting exists) |

## Find usages and rename (phase 2b)

| File | Role |
| --- | --- |
| `NativePHPRefs.swift` | `NPRefs.identify` (symbol at caret via `NPResolver` in light mode), bounded mmap byte prefilter of PHP files (vendor only on request), per-file lex + resolve of name-matching tokens, `collect` / `collectAsync` (chunks of 6 files on the project's fast-tier queue, cancellable `CancelToken`, cap 2000), `NPRelations` (hierarchy on demand). |
| `NativePHPRename.swift` | `NPRename.plan` (validation, conflicts, member family roots, file rename), `prepare` + `apply` (open tabs via text view, one undo group per file; closed files atomic after a disk re-check; then PSR-4 file move). |
| `NativePHPRefsUI.swift` | Alt-F7 list (existing `QuickPicker`, rows `snippet - rel:line [role]`), Shift-F6 prompt, preview list whose first row applies, vendor confirm. |

Matching rule: a token counts when `NPResolver` resolves it to a declaration of the same kind and name in a class related to the target (same class, ancestor or descendant). Rename widens this to the whole family (every class below the topmost declaring ancestor, so interface implementations and siblings are renamed together). Roles: declaration, import, read, write, usage, docblock, string. Member usages whose receiver type is unknown are listed as "possible" (find) and never edited (rename warns with a count).

Cost: nothing resident. A search maps each candidate file once, lexes it once, keeps hits only (snippet text, no file text), and uses at most the 6-entry `NPFiles` cache. Rename of a vendor symbol scans vendor/ and asks for confirmation.

## Accuracy limits (find usages / rename)

* Untyped receivers (`$x->publish()` with unknown `$x`) are not resolved: shown as possible in Find Usages, not renamed.
* Eloquent columns/attributes, `@property`/`@method` members and accessors are not supported (rename refuses accessors); scopes and relations are.
* Named arguments, `compact('x')`, `$$var`, `'callable'` function strings, Blade components and `route()`/`view()` names are not followed.
* Only the first type per file is parsed; members of additional classes in one file are invisible.
* String and docblock hits for classes are matched by FQCN/short name resolved through the file's `use` list; aliases are found but never edited.
* The target's declaration file is read from disk unless the tab is dirty; dirty tabs are scanned from their buffer.

## Accuracy limits

* Only the first type in a file is parsed (one class per file, PSR-4 style).
* Types come from FTEval: declared types, docblock `@return`/`@var`/`@param`, `new`, assignments, params, foreach, Eloquent chains,
  auth/container/facade helpers (see phase 2a). A docblock directly above `$x = ...` overrides the inferred type.
* Generics are element hints only: `Collection<int, Foo>`, `array<int, Foo>`, `Foo[]` all become one collection-of-Foo type (a plain
  array of Foo therefore lists Collection members in completion). Templates: only `of Bound` bounds and `class-string<T>` params.
  No flow analysis, no union/intersection narrowing beyond the first resolvable class name.
* Auth user: first provider model of the guard in `config/auth.php` (regex parse, not an evaluator); falls back to `App\Models\User`.
* Signature help: no overload lists (one signature per callee), no help inside `#[Attribute(...)]` or for dynamic callees
  (`$obj->$m()`, `$class::make()`); callee must be resolvable by the fast tier.
* Go to Implementation scans the project's PSR-4 source only (not vendor); implementers declared in vendor or generated at runtime are
  not listed; trait-provided implementations are not followed.
* Overloads: `__call`/`__get` magic only for Eloquent builder forwarding, facades and `@method`/`@property` tags.
* Dynamic names (`$obj->$name`, `$class::make()` with variable class) are not resolved.
* Built-in function/constant/class docs are a curated subset; unknown built-ins give no hover.

## Diagnostics (phase 2c)

Settings > Languages > PHP > "PHP diagnostics": one checkbox per rule group (syntax, classes, imports, variables, members, arguments)
and the severity of undefined classes (Warning default / Error). Prefs: `php.diag.syntax|classes|imports|variables|members|args`,
`php.diag.classSeverity`, hidden `php.diag.confirmWithPHP` (default on). Native results replace Intelephense's when `php.nativeOnly`
is on; with Intelephense running, a native finding is dropped when the server already reports the same line and range (two errors on
one line count as the same syntax problem), in the Problems panel (`NativePHPDiag.merged`), the squiggles and the hover.

Cost: a pass runs once, 0.9 s after the last edit (2.5x in power-saver mode), only for the edited PHP tab while its window is visible,
on the project's fast-tier queue. Files over 600 KB (or 150k tokens) only get the syntax check; at most 200 findings are kept. Nothing
is retained between passes except the finding list, a 4-entry autoload-file class-name cache and the hash of the last linted text.
A background tab opened by session restore is analysed the first time it is touched. `php -l` (one short-lived process, 4 s limit,
temp file) runs only when tree-sitter already reported an error.

Rules and the situations in which they stay silent:

* Syntax: tree-sitter ERROR / MISSING nodes, first token as the squiggle, one finding per line, max 5. If `php -l` accepts the file the
  findings are dropped (grammar limits such as `(string) match (...)`, `($f)()` in ternaries, `"$a->class"`). Without a PHP binary the
  tree-sitter result stands. Any syntax error suppresses every semantic rule of that pass.
* Undefined class: only in class positions (new, extends, implements, instanceof, catch, `Foo::`, parameter / return / property types,
  attributes, trait `use`). Resolved through imports, the file namespace, the PSR-4 project map, the vendor index (once loaded; until then
  only project namespaces are judged), PHP built-ins (generated list), composer `autoload.files` declarations, facade aliases and
  `config/app.php` aliases. Silent for: multi-namespace files, files calling `class_alias` / `spl_autoload_register`, bare names in the
  global namespace, `Facades\...`, names under an `use App\Models;` namespace import, projects whose composer.json has a `classmap`
  (project names outside PSR-4 prefixes are not judged), Blade and mixed HTML templates. An undefined import is reported once on the
  `use` line, not at every use.
* Imports: unused when the alias appears nowhere outside `use` statements, not even as a word in a docblock or string; function / const
  imports are never reported; duplicates and alias clashes (error) are reported on the second import.
* Undefined variable: only inside function / method / closure bodies. A variable counts as defined when it is assigned, a parameter,
  a closure `use`, a foreach / catch / list / static / global variable, passed to any call (possible by-reference output), taken by
  reference, or named in an `@var` / `@param` docblock, anywhere in the scope (flow-insensitive). Never reported: isset / empty / `??` /
  unset operands, superglobals, `$this`, static properties, anything in a scope that uses extract / include / require / eval /
  `$$var` / get_defined_vars / parse_str, top-level script code, strings and heredocs (not scanned).
* Undefined method / property: receiver is `$this` (direct method bodies of the file's single class, not closures, not files with
  `$this instanceof` / `method_exists` / `is_callable` / `__call`), `self::` / `static::` / `parent::` / `Foo::`, a parameter with exactly one
  class type (not interface, not reassigned, not narrowed by instanceof or a docblock) or a variable assigned once from `new Foo`. The
  whole hierarchy (parents, interfaces, traits) must be known and free of `__call` / `__callStatic` / `__get` / `__set`, `@method` /
  `@property` / `@mixin` docblocks and enums; Eloquent models are therefore silent (vendor `Model` has `__call`). Trait `as` aliases, methods the
  parser missed but the text declares, and properties mentioned anywhere in the hierarchy (assignments, promoted, hooks) are accepted.
  Only the first hop of a chain is checked.
* Arguments: too few only (PHP raises ArgumentCountError; extra arguments are legal). Named arguments, spreads and first-class callable
  syntax are skipped; ambiguous overrides are skipped; functions come from the same file or composer autoload helper files without a namespace.
* Blade templates, `.phpstorm.meta.php`, `_ide_helper*.php` and templates that mix HTML with PHP are not analysed semantically.

Developer aid: `CE_SELFTEST=1 CE_DIAG_SCAN=/path/to/project [CE_DIAG_SCAN_DIRS=app,src] .build/debug/CodeEditor` prints every native finding
of a real project to stderr and exits (used to hunt false positives; on ~8000 real PHP files, application and vendor code, every
finding that was spot-checked was a true positive; the false positives found that way are fixtures in SelfTestNativePHPDiag).

Known accuracy limits: no flow analysis (a variable defined only after its use, or only in a branch, counts as defined); no type
inference beyond the receivers above; docblock-only types and generics are ignored; undefined constants, enum cases and class constants are not
checked; Intelephense-style "Expected N arguments" for too many arguments is not reported; unused variables / private members are not
reported; the first type of a file is the only one whose members are checked.
