"""Capability discovery (Task 4 of the generative spec-authoring guide): FIND capabilities
BEFORE scaffolding them, so the undeclared-capability ceiling is reduced (not eliminated).

A fixed question sweep across dimensions, plus a durable, auditable `capability-discovery.json`
record (NOT chat memory). Integrity guarantees so nothing is silently lost:
  - every REJECTED candidate must carry a `reason` (a dropped capability is visible);
  - a `registry_link` may only reference an ACCEPTED candidate (no linking a dropped/unknown
    cap to a registry entry);
  - `unlinked_accepted(record)` surfaces accepted candidates not yet linked to a registry
    entry (F4 completeness — discovery -> scaffold -> registry must be traceable end-to-end).

HONEST CEILING: this reduces the chance a capability is never identified; it cannot conjure a
capability the author never thinks of. The claim ceiling stays 'complete relative to the
declared spec'.
"""

_DIMENSIONS = [
    ("surface", "What surfaces does the user touch (UI pages, CLI commands, APIs, libraries)?"),
    ("user_role", "Which user roles act, and what can each do (incl. admin / owner-only)?"),
    ("data_mutation", "What does the user create / edit / delete / move? Any money?"),
    ("lifecycle", "What state persists, and how is it confirmed after reload? Any migrations?"),
    ("failure", "What can go wrong, and what does the user see when it does?"),
    ("deployment", "Where does this run, and how is the deployed artifact verified?"),
]


def discovery_questions():
    """The fixed question sweep — one entry per discovery dimension."""
    return [{"dimension": d, "question": q} for d, q in _DIMENSIONS]


def build_discovery_record(*, answers, decisions, registry_links):
    """Assemble + validate the capability-discovery.json record.

    decisions: [{cap_id, accepted: bool, reason?: str}]  — a rejected decision MUST carry a
      non-empty reason (so a silently-dropped capability is visible).
    registry_links: [{cap_id, registry_entry}] — may only reference ACCEPTED cap_ids.
    Raises ValueError on either integrity violation.
    """
    accepted = {d.get("cap_id") for d in decisions if d.get("accepted")}
    for d in decisions:
        if not d.get("accepted") and not d.get("reason"):
            raise ValueError(f"rejected candidate {d.get('cap_id')!r} must carry a reason")
    for link in registry_links:
        if link.get("cap_id") not in accepted:
            raise ValueError(
                f"registry_link references {link.get('cap_id')!r} which is not an accepted candidate")
    return {
        "questions_asked": [q["question"] for q in discovery_questions()],
        "answers": answers,
        "candidate_cap_ids": [d.get("cap_id") for d in decisions],
        "decisions": decisions,
        "registry_links": registry_links,
    }


def unlinked_accepted(record):
    """F4 completeness check: accepted cap_ids that have NO registry_link yet (sorted).
    Empty => every accepted capability is traceable to a registry entry."""
    accepted = [d.get("cap_id") for d in record.get("decisions", []) if d.get("accepted")]
    linked = {link.get("cap_id") for link in record.get("registry_links", [])}
    return sorted(c for c in accepted if c not in linked)
