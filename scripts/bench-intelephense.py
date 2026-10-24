#!/usr/bin/env python3
"""Replays the positions written by `CE_NATIVE_BENCH` (NativePHPBench.swift) against Intelephense and compares latency,
memory and answers. Usage: bench-intelephense.py native.json [out.json]"""
import json, os, subprocess, sys, tempfile, threading, time, urllib.parse

data = json.load(open(sys.argv[1]))
root = data["root"]
store = tempfile.mkdtemp(prefix="ibench")
env = dict(os.environ, NODE_OPTIONS="--max-old-space-size=3072")
p = subprocess.Popen(["intelephense", "--stdio"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=open(os.environ.get("IB_ERR", os.devnull), "w"), env=env)
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
            for m in msgs:
                if m.get("id") == i and "method" not in m:
                    msgs.remove(m); return m.get("result")
                if "method" in m and "id" in m:   # server->client request: answer empty
                    msgs.remove(m); send({"jsonrpc": "2.0", "id": m["id"], "result": None if m["method"] != "workspace/configuration" else [{}]})
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
t0 = time.time()
request("initialize", {"processId": os.getpid(), "rootUri": uri(root), "capabilities": {"window": {"workDoneProgress": True}},
        "initializationOptions": {"storagePath": store, "clearCache": True}, "workspaceFolders": [{"uri": uri(root), "name": "p"}]})
send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
# wait for indexing: a $/progress "end" (or indexingEnded), then RSS stable for 8 s
done, last, stable_since, ended = False, 0, time.time(), False
deadline = time.time() + 900
while time.time() < deadline and not done:
    with cv:
        for m in list(msgs):
            meth = m.get("method", "")
            if meth == "indexingEnded" or (meth == "$/progress" and m["params"].get("value", {}).get("kind") == "end"): ended = True
            if "id" in m and "method" in m: msgs.remove(m); send({"jsonrpc": "2.0", "id": m["id"], "result": [{}] if meth == "workspace/configuration" else None})
            elif meth: msgs.remove(m)
        cv.wait(1.0)
    cur = rss_mb()
    if abs(cur - last) > 15: last, stable_since = cur, time.time()
    if time.time() - t0 > 20 and time.time() - stable_since > 8 and (ended or time.time() - t0 > 60): done = True
index_s = time.time() - t0
peak = rss_mb()
print(f"INTELEPHENSE indexSec={index_s:.1f} rssMB={peak:.0f} (indexing {'finished' if done else 'not confirmed'})", file=sys.stderr)

opened = set(); times = []; agree = disagree = missing = 0; rows = []
for r in data["rows"]:
    f = r["file"]
    if f not in opened:
        send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {"uri": uri(f), "languageId": "php", "version": 1, "text": open(f, encoding="utf-8", errors="replace").read()}}})
        opened.add(f)
    s = time.time()
    res = request("textDocument/definition", {"textDocument": {"uri": uri(f)}, "position": {"line": r["line"] - 1, "character": r["col"] - 1}}, timeout=30)
    ms = (time.time() - s) * 1000; times.append(ms)
    if isinstance(res, dict): res = [res]
    ip = sorted({urllib.parse.unquote(x.get("uri", x.get("targetUri", ""))[7:]) for x in (res or [])})
    np_ = sorted({t.rsplit(":", 1)[0] for t in r["targets"]})
    if not ip and not np_: kind = "both-none"
    elif not ip: kind = "native-only"
    elif not np_: kind = "intelephense-only"
    elif set(ip) & set(np_): kind = "agree"
    else: kind = "differ"
    rows.append({"word": r["word"], "file": f.replace(root, ""), "line": r["line"], "native": np_, "intelephense": ip, "kind": kind})
times.sort()
pc = lambda q: times[min(len(times) - 1, int(len(times) * q))]
from collections import Counter
c = Counter(x["kind"] for x in rows)
print(f"INTELEPHENSE lookups={len(times)} p50ms={pc(.5):.1f} p95ms={pc(.95):.1f} max={times[-1]:.1f} rssAfterMB={rss_mb():.0f}", file=sys.stderr)
print("AGREEMENT", dict(c), file=sys.stderr)
if len(sys.argv) > 2: json.dump(rows, open(sys.argv[2], "w"), indent=1)
p.kill()
