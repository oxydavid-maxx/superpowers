"""spec_quality_audit — block a spec from FINAL until each capability declares enough
to verify against. Pure functions, one per audit item; audit_spec aggregates into the
spec-audit.json shape. Mirrors lib/verify_lint.py.

CEILING: reduces but cannot eliminate spec gaps — a capability that exists only in the
author's head and is never written is unreachable by any lint. The audit makes the
DECLARED spec complete-enough; the claim ceiling stays "complete relative to the spec
it forced you to write." Audit items check field PRESENCE (deterministic, here) +
content-quality (vagueness-lint here, independent review for high-risk — separate)."""

import os as _os
import sys as _sys
_sys.path.insert(0, _os.path.expanduser("~/.claude/lib"))
from spec_required_fields import (applicable_rules, contract_satisfied,
                                   high_risk_tags, baseline_required_paths, baseline_paths_for)


def _get(cap, dotted):
    """Resolve a dotted path to its value (or None)."""
    cur = cap
    for k in dotted.split("."):
        if not isinstance(cur, dict):
            return None
        cur = cur.get(k)
    return cur


def _present(cap, dotted):
    """True iff the dotted path resolves to a truthy value."""
    return bool(_get(cap, dotted))


def baseline_presence_ok(cap):
    """Aggregate: every baseline 'required' path present. Used by the GAP-02 parity test;
    per-item audit functions enforce their own subset via baseline_paths_for."""
    return all(_present(cap, p) for p in baseline_required_paths())


def a4_state_data_contract(cap):
    """A4 (map-driven, DRY with the generative scaffold via spec_required_fields.RULES):
    a cap satisfies A4 iff every rule applicable to its tags is satisfied. The coverage
    invariant (every high_risk_tags() member is matched by a rule) is asserted by a parity
    test, so no high-risk cap can pass A4 with an empty contract."""
    tags = cap.get("type_tags", [])
    if not applicable_rules(tags):
        return "pass"
    return "pass" if contract_satisfied(tags, cap.get("state_data_contract")) else "fail"


def a2_oracle_complete(cap):
    """A2: acceptance has given/when/then (presence paths from the shared baseline) and
    `then` is an observable user-visible output, not a proxy (HTTP 200 / "works" / "looks ok")."""
    import re
    if not all(_present(cap, p) for p in baseline_paths_for("A2")):
        return "fail"
    then = str(_get(cap, "acceptance.then") or "").lower()
    proxy = [r"\bhttp\s*200\b", r"\b200\b", r"\blooks?\b", r"\bworks?\b", r"\bseems?\b", r"\bexists\b"]
    return "fail" if any(re.search(p, then) for p in proxy) else "pass"


_PLACEHOLDER = ("tbd", "todo", "tbc", "???", "fixme")


def a3_surface_complete(cap):
    """A3: entry_point + entry_type + reachable_path (presence paths from the shared baseline)
    all present AND not placeholders."""
    paths = baseline_paths_for("A3")
    if not all(_present(cap, p) for p in paths):
        return "fail"
    if any(str(_get(cap, p)).strip().lower() in _PLACEHOLDER for p in paths):
        return "fail"
    return "pass"


_DEFAULT_TAGS = {"ui", "cli_contract", "api_contract", "library_api", "batch_job", "scheduled",
                 "editable", "persists", "stateful", "schema_change", "destructive", "cache_sensitive",
                 "idempotent", "authz", "concurrent", "time_based", "money", "data_loss", "migration",
                 "external_io", "navigable", "deployed", "ai"}


def _known_tags():
    import os
    p = os.path.expanduser("~/.claude/lib/verification_archetypes.yaml")
    try:
        import yaml
        tax = (yaml.safe_load(open(p, encoding="utf-8")) or {}).get("type_taxonomy", {})
        tags = {t for dim in tax.values() for t in dim}
        return tags or _DEFAULT_TAGS
    except Exception:
        return _DEFAULT_TAGS


def a6_type_tags_required(cap):
    """A6: each Cap-ID carries ≥1 type_tag, all from the known taxonomy (§4a). Field path
    from the shared baseline."""
    tags = _get(cap, baseline_paths_for("A6")[0])
    if not tags:
        return "fail"
    return "pass" if set(tags) <= _known_tags() else "fail"


def a5_failure_modes(cap):
    """A5: ≥1 declared failure mode that actually DESCRIBES behaviour (≥3 words) —
    not a junk token like 'ok'. Field path from the shared baseline."""
    modes = _get(cap, baseline_paths_for("A5")[0]) or []
    return "pass" if any(len(str(m).split()) >= 3 for m in modes) else "fail"


def a7_gap_questions_resolved(cap):
    """A7: no open gap-question remains unanswered."""
    return "pass" if not cap.get("gap_questions") else "fail"


import re as _re

_UI_WORDS = (r"\bpage\b", r"\bscreen\b", r"\bbanner\b", r"\bbutton\b", r"\bvisible\b",
             r"\bdisplayed?\b", r"\brendered?\b", r"\bappears?\b", r"\bmodal\b", r"\bclick")
_CLI_WORDS = (r"\bstdout\b", r"\bstderr\b", r"\bexit code\b", r"\bprints?\b",
              r"\bconsole\b", r"\bterminal\b", r"`[^`]+`")


def a8_surface_consistency(cap):
    """A8: the acceptance `then` must describe an outcome on the cap's declared surface.
    ui -> a visible/rendered outcome; cli/cli_contract -> stdout/exit-code/printed output.
    Only ui and cli surfaces are scored (api/library outcomes vary too much to lint here)."""
    et = (cap.get("entry_type") or "").lower()
    then = ((cap.get("acceptance") or {}).get("then") or "").lower()
    if not then:
        return "fail"
    has_ui = any(_re.search(p, then) for p in _UI_WORDS)
    has_cli = any(_re.search(p, then) for p in _CLI_WORDS)
    if et == "ui":
        return "pass" if has_ui else "fail"          # CLI-only outcome on a ui cap -> fail
    if et in ("cli", "cli_contract"):
        return "pass" if has_cli else "fail"
    return "pass"


# A9: tag↔prose consistency. High-precision keyword families -> the high-risk tag they imply.
_RISK_PROSE = {
    "money": (r"\bbalance\b", r"\bpayment\b", r"\brefund", r"\binvoice", r"\bbilling\b",
              r"\bdeposit", r"\bwithdraw"),
    "authz": (r"\bauthoriz", r"\bunauthoriz", r"\bpermission", r"\bprivileg", r"\baccess control\b"),
    "destructive": (r"\bdelete", r"\bdestroy", r"\bwipe[sd]?\b", r"\berase", r"\bpurge",
                    r"\bdrop (table|database)\b"),
    "migration": (r"\bmigrat", r"\balter table\b"),
    "concurrent": (r"\brace condition\b", r"\bconcurren", r"\bsimultaneous"),
}
_FAMILY_TAGS = {"money": {"money"}, "authz": {"authz"},
                "destructive": {"destructive", "data_loss"},
                "migration": {"migration", "schema_change"}, "concurrent": {"concurrent"}}


def a9_tag_prose_consistency(cap):
    """A9 (round-5 Imp-2): if the acceptance/outcome prose describes a high-risk action but
    the matching high-risk type_tag is absent, the cap is UNDER-TAGGED -> fail. Without this,
    a money cap mis-tagged `ui` derives `standard`, A4 demands nothing, and it reaches
    final_ready (the exact thin-spec-passes the audit exists to kill). FLOOR-RAISING, not
    airtight: a high-precision keyword lint catches the accidental/obvious mis-tag (prose
    says 'new balance', no money tag), not an author who also scrubs the prose. Same ceiling
    as A2's proxy lint and A8's surface lint."""
    tags = set(cap.get("type_tags", []))
    a = cap.get("acceptance") or {}
    blob = " ".join(str(x) for x in (a.get("when"), a.get("then"), cap.get("user_outcome"))).lower()
    for family, pats in _RISK_PROSE.items():
        if any(_re.search(p, blob) for p in pats) and not (_FAMILY_TAGS[family] & tags):
            return "fail"
    return "pass"


# A1 (prose↔registry) needs the spec prose → deferred to the markdown-integration slice.
def _stub(cap):
    return "pass"


_ITEMS = {"A1": _stub, "A2": a2_oracle_complete, "A3": a3_surface_complete,
          "A4": a4_state_data_contract, "A5": a5_failure_modes,
          "A6": a6_type_tags_required, "A7": a7_gap_questions_resolved,
          "A8": a8_surface_consistency, "A9": a9_tag_prose_consistency}


_TIER_RANK = {"trivial": 0, "standard": 1, "high": 2}

_TIER_ITEMS = {"trivial": {"A1", "A2", "A6"},
               "standard": {"A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9"},
               "high": {"A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9"}}


def derive_risk_tier(registry, *, intent=None):
    """§15.0: risk_tier DERIVED from the registry, never trusted. 'high' if any cap carries a
    high-risk tag — high_risk_tags() is DERIVED from RULES (GAP-01; no inline _HIGH_RISK_TAGS
    literal) — else 'standard'. Empty registry is a DEFECT (P0-1/I-1) -> None unless
    intent='trivial-no-capability' -> 'trivial'."""
    if not registry:
        return "trivial" if intent == "trivial-no-capability" else None
    hot = high_risk_tags()
    for cap in registry:
        if set(cap.get("type_tags", [])) & hot:
            return "high"
    return "standard"


def _resolve_tier(derived, supplied):
    """Supplied tier may only ESCALATE (P1-5); unknown = ERROR not fallback (C-1).
    Returns (risk_tier, error)."""
    if supplied is None:
        return derived, None
    if supplied not in _TIER_RANK:
        return None, f"unknown tier {supplied!r} (valid: trivial/standard/high)"
    return (supplied if _TIER_RANK[supplied] > _TIER_RANK[derived] else derived), None


def audit_spec(registry, *, tier=None, review_verdict=None, intent=None):
    """AUTHORITY (§15.0). DERIVES risk_tier; final_ready RE-DERIVED from items every call.
    Empty registry / unknown tier / cap-less items are defects."""
    derived = derive_risk_tier(registry, intent=intent)
    if derived is None:
        return {"schema_version": "1.0", "risk_tier": None, "items": [],
                "independent_review": None, "final_ready": False,
                "error": "no capabilities declared (no registry and no intent:trivial-no-capability)"}
    risk_tier, err = _resolve_tier(derived, tier)
    if err:
        return {"schema_version": "1.0", "risk_tier": None, "items": [],
                "independent_review": None, "final_ready": False, "error": err}
    active = _TIER_ITEMS[risk_tier]
    items = []
    for cap in registry:
        for item_id, fn in _ITEMS.items():
            if item_id not in active:
                continue
            items.append({"id": item_id, "cap_id": cap.get("cap_id", "?"), "status": fn(cap)})
    if registry and not items:                       # I-1: caps but no items = contradiction
        return {"schema_version": "1.0", "risk_tier": risk_tier, "items": [],
                "independent_review": None, "final_ready": False,
                "error": "registry has capabilities but produced no audit items"}
    all_pass = all(i["status"] == "pass" for i in items)
    if risk_tier == "high":
        independent_review = {"required": True, "verdict": review_verdict}
        final_ready = all_pass and review_verdict == "pass"
    else:
        independent_review = None
        final_ready = all_pass
    return {"schema_version": "1.0", "risk_tier": risk_tier, "items": items,
            "independent_review": independent_review, "final_ready": final_ready}


def audit_spec_file(md_text, *, tier=None, review_verdict=None):
    """End-to-end: parse intent (frontmatter), extract the registry (intake lock), run the
    per-capability audit, add spec-level A1 (prose↔registry). final_ready requires A1 too."""
    import sys, os, re
    sys.path.insert(0, os.path.expanduser("~/.claude/lib"))
    from spec_registry import extract_registry, a1_capability_complete

    intent = reason = None
    fm = re.match(r"^---\s*\n(.*?)\n---\s*\n", md_text or "", re.DOTALL)
    if fm:
        block = fm.group(1)
        mi = re.search(r"^intent:\s*(\S+)\s*$", block, re.MULTILINE)   # anchored: reject trailing garbage
        mr = re.search(r"^reason:\s*(.+)$", block, re.MULTILINE)
        intent = mi.group(1).strip() if mi else None
        reason = mr.group(1).strip() if mr else None

    if intent == "trivial-no-capability" and not reason:
        return {"schema_version": "1.0", "risk_tier": None, "items": [],
                "independent_review": None, "final_ready": False,
                "error": "intent:trivial-no-capability requires a non-empty reason"}

    registry = extract_registry(md_text)
    result = audit_spec(registry, tier=tier, review_verdict=review_verdict, intent=intent)
    if intent == "trivial-no-capability" and reason:
        result["intent"] = intent
        result["reason"] = reason
    missing = a1_capability_complete(md_text, registry)
    a1_status = "fail" if missing else "pass"
    result["items"].insert(0, {"id": "A1", "cap_id": "*spec*", "status": a1_status,
                               "detail": ("prose caps missing from registry: " + ", ".join(missing)) if missing else ""})
    if a1_status == "fail":
        result["final_ready"] = False
    return result


if __name__ == "__main__":
    # CLI: audit a spec .md, emit the spec-audit.json record (risk_tier DERIVED unless escalated).
    #   py -3 spec_audit.py <spec.md> [tier] > .superpowers/spec/spec-audit.json
    # NOTE: the gate does NOT trust this record's verdict — it recomputes from the canonical
    # spec itself. This record is for humans + the spec_sha staleness signal.
    import sys, hashlib
    import json as _json
    md = open(sys.argv[1], encoding="utf-8").read()
    tier = sys.argv[2] if len(sys.argv) > 2 else None
    out = audit_spec_file(md, tier=tier)
    out["spec_path"] = sys.argv[1]
    out["spec_sha"] = hashlib.sha256(md.encode("utf-8")).hexdigest()
    print(_json.dumps(out, ensure_ascii=False, indent=2))
    sys.exit(0 if out["final_ready"] else 1)
