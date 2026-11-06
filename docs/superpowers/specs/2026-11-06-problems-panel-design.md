# Problems panel: PhpStorm-style tabs, project scan, Evaluate with Claude (design)

Approved by the user in chat on 2026-11-06.

## Intent
The existing Problems panel (`ProblemsPanelController`, ⌘5) lists problems of open files only and has no explanation or triage. The user liked PhpStorm's Problems window and wants it here, plus an on-request Claude evaluation: "is this really a problem, is it easy to fix, give me a proper solution", without opening an agent session.

## Goals
1. Three tabs like PhpStorm: **File** (current file), **Project Errors** (whole project), **Inspections on Current File** (grouped by category, then inspection name, with severity and counts).
2. Right-hand **detail pane** showing the selected problem (message, source/code, location, code snippet, Claude answer).
3. **Evaluate with Claude**: one `ClaudeCLI.run` call per click, for one problem, a group, or the whole file. One structured answer per problem, shown individually. Each answer has verdict (real / false positive / ignorable), difficulty (easy / moderate / hard), explanation, proposed fix. Easy fixes get **Apply** (preview first); moderate/hard get **Hand to agent** (existing `fixProblemWithClaude`).
4. **Project Errors** scans the whole project on demand, RAM-safe.

## Non-goals
- No new inspections (e.g. PHP "unused parameter", "dynamic method called as static"): only what the native engines and language servers already report.
- No automatic Claude calls, no background polling, no folder watching.
- No new tool-window key (⌘5 stays).

## Constraints
- RAM/lightweight is non-negotiable: lazy, capped, no polling.
- Project scan: user-triggered (Scan button), cancellable, one file at a time, file text discarded right after analysis, only compact problem records kept, global cap on kept problems (5,000), low QoS background queue, pauses while `PowerState.windowHidden`.
- Scan skips `vendor`, `node_modules`, `public/build` (user-mandated) and, my call: `.git`, `storage`, `bootstrap/cache`, `dist`, `build`, `.next`, `.nuxt`, `coverage`, `.idea`, `.vscode`, `.build`, `__pycache__`, minified/`.map` files, files over 5 MB (`EditorTab` large-file cap).
- After the scan, a file's results refresh only when it is edited/saved in the editor; a Rescan button refreshes the rest. Closing the Project Errors tab drops its results.
- Claude calls: existing `ClaudeCLI.run` (subscription, no API key, `--strict-mcp-config`, haiku default), JSON output parsed defensively. Max 20 problems per call; snippet = ±6 lines around each problem (`FixWithClaude.snippet`); file read cap 400 KB.
- Evaluation cache: in memory, keyed by file path + problem fingerprint (line text + message), capped at 200 entries, entry dropped when its line text changes.
- Verify headless (`AppEnv.headless`); never open visible windows. Build green + `CE_SELFTEST=1` green before pushing main (pre-authorised).

## Left to the builder (marked as my calls)
Exact layout metrics, icons, "ignorable" wording, Apply mechanism (replace line range in the open `EditorTab` via the undo-aware text API), which analyzers run per extension in the scan (PHP, JS/TS, web, Python, JSON/YAML as already wired).
