# Claude Code IDE bridge (Kode <-> `claude` CLI)

Kode implements the same IDE integration the VS Code / JetBrains extensions provide: the `claude` CLI finds Kode through a
lock file, connects over a loopback WebSocket and speaks MCP (JSON-RPC 2.0). This document records the protocol **as verified
against Claude Code 2.1.302** (`/Users/rutvijkothari/.local/bin/claude`) and what Kode implements of it.

Verification methods used below:

* **[docs]** official page https://code.claude.com/docs/en/vs-code (section "The built-in IDE MCP server").
* **[src]** the CLI is a Bun-compiled executable whose JavaScript is stored as readable text; `strings` on the binary
  exposes the IDE client code (lock scan, transport, tool calls, notification schemas). Quoted identifiers are from that code.
* **[live]** a real `claude` 2.1.302 TUI driven through a pty (no window) against a Kode bridge; wire trace below.
* **[test]** in-process client in `CE_SELFTEST=1` (`SelfTestClaude.swift`).

## Verified protocol

### 1. Discovery: lock file  [docs] [src] [live]

`~/.claude/ide/<port>.lock` (the CLI scans `$CLAUDE_CONFIG_DIR/ide` and also `~/.claude/ide`; files must end in `.lock`; the
port is taken from the **file name**). JSON body, as read by the CLI (`hIn`):

```json
{"pid": 4242, "workspaceFolders": ["/path/to/project"], "ideName": "Kode", "transport": "ws",
 "runningInWindows": false, "authToken": "<uuid>"}
```

* `transport == "ws"` selects `ws://127.0.0.1:<port>` (otherwise the legacy `http://.../sse` is used). `authToken` is sent as the header below.
* A lock file that fails to parse as JSON is treated as a newline-separated list of folders (legacy) and has no token.
* Matching: the CLI's cwd must be inside one of `workspaceFolders` (`contains-cwd`). It compares NFC-normalised paths
  **without resolving symlinks**, so Kode writes both the given path and its `realpath` (macOS `/var` vs `/private/var`).
* The CLI deletes lock files whose `pid` is dead ("stale lock") on startup, then polls the directory for up to 30 s.
* Permissions: file `0600` in a `0700` directory [docs]. Kode follows this.
* Pid check: only when the CLI itself runs inside a recognised VS Code / JetBrains terminal does it require the lock `pid`
  to be an ancestor process. Kode's terminal sets `TERM_PROGRAM=Kode`, so the check is skipped.

### 2. Auto-connect (env vars / flags)  [src] [live]

Interactive `claude` auto-connects when `k4e()` is true: `CLAUDE_CODE_AUTO_CONNECT_IDE` is not `false` **and** any of: global config
`autoConnectIde`, running in a VS Code/JetBrains terminal, `CLAUDE_CODE_SSE_PORT` is set, or `CLAUDE_CODE_AUTO_CONNECT_IDE=true`.
When `CLAUDE_CODE_SSE_PORT` equals a lock file's port that IDE is chosen even if the cwd match fails. Kode's docked terminal
sets `CLAUDE_CODE_SSE_PORT=<port>` and `CLAUDE_CODE_AUTO_CONNECT_IDE=true`. In any other terminal run `claude` and `/ide`, or
enable the global `autoConnectIde` setting once. `claude --ide` ("connect if exactly one valid IDE") exists too.
`ENABLE_IDE_INTEGRATION` does **not** occur in the CLI: it is not used. `CLAUDE_CODE_SSE_PORT` is scrubbed from child-process env.
Observed [live]: `claude -p` (print mode) never connected, even with `--ide`; only the interactive TUI does.

### 3. Transport  [src] [live]

* `new WebSocket("ws://127.0.0.1:<port>", {protocols: ["mcp"], headers: {"User-Agent": ..., "X-Claude-Code-Ide-Authorization": <authToken>}})`.
* Subprotocol `mcp`; one JSON-RPC message per **text** frame. The lock's `authToken` is the only credential.
* [docs]: unencrypted `ws://`, loopback only, random port (10000-65535 for VS Code), fresh token per activation.
* The handshake carries no `Origin`; Network.framework reports the `Host` header without port (cosmetic).

### 4. MCP handshake  [live]

Client -> server `initialize` (protocolVersion `2025-11-25`, capabilities `{roots:{listChanged:true}, elicitation:{}}`,
clientInfo `claude-code`), server result `{protocolVersion, capabilities:{tools:{}}, serverInfo}`; client sends
`notifications/initialized`, then **`ide_connected`** notification `{"pid": <claude pid>}` (`UNn`), then `tools/list`, then
`tools/call`. The server name in the CLI is `ide`. Kode echoes a supported `protocolVersion`.

### 5. Server -> CLI notifications (JSON-RPC notifications; `method` is the bare name)  [src]

| method | params (zod schemas in the CLI) | CLI behaviour |
|---|---|---|
| `selection_changed` | `{selection: {start:{line,character}, end:{line,character}} \| null, text?: string, filePath?: string}` (0-based) | CLI shows `⧉ Selected N lines`, attaches `selected_lines_in_ide` (`lineStart = start.line+1`; `lineCount = end.line-start.line+1`, minus one when `end.character == 0`) to the next prompt; a `Read` deny rule suppresses it |
| `at_mentioned` | `{filePath: string (absolute), lineStart?: number, lineEnd?: number}` (**0-based**; CLI adds 1) | CLI inserts `@<path relative to cwd>#L<start>-<end> ` (or `#L<n>`, or `@path `) at the prompt caret |

`@file#L5-10` is also the mention syntax the CLI parses when typed (`^([^#]+)(?:#L(\d+)(?:-(\d+))?)?`).

### 6. CLI -> server calls (`tools/call`)  [src] [live]

The server hosts more tools in VS Code, but the CLI **model** only sees `mcp__ide__getDiagnostics` and `mcp__ide__executeCode`
(allow-list `["mcp__ide__executeCode","mcp__ide__getDiagnostics"]`, everything else under `mcp__ide__` is filtered). The CLI's own UI calls:

| tool | arguments | result the CLI expects |
|---|---|---|
| `getDiagnostics` | `{uri?: "file:///abs/path"}` | `content[0].text` = JSON **string** of `[{uri, diagnostics:[{message, severity: "Error"\|"Warning"\|"Info"\|"Hint", range:{start:{line,character},end:{...}}, source?, code?}]}]` (0-based). Used (a) as the model tool and (b) by the CLI to snapshot a baseline before each edit and report *new* diagnostics afterwards. |
| `openDiff` | `{old_file_path, new_file_path, new_file_contents, tab_name}` | **blocks** until the user decides. `content: [{text:"FILE_SAVED"},{text:<final file contents>}]` = accepted and the **IDE saved the file**; `[{text:"DIFF_REJECTED"}]` = rejected; `[{text:"TAB_CLOSED"}]` = tab closed (CLI treats it as "proposed content, not saved"). Anything else = error ("Not accepted"). `tab_name` looks like `✻ [Claude Code] file.php (3f0e74) ⧉`. |
| `close_tab` | `{tab_name}` | ignored; sent when the user answers the permission prompt in the terminal instead (observed twice per diff) |
| `closeAllDiffTabs` | `{}` | ignored; sent once at start |
| `executeCode` | Python for a Jupyter kernel | Jupyter only; **not implemented** |

Not found anywhere in the 2.1.302 binary (so **not implemented**, not guessed): `getOpenEditors`, `getCurrentSelection`,
`getWorkspaceFolders`, `openFile`, `checkDocumentDirty`, `saveDocument`, `ide_disconnected`, `FILE_SAVED` notifications.
(They exist in the VS Code extension's server for other clients; the CLI does not call them.) Also received and ignored:
`log_event` `{eventName, eventData}` (telemetry), `notifications/message`.

Live wire trace (Claude Code 2.1.302 TUI, prompt "create hello-live.txt ... then call mcp__ide__getDiagnostics"):

```
<- initialize {protocolVersion:2025-11-25,...clientInfo:claude-code}      -> {result:{protocolVersion,serverInfo:Kode,capabilities:{tools}}}
<- notifications/initialized ; <- ide_connected {pid}
<- tools/list                                                              -> 4 tools
<- tools/call closeAllDiffTabs {}                                          -> CLOSED_0_DIFF_TABS
<- tools/call openDiff {old_file_path,new_file_path,new_file_contents:"hi from claude",tab_name}
   (Kode: accept)                                                          -> [FILE_SAVED, "hi from claude"]   (file appeared on disk)
<- tools/call close_tab x2 ; <- tools/call getDiagnostics {uri} and {}     -> diagnostics JSON
```

## What Kode implements

| Piece | Where |
|---|---|
| WebSocket server (Network.framework `NWListener` + `NWProtocolWebSocket`), 127.0.0.1 only, OS-chosen port, random 128-bit token, constant-time token compare, handshake rejected without the header, 16 MB message cap, 16 connections cap | `ClaudeBridgeServer.swift` |
| Lock file create/remove, stale cleanup (own dead locks only), quit/`atexit` cleanup, MCP dispatch, tools, `selection_changed`, `at_mentioned`, diff session handling | `ClaudeBridge.swift` |
| Accept/Reject review window (existing `SideBySideDiffView`, proposed side editable; accept returns the edited text) | `ClaudeDiffUI.swift` |
| Status bar `Claude: waiting` / `Claude connected`, Settings > Terminal > Claude Code toggle (`claudeBridgeEnabled`, default on) | `StatusBar.swift`, `SettingsPanesMore.swift`, `Prefs.swift` |
| Terminal env per window (`TerminalPanelController.extraEnvironment`) | `TerminalPanelController.swift`, `FeatureWiring.swift` |
| Menu Edit > Send Selection to Claude (@mention), ⌥⌘J | `Menu.swift`, `AppDelegate.swift` |

Behaviour:

* One bridge per project window; started when the project opens (never in `CE_SELFTEST`/`CE_SNAPSHOT` runs), lock removed on window close and on quit.
* Selection/active file are pushed on every caret/tab change (150 ms debounce, de-duplicated, selected text capped at 200k chars) and once when a CLI finishes connecting.
* ⌥⌘J: with a CLI connected sends `at_mentioned` (the CLI inserts `@file#L3-7 ` itself); otherwise pastes the same text into the terminal prompt via bracketed paste (no Return). ⌥⌘K and friends are unchanged.
* `openDiff`: path must resolve (through symlinks, including not-yet-existing files) inside the project folder, contents <= 10 MB. The file's tab is shown (jumping to the first change only if the file was not already open, keyboard focus stays in the terminal). Accept writes the file with `FileIO.write` (symlink-safe), refreshes an open clean buffer through the existing minimal-edit external reload (caret, scroll, undo preserved; Cmd-Z undoes it) and answers `FILE_SAVED` + final text. Reject (button or closing the window) answers `DIFF_REJECTED`. `close_tab`/disconnect answer/close with `TAB_CLOSED`. A dirty buffer keeps its conflict banner (existing behaviour).
* `getDiagnostics`: from the Problems store (open files only, same as the Problems panel), only files inside the project.

## Security

* Loopback bind (`requiredLocalEndpoint 127.0.0.1`, `acceptLocalOnly`), random port, fresh token per start, token only in the 0600 lock file; no token -> HTTP upgrade rejected before any MCP code runs.
* Unknown methods/tools -> JSON-RPC error; `executeCode` is never advertised or accepted; no tool runs code or shell; paths outside the project are refused; sizes capped.
* Settings toggle disables the server, removes the lock file and the terminal env (new shells).

## Not verified / gaps

* Git-aware extras: nothing in the CLI protocol exposes Git to the IDE, so none were built.
* `claude -p` does not use the bridge (observed). Auto-connect from a terminal other than Kode's needs `/ide` or the global `autoConnectIde` setting.
* The review window, status-bar label and real terminal env were exercised only headlessly (screenshots/hands-on not done): see tests.
* Lock matching for non-ASCII/NFD paths relies on the CLI's NFC normalisation.
* Live harness: `CE_SELFTEST=1 CE_CLAUDE_LIVE=<dir> .build/debug/CodeEditor` serves a bridge in the real `~/.claude/ide`
  (diffs auto-accepted) and `scripts/claude-bridge-live-drive.py <dir> "<prompt>"` drives a real `claude` through a pty.
  (It answers the folder-trust dialog, which records the temp folder in `~/.claude.json`.)
