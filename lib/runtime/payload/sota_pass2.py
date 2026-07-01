"""SOTA pass-2 verification (2026-07-01 recurrence-fix audit).

Real incident this closes: an agent skipped brainstorming's step 7-8 (PASS 2 SOTA —
re-search prior art for the NEW/changed capabilities after the revised design) and
instead silently REUSED an older spec's existing SOTA references. The spec looked
complete (a Prior-art section existed) but no one had actually searched for how
Gmail/Notion/Todoist etc. handle the NEW capability. Progress-line/format checks
cannot catch this — only checking that each Cap-ID has a genuine, non-reused source
citation (or an explicit N/A reason) can.

Canonical artifact: `.superpowers/spec/sota-pass2.json` = a list of
`{cap_id, sources: [{name, url, verdict}], sota_na_reason}`. Every registry Cap-ID
must have a record with >=1 real source (non-empty name AND url, not flagged
reused_from_prior_spec) OR a non-empty sota_na_reason.
"""
from __future__ import annotations


def _real_source(s):
    return bool(str(s.get("name") or "").strip()) and bool(str(s.get("url") or "").strip())


def validate_sota_pass2(registry, records):
    """Return a list of defect strings; [] means every Cap-ID has genuine SOTA
    coverage (or an explicit, non-empty N/A reason)."""
    defects = []
    by_cap = {r.get("cap_id"): r for r in (records or [])}
    for cap in registry or []:
        cid = cap.get("cap_id", "?")
        rec = by_cap.get(cid)
        if rec is None:
            defects.append(f"{cid}: no SOTA pass-2 record — real prior-art search was never done for this capability")
            continue
        na_reason = str(rec.get("sota_na_reason") or "").strip()
        sources = rec.get("sources") or []
        reused = [s for s in sources if s.get("reused_from_prior_spec")]
        if reused:
            defects.append(f"{cid}: SOTA source(s) marked reused_from_prior_spec — an OLD spec's citation "
                           "was reused instead of actually searching prior art for this capability")
            continue
        real = [s for s in sources if _real_source(s)]
        if not real and not na_reason:
            defects.append(f"{cid}: no real SOTA source (name+url) and no sota_na_reason — "
                           "prior art was never actually searched")
    return defects
