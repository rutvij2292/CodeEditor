# Change Ledger with notes (design)

Approved by the user in chat on 2026-11-07 ("your recommendation looks good ... start implementing"; "a ledger with notes ... so later I can keep track of what I have done and what code actually does").

## Intent
Agents write most of the code, so the user (a senior developer) no longer remembers what was added or why. Kode keeps a persistent, per-project **ledger** of reviewed agent changes: what changed (files and methods/classes, +/- lines), what the user asked the agent for (session title), and the user's **own one-line note** on what it does. Writing the note is the retention step (generation effect); the ledger is the lasting memory.

## Goals
1. Accepting agent changes in **Claude Changes** (file, session or all) records them in the ledger: session title, date, files, changed symbols with +/- lines (from `ChangedSymbols.rows`).
2. A **note field** in the Claude Changes panel: text typed there is attached to what is accepted next, then cleared. Empty = no note (never blocks Accept).
3. A **Ledger** bottom tool window: sessions newest first; type-to-search over title, note, files and symbol names; selecting a session shows an editable note (editable any time, later too) and its changed symbols; double-click a symbol opens the file at that line.
4. Zero AI calls. Persistent across restarts.

## Non-goals (this version)
- Gutter tint / hover notes in the editor (phase 2). Per-hunk accepts (via the gutter popover) do not record.
- "Check my note with Claude", predict-then-diff, spaced revisit, quiz (later phases, only if the ledger gets used).
- Recording changes the user never accepts.

## Constraints
- RAM first: nothing resident beyond the loaded ledger (cap 256 KB JSON); symbols are computed on a background queue only at accept time; no timers or polling.
- Storage: `~/Library/Application Support/Kode/ledger/<sha256 of canonical project root path>.json`, Codable, atomic writes. Caps: 300 sessions (oldest dropped), 256 KB encoded, 200 files per session, 40 symbols per file, note 2,000 characters, title 200.
- A corrupt, unreadable or future-version file loads as empty and is renamed `.bak`, never crashes.
- Same agent session accepted in several steps merges into one ledger entry (key: agent session id + start time); a file recorded again replaces its earlier row.
- Headless verification only (`AppEnv.headless`); tests never touch the real Application Support folder (`ChangeLedger.directory` override). Build green + `CE_SELFTEST=1` Problems/Ledger checks green before pushing main (pre-authorised; 3 pre-existing `history:` failures are known).

## Builder's calls (mine)
Separate "Ledger" tool window (not a sub-tab of Claude Changes); session title = the agent terminal tab title (`ChangeReviewStore.Session.title`); no shortcut unless a free ⌥⌘ key exists.
