"""SYS.1 stakeholder-elicitation gate (maturity feedback-loop, outcome 1).

Before a Spec Draft is allowed, the author must have produced three elicitation artifacts —
stakeholder-needs.json, material-unknowns.json, decision-log.md — with ZERO unresolved
material unknowns, and every stakeholder Need-ID must trace forward to a Capability Registry
Cap-ID (so no elicited need is silently dropped before design). This is the upstream analogue
of the prose<->registry / coverage gates: an explicit, acknowledged, traceable record, not
'I think I understand'. Pure/deterministic — consumed by the brainstorming skill + contracts.
"""
from __future__ import annotations


def validate(*, stakeholder_needs, material_unknowns, decision_log_text, registry):
    """Return {"ok": bool, "errors": [str]}.

    stakeholder_needs: [{"need_id": str, ...}]
    material_unknowns: [{"id": str, "status": "open"|"resolved", ...}]
    decision_log_text: contents of decision-log.md
    registry:          {"capabilities": [{"cap_id": str, "need_ids": [str], ...}]}
    """
    errors = []
    if not stakeholder_needs:
        errors.append("stakeholder-needs.json is empty/missing (SYS.1 elicitation required before Spec Draft)")
    if not (decision_log_text or "").strip():
        errors.append("decision-log.md is empty/missing")

    unresolved = [u.get("id") for u in (material_unknowns or []) if u.get("status") != "resolved"]
    if unresolved:
        errors.append(f"unresolved material unknowns block Spec Draft: {unresolved}")

    need_ids = {n.get("need_id") for n in (stakeholder_needs or []) if n.get("need_id")}
    traced = set()
    for c in registry.get("capabilities", []):
        traced |= set(c.get("need_ids", []) or [])
    untraced = sorted(n for n in need_ids if n not in traced)
    if untraced:
        errors.append(f"Need IDs not traced to any Capability Registry Cap-ID: {untraced}")

    return {"ok": not errors, "errors": errors}
