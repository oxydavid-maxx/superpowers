#!/usr/bin/env python3
"""Non-interactive visual mock generator (superpowers pipeline step).

Input : a spec markdown (with a Capability Registry table) OR a registry JSON.
Output: a static HTML site to <outdir> -- index.html (clickable surface list) +
        one page per entry point, each capability shown as a wireframe mock card.
Purpose: SEE the rough shape of the assembled product before building it. NOT
interactive. Surface-aware frames (UI / CLI / API / library).

Usage: py -3 mock_visual.py <spec.md|registry.json> <outdir> [--title TITLE]
"""
from __future__ import annotations
import html, json, re, sys
from pathlib import Path


def parse_md_registry(md: str):
    rows, lines, i = [], md.splitlines(), 0
    while i < len(lines):
        ln = lines[i].strip()
        if ln.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s:|\-]+\|$", lines[i + 1].strip()):
            header = [c.strip() for c in ln.strip("|").split("|")]
            hl = [h.lower() for h in header]
            if any("cap" in h and "id" in h for h in hl) and any("entry" in h for h in hl):
                j = i + 2
                while j < len(lines) and lines[j].strip().startswith("|"):
                    cells = [c.strip() for c in lines[j].strip().strip("|").split("|")]
                    if len(cells) == len(header):
                        rows.append({hl[k]: cells[k] for k in range(len(header))})
                    j += 1
                i = j
                continue
        i += 1
    return rows


def _g(row, *subs):
    for k, v in row.items():
        if any(s in k for s in subs):
            return v
    return ""


def normalize(rows):
    out = []
    for r in rows:
        et = (_g(r, "entry type", "entry_type", "entrytype") or "").strip().upper()
        ep = (_g(r, "entry point", "entry_point", "entrypoint") or _g(r, "entry") or "surface").strip()
        if not et:
            blob = (ep + " " + _g(r, "capabilit", "outcome")).lower()
            et = ("CLI" if any(w in blob for w in ["command", "cli", "`"]) else
                  "API" if any(w in blob for w in ["endpoint", "api", "/"]) else
                  "LIBRARY" if any(w in blob for w in ["function", "library", "import"]) else "UI")
        out.append({
            "cap_id": _g(r, "cap") or "CAP",
            "capability": _g(r, "capabilit", "outcome") or "(capability)",
            "entry_point": ep, "entry_type": et,
            "acceptance": _g(r, "acceptance", "example"),
            "reachable": _g(r, "reachable", "path"),
        })
    return out


def load(src: str):
    p = Path(src)
    txt = p.read_text(encoding="utf-8")
    if p.suffix == ".json":
        caps = json.loads(txt).get("capabilities", [])
        return normalize([{k: v for k, v in c.items()} for c in caps])
    return normalize(parse_md_registry(txt))


CSS = """
:root{--ink:#1f2328;--mut:#6b7280;--line:#d0d7de;--bg:#f6f8fa;--card:#fff;--accent:#3b5bdb}
*{box-sizing:border-box}body{margin:0;font:15px/1.5 -apple-system,Segoe UI,Roboto,sans-serif;color:var(--ink);background:var(--bg)}
.wrap{max-width:1040px;margin:0 auto;padding:28px 22px}
.badge{display:inline-block;background:#fff3cd;color:#7a5b00;border:1px solid #f0d98c;border-radius:999px;padding:3px 12px;font-size:12px;font-weight:600;letter-spacing:.3px}
h1{font-size:24px;margin:14px 0 4px}.sub{color:var(--mut);margin:0 0 22px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:14px}
a.surf{display:block;text-decoration:none;color:inherit;background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 18px;transition:.12s}
a.surf:hover{border-color:var(--accent);box-shadow:0 4px 14px rgba(59,91,219,.08);transform:translateY(-1px)}
.type{font-size:11px;font-weight:700;letter-spacing:.5px;color:var(--accent)}
.cnt{color:var(--mut);font-size:13px;margin-top:6px}
.back{color:var(--accent);text-decoration:none;font-size:14px}
.frame{margin-top:18px;border:1px solid var(--line);border-radius:12px;overflow:hidden;background:var(--card)}
.fbar{background:#eef1f4;border-bottom:1px solid var(--line);padding:8px 12px;font-size:12px;color:var(--mut);display:flex;gap:7px;align-items:center}
.dot{width:11px;height:11px;border-radius:50%;display:inline-block}
.fbody{padding:18px}
.term{background:#0d1117;color:#c9d1d9;font-family:ui-monospace,Menlo,Consolas,monospace;font-size:13px;white-space:pre-wrap}
.cap{border:1.5px dashed var(--line);border-radius:10px;padding:14px 16px;margin:12px 0;background:#fbfcfd}
.cap h3{margin:0 0 4px;font-size:15px}.cap .id{color:var(--mut);font-size:11px;font-weight:700}
.cap .ex{color:var(--mut);font-size:13px;margin-top:6px;border-left:3px solid var(--line);padding-left:10px}
.ph{height:46px;border-radius:8px;background:repeating-linear-gradient(45deg,#eef1f4,#eef1f4 9px,#e6eaef 9px,#e6eaef 18px);margin-top:10px}
.footer{color:var(--mut);font-size:12px;margin-top:30px;border-top:1px solid var(--line);padding-top:14px}
"""

FRAME = {
    "UI": ('<div class="fbar"><span class="dot" style="background:#ff5f56"></span>'
           '<span class="dot" style="background:#ffbd2e"></span>'
           '<span class="dot" style="background:#27c93f"></span>'
           '<span style="margin-left:8px">{ep}</span></div>'),
    "CLI": '<div class="fbar">terminal -- {ep}</div>',
    "API": '<div class="fbar">endpoint -- {ep}</div>',
    "LIBRARY": '<div class="fbar">library -- {ep}</div>',
}


def cap_html(c):
    e = html.escape
    if c["entry_type"] == "CLI":
        body = ('<div class="frame"><div class="fbody term">$ ' + e(c["entry_point"]) + "\n# "
                + e(c["capability"]) + "\n" + (e(c["acceptance"]) or "&lt;output&gt;") + "</div></div>")
    elif c["entry_type"] == "API":
        body = ('<div class="frame"><div class="fbody term">GET ' + e(c["entry_point"]) + "\n# "
                + e(c["capability"]) + "\n" + (e(c["acceptance"]) or "200 {...}") + "</div></div>")
    elif c["entry_type"] == "LIBRARY":
        body = ('<div class="frame"><div class="fbody term">' + e(c["entry_point"]) + "(...)  # "
                + e(c["capability"]) + "\n-> " + (e(c["acceptance"]) or "result") + "</div></div>")
    else:
        body = '<div class="ph"></div>'
    out = ('<div class="cap"><span class="id">' + e(c["cap_id"]) + " . " + e(c["entry_type"]) + "</span>"
           "<h3>" + e(c["capability"]) + "</h3>")
    if c["acceptance"]:
        out += '<div class="ex">[ok] ' + e(c["acceptance"]) + "</div>"
    if c["reachable"]:
        out += '<div class="ex" style="border-color:#cdd">path: ' + e(c["reachable"]) + "</div>"
    return out + body + "</div>"


def _page(body):
    return ("<!doctype html><meta charset=utf-8><style>" + CSS + "</style><div class=wrap>" + body
            + '<div class=footer>Non-interactive mock - generated from the Capability Registry - '
              'superpowers verification-arm pipeline</div></div>')


def build(caps, outdir: Path, title: str):
    outdir.mkdir(parents=True, exist_ok=True)
    surfaces = {}
    for c in caps:
        surfaces.setdefault((c["entry_point"], c["entry_type"]), []).append(c)
    ordered = list(surfaces.items())
    cards = ""
    for n, ((ep, et), cs) in enumerate(ordered):
        cards += ('<a class="surf" href="surface_' + str(n) + '.html"><div class="type">' + html.escape(et)
                  + '</div><div style="font-weight:600;margin-top:4px">' + html.escape(ep)
                  + '</div><div class="cnt">' + str(len(cs)) + " capabilit"
                  + ("y" if len(cs) == 1 else "ies") + "</div></a>")
    (outdir / "index.html").write_text(_page(
        '<span class=badge>NON-INTERACTIVE MOCK</span><h1>' + html.escape(title) + "</h1>"
        '<p class=sub>Rough visual of the designed surfaces -- click a surface to see its capabilities. '
        'Nothing here is wired up.</p><div class=grid>' + cards + "</div>"), encoding="utf-8")
    for n, ((ep, et), cs) in enumerate(ordered):
        frame_top = FRAME.get(et, FRAME["UI"]).format(ep=html.escape(ep))
        body = ('<a class=back href="index.html">&larr; all surfaces</a>'
                '<h1 style="margin-top:10px">' + html.escape(ep) + ' <span class=type>. '
                + html.escape(et) + "</span></h1>"
                '<div class=frame>' + frame_top + '<div class=fbody>'
                + "".join(cap_html(c) for c in cs) + "</div></div>")
        (outdir / ("surface_" + str(n) + ".html")).write_text(_page(body), encoding="utf-8")
    return outdir / "index.html"


def main(argv):
    src = argv[1]
    outdir = Path(argv[2])
    title = "Product mock"
    if "--title" in argv:
        title = argv[argv.index("--title") + 1]
    caps = load(src)
    if not caps:
        print("WARN: no Capability Registry found in", src, file=sys.stderr)
    idx = build(caps, outdir, title)
    print("MOCK_INDEX:", idx)
    print("SURFACES:", len({(c["entry_point"], c["entry_type"]) for c in caps}), "CAPS:", len(caps))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
