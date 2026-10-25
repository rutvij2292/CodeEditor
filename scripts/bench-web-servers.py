#!/usr/bin/env python3
"""Replays the positions written by `CE_WEB_BENCH` (NativeWebBench.swift) against the external HTML / CSS / Tailwind language servers
(vscode-html-language-server, vscode-css-language-server, tailwindcss-language-server) and compares latency, memory and answers.
Usage: bench-web-servers.py native.json [out.json] [--only html,css,tailwind] [--html-all]   (--html-all also sends .blade.php / .vue files to the HTML server as html)
Read-only on the project; every server is stopped at the end (only the processes this script started)."""
import json, os, re, subprocess, sys, tempfile, threading, time, urllib.parse
from collections import Counter, defaultdict

data = json.load(open(sys.argv[1]))
root = data["root"]
only = set((sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else "html,css,tailwind").split(","))
uri = lambda path: "file://" + urllib.parse.quote(path)

TAILWIND_SETTINGS = {"tailwindCSS": {
    "includeLanguages": {"blade": "html", "blade.php": "html", "vue": "html", "html": "html", "php": "html", "javascript": "javascript",
                         "javascriptreact": "javascriptreact", "typescript": "typescript", "typescriptreact": "typescriptreact", "css": "css"},
    "classAttributes": ["class", "className", ":class", "ngClass", "class:list", "classList"], "emmetCompletions": False, "validate": True,
    "hovers": True, "suggestions": True, "colorDecorators": True, "codeActions": True, "showPixelEquivalents": True, "rootFontSize": 16,
    "experimental": {"classRegex": []}, "files": {"exclude": ["**/.git/**", "**/node_modules/**"]}}, "editor": {"tabSize": 4}}
HTML_SETTINGS = {"html": {"suggest": {"html5": True}, "validate": {"scripts": True, "styles": True}, "autoClosingTags": True}, "css": {"validate": True}, "javascript": {"format": {"enable": True}}}
CSS_SETTINGS = {"css": {"validate": True}, "scss": {"validate": True}, "less": {"validate": True}}


class Server:
    def __init__(self, name, exe, settings):
        self.name, self.settings = name, settings
        self.p = subprocess.Popen([exe, "--stdio"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=root)
        self.msgs, self.cv, self.nid, self.opened = [], threading.Condition(), 0, set()
        threading.Thread(target=self.reader, daemon=True).start()
        r = self.request("initialize", {"processId": os.getpid(), "rootUri": uri(root), "workspaceFolders": [{"uri": uri(root), "name": "p"}],
                                         "capabilities": {"textDocument": {"completion": {"completionItem": {"snippetSupport": True, "documentationFormat": ["markdown", "plaintext"]}},
                                                                           "hover": {"contentFormat": ["markdown", "plaintext"]}, "definition": {}},
                                                          "workspace": {"configuration": True, "workspaceFolders": True}},
                                         "initializationOptions": {"provideFormatter": False, "embeddedLanguages": {"css": True, "javascript": True}} if name != "tailwind" else {}}, timeout=60)
        self.caps = (r or {}).get("capabilities", {})
        self.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
        self.send({"jsonrpc": "2.0", "method": "workspace/didChangeConfiguration", "params": {"settings": settings}})

    def reader(self):
        f = self.p.stdout
        while True:
            h = b""
            while not h.endswith(b"\r\n\r\n"):
                c = f.read(1)
                if not c:
                    return
                h += c
            n = int([l for l in h.split(b"\r\n") if l.lower().startswith(b"content-length")][0].split(b":")[1])
            m = json.loads(f.read(n))
            with self.cv:
                self.msgs.append(m)
                self.cv.notify_all()

    def send(self, o):
        b = json.dumps(o).encode()
        self.p.stdin.write(b"Content-Length: %d\r\n\r\n" % len(b) + b)
        self.p.stdin.flush()

    def answer_server_requests(self, m):
        meth = m["method"]
        if meth == "workspace/configuration":
            res = []
            for it in m["params"].get("items", []):
                sec = it.get("section", "")
                cur = self.settings
                for part in sec.split(".") if sec else []:
                    cur = cur.get(part, {}) if isinstance(cur, dict) else {}
                res.append(cur if sec else self.settings)
            self.send({"jsonrpc": "2.0", "id": m["id"], "result": res})
        else:
            self.send({"jsonrpc": "2.0", "id": m["id"], "result": None})

    def request(self, method, params, timeout=30):
        self.nid += 1
        i = self.nid
        self.send({"jsonrpc": "2.0", "id": i, "method": method, "params": params})
        end = time.time() + timeout
        with self.cv:
            while True:
                for m in list(self.msgs):
                    if m.get("id") == i and "method" not in m:
                        self.msgs.remove(m)
                        return m.get("result")
                    if "method" in m and "id" in m:
                        self.msgs.remove(m)
                        self.answer_server_requests(m)
                    elif "method" in m:
                        self.msgs.remove(m)
                if time.time() > end:
                    return None
                self.cv.wait(0.05)

    def open(self, path, lang):
        if path in self.opened:
            return
        self.opened.add(path)
        self.send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {"textDocument": {"uri": uri(path), "languageId": lang, "version": 1,
                                                                                                  "text": open(path, encoding="utf-8", errors="replace").read()}}})

    def rss_mb(self):
        out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,rss="], capture_output=True, text=True).stdout
        rows = [tuple(map(int, l.split())) for l in out.strip().splitlines()]
        pids, grew = {self.p.pid}, True
        while grew:
            grew = False
            for pid, ppid, _ in rows:
                if ppid in pids and pid not in pids:
                    pids.add(pid)
                    grew = True
        return sum(r for pid, _, r in rows if pid in pids) / 1024

    def stop(self):
        try:
            self.request("shutdown", None, timeout=3)
            self.send({"jsonrpc": "2.0", "method": "exit"})
        except Exception:
            pass
        try:
            self.p.terminate()
        except Exception:
            pass


def lang_for(path):
    e = os.path.splitext(path)[1].lower()
    if path.endswith(".blade.php"):
        return "html" if "--html-all" in sys.argv and "html" in only and len(only) == 1 else "blade"
    return {".css": "css", ".scss": "scss", ".less": "less", ".html": "html", ".htm": "html", ".vue": "vue", ".php": "php", ".jsx": "javascriptreact", ".tsx": "typescriptreact"}.get(e, "html")


def md_text(h):
    if not h:
        return ""
    c = h.get("contents") if isinstance(h, dict) else h
    if isinstance(c, str):
        return c
    if isinstance(c, dict):
        return c.get("value", "")
    if isinstance(c, list):
        return "\n".join(md_text({"contents": x}) for x in c)
    return ""


def decls(text):
    """normalised `prop:value` set from css-looking text"""
    out = set()
    for m in re.finditer(r"([a-zA-Z-]+)\s*:\s*([^;{}\n]+);?", text):
        out.add(m.group(1).lower() + ":" + re.sub(r"\s+", "", m.group(2)).rstrip(";").lower())
    return out


def pct(a, q):
    a = sorted(a)
    return a[min(len(a) - 1, int(len(a) * q))] if a else 0


rows = data["rows"]
result = {"servers": {}, "rows": []}
completion_kinds = {"css-prop", "css-value", "html-tag", "html-attr", "class-complete"}
hover_kinds = {"css-hover", "html-hover", "attr-hover", "class-hover", "css-var"}

plan = {"css": ("vscode-css-language-server", CSS_SETTINGS, lambda r: r["file"].endswith((".css", ".scss", ".less")) and r["kind"].startswith("css-")),
        "html": ("vscode-html-language-server", HTML_SETTINGS, lambda r: r["kind"] in ("html-tag", "html-attr", "html-hover", "attr-hover") and (r["file"].endswith((".html", ".htm")) or "--html-all" in sys.argv and r["file"].endswith((".blade.php", ".vue")))),
        "tailwind": ("tailwindcss-language-server", TAILWIND_SETTINGS, lambda r: r["kind"] in ("class-hover", "class-complete"))}
for name, (exe, settings, pick) in plan.items():
    if name not in only:
        continue
    mine = [r for r in rows if pick(r)]
    if not mine:
        print(f"{name.upper()} no rows to replay", file=sys.stderr)
        continue
    t0 = time.time()
    s = Server(name, exe, settings)
    boot = time.time() - t0
    times = defaultdict(list)
    cmp_ = defaultdict(list)
    kinds = defaultdict(Counter)
    if name == "tailwind":      # the server loads the project's tailwind asynchronously: wait until a hover on a class answers
        for dirpath, dirs, files in os.walk(root):                     # v4: the CSS entry (@import "tailwindcss") tells the server which design system to build
            dirs[:] = [d for d in dirs if d not in ("node_modules", "vendor", ".git", "storage", "public")]
            for fn in files:
                fp = os.path.join(dirpath, fn)
                if fn.endswith(".css") and 'tailwindcss"' in open(fp, encoding="utf-8", errors="replace").read(20000).replace("'", '"'):
                    s.open(fp, "css")
        probe = next((r for r in mine if r["kind"] == "class-hover" and r["hover"]), mine[0])
        s.open(probe["file"], lang_for(probe["file"]))
        end = time.time() + 25
        while time.time() < end:
            if md_text(s.request("textDocument/hover", {"textDocument": {"uri": uri(probe["file"])}, "position": {"line": probe["line"], "character": probe["character"]}}, timeout=10)):
                break
            time.sleep(1)
    ready = time.time() - t0
    rss_boot = s.rss_mb()
    timeouts = 0
    for r in mine:
        if timeouts >= 6:
            print(f"{name.upper()} server stopped answering: remaining rows skipped", file=sys.stderr)
            break
        if r["kind"] == "class-complete" and r.get("prefix", "").startswith("!"):
            continue          # the server never offers the `!` form; Kode inserts it (label keeps the typed `!`), so the sets cannot be compared
        s.open(r["file"], lang_for(r["file"]))
        pos = {"textDocument": {"uri": uri(r["file"])}, "position": {"line": r["line"], "character": r["character"]}}
        t = time.time()
        if r["kind"] in completion_kinds:
            res = s.request("textDocument/completion", dict(pos, context={"triggerKind": 1}), timeout=10)
            timeouts = timeouts + 1 if res is None else 0
            if res is not None and r["kind"] in completion_kinds:
                for it in (res.get("items", []) if isinstance(res, dict) else res):
                    kinds[r["kind"]][it.get("kind")] += 1
            ms = (time.time() - t) * 1000
            items = res.get("items", []) if isinstance(res, dict) else (res or [])
            q = r.get("prefix", "").lower()
            def sub(label, q=q):
                i = 0
                for ch in label.lower():
                    if i < len(q) and ch == q[i]:
                        i += 1
                return i == len(q)
            labels = {it.get("filterText") or it["label"] for it in items}
            labels = {l for l in labels if sub(l)}
            nat = set(r.get("labels", []))
            inter = labels & nat
            sp = {l for l in labels if l.lower().startswith(q)}
            npfx = {l for l in nat if l.lower().startswith(q)}
            cmp_[r["kind"]].append({"file": r["file"].replace(root, ""), "prefix": q, "server": len(labels), "native": len(nat), "both": len(inter),
                                    "pServer": len(sp), "pNative": len(npfx), "pBoth": len(sp & npfx), "pOnlyServer": sorted(sp - npfx)[:8], "pOnlyNative": sorted(npfx - sp)[:8],
                                    "fullOnlyServer": sorted(sp - npfx), "fullOnlyNative": sorted(npfx - sp),
                                    "onlyServer": sorted(labels - nat)[:8], "onlyNative": sorted(nat - labels)[:8]})
        else:
            res = s.request("textDocument/hover", pos, timeout=10)
            ms = (time.time() - t) * 1000
            sv = md_text(res)
            nv = r.get("hover", "")
            row = {"file": r["file"].replace(root, ""), "line": r["line"], "server": bool(sv), "native": bool(nv)}
            if r["kind"] == "class-hover":
                row["declsServer"], row["declsNative"] = sorted(decls(sv)), sorted(decls(nv))
                row["same"] = decls(sv) == decls(nv) and bool(sv)
                row["subset"] = bool(decls(nv)) and decls(nv) <= decls(sv)
            if r["kind"] == "css-var" and s.caps.get("definitionProvider"):
                d = s.request("textDocument/definition", pos, timeout=20)
                d = [d] if isinstance(d, dict) else (d or [])
                row["defServer"] = sorted({urllib.parse.unquote(x.get("uri", x.get("targetUri", ""))[7:]) + ":" + str(x.get("range", x.get("targetRange", {})).get("start", {}).get("line", 0) + 1) for x in d})
                row["defNative"] = sorted(r.get("targets", []))
            cmp_[r["kind"]].append(row)
        times[r["kind"]].append(ms)
    rss = s.rss_mb()
    for k, c in kinds.items():
        print(f"{name.upper()} completion kinds {k}: {dict(c)}", file=sys.stderr)
    result["servers"][name] = {"bootSec": boot, "readySec": ready, "rssBootMB": rss_boot, "rssAfterMB": rss,
                               "latency": {k: {"n": len(v), "p50": pct(v, .5), "p95": pct(v, .95), "max": max(v)} for k, v in times.items()}}
    print(f"{name.upper()} bootSec={boot:.1f} readySec={ready:.1f} rssBootMB={rss_boot:.0f} rssAfterMB={rss:.0f}", file=sys.stderr)
    for k, v in sorted(times.items()):
        print(f"{name.upper()} {k} n={len(v)} p50={pct(v, .5):.1f}ms p95={pct(v, .95):.1f}ms max={max(v):.1f}ms", file=sys.stderr)
    for k, lst in sorted(cmp_.items()):
        if k in completion_kinds:
            tot_s = sum(x["server"] for x in lst)
            tot_n = sum(x["native"] for x in lst)
            both = sum(x["both"] for x in lst)
            exact = sum(1 for x in lst if x["server"] == x["both"] == x["native"])
            recall = both / tot_s if tot_s else 1
            prec = both / tot_n if tot_n else 1
            full = sum(1 for x in lst if x["both"] == x["server"])
            ps, pn, pb = sum(x["pServer"] for x in lst), sum(x["pNative"] for x in lst), sum(x["pBoth"] for x in lst)
            pexact = sum(1 for x in lst if x["pServer"] == x["pBoth"] == x["pNative"])
            print(f"PARITY {name}/{k} positions={len(lst)} prefixMatches: recall={pb / ps if ps else 1:.1%} ({pb}/{ps} of the server's items) precision={pb / pn if pn else 1:.1%} identicalPositions={pexact}/{len(lst)}; fuzzy: recall={recall:.1%} precision={prec:.1%}", file=sys.stderr)
            miss = Counter(l for x in lst for l in x["pOnlyServer"])
            extra = Counter(l for x in lst for l in x["pOnlyNative"])
            if miss: print(f"   server-only (prefix): {dict(miss.most_common(12))}", file=sys.stderr)
            if extra: print(f"   native-only (prefix): {dict(extra.most_common(12))}", file=sys.stderr)
        else:
            both = sum(1 for x in lst if x["server"] and x["native"])
            so = sum(1 for x in lst if x["server"] and not x["native"])
            no = sum(1 for x in lst if x["native"] and not x["server"])
            none = sum(1 for x in lst if not x["native"] and not x["server"])
            extra = ""
            if k == "class-hover":
                extra = f" sameDecls={sum(1 for x in lst if x.get('same'))} nativeSubsetOfServer={sum(1 for x in lst if x.get('subset'))}"
            if k == "css-var":
                ds = [x for x in lst if "defServer" in x]
                if ds:
                    extra = f" defAgree={sum(1 for x in ds if set(x['defServer']) & set(x['defNative']))}/{len(ds)}"
            print(f"PARITY {name}/{k} positions={len(lst)} bothAnswer={both} serverOnly={so} nativeOnly={no} neitherAnswers={none}{extra}", file=sys.stderr)
    if "--dump-missing" in sys.argv:
        dump = {}
        for k, lst in cmp_.items():
            if k in completion_kinds:
                dump[k] = {"serverOnly": dict(Counter(l for x in lst for l in x["fullOnlyServer"]).most_common(400)),
                           "nativeOnly": dict(Counter(l for x in lst for l in x["fullOnlyNative"]).most_common(400))}
        json.dump(dump, open(sys.argv[sys.argv.index("--dump-missing") + 1] + "." + name + ".json", "w"), indent=1)
    for lst in cmp_.values():
        for x in lst:
            x.pop("fullOnlyServer", None)
            x.pop("fullOnlyNative", None)
    result["rows"].append({name: {k: v[:400] for k, v in cmp_.items()}})
    s.stop()

if len(sys.argv) > 2 and not sys.argv[2].startswith("--"):
    json.dump(result, open(sys.argv[2], "w"), indent=1)
