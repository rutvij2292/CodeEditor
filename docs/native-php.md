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
| `NativePHPDocs.swift` | `NPFiles` (last 6 PHP texts, 3 M character cap), `NPDoc` (docblock locate/parse/render), line/column helpers. |
| `NativePHPFunctions.swift` | `NPFuncIndex`: global functions/constants from composer autoload files (app helpers + vendor `helpers.php`); names and offsets only, max 3 projects. |
| `PHPStubs.swift` + `PhpStubs/` | Bundled PHP built-in stubs (JetBrains phpstorm-stubs, Apache-2.0): lazy index lookup, parsed-class cache. See "Built-in stubs". |
| `NativePHPBuiltins.swift` | Offline fallback only: ~180 PHP function docs, ~50 constants, core class names (used when the stub directory is missing, and for one-line constant docs the stubs lack). |
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
| Definition + hover: built-in classes / interfaces / enums / functions / constants / members (PDO, DateTime, Exception, ZipArchive, SplFileObject, ArrayObject, Closure, Generator, DOM, SimpleXML, mysqli, curl_*, mb_*, json_*, preg_*, array_* ...) | done: opens the read-only stub (banner 'PHP built-in stub'), see "Built-in stubs" |
| Blade-embedded PHP (`{{ }}`, `{!! !!}`, `@php`, directive arguments) | done |
| Cmd-hover link underline | done |
| Completion | done earlier (fast tier) |
| Signature help | done (phase 2a): functions, built-ins (all stub functions, methods and constructors), methods, static methods, constructors, closure variables, facades, Eloquent builder forwarding/scopes; active parameter incl. named args, variadics, nested calls, strings/comments; Intelephense only as fallback when the callee is unresolved |
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
* Conditional `@return ($p is T ? A : B)` (also nested; `response()`, `redirect()`, `pick()`-style helpers and methods) is decided from the
  call's argument: an omitted argument takes its declared default, literal `null` / string / number / bool / array / `Foo::class` arguments are
  matched against `T`; any other argument expression gives no answer (never a guess).
* Receivers: `a ? b : c`, `a ?: c` and `a ?? c` evaluate both branches (agree or one unknown: that type; disagree: none). `[$a, $b] = $this->m()` /
  `list(...)` take element N of the `return [ ... ];` of a method in the same file (positional elements only). `"... $this->prop ..."` and
  `"{$a->b->c}"` resolve the property under the pointer. An untyped, undocumented property takes the class of its first `$this->p = new Foo(...)`
  in its own file (generated API clients). Migrations are read from `database/migrations` plus each module's `database/migrations` (next to a
  PSR-4 root, or one level below it for `"Modules\\": "Modules/"`).
* The live-buffer parse memo compares the full text, not just length + `NSString.hash` (which samples long strings), so a same-length edit never reuses a stale parse.
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
* Built-ins come from the bundled stubs (PHP 8.3 + the extensions listed under "Built-in stubs"); anything outside them (e.g. imagick, mongodb, swoole) has no hover or definition. Stub members are only as typed as the stubs are (e.g. `str_replace`'s `&$count` is untyped).

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

## Built-in stubs (PHP classes, functions, constants)

Source: [JetBrains/phpstorm-stubs](https://github.com/JetBrains/phpstorm-stubs) (Apache License 2.0; NOT Intelephense's proprietary bundled stubs).
`scripts/make-php-stubs.py <phpstorm-stubs clone> PhpStubs` regenerates the committed `PhpStubs/` directory (documented in the script header):

```
git clone --depth 1 https://github.com/JetBrains/phpstorm-stubs /tmp/phpstorm-stubs
python3 scripts/make-php-stubs.py /tmp/phpstorm-stubs PhpStubs
```

| Part | Content |
| --- | --- |
| `PhpStubs/classes/<Name>.php` | one class / interface / trait / enum per file (namespaced names use `_`, e.g. `Random_Randomizer.php`), 333 files |
| `PhpStubs/functions/<ext>_<file>.php` | all functions of one upstream file (about 2000 functions) |
| `PhpStubs/constants/<ext>_<file>.php` | `const NAME = value;` with docblocks (about 3000 constants) |
| `PhpStubs/index.txt` | sorted `kind TAB lowercase-name TAB name TAB file TAB nameOffset TAB declOffset TAB extra [TAB signature]`, UTF-16 offsets (what NSString uses) |
| `PhpStubs/LICENSE`, `SOURCE.txt` | Apache-2.0 text; upstream commit and the list of modifications (Apache section 4) |

Extensions: Core, standard, date, SPL, json, mbstring, ctype, pcre, PDO, mysqli, curl, zip, dom, SimpleXML, libxml, xml, xmlreader, xmlwriter, fileinfo,
filter, hash, openssl, session, iconv, intl, bcmath, gd, Reflection, random, zlib, sodium, tokenizer, posix, pcntl, calendar, exif, gmp, sqlite3, pgsql, redis,
Phar, soap, ftp, sockets, readline, xsl (edit `EXTENSIONS` in the script to change). Generation resolves the JetBrains attributes for PHP 8.3:
`#[PhpStormStubsElementAvailable]` removes elements that do not exist in 8.3, `#[LanguageLevelTypeAware]` becomes a real type, `#[Deprecated]` becomes
`@deprecated`, other attributes are dropped, bodies are emptied and PHPDoc is cleaned (HTML, `@link`, URL `@see`, length caps).

Location at run time (`PHPStubs.root`): `CE_PHP_STUBS`, `Kode.app/Contents/Resources/PhpStubs` (build-app.sh copies it, next to Fonts), else walking up from the
executable to a `PhpStubs/` directory (so `.build/debug/CodeEditor` and tests find the repo copy). A copy of the binary outside the repo needs `CE_PHP_STUBS`.

How it plugs in (the stubs are real PHP files, so no special cases downstream):

* `FastProject.classPath(fqn)`: project PSR-4, then the stub index, then vendor. Every consumer (hierarchy walker, member search, type inference, hover,
  go to definition, constructor signature help, member completion) therefore treats `\PDO`, `Carbon extends DateTime`, `catch (\PDOException $e)`,
  a user class implementing `ArrayAccess` or extending `RuntimeException` exactly like project classes. `FastProject.classInfo(path:)` parses stub files into a
  24-entry cache of their own (`PHPStubs.maxCachedClasses`). `catch (A | B $e)` variables are now typed by their first class.
* `NPFuncIndex.function/constant(name, stubs:)`: composer helper functions first, then the stub index (the argument-count diagnostic passes `stubs: false`).
* Definition on a built-in opens the stub file read-only at the declaration with the banner "PHP built-in stub"; hover shows signature, return type,
  PHPDoc summary, `@param`/`@return`/`@throws`/`@since`/`@deprecated` and the origin "PHP built-in stub".
* Completion: class names (also in `use` lines, added with an import edit), functions (prefix of 2+ characters, signature as detail, curated entries win)
  and constants (uppercase prefix); members through the normal hierarchy.
* Diagnostics: a class that exists in the stub index is never "undefined" (`NPDiagBuiltins` stays as an extra safety net for extensions that are not bundled);
  stub files themselves are not analysed. Member / argument checks stay silent on receivers whose hierarchy contains a built-in class (no new false positives
  from stub gaps such as `SimpleXMLElement` dynamic properties); this is a deliberate limit.

Cost: nothing is read at launch or by lookups that do not mention a built-in. First use memory-maps `index.txt` (about 600 KB; only the pages a binary search
touches become resident) and each lookup is a binary search over the mapping (no dictionary is built). A class lookup reads and parses one small file (typically
2-60 KB); function and constant lookups read one grouped file (about 60 KB) through the existing 6-entry `NPFiles` cache. Function completion scans at most 60
index lines. Bundle size: `PhpStubs/` is about 2.9 MB of text (3.9 MB on disk), no resident cost.

Limits: no stubs outside the extension list; PHP 8.3 view only (8.4 / 8.5 additions are absent or partial); tabs opened on a stub file get no hover or go to
definition (no project root); namespaced built-in functions are indexed under their full name and are not reachable from the short-name lookups; functions the
stubs type loosely stay loosely typed; Eloquent attribute casts (`$model->created_at->format()`) are still not inferred.

Verification: `SelfTestNativePHPStubs` (lazy loading, bounded cache, definition / hover / signature help / inherited members, diagnostics without false
positives) and the benchmark `CE_SELFTEST=1 CE_NATIVE_BENCH=<project> CE_NATIVE_BENCH_OUT=x.json .build/debug/CodeEditor` followed by
`python3 scripts/bench-intelephense.py x.json out.json` (a definition that lands in a built-in stub on both sides counts as agreement).

## Performance

Measured on `~/PHPStromProjects/arht_pos` (Laravel, 647 PHP files in app / routes / database / config / Modules) with a **release** build
(`swift build -c release --build-system native`), headless:

```
CE_PHP_STUBS=<repo>/PhpStubs CE_SELFTEST=1 CE_NATIVE_BENCH=<project> CE_NATIVE_BENCH_OUT=x.json \
  [CE_NATIVE_BENCH_FILES=40] [CE_NATIVE_BENCH_DIAG_FILES=700] [CE_NATIVE_BENCH_LOOP=600] [CE_NATIVE_BENCH_HOLD=1] .build/release/CodeEditor
```

The bench prints `NBENCH` lines: the first stub-touching lookup, cold pass (p50 / p95 / p99 / max / first, the 15 slowest lookups each with
the read / parse / helper-index / docblock time spent in them), a warm repeat pass, a parse profile of the big vendor classes (read / lex /
FTParser), signature help on the slowest calls, find usages for 4-5 popular symbols, diagnostics over the sample (p50 / p95 / worst file, split by
rule group) and the footprint after every phase (plus cache sizes and the effect of `NativePHP.trimMemory()`). `CE_NATIVE_BENCH_LOOP=n` hammers the
8 slowest lookups n times (attach `sample <pid>`), `CE_NATIVE_BENCH_HOLD=1` sleeps at the end so `heap <pid>` / `vmmap` can be run.
The JSON answers are unchanged by the optimisations (319 + 390 recorded lookups compared target by target before / after: 0 differences).

| Metric (release) | Before | After |
| --- | --- | --- |
| Go to definition, 319 lookups: p50 / p95 / p99 | 0.2 / 2.2 / 14.0 ms | 0.2 / 1.7 / 5.6 ms |
| Slowest single lookup (cold: `response()->json`, first helper index) | 38.0 ms | 12.7 ms |
| First lookup of a process | 5.7 ms | 3.1 ms |
| First lookup touching the built-in stubs (`ZipArchive::open`) | n/m (145 ms in a debug build) | 2.3 - 3.8 ms |
| Whole sample, cold / warm total | 245 / 99 ms | 137 / 52 ms |
| Warm repeat pass, slowest lookup | 13.9 ms | 1.7 ms |
| Carbon / facade `@method` lookups (`parse`, `subDays`, `addDay`) | 14 - 20 ms | 0.5 - 14 ms cold (parsing 31 Carbon files), 0.3 ms warm |
| Signature help on the slowest calls | up to 13.4 ms | 0.5 ms |
| Find usages (class / class / `get` / `user`) | 122 / 52 / 493 / 190 ms | 68 / 50 / 281 / 134 ms |
| Diagnostics, 647 files: p50 / p95 / worst | 3.0 / 21.8 / 56.4 ms | 2.9 / 22.1 / 54.7 ms (unchanged: dominated by tree-sitter + member pass) |
| Footprint growth after lookups + usages + diagnostics over 647 files | +72 MB (leak: ~85 KB per analysed file) | +12 .. 29 MB (run-to-run noise of the AppKit test harness; no per-file growth) |

Targets: cold first lookup < 40 ms (**3 - 4 ms**), any single lookup < 30 ms (**12.7 ms**), p95 < 4 ms (**1.7 ms**), diagnostics worst file < 100 ms
(**55 ms**, was already below), footprint growth < ~30 MB after the heavy sample (**met**, see below).

### What was slow, and what changed

* **Leak (RAM, the big one).** `NPDiagContext.flow` (lazy var) and `NPFlow.c` pointed at each other strongly, so every diagnostics pass leaked the context,
  its token array (`PHPTok`), the per-token word cache and the lexer (about 85 KB per analysed file, on every edit). `NPFlow.c` is now `unowned`.
  `NPDiagContext.liveCount` + a self-test (30 analyses, 0 live contexts) guard it.
* **Huge docblocks.** Carbon / facade class docblocks hold thousands of `@method` lines and were fully parsed (string split, trim, per-line allocations) up to
  6 times per lookup. `NPDoc.parse(_:start:query:)` scans big docblocks (> 4 KB) once as bytes and builds only what the caller needs (`@method name`,
  `@property name`, `@see/@mixin`, summary + core tags, `@template` lines); small docblocks still take the full parser. `NPResolver` memoises class docblock
  queries per request; `FTEval.docOf` uses the class-info query for `::class` keys.
* **`inPHP`** (is the pointer inside PHP code) did two backwards substring searches over the whole file per lookup; in a big file without a closing tag
  that scanned the entire text. The `<?` / `?>` positions are now collected once per request (chunked `getCharacters`) and binary-searched.
* **Helper function index** (first `response()` / `route()` lookup): the regexes ran over every composer autoload file and compiled a regex per match.
  ASCII files are now scanned as bytes (`NPFuncIndex.scanBytes`, same matching rules), others keep the regex path. 31 ms -> 11 ms once per session.
* **Line / column** (`NPText.lineCol`) copied the whole file prefix into an array per target; it now counts in 4 KB chunks, and for offsets > 30 000
  uses a line table cached for the last 2 texts. `NPLineStarts` builds its table in chunks instead of one `character(at:)` call per character.
* **Case-insensitive method scan** lowercased every method name of every class in the hierarchy (allocation per method) when a name was not found in a
  class; `FTClass.method(named:)` compares bytes without allocating.
* **Regex compilation**: `NPRe.make` caches compiled expressions (64 entries) for the signature / diagnostics / helper-index patterns that were rebuilt per call.
* **`PHPStubs.isStubFile`** did a substring search plus string concatenation per class lookup; it compares against one cached prefix.
* **File reads** produce a CF-backed `NSString` (`NSString(data:encoding:)`) instead of a bridged Swift `String`, so UTF-16 access in the lexer / parser is O(1).
* **`PHPTok`** is 24 bytes instead of 40 (`len` / `line` / `col` stored as `Int32`, same API).
* **Class cache**: `FastProject.classInfo` used to wipe all 400 entries when the 401st was added (thrash on big sessions). It is now least-recently-used with
  an entry cap (400) and a byte cap (6 MB by `FTClass.approxBytes`), evicting the oldest quarter. Stub classes keep their own 24-entry cache.

What is left in a cold lookup is reading and parsing the vendor classes of the receiver's hierarchy (Carbon: 31 files, about 8 ms read + 6 ms parse in
release). A warm lookup is 0.1 - 0.5 ms. The parse profile of 53 big vendor files (1.77 M characters) is 3.3 ms read, 3.6 ms lex, 8 ms `FTParser` per
round, so parsing is already near 200 MB/s; making the hierarchy lazy (stop at the first class that has the member) would save more but was not done
because the member search order and the `@mixin` / interface walks need the whole list.

### Cold start and common-member find usages (second pass)

Same project and bench (two runs of each build, `CE_NATIVE_BENCH`), answers compared before / after: 319 lookups and 7 usage lists (3 + 9 + 54 + 59 + 75 + 110 + 120 hits)
identical (the only textual difference is the stub directory path of the baseline build).

| Metric (release) | Before | After |
| --- | --- | --- |
| Go to definition cold pass, p50 / p95 / p99 / max | 0.2 / 2.2 / 7.8 / 20.5 ms | 0.1 / 1.0 / 2.8 / 5.4 ms |
| First lookup of a process | 6.1 - 7.0 ms | 0.8 ms |
| First helper-function index (`response()->json`) | 20 ms | ~3 ms |
| Cold slowest: Carbon `parse` / Auth `id` / `subDays` | 17.8 / 17.2 / ~14 ms | ~3 / 4.4 / 5.4 ms |
| Cold pass total | 202 - 206 ms | 80 - 82 ms |
| Find usages `get` (cold) | 257 - 325 ms | 75 ms |
| Find usages `user` | 135 - 176 ms | 35 - 38 ms |
| Find usages `first` (cold / warm) | 310 - 390 / 180 - 218 ms | 79 - 84 / 46 ms |
| Find usages `create` / `count` | 197 - 248 / 197 - 244 ms | 46 - 49 / 45 - 46 ms |
| Find usages of a class (8 candidates, cold) | 50 - 160 ms | 23 - 40 ms |
| Project class index: cold build / per-epoch revalidation | 109 - 174 / 53 - 86 ms | 24 / 9 - 11 ms |
| RAM growth over the whole bench | +18 MB | +13 - 15 MB |

(Numbers vary by machine load; the baseline runs above were slower than the first baseline run because the machine was busy. Ratios are what matters.)

What changed:

* **Find usages.** The file walk is a parallel `readdir` walk (no per-entry strings) with the content prefilter fused into it (files read into reused buffers, no mmap);
  candidate files are read / lexed / parsed on worker threads one chunk ahead of the serial resolver pass; `scanMember` rejects tokens by length before building Strings
  and rejects string tokens with a byte check before `strValue` / `lowercased` (this alone halved the resolve time); a per-request `NPSharedMemo` shares docblock queries and
  completed hierarchies of library classes between files (never anything that involves the file's own, possibly unsaved, class);
  `FTEval.varType` skips tokens of the wrong length and only runs its `@var` regex when the range contains `@var`.
* **Class cache** re-checks the file mtime once per validation epoch (`beginRequest`: 1.5 s or after a change notification) instead of a `stat` on every call.
* **Lazy hierarchy.** `FTEval.hierarchy` returns `FTHier`, a lazy sequence with the same order and caps as the old eager walk; member searches (`NPSearchClasses`) stop
  at the first class that declares the member. `FastProject.prefetch` reads and parses the classes the walk will need next on worker threads (capped at 48 pending, skipped
  in power saver; unclaimed results go into the normal LRU class cache on the next request).
* **Helper index** scans autoload files in parallel and merges in file order.
* **Project class index / other sections**: one `readdir` pass with entry types instead of `FileManager.contentsOfDirectory` + `stat` per entry; PSR-4 roots in parallel.

Tried / not done: a persistent on-disk header cache and a byte-level member scan before the full parse (not needed once reads and parses overlap; a member that is
not declared anywhere, such as an Eloquent column `id`, still has to load its whole hierarchy). Walk worker count was not tuned.

New self-tests (`SelfTestNativePHPPerf`): fast walk equals the FindEngine walk, walk filter, string prefilter verdicts, lazy hierarchy order and early stop,
nested-trait member lookup, class cache sees a changed file after revalidation, `collect` equals a plain per-file scan.

### RAM

Retained by the engine, all bounded and all dropped by `NativePHP.trimMemory()`:

| Cache | Bound | Typical |
| --- | --- | --- |
| `FastProject` class cache | 400 entries and 6 MB (estimated) | 360 entries, about 1.5 MB estimated after the 150-file sample |
| `PHPStubs` parsed classes | 24 entries | 17 - 18 |
| `NPFiles` text cache | 6 files and 3 M characters (was 6 M) | 6 files |
| Last lexed buffer (`NativePHP.lastParse`) | 1 | 1 |
| Line tables of big texts | 2 | 0 - 2 |
| `NPRe` compiled regexes | 64 | about 15 |
| `NPFuncIndex` names | 3 projects | about 1 KB per 100 helpers |

`trimMemory()` (also `malloc_zone_pressure_relief`) runs on system memory pressure (warning / critical), when the app is hidden or every window is
occluded / minimised, and when power saver switches on. It is event driven (a `DispatchSource` memory-pressure source and notifications); there are no
timers. The next request after a trim simply re-reads what it needs (a self-test checks that the answer is identical).
The footprint after the heavy sample (150 files, 390 lookups, 4 find usages, 647 diagnostics passes) moves by -20 .. +29 MB between runs because the
test harness (AppKit text layout in the self-test process, about 150 MB of glyph storage) dominates the baseline; the engine's own contribution is the
table above plus transient allocator high-water marks. Measure with `CE_NATIVE_BENCH_HOLD=1` and `heap <pid>`.

### Guards

`SelfTestNativePHPPerf`: docblock query parity with the full parser (methods, properties, `@see`, core tags, offsets) and a 6000-line docblock parsed
in < 150 ms; `inPHP` tag table equals the old backwards search at every offset (including chunk boundaries); helper byte scanner rules; class cache entry
and byte caps and LRU behaviour; no leaked diagnostics contexts; `trimMemory` empties the caches and answers stay identical; a lookup behind a
3000-line `@method` docblock resolves and stays under 250 ms (debug build).
