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
    # the server echoes the case an import was typed with; native returns the real on-disk spelling: compare case-insensitively
    ext_ = sorted({l.lower() for l in ext_}); extl = sorted({(l[0].lower(), l[1]) for l in extl})
    nat_l = [(a.lower(), b) for a, b in nat]
    npaths = sorted({t[0] for t in nat_l})
    if not ext_ and not npaths: kind = "both-none"
    elif not npaths: kind = "server-only"
    elif not ext_: kind = "native-only"
    elif set(nat_l) & set(extl): kind = "agree"
    elif ext_ == [f.lower()] and f.lower() not in npaths: kind = "native-resolves-more"      # the server stopped at the local import binding (unresolved module)
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

# signature help parity
sigs = data.get("sigs") or []
if sigs:
    agree = lab = srv_only = nat_only = both_none = unknown = 0
    shown = 0
    for r in sigs:
        f = r["file"]; open_doc(f)
        res = request("textDocument/signatureHelp", {"textDocument": {"uri": uri(f)}, "position": {"line": r["line"], "character": r["character"]}}, timeout=30)
        ss = (res or {}).get("signatures") or []
        native = r["result"] == "help"
        norm = lambda x: x.replace(" ", "").replace("\n", "")
        if not ss and not native: both_none += 1
        elif ss and not native:
            srv_only += 1 if r["result"] in ("unknown", "none") else 0
        elif native and not ss: nat_only += 1
        else:
            sl = {norm(x["label"].split(": ")[0] if False else x["label"]) for x in ss}
            nl = {norm(x) for x in r["labels"]}
            # TypeScript prints the return type after a colon and `name(...)`: compare name + parameter lists
            def key(l):
                # callee name + parameter NAMES (TypeScript instantiates generics and adds `: any` to JS parameters; types are inference, not structure)
                l = norm(l); i = l.find("(")
                depth = 0; params = []; cur = ""
                for j in range(i, len(l)):
                    ch = l[j]
                    if ch in "([{<": depth += 1
                    if ch in ")]}>" and not (ch == ">" and l[j - 1] == "="): depth -= 1
                    if depth == 0: break
                    if ch == "," and depth == 1: params.append(cur); cur = ""; continue
                    if depth >= 1 and j > i: cur += ch
                if cur: params.append(cur)
                import re
                names = []
                for pr in params:
                    pr = pr.lstrip(".")
                    m = re.match(r"[A-Za-z_$][\w$]*", pr)
                    names.append(m.group(0) if m else pr[:6])
                return (l[:i].split("<")[0]).replace("new", "", 1) + "(" + ",".join(names) + ")"
            if {key(x) for x in sl} & {key(x) for x in nl}: agree += 1
            else:
                lab += 1
                if shown < 8: shown += 1; print("SIGMISMATCH", f.replace(root, ""), r["line"] + 1, "native", r["labels"][:2], "server", [x["label"] for x in ss][:2], file=sys.stderr)
    print(f"SIGNATURE sampled={len(sigs)} agree={agree} labelDiffers={lab} serverOnly={srv_only} nativeOnly={nat_only} bothNone={both_none}", file=sys.stderr)

# rename parity: the server's edit set for the same symbols
rens = data.get("renames") or []
if rens:
    same = subset = missing = refused = superset = 0
    for r in rens:
        f = r["file"]; open_doc(f)
        res = request("textDocument/rename", {"textDocument": {"uri": uri(f)}, "position": {"line": r["line"], "character": r["character"]}, "newName": "NjsRenamed"}, timeout=60)
        srv = set()
        changes = (res or {}).get("changes") or {}
        for u, es in changes.items():
            for e in es: srv.add((urllib.parse.unquote(u[7:]), e["range"]["start"]["line"]))
        for dc in (res or {}).get("documentChanges") or []:
            u = dc["textDocument"]["uri"]
            for e in dc["edits"]: srv.add((urllib.parse.unquote(u[7:]), e["range"]["start"]["line"]))
        if "edits" not in r: refused += 1; continue
        nat = {(e["path"], e["line"]) for e in r["edits"]}
        # project files only: the server also edits declarations inside node_modules typings, which native refuses by design
        srv_p = {x for x in srv if "/node_modules/" not in x[0]}
        if nat == srv_p: same += 1
        elif nat <= srv_p: subset += 1; print("RENAME native subset", r["name"], len(nat), "of", len(srv_p), file=sys.stderr)
        elif srv_p <= nat: superset += 1; print("RENAME native superset", r["name"], "extra", sorted(nat - srv_p)[:2], file=sys.stderr)
        else: missing += 1; print("RENAME MISMATCH", r["name"], "native", len(nat), "server", len(srv_p), "onlyNative", sorted(nat - srv_p)[:2], file=sys.stderr)
    print(f"RENAME sampled={len(rens)} identical={same} nativeSuperset={superset} nativeSubset={subset} mismatch={missing} refusedNative={refused}", file=sys.stderr)
p.kill()
