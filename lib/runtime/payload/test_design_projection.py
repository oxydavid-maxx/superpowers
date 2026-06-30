"""Deterministic projection of the verification test-design (maturity feedback-loop, outcomes 2+3).

`.superpowers/verify/test-design.json` is the SOURCE OF TRUTH; `.superpowers/verify/test-design.md`
is a DETERMINISTIC projection of it (a human checklist). project_md() is pure + stable-ordered,
so the .md can never silently drift from the JSON: parity_defects() flags a missing or
out-of-sync .md. The skill emits both; runtime/contracts assert parity.
"""
from __future__ import annotations

_HEADER = ("# Verification test-design checklist\n"
           "# (PROJECTION of test-design.json — the JSON is the source of truth; do not hand-edit this file)\n")


def project_md(td):
    """Render the canonical .md projection of a test-design JSON dict. Deterministic:
    capabilities sorted by cap_id, techniques sorted, fixed line shapes."""
    lines = [_HEADER.rstrip("\n")]
    caps = sorted(td.get("capabilities", []), key=lambda c: str(c.get("cap_id", "")))
    for c in caps:
        cid = c.get("cap_id", "?")
        then = ((c.get("acceptance") or {}).get("then") or "").strip()
        lines.append("")
        lines.append(f"## {cid}")
        lines.append(f"- acceptance.then: {then}")
        for tech in sorted(c.get("techniques", []) or []):
            lines.append(f"- [ ] technique: {tech}")
    return "\n".join(lines) + "\n"


def _normalize(text):
    # tolerate CRLF and trailing blank lines so parity is about content, not line-ending noise
    return "\n".join(line.rstrip() for line in (text or "").replace("\r\n", "\n").split("\n")).strip("\n")


def parity_defects(td, md_text):
    """Return [] iff md_text is the canonical projection of td. A missing/empty .md or any
    divergence is a defect (the .md must be regenerated from the JSON)."""
    if md_text is None or not str(md_text).strip():
        return ["test-design.md is missing/empty — it must be the projection of test-design.json"]
    if _normalize(md_text) != _normalize(project_md(td)):
        return ["test-design.md does not match the deterministic projection of test-design.json "
                "(regenerate it; the JSON is the source of truth)"]
    return []
