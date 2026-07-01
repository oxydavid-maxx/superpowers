"""Issue coverage gate validator.
Enforces that every user-raised issue has durable, complete elicitation before Spec Draft.
Pure functions; no I/O.
"""
from __future__ import annotations

ELICITATION_DIMENSIONS = [
    "answer_status",
    "background_status",
    "need_status",
    "intent_status",
    "implicit_context_status",
]

ALLOWED_RESOLVED_STATUSES = frozenset(
    ["resolved", "repo_evidence", "prior_approved_spec", "deferred_with_user_approval"]
)

BLOCKING_STATUSES = frozenset(["needs_user"])


def validate_issue_coverage(
    issue_coverage: dict | list,
    clarification_log: dict | list | None = None,
) -> list[str]:
    """Return defect strings ([] = clean).

    issue_coverage: list of issue dicts, or a dict with an 'issues' key.
    clarification_log: list of log entries, or a dict with an 'entries' key.
    """
    defects: list[str] = []

    issues = _to_list(issue_coverage, "issues")
    log_entries = _to_list(clarification_log or [], "entries")
    logged_question_ids: set[str] = {
        str(e["question_id"]) for e in log_entries if "question_id" in e
    }

    for issue in issues:
        issue_id = issue.get("issue_id", "<unknown>")

        # source_turn_id is required
        if not issue.get("source_turn_id"):
            defects.append(f"issue {issue_id}: missing source_turn_id")

        decision_status = issue.get("decision_status", "")

        # deferred_with_user_approval requires evidence
        if decision_status == "deferred_with_user_approval":
            if not issue.get("deferral_evidence"):
                defects.append(
                    f"issue {issue_id}: deferred_with_user_approval requires deferral_evidence"
                )
            continue  # dimensions not required for explicitly-approved deferrals

        # every dimension must be in an allowed resolved state
        for dim in ELICITATION_DIMENSIONS:
            dim_status = issue.get(dim, "")
            if dim_status in BLOCKING_STATUSES:
                defects.append(
                    f"issue {issue_id}: dimension {dim} is '{dim_status}' — blocks Spec Draft"
                )
            elif dim_status and dim_status not in ALLOWED_RESOLVED_STATUSES:
                defects.append(
                    f"issue {issue_id}: dimension {dim} has unrecognised status '{dim_status}'"
                )

        # resolved items must have clarification-log entries for all referenced question_ids
        if decision_status == "resolved":
            for qid in issue.get("question_ids", []):
                if str(qid) not in logged_question_ids:
                    defects.append(
                        f"issue {issue_id}: question_id {qid} resolved but missing"
                        f" from clarification-log.json"
                    )

    return defects


def _to_list(value: dict | list | None, key: str) -> list:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, dict):
        return value.get(key, [])
    return []
