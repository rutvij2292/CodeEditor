# Agent attention alerts (Kode terminal)

When a Claude Code tab running in Kode's terminal finishes a turn or needs you (permission prompt, question), Kode shows:

* a **dot on that terminal tab** (green = finished, red = waiting for you), cleared when you focus the tab;
* the **Dock badge** (count of tabs needing attention) and a **Dock bounce**, only while Kode is inactive;
* a **macOS notification** (permission is requested lazily on the first alert; only works from the packaged `Kode.app`).

Nothing is shown while Kode is the active app and that tab is the visible one. Toggle: Settings > Terminal > "Alert when an agent
finishes or needs input" (default on).

## How it works (no polling)

Every shell Kode starts gets two environment variables:

| variable | meaning |
| --- | --- |
| `KODE_ALERT_SOCK` | path of a unix socket (`$TMPDIR/kode-alert-<pid>.sock`, mode 0600) Kode listens on with a `DispatchSource` |
| `KODE_TAB_ID` | id of this terminal tab |

A hook writes one line `"<KODE_TAB_ID> <event>"` to the socket. Events: `stop` (finished) and `input` (waiting for you).
The listener is created when the first shell is spawned and only while the setting is on; it uses no timers.

## Hooks (`~/.claude/settings.json`)

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command",
          "command": "[ -n \"$KODE_ALERT_SOCK\" ] && printf '%s stop\\n' \"$KODE_TAB_ID\" | nc -U -w 1 \"$KODE_ALERT_SOCK\"; true" } ] }
    ],
    "Notification": [
      { "hooks": [ { "type": "command",
          "command": "[ -n \"$KODE_ALERT_SOCK\" ] && printf '%s input\\n' \"$KODE_TAB_ID\" | nc -U -w 1 \"$KODE_ALERT_SOCK\"; true" } ] }
    ]
  }
}
```

Outside Kode the variables are unset, so the hooks do nothing. They also work for a `claude` started by hand inside any Kode
terminal tab. `nc` is the BSD netcat that ships with macOS.

## Fallback without hooks

* **Terminal bell (BEL):** treated as "waiting for you".
* **Window title (OSC 0/2):** for agent tabs, a title that goes from the Claude Code spinner (braille glyph prefix) to the idle
  marker (`✳`) is treated as "finished".

A "waiting" alert is never downgraded by a later "finished" for the same tab until you focus it.

# Terminal search

Cmd-F inside the terminal opens a small find bar (top right of the terminal): type to search, Return / Shift-Return (or the
arrows) for next / previous, `Aa` toggles case sensitivity, Esc closes. The current match is selected and scrolled into view;
the counter shows `n/total`. The bar is allocated on open and released on close or when you switch terminal tab.
