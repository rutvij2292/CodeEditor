#!/usr/bin/env python3
"""Builds Kode's bundled PHP built-in stubs (PhpStubs/) from JetBrains' phpstorm-stubs (Apache-2.0).

    git clone --depth 1 https://github.com/JetBrains/phpstorm-stubs /tmp/phpstorm-stubs
    python3 scripts/make-php-stubs.py /tmp/phpstorm-stubs PhpStubs

What it does (see docs/native-php.md, "Built-in stubs"):
  * keeps only the extensions in EXTENSIONS (Laravel / PHP web work),
  * splits every class / interface / trait / enum into its own file  classes/<Name>.php  (so the native engine can parse a single
    declaration lazily; namespaced names use '_' instead of '\\'),
  * groups functions and constants per source stub file  functions/<ext>_<file>.php, constants/<ext>_<file>.php,
  * resolves JetBrains attributes for PHP TARGET (8.3): #[PhpStormStubsElementAvailable] drops elements that do not exist in 8.3,
    #[LanguageLevelTypeAware] becomes a real type, #[Deprecated] becomes @deprecated, every other attribute is dropped,
  * empties function bodies and cleans PHPDoc (HTML, @link / URL @see lines, size caps),
  * writes index.txt, a sorted tab separated table  kind \\t lowercase-name \\t name \\t file \\t nameOffset \\t declOffset \\t extra
    (offsets are UTF-16 code units, what NSString uses), searched by binary search over an mmap'd file at runtime,
  * copies LICENSE and writes SOURCE.txt (upstream commit, the modifications made, as Apache-2.0 section 4 requires).

The output is committed, so building Kode never needs this script or the upstream repository.
"""
import html
import os
import re
import shutil
import subprocess
import sys

TARGET = (8, 3)
EXTENSIONS = [
    "Core", "standard", "date", "SPL", "json", "mbstring", "ctype", "pcre", "PDO", "mysqli", "curl", "zip", "dom", "SimpleXML",
    "libxml", "xml", "xmlreader", "xmlwriter", "fileinfo", "filter", "hash", "openssl", "session", "iconv", "intl", "bcmath", "gd",
    "Reflection", "random", "zlib", "sodium", "tokenizer", "posix", "pcntl", "calendar", "exif", "gmp", "sqlite3", "pgsql", "redis",
    "Phar", "soap", "ftp", "sockets", "readline", "xsl",
]
MODIFIERS = {"public", "protected", "private", "static", "abstract", "final", "readonly", "var"}
CLASS_KW = {"class", "interface", "trait", "enum"}

TOKEN_RE = re.compile(r"""
    (?P<ws>\s+)
  | (?P<doc>/\*\*.*?\*/)
  | (?P<bcomment>/\*.*?\*/)
  | (?P<lcomment>//[^\n]*|\#(?!\[)[^\n]*)
  | (?P<attr>\#\[)
  | (?P<str>'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")
  | (?P<var>\$\w+)
  | (?P<ident>\\?[A-Za-z_\x80-\U0010ffff][\w\\\x80-\U0010ffff]*)
  | (?P<num>\d[\w.]*)
  | (?P<punct>\.\.\.|=>|::|->|.)
""", re.S | re.X)


class Tok:
    __slots__ = ("kind", "text", "start", "end")

    def __init__(self, kind, text, start, end):
        self.kind, self.text, self.start, self.end = kind, text, start, end

    def __repr__(self):
        return f"{self.kind}:{self.text[:20]!r}"


def tokenize(src):
    toks, pos, n = [], 0, len(src)
    while pos < n:
        m = TOKEN_RE.match(src, pos)
        if not m:
            raise ValueError("cannot tokenize at %d: %r" % (pos, src[pos:pos + 30]))
        kind = m.lastgroup
        if kind == "attr":
            depth, j = 0, pos + 1
            while j < n:
                c = src[j]
                if c in "'\"":
                    mm = TOKEN_RE.match(src, j)
                    j = mm.end()
                    continue
                if c == "[":
                    depth += 1
                elif c == "]":
                    depth -= 1
                    if depth == 0:
                        j += 1
                        break
                j += 1
            toks.append(Tok("attr", src[pos:j], pos, j))
            pos = j
            continue
        if kind not in ("ws", "doc", "bcomment", "lcomment"):
            toks.append(Tok(kind, m.group(), pos, m.end()))
        pos = m.end()
    return toks


def vkey(s):
    m = re.match(r"(\d+)(?:\.(\d+))?", s.strip())
    return (int(m.group(1)), int(m.group(2) or 0)) if m else (0, 0)


def attr_name(a):
    m = re.match(r"#\[\s*\\?([\w\\]+)", a.text)
    return m.group(1).split("\\")[-1] if m else ""


def available(attrs):
    for a in attrs:
        if attr_name(a) != "PhpStormStubsElementAvailable":
            continue
        body = a.text
        frm = re.search(r"from\s*:\s*['\"]([\d.]+)['\"]", body)
        to = re.search(r"to\s*:\s*['\"]([\d.]+)['\"]", body)
        pos = re.search(r"\(\s*['\"]([\d.]+)['\"]", body)
        lo = vkey(frm.group(1)) if frm else (vkey(pos.group(1)) if pos else (0, 0))
        hi = vkey(to.group(1)) if to else (99, 0)
        if not (lo <= TARGET <= hi):
            return False
    return True


def lang_type(attrs):
    for a in attrs:
        if attr_name(a) != "LanguageLevelTypeAware":
            continue
        best, bestv = None, (-1, 0)
        for v, t in re.findall(r"['\"](\d+\.\d+)['\"]\s*=>\s*['\"]([^'\"]*)['\"]", a.text):
            if vkey(v) <= TARGET and vkey(v) > bestv:
                best, bestv = t, vkey(v)
        if best is None:
            m = re.search(r"default\s*:\s*['\"]([^'\"]*)['\"]", a.text)
            best = m.group(1) if m else ""
        return best
    return ""


def deprecated(attrs):
    for a in attrs:
        if attr_name(a) == "Deprecated":
            m = re.search(r"since\s*:\s*['\"]([\d.]+)['\"]", a.text)
            if m and vkey(m.group(1)) > TARGET:
                return None
            r = re.search(r"reason\s*:\s*['\"]([^'\"]*)['\"]", a.text)
            return r.group(1) if r else ""
    return None


# ---------------------------------------------------------------- PHPDoc cleanup

def clean_doc(raw, indent, extra_deprecated=None):
    body = raw[3:-2] if raw.endswith("*/") else raw[3:]
    lines = []
    for ln in body.split("\n"):
        ln = re.sub(r"^\s*\*? ?", "", ln.rstrip())
        lines.append(ln)
    text = "\n".join(lines)
    text = re.sub(r"\{@link\s+\S+\s+([^}]*)\}", r"\1", text)
    text = re.sub(r"\{@(?:link|see)\s+([^}\s]*)[^}]*\}", r"\1", text)
    text = re.sub(r"<br\s*/?>", "\n", text)
    text = re.sub(r"</?(?:p|b|i|em|strong|code|tt|pre|ul|ol|li|table|tr|td|th|tbody|thead|span|a|var|dl|dt|dd|h\d|blockquote|div|function|methodname|classname|parameter|constant|literal|varname|filename|command|option|replaceable|emphasis|type|interfacename|exceptionname|systemitem|acronym|abbrev|quote|simpara|para|note|example|programlisting|informaltable|entry|row|member|itemizedlist|listitem|link|productname|envar|property|methodparam|ooclass|oointerface|simplelist|title|screen|sgmltag|tag|collapsed|class|object|keycap|firstterm|trademark)(?:\s[^>]*)?/?>", "", text)
    text = html.unescape(text)
    summary, tags = [], []
    cur = summary
    for ln in text.split("\n"):
        s = ln.strip()
        if re.match(r"^\(PHP[^)]*\)$", s) or re.match(r"^\(PECL[^)]*\)$", s) or re.match(r"^\(No version information", s):
            continue
        if s.startswith("@"):
            tag = s.split()[0]
            if tag in ("@link", "@meta", "@package", "@subpackage", "@author", "@copyright", "@license", "@version", "@internal", "@access"):
                cur = [None]
                continue
            if tag == "@see" and re.search(r"https?://", s):
                cur = [None]
                continue
            cur = [s]
            tags.append(cur)
            continue
        if cur and cur[0] is None:
            continue
        cur.append(s) if cur is not summary else summary.append(s)
    # summary: collapse blank runs, cap
    summ = re.sub(r"\n{3,}", "\n\n", "\n".join(summary).strip())
    if len(summ) > 700:
        summ = summ[:700].rsplit(" ", 1)[0] + " ..."
    out = [summ] if summ else []
    seen_dep = False
    for t in tags:
        parts = [p for p in t if p is not None and p != ""]
        s = " ".join(parts)
        if s.startswith("@deprecated"):
            seen_dep = True
        if len(s) > 300:
            s = s[:300].rsplit(" ", 1)[0] + " ..."
        out.append(s)
    if extra_deprecated is not None and not seen_dep:
        out.append(("@deprecated " + extra_deprecated).strip())
    if not out:
        return ""
    res = [indent + "/**"]
    for chunk in out:
        for ln in chunk.split("\n"):
            res.append(indent + " * " + ln if ln else indent + " *")
    res.append(indent + " */")
    return "\n".join(res)


# ---------------------------------------------------------------- structure helpers

def match_close(toks, i, open_c, close_c):
    depth = 0
    for j in range(i, len(toks)):
        t = toks[j]
        if t.kind == "punct":
            if t.text == open_c:
                depth += 1
            elif t.text == close_c:
                depth -= 1
                if depth == 0:
                    return j
    raise ValueError("unbalanced " + open_c)


def line_indent(src, pos):
    ls = src.rfind("\n", 0, pos) + 1
    m = re.match(r"[ \t]*", src[ls:pos])
    return m.group()


class Gen:
    def __init__(self, src, toks):
        self.src, self.toks = src, toks

    # Collect (docs, attrs) preceding token index i. Docs come from the raw text between the previous significant token and i.
    def lead(self, i, prev_end):
        """(attrs directly before token i, last /** doc */ between prev_end and token i as (start, end, text) or None, 0)."""
        j = i
        attrs = []
        while j > 0 and self.toks[j - 1].kind == "attr" and self.toks[j - 1].start >= prev_end:
            j -= 1
            attrs.insert(0, self.toks[j])
        region = self.src[prev_end:self.toks[i].start]
        docs = list(re.finditer(r"/\*\*.*?\*/", region, re.S))
        doc = None
        if docs:
            m = docs[-1]
            doc = (prev_end + m.start(), prev_end + m.end(), m.group())
        return attrs, doc, 0

    # Strips attributes / fixes params / empties body for a member or function in toks[i..end] (inclusive end index).
    def render_decl(self, i, end, attrs, doc, doc_start, indent, kind_hint):
        src, toks = self.src, self.toks
        s0 = toks[i].start
        e0 = toks[end].end
        edits = []   # (start, end, replacement) over absolute offsets
        # find function keyword / var
        is_fn = False
        fn_idx = None
        depth = 0
        for j in range(i, end + 1):
            t = toks[j]
            if t.kind == "punct" and t.text in "([{":
                depth += 1
            elif t.kind == "punct" and t.text in ")]}":
                depth -= 1
            if depth == 0 and t.kind == "ident" and t.text.lower() == "function":
                is_fn, fn_idx = True, j
                break
            if t.kind == "punct" and t.text in "=;":
                break
        ret_type = ""
        if attrs:
            ret_type = lang_type(attrs)
        if is_fn:
            # params
            lp = fn_idx + 1
            while toks[lp].text != "(":
                lp += 1
            rp = match_close(toks, lp, "(", ")")
            groups, cur, d = [], [], 0
            for j in range(lp + 1, rp):
                t = toks[j]
                if t.kind == "punct" and t.text in "([{":
                    d += 1
                elif t.kind == "punct" and t.text in ")]}":
                    d -= 1
                if d == 0 and t.kind == "punct" and t.text == ",":
                    groups.append(cur)
                    cur = []
                else:
                    cur.append(t)
            if cur:
                groups.append(cur)
            commas = [t for t in toks[lp + 1:rp] if t.kind == "punct" and t.text == ","]
            kept = 0
            for gi, g in enumerate(groups):
                pattrs = [t for t in g if t.kind == "attr"]
                rest = [t for t in g if t.kind != "attr"]
                if not rest:
                    continue
                if not available(pattrs):
                    # remove group and its following comma (or preceding for the last kept)
                    a, b = g[0].start, g[-1].end
                    if gi < len(groups) - 1:
                        nxt = groups[gi + 1][0].start
                        b = nxt
                    else:
                        # last group: also eat the previous comma
                        prev_end = groups[gi - 1][-1].end if gi > 0 else a
                        a = prev_end
                    edits.append((a, b, ""))
                    continue
                kept += 1
                for t in pattrs:
                    edits.append((t.start, self.skip_ws(t.end), ""))
                lt = lang_type(pattrs)
                if lt:
                    typed = False
                    ins = None
                    for t in rest:
                        if t.kind == "var":
                            ins = ins if ins is not None else t.start
                            break
                        if t.kind == "punct" and t.text in ("&", "..."):
                            ins = ins if ins is not None else t.start
                            continue
                        if t.kind == "ident" and t.text.lower() in ("public", "protected", "private", "readonly"):
                            continue
                        typed = True
                    if not typed and ins is not None:
                        edits.append((ins, ins, lt + " "))
            # return type
            if ret_type and not (rp + 1 < len(toks) and toks[rp + 1].text == ":" and rp + 1 <= end):
                edits.append((toks[rp].end, toks[rp].end, ": " + ret_type))
            # body
            b = None
            for j in range(rp + 1, end + 1):
                if toks[j].kind == "punct" and toks[j].text == "{":
                    b = j
                    break
            if b is not None:
                be = match_close(toks, b, "{", "}")
                if toks[be].start - toks[b].end > 0:
                    edits.append((toks[b].start, toks[be].end, "{}"))
        else:
            # property / constant / case / use: LanguageLevelTypeAware gives a type before the variable
            lt = ret_type
            if lt:
                var = next((t for t in toks[i:end + 1] if t.kind == "var"), None)
                if var is not None:
                    typed = False
                    for t in toks[i:end + 1]:
                        if t is var:
                            break
                        if t.kind == "ident" and t.text.lower() not in MODIFIERS:
                            typed = True
                        if t.kind == "punct" and t.text in ("?", "|"):
                            typed = True
                    if not typed:
                        edits.append((var.start, var.start, lt + " "))
        # attributes inside the declaration range (e.g. inline) are handled via groups above; strip remaining top-level ones
        for t in toks[i:end + 1]:
            if t.kind == "attr" and not any(e[0] == t.start for e in edits) and not self._inside_params(t, i, end, is_fn, fn_idx):
                edits.append((t.start, self.skip_ws(t.end), ""))
        edits.sort(key=lambda e: (e[0], e[1]))
        out, pos = [], s0
        for a, b, r in edits:
            if a < pos:
                continue
            out.append(src[pos:a])
            out.append(r)
            pos = b
        out.append(src[pos:e0])
        body = "".join(out)
        dep = deprecated(attrs) if attrs else None
        docs = ""
        if doc is not None:
            docs = clean_doc(doc[2], indent, dep)
        elif dep is not None:
            docs = clean_doc("/** */", indent, dep)
        return (docs + "\n" if docs else "") + indent + body

    def _inside_params(self, t, i, end, is_fn, fn_idx):
        return False

    def skip_ws(self, p):
        while p < len(self.src) and self.src[p] in " \t\r\n":
            p += 1
        return p


def parse_file(path, ext, state):
    src = open(path, encoding="utf-8").read()
    src = src.replace("\r\n", "\n")
    if src.startswith("<?php"):
        src = "     " + src[5:]
    toks = tokenize(src)
    g = Gen(src, toks)
    base = os.path.splitext(os.path.basename(path))[0]
    walk(g, 0, len(toks), "", [], ext, base, state, prev_end=0)


def stmt_end(toks, i):
    """Index of the `;` ending the statement that starts at i (depth aware), or the end of a `{}` block."""
    d = 0
    for j in range(i, len(toks)):
        t = toks[j]
        if t.kind == "punct":
            if t.text in "([{":
                d += 1
            elif t.text in ")]}":
                d -= 1
            elif t.text == ";" and d == 0:
                return j
    return len(toks) - 1


def walk(g, i, end, ns, uses, ext, base, state, prev_end):
    toks, src = g.toks, g.src
    uses = list(uses)
    while i < end:
        t = toks[i]
        if t.kind == "punct" and t.text in ";}":
            prev_end = t.end
            i += 1
            continue
        # leading attrs
        start_i = i
        while i < end and toks[i].kind == "attr":
            i += 1
        if i >= end:
            break
        t = toks[i]
        word = t.text.lower() if t.kind == "ident" else ""
        if t.kind == "ident" and word == "namespace" and not (i + 1 < end and toks[i + 1].text == "\\"):
            j = i + 1
            name = ""
            if toks[j].kind == "ident":
                name = toks[j].text
                j += 1
            if toks[j].text == "{":
                close = match_close(toks, j, "{", "}")
                walk(g, j + 1, close, name, [], ext, base, state, toks[j].end)
                i = close + 1
                prev_end = toks[close].end
            else:
                ns = name
                uses = []
                i = j + 1
                prev_end = toks[j].end
            continue
        if word == "use":
            e = stmt_end(toks, i)
            text = src[t.start:toks[e].end]
            if "JetBrains" not in text:
                uses.append(text)
            i = e + 1
            prev_end = toks[e].end
            continue
        if word == "declare":
            e = stmt_end(toks, i)
            i = e + 1
            prev_end = toks[e].end
            continue
        attrs, doc, doc_start = g.lead(i, prev_end)
        if word == "const":
            e = stmt_end(toks, i)
            if available(attrs):
                add_constants(g, i, e, doc, ns, ext, base, state)
            i = e + 1
            prev_end = toks[e].end
            continue
        if word == "define" and i + 1 < end and toks[i + 1].text == "(":
            e = stmt_end(toks, i)
            if available(attrs):
                add_define(g, i, e, doc, ext, base, state)
            i = e + 1
            prev_end = toks[e].end
            continue
        if word == "function":
            e = i
            while toks[e].text != "(":
                e += 1
            rp = match_close(toks, e, "(", ")")
            e = rp
            while not (toks[e].kind == "punct" and toks[e].text in "{;"):
                e += 1
            if toks[e].text == "{":
                e = match_close(toks, e, "{", "}")
            if available(attrs):
                add_function(g, i, e, attrs, doc, doc_start, ns, ext, base, state)
            i = e + 1
            prev_end = toks[e].end
            continue
        # class-like (modifiers first)
        j = i
        while j < end and toks[j].kind == "ident" and toks[j].text.lower() in ("final", "abstract", "readonly"):
            j += 1
        if j < end and toks[j].kind == "ident" and toks[j].text.lower() in CLASS_KW:
            e = j
            while toks[e].text != "{":
                e += 1
            close = match_close(toks, e, "{", "}")
            if available(attrs):
                add_class(g, i, j, e, close, attrs, doc, doc_start, ns, uses, ext, base, state)
            i = close + 1
            prev_end = toks[close].end
            continue
        # unknown statement: skip
        e = stmt_end(toks, i)
        i = e + 1
        prev_end = toks[e].end


# ---------------------------------------------------------------- emitters

def u16(s):
    return len(s.encode("utf-16-le")) // 2


def add_class(g, i, kw, brace, close, attrs, doc, doc_start, ns, uses, ext, base, state):
    toks, src = g.toks, g.src
    name = toks[kw + 1].text
    if ns.startswith("___") or name.startswith("PS_UNRESERVE"):
        return
    fqn = (ns + "\\" if ns else "") + name
    header = " ".join(t.text for t in toks[i:brace])
    # keep the original header spacing
    header = re.sub(r"\s+", " ", src[toks[i].start:toks[brace].start]).strip()
    out = ["<?php"]
    if ns:
        out.append("namespace %s;" % ns)
    out.append("")
    for u in uses:
        out.append(u)
    if uses:
        out.append("")
    dep = deprecated(attrs)
    docs = clean_doc(doc[2], "", dep) if doc else (clean_doc("/** */", "", dep) if dep is not None else "")
    if docs:
        out.append(docs)
    head_off_text = "\n".join(out) + "\n"
    decl_start = u16(head_off_text)
    # name offset
    head_prefix = header[: header.index(name, header.lower().index(toks[kw].text.lower()) + len(toks[kw].text))] if name in header else ""
    name_loc = decl_start + u16(head_prefix)
    # members
    k = brace + 1
    prev = toks[brace].end
    body_parts = []
    while k < close:
        m_start = k
        while m_start < close and toks[m_start].kind == "attr":
            m_start += 1
        if m_start >= close:
            break
        if toks[m_start].kind == "punct" and toks[m_start].text == ";":
            prev = toks[m_start].end
            k = m_start + 1
            continue
        a, d, ds = g.lead(m_start, prev)
        e = m_start
        depth = 0
        is_fn = False
        while e < close:
            tt = toks[e]
            if tt.kind == "ident" and tt.text.lower() == "function" and depth == 0:
                is_fn = True
            if tt.kind == "punct":
                if tt.text in "([":
                    depth += 1
                elif tt.text in ")]":
                    depth -= 1
                elif tt.text == "{" and depth == 0:
                    e = match_close(toks, e, "{", "}")
                    break
                elif tt.text == ";" and depth == 0:
                    break
            e += 1
        if e >= close:
            e = close - 1
        prev = toks[e].end
        k = e + 1
        if not available(a):
            continue
        body_parts.append(g.render_decl(m_start, e, a, d, ds, "    ", "member"))
    out_text = head_off_text
    sig_start = u16(out_text)
    kind = toks[kw].text.lower()
    out_text += header + "\n{\n" + "\n\n".join(body_parts) + "\n}\n"
    # name offset recomputed against the final text
    pos = out_text.find(header, 0)
    name_loc = u16(out_text[: out_text.index(name, pos + header.lower().index(kind) + len(kind))])
    cpath = "classes/" + fqn.replace("\\", "_") + ".php"
    key = fqn.lower()
    if key in state["classes"]:
        return
    state["classes"][key] = (fqn, cpath, name_loc, decl_start, kind, ext)
    state["files"][cpath] = out_text


def add_function(g, i, e, attrs, doc, doc_start, ns, ext, base, state):
    toks = g.toks
    j = i + 1
    if toks[j].text == "&":
        j += 1
    name = toks[j].text
    if ns.startswith("___") or name.startswith("PS_UNRESERVE"):
        return
    text = g.render_decl(i, e, attrs, doc, doc_start, "", "function")
    # position of the `function` keyword and name inside text
    fkey = (ns + "\\" if ns else "") + name
    key = fkey.lower()
    if key in state["functions"]:
        return
    path = "functions/%s_%s.php" % (ext, state["base"])
    buf = state["fbuf"].setdefault(path, "<?php\n")
    kwpos = text.index("function")
    namepos = text.index(name, kwpos + 8)
    docblock_len = kwpos
    base_off = u16(buf + "\n")
    sig = re.sub(r"\s+", " ", text[namepos:]).strip()
    sig = re.sub(r"\(\s+", "(", sig)
    sig = re.sub(r"\s+\)", ")", sig)
    sig = re.sub(r"\s*(\{\s*\}|;)\s*$", "", sig)
    if len(sig) > 240:
        sig = sig[:240].rsplit(",", 1)[0] + ", ...)"
    state["functions"][key] = (fkey, path, base_off + u16(text[:namepos]), base_off + u16(text[:kwpos]), ext + "\t" + sig)
    state["fbuf"][path] = buf + "\n" + text + "\n"


def add_constants(g, i, e, doc, ns, ext, base, state):
    toks, src = g.toks, g.src
    # const A = 1, B = 2;
    j = i + 1
    d = 0
    items = []
    cur = []
    for k in range(j, e):
        t = toks[k]
        if t.kind == "punct" and t.text in "([{":
            d += 1
        elif t.kind == "punct" and t.text in ")]}":
            d -= 1
        if d == 0 and t.kind == "punct" and t.text == ",":
            items.append(cur)
            cur = []
        else:
            cur.append(t)
    items.append(cur)
    for it in items:
        if not it:
            continue
        name = it[0].text
        text = "const " + re.sub(r"\s+", " ", src[it[0].start:it[-1].end]) + ";"
        emit_constant(name, text, doc, ns, ext, base, state)


def add_define(g, i, e, doc, ext, base, state):
    toks, src = g.toks, g.src
    # define('NAME', value);
    lp = i + 1
    rp = match_close(toks, lp, "(", ")")
    name_t = toks[lp + 1]
    if name_t.kind != "str":
        return
    name = name_t.text[1:-1]
    comma = lp + 2
    val = src[toks[comma + 1].start:toks[rp - 1].end] if comma + 1 < rp else "null"
    emit_constant(name, "const %s = %s;" % (name, re.sub(r"\s+", " ", val)), doc, "", ext, base, state)


def emit_constant(name, text, doc, ns, ext, base, state):
    key = ((ns + "\\") if ns else "") + name
    if key in state["constants"]:
        return
    path = "constants/%s_%s.php" % (ext, state["base"])
    buf = state["cbuf"].setdefault(path, "<?php\n")
    docs = clean_doc(doc[2], "", None) if doc else ""
    chunk = "\n" + (docs + "\n" if docs else "")
    base_off = u16(buf + chunk)
    namepos = text.index(name)
    state["constants"][key] = (key, path, base_off + u16(text[:namepos]), base_off, ext)
    state["cbuf"][path] = buf + chunk + text + "\n"


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    srcdir, outdir = sys.argv[1], sys.argv[2]
    commit = subprocess.run(["git", "-C", srcdir, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip() or "unknown"
    state = {"classes": {}, "functions": {}, "constants": {}, "files": {}, "fbuf": {}, "cbuf": {}, "base": ""}
    for ext in EXTENSIONS:
        d = os.path.join(srcdir, ext)
        if not os.path.isdir(d):
            print("missing extension dir", ext, file=sys.stderr)
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.endswith(".php"):
                continue
            state["base"] = os.path.splitext(fn)[0]
            try:
                parse_file(os.path.join(d, fn), ext.lower(), state)
            except Exception as ex:   # noqa
                print("FAILED", ext, fn, ex, file=sys.stderr)
                raise
    # case-insensitive file collisions
    seen = {}
    for p in list(state["files"]):
        if p.lower() in seen:
            raise SystemExit("file name collision: " + p)
        seen[p.lower()] = p
    if os.path.isdir(outdir):
        shutil.rmtree(outdir)
    for sub in ("classes", "functions", "constants"):
        os.makedirs(os.path.join(outdir, sub))
    allfiles = dict(state["files"])
    allfiles.update(state["fbuf"])
    allfiles.update(state["cbuf"])
    for p, text in allfiles.items():
        with open(os.path.join(outdir, p), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    lines = []
    for key, (fqn, path, nl, ds, kind, ext) in state["classes"].items():
        lines.append("c\t%s\t%s\t%s\t%d\t%d\t%s" % (key, fqn, path, nl, ds, kind))
    for key, (fqn, path, nl, ds, ext) in state["functions"].items():
        lines.append("f\t%s\t%s\t%s\t%d\t%d\t%s" % (key, fqn, path, nl, ds, ext))
    for key, (name, path, nl, ds, ext) in state["constants"].items():
        lines.append("k\t%s\t%s\t%s\t%d\t%d\t%s" % (name, name, path, nl, ds, ext))   # constants are case sensitive
    lines.sort()
    with open(os.path.join(outdir, "index.txt"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    shutil.copy(os.path.join(srcdir, "LICENSE"), os.path.join(outdir, "LICENSE"))
    with open(os.path.join(outdir, "SOURCE.txt"), "w") as f:
        f.write(
            "PHP built-in stubs for Kode's native PHP engine.\n\n"
            "Derived from JetBrains phpstorm-stubs (https://github.com/JetBrains/phpstorm-stubs), commit %s,\n"
            "licensed under the Apache License 2.0 (see LICENSE in this directory). Copyright JetBrains s.r.o. and contributors.\n\n"
            "Modifications made by scripts/make-php-stubs.py (changed files are therefore NOT the upstream files):\n"
            "  * only a subset of extensions is kept; every class / interface / trait / enum is split into its own file,\n"
            "    functions and constants are grouped per upstream file;\n"
            "  * JetBrains attributes are resolved for PHP %d.%d (elements not available there are removed, LanguageLevelTypeAware\n"
            "    becomes a plain type) and removed; function bodies are emptied; PHPDoc is shortened and stripped of HTML and links;\n"
            "  * index.txt is generated.\n" % (commit, TARGET[0], TARGET[1])
        )
    print("classes %d functions %d constants %d files %d" % (len(state["classes"]), len(state["functions"]), len(state["constants"]), len(allfiles)))


if __name__ == "__main__":
    main()
