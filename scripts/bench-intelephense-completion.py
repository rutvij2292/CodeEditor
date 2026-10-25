#!/usr/bin/env python3
"""Replays the PHP samples written by CE_COMPLETION_BENCH (CompletionBench.swift, CE_COMPLETION_BENCH_OUT=<json>) against
Intelephense completion and prints the same metrics (found / top1 / top5 / MRR / latency) per category, so native and
Intelephense can be compared on identical truncated documents.
Usage: bench-intelephense-completion.py bench.json <project root> [categories-prefix,...]"""
import json, os, subprocess, sys, tempfile, threading, time, urllib.parse
from collections import defaultdict

data = json.load(open(sys.argv[1]))["rows"]
root = sys.argv[2]
want = sys.argv[3].split(",") if len(sys.argv) > 3 else ["php.this", "php.member", "php.chain", "php.static", "php.new", "php.use", "php.var", "php.func", "php.namedarg"]
rows = [r for r in data if r["file"].endswith(".php") and not r["file"].endswith(".blade.php") and r["file"].startswith(root)
        and any(r["cat"].startswith(w) for w in want)]
store = tempfile.mkdtemp(prefix="ibench")
p = subprocess.Popen(["intelephense", "--stdio"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                     env=dict(os.environ, NODE_OPTIONS="--max-old-space-size=3072"))
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

def request(method, params, timeout=60):
    nid[0] += 1; i = nid[0]
    send({"jsonrpc": "2.0", "id": i, "method": method, "params": params})
    end = time.time() + timeout
    with cv:
        while True:
            for m in list(msgs):
                if m.get("id") == i and "method" not in m: msgs.remove(m); return m.get("result")
                if "method" in m and "id" in m:
                    msgs.remove(m); send({"jsonrpc": "2.0", "id": m["id"], "result": [{}] if m["method"] == "workspace/configuration" else None})
                elif "method" in m: msgs.remove(m)
            if time.time() > end: return None
            cv.wait(0.2)

uri = lambda path: "file://" + urllib.parse.quote(path)
request("initialize", {"processId": os.getpid(), "rootUri": uri(root), "capabilities": {"window": {"workDoneProgress": True}, "textDocument": {"completion": {"completionItem": {"snippetSupport": True}}}},
        "initializationOptions": {"storagePath": store, "clearCache": True}, "workspaceFolders": [{"uri": uri(root), "name": "p"}]})
send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
t0 = time.time()
while time.time() - t0 < float(os.environ.get("IB_INDEX_WAIT", "60")):   # indexing wait (progress end is not reliable across versions)
    with cv:
        for m in list(msgs):
            msgs.remove(m)
            if "id" in m and "method" in m: send({"jsonrpc": "2.0", "id": m["id"], "result": [{}] if m["method"] == "workspace/configuration" else None})
        cv.wait(1.0)
agg = defaultdict(lambda: {"n": 0, "found": 0, "top1": 0, "top5": 0, "mrr": 0.0, "ms": []})
ver = defaultdict(int)
for r in rows:
    text = open(r["file"], encoding="utf-8", errors="replace").read()
    u16 = text.encode("utf-16-le")
    caret = r["loc"] + r["prefix"]
    pre = u16[:caret * 2].decode("utf-16-le", errors="replace")
    line = pre.count("\n"); col = len(pre) - (pre.rfind("\n") + 1)
    ver[r["file"]] += 1
    d = {"uri": uri(r["file"]), "languageId": "php", "version": ver[r["file"]], "text": pre}
    if ver[r["file"]] == 1: send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": d}})
    else: send({"jsonrpc": "2.0", "method": "textDocument/didChange", "params": {"textDocument": {"uri": d["uri"], "version": d["version"]}, "contentChanges": [{"text": pre}]}})
    s = time.time()
    res = request("textDocument/completion", {"textDocument": {"uri": uri(r["file"])}, "position": {"line": line, "character": col}}, timeout=30)
    ms = (time.time() - s) * 1000
    items = res.get("items", []) if isinstance(res, dict) else (res or [])
    typed = pre[len(pre) - r["prefix"]:] if r["prefix"] else ""
    # the editor's matcher: filter by typed prefix (subsequence, case-insensitive), then order like the client would: sortText, then label
    def lab(i): return i.get("filterText") or i["label"]
    def keep(i):
        l = lab(i).lstrip("$").lower(); q = typed.lower(); k = 0
        for ch in l:
            if k < len(q) and ch == q[k]: k += 1
        return k == len(q)
    items = [i for i in items if keep(i)]
    items.sort(key=lambda i: (not lab(i).lstrip("$").lower().startswith(typed.lower()), i.get("sortText") or i["label"]))
    exp = r["expected"]
    rank = 0
    for k, i in enumerate(items):
        l = i["label"].lstrip("$@:<")
        if l == exp or l.split("(")[0] == exp or i.get("insertText", "").lstrip("$").split("(")[0].endswith(exp) and (r["cat"] == "php.use"):
            rank = k + 1; break
    a = agg[f'{r["cat"]}@{r["prefix"]}']
    a["n"] += 1; a["ms"].append(ms)
    if rank: a["found"] += 1; a["mrr"] += 1 / rank; a["top1"] += rank == 1; a["top5"] += rank <= 5
print("INTELEPHENSE completion (same truncated documents as the native bench; typed-prefix filter + sortText order)", file=sys.stderr)
for k in sorted(agg, key=lambda k: agg[k]["mrr"] / agg[k]["n"]):
    a = agg[k]; n = a["n"]; ms = sorted(a["ms"])
    print(f'IBENCH {k:20s} {n:4d}  found {100*a["found"]/n:5.1f}%  top1 {100*a["top1"]/n:5.1f}%  top5 {100*a["top5"]/n:5.1f}%  MRR {a["mrr"]/n:.3f}  p50 {ms[n//2]:.1f}  p95 {ms[min(n-1,int(n*.95))]:.1f} ms', file=sys.stderr)
p.kill()
