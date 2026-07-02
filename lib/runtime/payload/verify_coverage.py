"""Deterministic verification-arm coverage gate.

The denominator is the spec's Capability Registry, NOT what was checked:
"I verified the parts I built" cannot pass. See spec sections 9 and 17.1.
"""
from __future__ import annotations

MATCH = "MATCHES"


def evaluate_coverage(registry, verdicts, *, now, max_age_s=3600):
    """Denominator discipline with an out-of-scope contract (N/A drift fix,
    SUPERPOWER-FEEDBACK 2026-06-30; implemented 2026-07-03, 光佑-authorized):
    a registry cap explicitly declared out of scope (out_of_scope / scope
    starting with "out_of_scope" + expected_verdict) is satisfied by an HONEST
    matching N/A row (verdict == expected_verdict, carrying a reason/evidence)
    — never forced into a false MATCHES; a missing/drifting/unexplained row is
    an out_of_scope_violation."""
    by_id = {r["cap_id"]: r for r in verdicts.get("results", [])}
    uncovered, non_matches, stale = [], [], []
    oos_violations, oos_detail, na_ok = [], {}, []
    for cap_row in registry.get("capabilities", []):
        cap = cap_row["cap_id"]
        declared_oos = (cap_row.get("out_of_scope")
                        or str(cap_row.get("scope", "")).startswith("out_of_scope")
                        or bool(cap_row.get("expected_verdict")))
        r = by_id.get(cap)
        if declared_oos:
            expected = cap_row.get("expected_verdict") or "N/A_NOT_IMPLEMENTED"
            if r is None:
                oos_violations.append(cap)
                oos_detail[cap] = "declared out-of-scope but no honest N/A row present"
            elif r.get("verdict") != expected:
                oos_violations.append(cap)
                oos_detail[cap] = f"expected {expected}, got {r.get('verdict')}"
            elif not (r.get("reason") or r.get("evidence")):
                oos_violations.append(cap)
                oos_detail[cap] = "N/A row lacks a reason"
            else:
                na_ok.append(cap)   # honest N/A: satisfied, not a non_match
            continue
        if r is None:
            uncovered.append(cap)
            continue
        if r.get("verdict") != MATCH:
            non_matches.append(cap)
            continue
        if (now - float(r.get("evidence_ts", 0))) > max_age_s:
            stale.append(cap)
            continue
    complete = not (uncovered or non_matches or stale or oos_violations)
    return {"complete": complete, "uncovered": uncovered,
            "non_matches": non_matches, "stale": stale, "na_ok": na_ok,
            "out_of_scope_violations": oos_violations,
            "out_of_scope_detail": oos_detail}


def category_coverage(required, present):
    """required/present: {cap_id: set(categories)}. Returns {cap_id: [missing...]}
    for any Cap-ID missing a required test-design category. Empty dict = covered."""
    gaps = {}
    for cap, reqs in required.items():
        miss = sorted(set(reqs) - set(present.get(cap, set())))
        if miss:
            gaps[cap] = miss
    return gaps


def head_sha_ok(verdicts, *, current_sha):
    """SOTA #2: a verdict set is only valid for the commit it was produced
    against. Missing or mismatched head_sha -> stale (treated as no coverage)."""
    return bool(verdicts.get("head_sha")) and verdicts["head_sha"] == current_sha


def backward_drift(registry, verdicts):
    """RTM backward traceability: a verdict whose cap_id is not in the registry
    is scope drift (something verified that was never designed)."""
    reg_ids = {c["cap_id"] for c in registry.get("capabilities", [])}
    return [r["cap_id"] for r in verdicts.get("results", []) if r.get("cap_id") not in reg_ids]


def reconcile_baseline(new_registry, baseline_registry, *, signed_off):
    """Spec 17.1: any baseline capability absent from the new registry is a
    silent OMISSION across a redesign -> surface as DROPPED, requiring an
    explicit per-Cap-ID sign-off. Absence is harder to review than a wrong value."""
    new_ids = {c["cap_id"] for c in new_registry.get("capabilities", [])}
    base_ids = [c["cap_id"] for c in baseline_registry.get("capabilities", [])]
    dropped = [c for c in base_ids if c not in new_ids]
    unsigned = [c for c in dropped if c not in (signed_off or set())]
    return {"dropped": dropped, "unsigned": unsigned, "ok": not unsigned}


if __name__ == "__main__":
    import json
    import sys
    import time
    reg = json.load(open(sys.argv[1], encoding="utf-8"))
    vd = json.load(open(sys.argv[2], encoding="utf-8"))
    out = evaluate_coverage(reg, vd, now=time.time())
    print(json.dumps(out, ensure_ascii=False, indent=2))
    sys.exit(0 if out["complete"] else 1)
