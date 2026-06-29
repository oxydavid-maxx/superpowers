"""g0 guard: an acceptance_example must be a concrete given/when/then (BDD /
Specification by Example). Returns a list of defect strings; empty = clean."""
import re

# word-boundary matched so "ok" does not fire inside "broker"/"token"/"lookup"
VAGUE = (r"works correctly", r"\bworks\b", r"is correct", r"functions properly", r"\bok\b")


def lint_example(text):
    t = (text or "").lower()
    defects = []
    for kw in ("given", "when", "then"):
        if kw not in t:
            defects.append(f"missing '{kw}' clause")
    has_gwt = all(k in t for k in ("given", "when", "then"))
    if not has_gwt and any(re.search(v, t) for v in VAGUE):
        defects.append("vague acceptance ('works correctly' is not observable)")
    return defects


def lint_registry_table(spec_text):
    """Scan a spec's Capability Registry markdown table and lint each row's
    acceptance_example cell. A registry row looks like `| CAP-xx | ... | <accept> |`.
    Returns a list of (cap_id, defects) for rows whose acceptance cell is not a
    concrete given/when/then. Empty list = clean (or no registry found)."""
    import re
    out = []
    for line in spec_text.splitlines():
        s = line.strip()
        if not s.startswith("|"):
            continue
        m = re.match(r"\|\s*(CAP-[\w-]+)\s*\|", s)
        if not m:
            continue
        cap_id = m.group(1)
        cells = [c.strip() for c in s.strip("|").split("|")]
        accept = cells[-1] if cells else ""
        defects = lint_example(accept)
        if defects:
            out.append((cap_id, defects))
    return out


if __name__ == "__main__":
    import sys
    bad = lint_example(" ".join(sys.argv[1:]))
    if bad:
        print("acceptance-lint DEFECTS: " + "; ".join(bad))
        sys.exit(1)
    print("acceptance-lint: ok")
    sys.exit(0)
