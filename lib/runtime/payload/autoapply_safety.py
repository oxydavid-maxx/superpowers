"""Auto-apply safety predicate for low-risk lint changes (maturity feedback-loop, outcome 5).

A lint/calibration change may be AUTO-APPLIED (no human inbox) ONLY when it is, all at once:
deterministic, regression-backed, rollback-safe, house-cleaning-controlled, AND risk == "low".
This mirrors the operating-tiers IRON RULE (auto-fix requires a verified, reversible, verifiable
change). Anything short of all five conditions must NOT auto-apply — it routes to draft/inbox.
"""
from __future__ import annotations

_REQUIRED_FLAGS = ("deterministic", "regression_backed", "rollback_safe", "house_cleaning_controlled")


def is_auto_applicable(change):
    """Return (ok, reasons). ok is True only if every safety flag is truthy AND risk == 'low'.
    `change` keys: deterministic, regression_backed, rollback_safe, house_cleaning_controlled (bool),
    risk ('low'|...)."""
    reasons = []
    for flag in _REQUIRED_FLAGS:
        if not change.get(flag):
            reasons.append(f"not {flag}")
    if change.get("risk") != "low":
        reasons.append(f"risk!=low (got {change.get('risk')!r})")
    return (not reasons, reasons)
