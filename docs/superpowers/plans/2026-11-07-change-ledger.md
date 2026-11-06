# Change Ledger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persistent per-project ledger of accepted agent changes with the user's own notes, a note field in Claude Changes, and a Ledger tool window.

**Architecture:** `ChangeLedger` (Codable store, caps, persistence) is pure and tested alone. `ChangeReviewStore` gains an `onAccept` hook fired with the baselines before they are discarded. `ProjectWindow.recordLedger` computes symbols off-main with `ChangedSymbols.rows` and records. `ChangeLedgerPanel` is the UI; `ChangeReviewPanel` gets the note field.

**Tech Stack:** Swift/AppKit, SwiftPM (`swift build --build-system native`), in-app self-tests (`CE_SELFTEST=1`, `SelfTest.check`).

**Spec:** `docs/superpowers/specs/2026-11-07-change-ledger-design.md`

## Global Constraints
- Caps: 300 sessions, 256 KB encoded, 200 files/session, 40 symbols/file, note 2,000 chars, title 200.
- File: `~/Library/Application Support/Kode/ledger/<sha256(canonical root path)>.json`; tests override `ChangeLedger.directory`.
- Corrupt/future-version file loads empty and is renamed `.bak`.
- No AI calls, no timers/polling; symbols computed on a background queue at accept time only.
- Never block Accept; empty note is fine. Headless verification only. Push main only after green build + ledger/problems self-tests (3 pre-existing `history:` FAILs are known).

## Review Focus
- Note with newlines/unicode/emoji/2,001+ chars: truncated to 2,000, round-trips through save/load intact.
- Corrupt, empty, or unreadable ledger JSON and a JSON with a higher `version`: loads as empty, file renamed `.bak`, no crash.
- Accept of a file with no baseline (too big / bridge): still recorded, file-level row without symbols.
- Same agent session accepted in two steps: one ledger entry, files merged, notes joined.
- Ledger over 256 KB / 300 sessions: oldest dropped, saved file never exceeds the cap.

---

### Task 1: ChangeLedger store

**Files:**
- Create: `Sources/CodeEditor/ChangeLedger.swift`
- Create: `Sources/CodeEditor/SelfTestChangeLedger.swift` (`enum SelfTestChangeLedger { static func run(w: ProjectWindow) }`, called from `SelfTest.swift` next to `SelfTestProblems.run(w: w)`; check names prefixed `ledger:`)

**Interfaces:**
- Produces:
  - `struct LedgerSymbol: Codable, Equatable { var name: String; var kind: String?; var line: Int; var added: Int; var removed: Int; var isNewFile: Bool }`
  - `struct LedgerFile: Codable, Equatable { var rel: String; var added: Int; var removed: Int; var symbols: [LedgerSymbol] }`
  - `struct LedgerSession: Codable, Equatable { var id: String; var started: Date; var updated: Date; var title: String; var note: String; var files: [LedgerFile]; var symbolCount: Int { get }; var searchText: String { get } }` (searchText = lowercased title, note, file rels and symbol names joined by newline)
  - `final class ChangeLedger { static var directory: URL; static var maxSessions = 300, maxBytes = 256 * 1024, maxFilesPerSession = 200, maxSymbolsPerFile = 40, maxNoteChars = 2000, maxTitleChars = 200; init(root: URL); var fileURL: URL { get }; private(set) var sessions: [LedgerSession] /* newest updated first, lazily loaded on first access */; var onChange: (() -> Void)?; func record(id: String, title: String, started: Date, files: [LedgerFile], note: String, now: Date); func setNote(_ note: String, for id: String); func remove(id: String); @discardableResult func save() -> Bool; func reload() }`
  - JSON schema: `{"version":1,"sessions":[LedgerSession]}`.

- [ ] **Step 1: Write failing checks** (temp `directory`): (a) record then reload from a second `ChangeLedger` on the same root shows the session; (b) different roots use different files; (c) merge: recording the same `id` twice with files `[a]` then `[b, a']` yields files `[b, a']` (a replaced, order: newest recorded first is not required, but no duplicates by `rel`), notes `"one"` then `"two"` become `"one\ntwo"`, empty note adds nothing, `updated` = latest `now`; (d) note of 2,100 chars is truncated to 2,000; a note with `"line1\nline2 🙂 ünï"` round-trips; (e) `maxSessions = 3` (lowered) with 5 records keeps the 3 most recently updated; (f) `maxBytes` lowered to 2,000 with many sessions: file on disk ≤ 2,000 bytes and newest session kept; (g) corrupt file (`"{not json"`), empty file, and `{"version":99,"sessions":[]}` load as empty and leave a `.bak` beside the file; (h) 50 symbols in one file are cut to 40; (i) `searchText` contains lowercased symbol and note text; (j) `setNote` persists; `remove` deletes.
- [ ] **Step 2: Run** `swift build --build-system native 2>&1 | grep error: | head -3` — Expected: errors (types missing).
- [ ] **Step 3: Implement** per Interfaces. Load lazily; `save()` encodes with `JSONEncoder` (ISO8601 dates), drops oldest sessions until encoded size ≤ `maxBytes`, writes atomically after creating the directory; file name = lowercase hex SHA-256 (CryptoKit) of the canonical root path (`VCSKind.canonical(root.standardizedFileURL.path)`) + `.json`; `onChange` called after every mutation.
- [ ] **Step 4: Run** the full self-test (`CE_SELFTEST=1 .build/debug/CodeEditor > /tmp/x.log 2>&1; grep -E "ledger:" /tmp/x.log`) — Expected: every `ledger:` line PASS.
- [ ] **Step 5: Commit** `git add -A Sources && git commit -m "Ledger: persistent change ledger store"`

### Task 2: Recording on accept

**Files:**
- Modify: `Sources/CodeEditor/ChangeReviewStore.swift` (accept paths, lines ~198-235)
- Modify: `Sources/CodeEditor/ChangeReviewPanel.swift` (installChangeReview wiring ~211-240)
- Create: `Sources/CodeEditor/LedgerRecorder.swift`
- Modify: `Sources/CodeEditor/SelfTestChangeLedger.swift`

**Interfaces:**
- Consumes: Task 1 types; `ChangedSymbols.rows(path:rel:old:new:outline:isNew:) -> [ChangedSymbols.Row]`; `BreadcrumbOutlineBuilder.supports(key:)/languages(for:)/build(text:key:languages:)`; `Languages.key(forFileName:)`.
- Produces:
  - `struct ChangeReviewStore.AcceptedFile { let path: String; let rel: String; let baseline: String?; let added: Int; let removed: Int }`
  - `ChangeReviewStore.onAccept: ((Session, [AcceptedFile], String) -> Void)?` and `ChangeReviewStore.acceptNote: String` (consumed and reset to `""` on every accept batch). `acceptFile`, `acceptAll(in:)` and `acceptAll()` fire the hook ONCE per session per call, with baselines captured BEFORE they are cleared; only entries that were pending are included; nothing fires when no entry was pending. Hunk-level accepts (`acceptHunk`) do not fire it.
  - `enum LedgerRecorder { static func sessionID(_ s: ChangeReviewStore.Session) -> String /* "\(s.id)-\(Int(s.started.timeIntervalSince1970))" */; static func file(_ f: ChangeReviewStore.AcceptedFile, rows: [ChangedSymbols.Row]) -> LedgerFile /* symbols from rows: name, kind?.rawValue, line, added, removed, isNewFile; with no rows keeps f.added/f.removed and symbols [] */ }`
  - `extension ProjectWindow { func recordLedger(session: ChangeReviewStore.Session, files: [ChangeReviewStore.AcceptedFile], note: String) }` and `var changeLedger: ChangeLedger?` on `ProjectWindow` (stored property next to `changeReview`).

- [ ] **Step 1: Write failing checks**: (a) store with one pending entry (use `record(path:current:baseline:source:agent:)` as `SelfTestChangeReview` does): `acceptFile` fires the hook once with the entry's baseline and added/removed, entry state `.accepted`, baseline cleared afterwards; (b) `acceptAll(in:)` with 3 pending entries fires once with 3 files; (c) `acceptAll()` over two sessions fires twice; (d) accepting an already accepted entry fires nothing; (e) `acceptNote = "why"` is passed to the hook and reset to `""`; (f) `LedgerRecorder.file` with two `ChangedSymbols.Row`s gives two `LedgerSymbol`s with the row's kind raw value and line; with no rows gives `symbols == []` and the accepted counts; (g) `sessionID` is stable for one session and differs for another; (h) end to end on `w`: with `w.changeLedger` pointed at a temp directory, a pending entry on a real temp PHP file (baseline = old text, disk = new text with a changed method) accepted through `w.changeReview` leads (after waiting on a background semaphore/poll up to 20 s) to a ledger session whose file has a symbol named like the changed method.
- [ ] **Step 2: Run** the build — Expected: errors.
- [ ] **Step 3: Implement.** In the store add one private `accept(_ entries: [Entry])` that captures `AcceptedFile`s, sets state/baseline, groups by owning session, fires `onAccept` per session, then `changed()`. `recordLedger` mirrors `collectChangedSymbols` (ChangedSymbols.swift:90-120): gather open-buffer text and grammar `languages` on main, compute `ChangedSymbols.rows` on a `.userInitiated` background queue (skip files > `ChangedSymbols.maxFileBytes`), then on main call `changeLedger?.record(id: LedgerRecorder.sessionID(session), title: session.title, started: session.started, files:, note:, now: Date())`. In `installChangeReview` create `changeLedger = ChangeLedger(root: root)` and set `store.onAccept`.
- [ ] **Step 4: Run** the self-test grep for `ledger:` — Expected: all PASS; also run the existing `change review` checks: no FAIL lines mentioning "review".
- [ ] **Step 5: Commit.**

### Task 3: Ledger panel, note field, wiring

**Files:**
- Create: `Sources/CodeEditor/ChangeLedgerPanel.swift`
- Modify: `Sources/CodeEditor/ChangeReviewPanel.swift` (note field + `acceptNote` hand-off in `accept(_:)` and `acceptAllTapped`)
- Modify: `Sources/CodeEditor/ChangeReviewPanel.swift` wiring (`installChangeReview`: register the Ledger tool), `Sources/CodeEditor/ToolStrip.swift:34` (add entry), `Sources/CodeEditor/Menu.swift:239` + `AppDelegate.swift:325` (menu item "Change Ledger Tool Window", `showChangeLedgerTool`, shortcut ⌥⌘4 only if unused in `Menu.swift`/keymap, else none)
- Modify: `Sources/CodeEditor/SelfTestChangeLedger.swift`

**Interfaces:**
- Consumes: Task 1-2 APIs; `SpeedTableView`, `SpeedSearch` (as `ChangeReviewPanel`), `Theme`.
- Produces:
  - `final class ChangeLedgerPanel: NSObject { let view: NSView; init(ledger: ChangeLedger); var openFile: ((URL, Int) -> Void)?; var root: URL; func reload(); func selectSession(id: String) -> Bool; var rowDescriptions: [String] /* "<yyyy-MM-dd HH:mm> <title> · <n> files · <m> symbols" + (note.isEmpty ? "" : " — " + first 60 chars of note) */; var symbolRowDescriptions: [String] /* "FILE <rel> +a −r" then "  <name> <line> +a −r" */; var noteText: String; func setNoteText(_ s: String) /* edits the field like typing */; func commitNote() /* saves to ledger */; func openSymbol(row: Int) /* calls openFile(root/rel, line) */ ; func snapshot(to: String, size: NSSize) }`
  - Claude Changes panel: `var noteField` (placeholder "What does this change do, in your words? (optional)"); `func acceptWithNote(_ row: Row)` behaviour: trims the field text into `store.acceptNote`, clears the field, then accepts.

- [ ] **Step 1: Write failing checks**: (a) panel over a ledger with 2 sessions lists newest first with the description format above; (b) selecting a session fills `noteText` and `symbolRowDescriptions`; (c) `setNoteText("mine")` + `commitNote()` persists to a fresh `ChangeLedger` on the same file; (d) speed-search filter hook: the panel's `filteredRowDescriptions(query: "invoice")` (pure helper over `searchText`) returns only matching sessions, case-insensitive, matching symbol names and notes; (e) `openSymbol` calls `openFile` with the absolute URL and the recorded line; (f) Claude Changes: typing a note, calling `accept` on a file row passes the note into the ledger session note and empties the field; accepting with an empty field records an empty note; (g) `w` has a registered `"ledger"` tool panel and `w.hasToolPanel("ledger")`; (h) env-gated snapshot (`CE_LEDGER_SNAPSHOT=<path prefix>`) renders the panel with sample data.
- [ ] **Step 2: Run** the build — Expected: errors.
- [ ] **Step 3: Implement.** Layout: left sessions table (≈45 % width), right a note `NSTextView` (editable, saved on `textDidEndEditing` and on selection change) above a symbols table; empty state "No reviewed agent changes yet. Accept changes in Claude Changes to start your ledger." Ledger reloads on `ledger.onChange`. Sessions table uses `SpeedSearch.attach` with `searchText`.
- [ ] **Step 4: Run** self-test grep `ledger:`; render the snapshot and look at it (`CE_LEDGER_SNAPSHOT=<scratch>/ledger CE_SELFTEST=1 .build/debug/CodeEditor`).
- [ ] **Step 5: Commit.**

### Task 4: Verify, document, ship

**Files:** Modify `docs/CHANGELOG.md`.

- [ ] **Step 1:** `swift build --build-system native 2>&1 | tail -3` — Expected: `Build complete!`.
- [ ] **Step 2:** `CE_SELFTEST=1 .build/debug/CodeEditor > /tmp/x.log 2>&1; grep -E "^FAIL" /tmp/x.log` — Expected: only the 3 known `history:` lines.
- [ ] **Step 3:** Add a changelog entry (next version = commit count + 1) describing the ledger, note field and Ledger tool window.
- [ ] **Step 4:** Commit, final whole-branch review, fix pass, push main.
