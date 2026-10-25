#!/usr/bin/env python3
"""Replays the positions written by `CE_VUE_BENCH` (NativeVueBench.swift) against the external Vue language server (Volar 3, hybrid mode,
with typescript-language-server + @vue/typescript-plugin as its tsserver companion, exactly like the app launches them) and compares
latency, memory and answers (go to definition).

Usage: bench-vue-server.py native.json [out.json] [--limit N] [--kinds tag,prop,event,model,slot,expr]
Needs globally installed @vue/language-server and typescript-language-server (npm i -g), and a TypeScript 5 tsserver
(TSDK=<dir>/node_modules/typescript/lib; the global TypeScript 7 has no JS tsserver / plugin support)."""
import json, os, shutil, subprocess, sys, threading, time, urllib.parse
from collections import Counter

args = [a for a in sys.argv[1:] if not a.startswith("--")]
limit = int(sys.argv[sys.argv.index("--limit") + 1]) if "--limit" in sys.argv else 400
kinds = set(sys.argv[sys.argv.index("--kinds") + 1].split(",")) if "--kinds" in sys.argv else {"tag", "prop", "event", "model", "slot", "expr"}
data = json.load(open(args[0]))
root = data["root"]
vb_root = os.environ.get("VB_ROOT") or root        # VB_ROOT: a scratch dir (symlinks to the project + a jsconfig.json) used as the server's workspace when the project has none
def mapped(path): return path.replace(root, vb_root, 1)
npm_root = subprocess.run(["bash", "-lc", "npm root -g"], capture_output=True, text=True).stdout.strip()
vue_js = npm_root + "/@vue/language-server/bin/vue-language-server.js"
plugin_loc = npm_root + "/@vue/language-server"
tsdk = os.environ.get("TSDK")
if not tsdk or not os.path.exists(tsdk + "/tsserver.js"):
    sys.exit("set TSDK=<dir>/node_modules/typescript/lib (TypeScript 5)")
tsls_bin = shutil.which("typescript-language-server") or sys.exit("typescript-language-server not found")


class Server:
    def __init__(self, cmd, name):
        self.name = name
        self.p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=open(os.environ.get("VB_ERR", os.devnull), "a"), cwd=vb_root)
        self.msgs, self.cv, self.nid, self.on_notify = [], threading.Condition(), 0, None
        self.lock = threading.Lock()
        threading.Thread(target=self.reader, daemon=True).start()

    def reader(self):
        f = self.p.stdout
        while True:
            h = b""
            while not h.endswith(b"\r\n\r\n"):
                c = f.read(1)
                if not c: return
                h += c
            n = int([l for l in h.split(b"\r\n") if l.lower().startswith(b"content-length")][0].split(b":")[1])
            m = json.loads(f.read(n))
            if "method" in m and "id" not in m:                         # notification
                if self.on_notify: threading.Thread(target=self.on_notify, args=(m,), daemon=True).start()
                continue
            if "method" in m and "id" in m:                             # server -> client request
                res = [None] * len(m.get("params", {}).get("items", [])) if m["method"] == "workspace/configuration" else None
                self.send({"jsonrpc": "2.0", "id": m["id"], "result": res})
                continue
            with self.cv: self.msgs.append(m); self.cv.notify_all()

    def send(self, o):
        b = json.dumps(o).encode()
        with self.lock:
            try: self.p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b); self.p.stdin.flush()
            except Exception: pass

    def notify(self, method, params): self.send({"jsonrpc": "2.0", "method": method, "params": params})

    def request(self, method, params, timeout=60):
        with self.lock: self.nid += 1; i = self.nid
        self.send({"jsonrpc": "2.0", "id": i, "method": method, "params": params})
        end = time.time() + timeout
        with self.cv:
            while True:
                for m in list(self.msgs):
                    if m.get("id") == i:
                        self.msgs.remove(m); return m.get("result")
                if time.time() > end: return None
                self.cv.wait(0.2)


def rss_mb(pids):
    out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,rss="], capture_output=True, text=True).stdout
    rows = [tuple(map(int, l.split())) for l in out.strip().splitlines()]
    tree, grew = set(pids), True
    while grew:
        grew = False
        for pid, ppid, _ in rows:
            if ppid in tree and pid not in tree: tree.add(pid); grew = True
    return sum(r for pid, _, r in rows if pid in tree) / 1024


caps = {"workspace": {"workspaceFolders": True, "configuration": True}, "textDocument": {"definition": {"linkSupport": True}, "synchronization": {}, "hover": {}}}
uri = "file://" + urllib.parse.quote(vb_root)
tsls = Server([tsls_bin, "--stdio"], "tsls")
vue = Server(["node", vue_js, "--stdio", "--tsdk=" + tsdk], "volar")
t0 = time.time()
tsls.request("initialize", {"processId": os.getpid(), "rootUri": uri, "workspaceFolders": [{"uri": uri, "name": "p"}], "capabilities": caps,
    "initializationOptions": {"tsserver": {"path": tsdk + "/tsserver.js", "useSyntaxServer": "never"}, "disableAutomaticTypingAcquisition": True,
                              "plugins": [{"name": "@vue/typescript-plugin", "location": plugin_loc, "languages": ["vue"], "configNamespace": "typescript"}]}})
tsls.notify("initialized", {})
vue.request("initialize", {"processId": os.getpid(), "rootUri": uri, "workspaceFolders": [{"uri": uri, "name": "p"}], "capabilities": caps,
    "initializationOptions": {"vue": {"hybridMode": True}, "typescript": {"tsdk": tsdk}}})
vue.notify("initialized", {})


bridged = [0, 0]


def bridge(m):                                                         # Volar -> tsserver bridge
    if m.get("method") == "window/logMessage" and os.environ.get("VB_LOG"): print("VOLARLOG", m["params"].get("message"), file=sys.stderr)
    if m.get("method") != "tsserver/request": return
    bridged[0] += 1
    for rid, command, a in m["params"] if isinstance(m["params"][0], list) else [m["params"]]:
        r = tsls.request("workspace/executeCommand", {"command": "typescript.tsserverRequest", "arguments": [command, a, {"isAsync": True, "lowPriority": True}]}, timeout=30)
        body = r.get("body") if isinstance(r, dict) else None
        if body is not None: bridged[1] += 1
        if os.environ.get("VB_DEBUG"): print("BRIDGE", command, json.dumps(a)[:120], "->", json.dumps(r)[:200], file=sys.stderr)
        vue.notify("tsserver/response", [[rid, body]])


vue.on_notify = bridge
print("servers initialised in %.1f s" % (time.time() - t0), file=sys.stderr)

rows = [r for r in data["rows"] if r["kind"] in kinds]
step = max(1, len(rows) // limit)
rows = rows[::step][:limit]
opened = set()
res, lat, kind_stats = [], [], {}
for r in rows:
    f = r["file"]
    furi = "file://" + urllib.parse.quote(mapped(f))
    if f not in opened:
        text = open(f, encoding="utf-8", errors="replace").read()
        doc = {"textDocument": {"uri": furi, "languageId": "vue", "version": 1, "text": text}}
        tsls.notify("textDocument/didOpen", doc); vue.notify("textDocument/didOpen", doc)
        opened.add(f)
        time.sleep(float(os.environ.get('VB_GAP', '0.4')) if len(opened) > 1 else float(os.environ.get('VB_WARM', '6')))
    t = time.time()
    out = vue.request("textDocument/definition", {"textDocument": {"uri": furi}, "position": {"line": r["line"], "character": r["character"]}}, timeout=25)
    ms = (time.time() - t) * 1000
    if os.environ.get("VB_DEBUG") and len(res) < 6: print("RAW", r["kind"], r["word"], json.dumps(out)[:300], file=sys.stderr)
    locs = out if isinstance(out, list) else ([out] if out else [])
    targets = []
    for l in locs:
        u = l.get("targetUri") or l.get("uri")
        rng = l.get("targetSelectionRange") or l.get("range") or {}
        if u: targets.append((urllib.parse.unquote(urllib.parse.urlparse(u).path), rng.get("start", {}).get("line", 0) + 1))
    native = [(t["path"], t["line"]) for t in r["native"]]
    if native and targets: cat = "agree" if any(os.path.basename(a[0]) == os.path.basename(b[0]) for a in native for b in targets) else "differ"
    elif native: cat = "native-only"
    elif targets: cat = "volar-only"
    else: cat = "neither"
    kind_stats.setdefault(r["kind"], Counter())[cat] += 1
    lat.append(ms)
    res.append({"file": f, "line": r["line"], "word": r["word"], "kind": r["kind"], "native": native, "volar": targets, "cat": cat, "volarMs": ms})

lat.sort()
pct = lambda p: lat[min(len(lat) - 1, int(len(lat) * p))] if lat else 0
print("VOLAR replayed %d positions (%d files)" % (len(res), len(opened)), file=sys.stderr)
for k, c in kind_stats.items(): print("VOLAR %-6s %s" % (k, dict(c)), file=sys.stderr)
print("VOLAR bridge calls %d, answered %d" % tuple(bridged), file=sys.stderr)
print("VOLAR latency p50=%.1f p95=%.1f max=%.1f ms" % (pct(0.5), pct(0.95), lat[-1] if lat else 0), file=sys.stderr)
print("VOLAR resident: volar+tsserver trees %.0f MB (vue-language-server %.0f MB, typescript-language-server %.0f MB)" %
      (rss_mb([vue.p.pid, tsls.p.pid]), rss_mb([vue.p.pid]), rss_mb([tsls.p.pid])), file=sys.stderr)
if len(args) > 1: json.dump(res, open(args[1], "w"), indent=1)
for s in (vue, tsls):
    try: s.p.kill()
    except Exception: pass
