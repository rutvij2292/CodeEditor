# Problems Panel (tabs, project scan, Evaluate with Claude) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the ⌘5 Problems panel into a PhpStorm-style window (File / Project Errors / Inspections on Current File tabs, detail pane) with an on-request, per-problem "Evaluate with Claude".

**Architecture:** Pure, testable logic lives in three new files (`ProblemGrouping`, `ProblemEvaluator`, `ProjectProblemScanner`). `ProblemsPanelController` (LSPProblems.swift) gains a tab bar and a detail pane (new `ProblemsDetailPane.swift`) and consumes those. Evaluation reuses `ClaudeCLI.run`; hand-off reuses `ProjectWindow.fixProblemWithClaude`.

**Tech Stack:** Swift/AppKit, SwiftPM (`swift build --build-system native`), in-app self-tests (`CE_SELFTEST=1`, `SelfTest.check(_:_:)`, files named `SelfTest*.swift`, called from `SelfTest.swift` near line 142).

**Spec:** `docs/superpowers/specs/2026-11-06-problems-panel-design.md`

## Global Constraints
- RAM first: everything on demand; no timers, polling or folder watching; caps as below.
- Scan skips (case-sensitive dir names): `vendor`, `node_modules`, `public/build`, `.git`, `storage`, `bootstrap/cache`, `dist`, `build`, `.next`, `.nuxt`, `coverage`, `.idea`, `.vscode`, `.build`, `__pycache__`; skips `*.min.js`, `*.min.css`, `*.map`; skips files > 5,000,000 bytes.
- Scan keeps at most 5,000 problems total; text of each file is discarded right after analysis; runs at `.utility` QoS; waits while `PowerState.windowHidden`.
- Evaluate: max 20 problems per call; snippet ±6 lines (`FixWithClaude.snippet`); file read ≤ 400 KB; cache ≤ 200 entries keyed by path + fingerprint.
- Claude only via `ClaudeCLI.run` (no API key, haiku default). Never called automatically.
- ⌘5 unchanged. No new inspections. Verify headless (`AppEnv.headless`); never open visible windows. Build green + `CE_SELFTEST=1` green before pushing main (pre-authorised).

## Review Focus
- Claude returns prose, fenced JSON, or JSON missing some problem ids: parser accepts fenced/embedded JSON; unanswered ids show "No answer"; nothing crashes.
- Claude is not installed / times out / is cancelled: the pane shows the error text and the Evaluate button returns.
- File edited after evaluation: cached answer for a changed line is dropped; Apply is disabled when `oldText` no longer matches exactly once.
- Project with 50k+ files or a huge `vendor`: scan only walks non-skipped dirs, honours the 5,000 cap, and Cancel stops within one file.
- Unreadable, binary, or non-UTF-8 files during scan: skipped silently.

---

### Task 1: Grouping model for the Inspections tab

**Files:**
- Create: `Sources/CodeEditor/ProblemGrouping.swift`
- Create: `Sources/CodeEditor/SelfTestProblems.swift` (shared by all tasks; add `enum SelfTestProblems { static func run(w: ProjectWindow) }` and call it from `SelfTest.swift` next to `SelfTestToolStrip.run(w: w)`)

**Interfaces:**
- Produces:
  - `struct InspectionGroup { let category: String; var inspections: [Inspection] }`
  - `struct InspectionGroup.Inspection { let name: String; let severity: Int; var items: [(url: URL, d: FileProblems.Diagnostic)] }`
  - `enum ProblemGrouping { static func group(_ files: [FileProblems]) -> [InspectionGroup] ; static func category(for d: FileProblems.Diagnostic) -> String ; static func inspectionName(for d: FileProblems.Diagnostic) -> String }`

- [ ] **Step 1: Write failing checks in `SelfTestProblems.run`**: build two `FileProblems` with diagnostics (source `"native-php"` code `"unused-import"`, source `"intelephense"` code `"P1009"`, one without source/code). Assert: groups sorted by category name; within a category inspections sorted by name; items counted correctly; a diagnostic with no source/code lands in category `"General"` with name = first 40 chars of its message.
- [ ] **Step 2: Run** `swift build --build-system native && CE_SELFTEST=1 .build/debug/CodeEditor 2>&1 | grep -i "problems:"` — Expected: build fails (types missing).
- [ ] **Step 3: Implement** `ProblemGrouping` (category from `source` mapped: native-php/intelephense → "PHP", native-js/typescript → "JavaScript", native-py → "Python", else source capitalised or "General"; inspection name from `code`, falling back to message prefix). Check the real `source`/`code` strings the native engines emit in `NativePHPDiag.diagnostics(_:in:)` and the JS/Py equivalents and map those exact values.
- [ ] **Step 4: Run** the command from Step 2 — Expected: all `problems:` checks pass.
- [ ] **Step 5: Commit** `git add Sources/CodeEditor/ProblemGrouping.swift Sources/CodeEditor/SelfTestProblems.swift Sources/CodeEditor/SelfTest.swift && git commit -m "Problems: grouping model"`

### Task 2: Evaluation prompt, parser and cache

**Files:**
- Create: `Sources/CodeEditor/ProblemEvaluator.swift`
- Modify: `Sources/CodeEditor/SelfTestProblems.swift`

**Interfaces:**
- Consumes: `FixWithClaude.snippet(of:around:context:)` (ClaudeComposerSupport.swift:213), `ClaudeCLI.run(prompt:model:system:cwd:timeout:completion:) -> Process?`.
- Produces:
  - `struct ProblemRef { let id: Int; let url: URL; let relPath: String; let d: FileProblems.Diagnostic; let fileText: String? }`
  - `struct ProblemAnswer: Equatable { enum Verdict: String { case real, falsePositive, ignorable }; enum Difficulty: String { case easy, moderate, hard }; let verdict: Verdict; let difficulty: Difficulty; let explanation: String; let oldText: String?; let newText: String? }`
  - `enum ProblemEvaluator { static let maxPerCall = 20; static func prompt(_ refs: [ProblemRef]) -> String; static func parse(_ raw: String, ids: [Int]) -> [Int: ProblemAnswer]; static func fingerprint(_ ref: ProblemRef) -> String; @discardableResult static func evaluate(_ refs: [ProblemRef], completion: @escaping (Result<[Int: ProblemAnswer], ClaudeCLI.Failure>) -> Void) -> Process? }`
  - `final class ProblemAnswerCache { static let shared; let capacity = 200; func get(_ key: String) -> ProblemAnswer?; func set(_ key: String, _ a: ProblemAnswer); func invalidate(path: String); func removeAll() }` (key = path + "|" + fingerprint; fingerprint = trimmed text of the problem's line + message; evicts oldest when full).

- [ ] **Step 1: Write failing checks**: `parse` of (a) bare JSON array, (b) JSON inside a ```json fence with surrounding prose, (c) array missing one id, (d) garbage → `[:]`; expected schema `[{"id":1,"verdict":"real|false_positive|ignorable","difficulty":"easy|moderate|hard","explanation":"…","oldText":"…","newText":"…"}]`. `prompt` contains each id, path:line, message and the fenced snippet, and says to reply with only that JSON. `evaluate` with 21 refs calls completion with `.failure` mentioning "20". Cache: 201 inserts leave 200 entries and the first key gone.
- [ ] **Step 2: Run** the self-test command — Expected: build fails.
- [ ] **Step 3: Implement** per the Interfaces. Extract the JSON array by locating the first `[` and last `]`; decode with `JSONSerialization`; ignore unknown ids and invalid enum values (drop that entry).
- [ ] **Step 4: Run** — Expected: `problems:` checks pass.
- [ ] **Step 5: Commit** `git commit -am "Problems: Claude evaluation prompt, parser, cache"` (add new files first).

### Task 3: Project scanner

**Files:**
- Create: `Sources/CodeEditor/ProjectProblemScanner.swift`
- Modify: `Sources/CodeEditor/SelfTestProblems.swift`

**Interfaces:**
- Consumes: `NativePHPDiag.handles/analyze/diagnostics(_:in:)` (NativePHPDiag.swift:53,63,122), `FastProject.shared(root:)` and its queue, `NativeJSDiag.analyze(url:text:)` (NativeJSDiag.swift:110); look at `NativePyDiagController` and the web diag controller for how Python/web analysis is invoked and include them if they can run from a file URL without an open tab, otherwise leave them out and note it in the commit message.
- Produces:
  - `enum ProjectProblemScanner { static func shouldSkip(relativePath: String, isDirectory: Bool) -> Bool; static let maxProblems = 5000; static let maxFileBytes = 5_000_000 }`
  - `final class ProjectScan { init(root: URL); var onProgress: ((Int, Int) -> Void)?  /* scanned, problemsSoFar */; var onFinish: (([FileProblems], Bool) -> Void)?  /* results, wasCancelled */; func start(); func cancel() }` (callbacks on main queue; results sorted by path; files with zero problems omitted).
  - `static func analyzeFile(url: URL, root: URL) -> FileProblems?` (reads text, returns nil for unreadable/binary/over-cap/no-analyzer files) — also used when one file is saved.

- [ ] **Step 1: Write failing checks**: `shouldSkip` true for `vendor`, `src/vendor`, `node_modules/a`, `public/build`, `public/build/x.js`, `bootstrap/cache`, `storage`, `a.min.js`, `a.js.map`; false for `public/index.php`, `bootstrap/app.php`, `app/Build.php`. Temp-dir scan with `a.php` (syntax error `<?php function {`), `ok.php`, `vendor/v.php` (syntax error), `node_modules/n.js` (syntax error): results contain only `a.php`. A temp file of 5,000,001 bytes is skipped. Cancel before start finishes yields `wasCancelled == true`. With 6,000 synthetic diagnostics from one fake analyzer hook (`ProjectProblemScanner.analyzerOverride`), total kept is 5,000.
- [ ] **Step 2: Run** the self-test command — Expected: build fails.
- [ ] **Step 3: Implement.** Walk with `FileManager.enumerator` using `skipDescendants()` for skipped directories; process on a serial `.utility` queue, one file per iteration, checking a cancel flag and waiting (short `usleep` loop, no timer) while `PowerState.windowHidden`; read bytes, reject if they contain NUL or are not valid UTF-8; drop text after `analyzeFile` returns. PHP analysis must run on the `FastProject` queue (see how `NativePHPDiagController` does it, around line 165).
- [ ] **Step 4: Run** — Expected: `problems:` checks pass.
- [ ] **Step 5: Commit.**

### Task 4: Panel UI — tabs, detail pane, Evaluate/Apply/Hand off

**Files:**
- Create: `Sources/CodeEditor/ProblemsDetailPane.swift`
- Modify: `Sources/CodeEditor/LSPProblems.swift` (ProblemsPanelController, lines 141-439)
- Modify: `Sources/CodeEditor/FeatureWiring.swift:63-79`, `Sources/CodeEditor/ClaudeComposerWiring.swift` (add Apply helper next to `fixProblemWithClaude`, line 93)
- Modify: `Sources/CodeEditor/SelfTestProblems.swift`

**Interfaces:**
- Consumes: Tasks 1-3 APIs.
- Produces:
  - `ProblemsPanelController`: `enum Tab { case file, project, inspections }`, `var tab: Tab`, `func select(tab: Tab)`, `var onEvaluate/onApply/onHandOff` closures replaced by direct calls to `ProblemEvaluator`; new `var applyFix: ((URL, _ oldText: String, _ newText: String) -> Bool)?` (returns false when `oldText` is not found exactly once in the open buffer or file); `var handOff: ((URL, FileProblems.Diagnostic) -> Void)?` (wired to `fixProblemWithClaude`); `var rowDescriptions` keeps working per tab; `func snapshot(to:size:)` keeps working.
  - `final class ProblemsDetailPane: NSView { func show(problem: (URL, FileProblems.Diagnostic)?, answer: ProblemAnswer?, state: State) ; enum State { case idle, evaluating, failed(String) }; var onEvaluate: (() -> Void)?; var onApply: (() -> Void)?; var onHandOff: (() -> Void)? }`

- [ ] **Step 1: Write failing checks** using a temp project and a `ProblemsPanelController` with fake data injected through a new `var problemsProvider: (() -> [FileProblems])?` (defaults to `LanguageServers.problems(forRoot:)`): (a) `.file` tab lists only the current file; (b) `.inspections` tab rows are `CATEGORY` / `inspection (n)` / problem rows in grouping order; (c) `.project` tab shows scan results after a fake scan completes and shows "Scan" idle text before; (d) selecting a problem shows its message in the pane; (e) with `ProblemEvaluator` stubbed through `var evaluateOverride`, clicking Evaluate on a group of 3 sends ONE call and each of the 3 problems shows its own answer when selected; (f) Apply is enabled only for `.easy` answers with non-nil `oldText/newText` and calls `applyFix` once; (g) moderate/hard shows Hand to agent and calls `handOff`; (h) closing the project tab (`select(tab:)` away) clears scan results (`projectResultCount == 0`); (i) editing a file's line invalidates its cached answer (`ProblemAnswerCache.get` nil after `invalidate(path:)`).
- [ ] **Step 2: Run** the self-test command — Expected: build fails.
- [ ] **Step 3: Implement.** Tab bar replaces the Errors/Warnings/Current-file filter row's left side (keep the Errors/Warnings filters on the right); `NSSplitView` holds the outline (left) and `ProblemsDetailPane` (right, ~35% width, collapsible when nothing selected; my call). Context menu gains "Evaluate with Claude" on problem, group and file rows (collects up to 20 `ProblemRef`s; extra problems are listed as "N more not evaluated, evaluate again"). Project tab toolbar: Scan / Cancel / Rescan, progress text "Scanning… 412 files, 37 problems"; saving or editing a file in the editor calls `ProjectProblemScanner.analyzeFile` for that path only while the Project tab has results. Apply: replace the unique `oldText` occurrence in the open `EditorTab` through its undo-aware text API (find the helper the existing "format/replace" code uses), else in the file on disk; show the replacement text in the pane before Apply is pressed. Keep ⌘5 and the badge logic in `installProblemsPanel` unchanged.
- [ ] **Step 4: Run** — Expected: `problems:` checks pass; also `CE_SNAPSHOT=1 CE_PICKER=problems CE_SNAPSHOT_PATH=/tmp/problems.png .build/debug/CodeEditor` produces a PNG showing tabs and the detail pane (open the PNG and look at it).
- [ ] **Step 5: Commit.**

### Task 5: Full verification, docs, ship

**Files:**
- Modify: `docs/CHANGELOG.md`, `README.md` only if it lists Problems features.

- [ ] **Step 1:** `swift build --build-system native 2>&1 | tail -5` — Expected: `Build complete!`.
- [ ] **Step 2:** `CE_SELFTEST=1 .build/debug/CodeEditor 2>&1 | tail -15` — Expected: zero FAIL lines.
- [ ] **Step 3:** Add a changelog entry for the next version describing tabs, project scan (skips vendor/node_modules/public/build, on demand) and Evaluate with Claude.
- [ ] **Step 4:** Commit, then push main to origin (user pre-authorised after green build and self-test).
