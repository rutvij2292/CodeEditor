#!/usr/bin/env python3
"""Replays the positions written by `CE_NJS_BENCH` (NativeJSBench.swift) against the external TypeScript server and compares latency,
memory and answers (go to definition + find usages). Usage: bench-tsserver.py native.json [out.json]
Server: `tsc --lsp --stdio` (TypeScript 7 native) when found, else typescript-language-server (set TS_SERVER=tsls to force)."""
import json, os, shutil, subprocess, sys, threading, time, urllib.parse
from collections import Counter

data = json.load(open(sys.argv[1]))
root = data["root"]

def find_native_tsc():
    cands = []
    for d in subprocess.run(["bash", "-lc", "npm root -g"], capture_output=True, text=True).stdout.split():
        cands.append(d + "/typescript/node_modules/@typescript/typescript-darwin-arm64/lib/tsc")
        cands.append(d + "/typescript/node_modules/@typescript/typescript-darwin-x64/lib/tsc")
    cands.append(root + "/node_modules/@typescript/typescript-darwin-arm64/lib/tsc")
    for c in cands:
        if os.access(c, os.X_OK): return c

mode = os.environ.get("TS_SERVER", "tsc")
if mode == "tsc" and find_native_tsc(): cmd = [find_native_tsc(), "--lsp", "--stdio"]; label = "tsc --lsp"
else:
    cmd = [shutil.which("typescript-language-server"), "--stdio"]; label = "typescript-language-server"
p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=open(os.environ.get("TB_ERR", os.devnull), "w"), env=dict(os.environ), cwd=root)
msgs, cv, nid = [], threading.Condition(), [0]

def reader():
    f = p.stdout
    while True:
        h = b""
        while not h.endswith(b"\r\n\r\n"):
            c = f.read(1)
            if not c: return
            h += c
        n = int([l for l in h.split(b"\r\n") if l.lower().startswith(b"content-length")][0].split(b":")[1])
        m = json.loads(f.read(n))
        with cv: msgs.append(m); cv.notify_all()
threading.Thread(target=reader, daemon=True).start()

def send(o):
    b = json.dumps(o).encode(); p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b); p.stdin.flush()

def request(method, params, timeout=120):
    nid[0] += 1; i = nid[0]
    send({"jsonrpc": "2.0", "id": i, "method": method, "params": params})
    end = time.time() + timeout
    with cv:
        while True:
            for m in list(msgs):
                if m.get("id") == i and "method" not in m:
                    msgs.remove(m); return m.get("result")
                if "method" in m and "id" in m:
                    msgs.remove(m); send({"jsonrpc": "2.0", "id": m["id"], "result": [{}] if m["method"] == "workspace/configuration" else None})
                elif "method" in m: msgs.remove(m)
            if time.time() > end: return None
            cv.wait(0.2)

def rss_mb():
    out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,rss="], capture_output=True, text=True).stdout
    rows = [tuple(map(int, l.split())) for l in out.strip().splitlines()]
    pids = {p.pid}; grew = True
    while grew:
        grew = False
        for pid, ppid, _ in rows:
            if ppid in pids and pid not in pids: pids.add(pid); grew = True
    return sum(r for pid, _, r in rows if pid in pids) / 1024

uri = lambda path: "file://" + urllib.parse.quote(path)
init = {"processId": os.getpid(), "rootUri": uri(root), "capabilities": {"textDocument": {"definition": {"linkSupport": True}}}, "workspaceFolders": [{"uri": uri(root), "name": "p"}]}
if label == "typescript-language-server":
    init["initializationOptions"] = {"tsserver": {"useSyntaxServer": "never"}, "disableAutomaticTypingAcquisition": True}
request("initialize", init)
send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
opened = set()

def open_doc(f):
    if f in opened: return
    text = data.get("texts", {}).get(f) or open(f, encoding="utf-8", errors="replace").read()
    ext = f.rsplit(".", 1)[-1]
    lang = {"ts": "typescript", "tsx": "typescriptreact", "jsx": "javascriptreact", "vue": "javascript"}.get(ext, "javascript")
    if ext == "vue" and "lang=\"ts\"" in text: lang = "typescript"
    send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {"uri": uri(f), "languageId": lang, "version": 1, "text": text}}})
    opened.add(f)

rows_in = data["rows"]
first = None
times = []; out = []
for r in rows_in:
    f = r["file"]; open_doc(f)
    s = time.time()
    res = request("textDocument/definition", {"textDocument": {"uri": uri(f)}, "position": {"line": r["line"], "character": r["character"]}}, timeout=60)
    ms = (time.time() - s) * 1000
    if first is None: first = ms; print(f"SERVER {label}: first request (project load) {ms:.0f} ms, rss {rss_mb():.0f} MB", file=sys.stderr)
    else: times.append(ms)
    if isinstance(res, dict): res = [res]
    locs = []
    for x in (res or []):
        u = x.get("uri", x.get("targetUri", ""))
        rng = x.get("range", x.get("targetSelectionRange", {}))
        locs.append((urllib.parse.unquote(u[7:]), rng.get("start", {}).get("line", 0) + 1))
    ext_ = sorted({l[0] for l in locs}); extl = sorted(set(locs))
    nat = [(t["path"], t["line"]) for t in r["native"]]
    npaths = sorted({t[0] for t in nat})
    if not ext_ and not npaths: kind = "both-none"
    elif not npaths: kind = "server-only"
    elif not ext_: kind = "native-only"
    elif set(nat) & set(extl): kind = "agree"
    elif ext_ == [f] and f not in npaths: kind = "native-resolves-more"      # the server stopped at the local import binding (unresolved module)
    elif set(npaths) & set(ext_): kind = "same-file-other-line"
    else: kind = "differ"
    out.append({"word": r["word"], "kind": r["kind"], "file": f.replace(root, ""), "line": r["line"] + 1, "native": nat, "server": extl, "result": kind})
times.sort()
pc = lambda q: times[min(len(times) - 1, int(len(times) * q))] if times else 0
c = Counter(x["result"] for x in out)
print(f"SERVER lookups={len(times)} p50ms={pc(.5):.1f} p95ms={pc(.95):.1f} max={(times[-1] if times else 0):.1f} rssAfterMB={rss_mb():.0f}", file=sys.stderr)
print("AGREEMENT", dict(c), file=sys.stderr)
nat_ms = sorted(r["ms"] for r in rows_in)
print(f"NATIVE p50ms={nat_ms[len(nat_ms)//2]:.1f} p95ms={nat_ms[int(len(nat_ms)*.95)]:.1f}", file=sys.stderr)
wrong = [x for x in out if x["result"] in ("differ", "same-file-other-line")]
for x in wrong[:20]: print("MISMATCH", x["result"], x["file"], x["line"], x["word"], "native", x["native"][:2], "server", x["server"][:2], file=sys.stderr)
if len(sys.argv) > 2: json.dump(out, open(sys.argv[2], "w"), indent=1)

print("FINDUSAGES symbol native server both onlyNative onlyServer nativeMs serverColdMs serverWarmMs", file=sys.stderr)
for name, u in (data.get("usages") or {}).items():
    f = u["file"]; open_doc(f)
    params = {"textDocument": {"uri": uri(f)}, "position": {"line": u["line"], "character": u["character"]}, "context": {"includeDeclaration": True}}
    s0 = time.time(); res = request("textDocument/references", params, timeout=60); cold = (time.time() - s0) * 1000
    s0 = time.time(); request("textDocument/references", params, timeout=60); warm = (time.time() - s0) * 1000
    srv = {(urllib.parse.unquote(x["uri"][7:]), x["range"]["start"]["line"]) for x in (res or [])}
    nat = {(h["path"], h["line"]) for h in u["hits"]}
    for x in sorted(srv - nat)[:3]: print("  onlyServer", x[0].replace(root, ""), x[1] + 1, file=sys.stderr)
    for x in sorted(nat - srv)[:3]: print("  onlyNative", x[0].replace(root, ""), x[1] + 1, file=sys.stderr)
    print(f"FINDUSAGES {name} native={len(nat)} server={len(srv)} both={len(srv & nat)} onlyNative={len(nat - srv)} onlyServer={len(srv - nat)} nativeMs={u['ms']:.0f} cold={cold:.0f}ms warm={warm:.0f}ms", file=sys.stderr)
p.kill()
