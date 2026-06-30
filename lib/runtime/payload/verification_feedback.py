"""Verification gap feedback loop (maturity feedback-loop, outcome 4).

Append-only event sinks record verification gaps found in the field:
  * project-local: <repo>/.superpowers/verify/feedback-events.jsonl
  * global:        ~/.claude/governance/verification-feedback/events.jsonl
Each gap has a severity P0|P1|P2|P3. An UNRESOLVED gap of ANY of those severities BLOCKS
production signoff — blocked is not done. The sinks are append-only (status changes are new
events, not edits), so the history is auditable and the latest status per gap_id wins.
House-cleaning aggregates/calibrates these (see docs/superpowers/plans/...maturity-feedback-loop.md);
this module is the pure data contract + the signoff predicate.
"""
from __future__ import annotations

import json
import os

SEVERITIES = ("P0", "P1", "P2", "P3")
SCHEMA_VERSION = "1.0"


def make_event(*, gap_id, severity, cap_id, status, ts, detail="", source=""):
    if severity not in SEVERITIES:
        raise ValueError(f"severity must be one of {SEVERITIES}, got {severity!r}")
    if status not in ("open", "ack", "resolved", "wontfix"):
        raise ValueError(f"status must be open|ack|resolved|wontfix, got {status!r}")
    return {"schema_version": SCHEMA_VERSION, "gap_id": gap_id, "severity": severity,
            "cap_id": cap_id, "status": status, "ts": ts, "detail": detail, "source": source}


def append_event(path, event):
    """Append one event as a JSON line (append-only; never rewrites prior events)."""
    p = os.fspath(path)
    os.makedirs(os.path.dirname(p) or ".", exist_ok=True)
    with open(p, "a", encoding="utf-8") as f:
        f.write(json.dumps(event, ensure_ascii=False) + "\n")


def load_events(path):
    p = os.fspath(path)
    if not os.path.exists(p):
        return []
    out = []
    with open(p, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def _latest_by_gap(events):
    """Latest event per gap_id (by ts, then file order)."""
    latest = {}
    for i, e in enumerate(events):
        gid = e.get("gap_id")
        key = (e.get("ts", 0), i)
        if gid not in latest or key > latest[gid][0]:
            latest[gid] = (key, e)
    return {gid: e for gid, (_, e) in latest.items()}


def unresolved_gaps(events):
    """gap_ids whose latest status is not resolved/wontfix."""
    return sorted(gid for gid, e in _latest_by_gap(events).items()
                  if e.get("status") not in ("resolved", "wontfix"))


def blocks_signoff(events):
    """gap_ids that BLOCK production signoff: latest status unresolved AND severity in P0..P3.
    Non-empty => signoff is BLOCKED (blocked is not done)."""
    latest = _latest_by_gap(events)
    return sorted(gid for gid, e in latest.items()
                  if e.get("status") not in ("resolved", "wontfix")
                  and e.get("severity") in SEVERITIES)
