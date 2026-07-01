"""Superpower FSM state contract and compact progress formatter.
Runtime-neutral decision core — no I/O, no project-local state.
"""
from __future__ import annotations
from dataclasses import dataclass

@dataclass(frozen=True)
class Stage:
    gate: str
    skill: str

STAGES = [
    Stage("S0_DISCUSS", "superpowers:brainstorming"),
    Stage("S1_SPEC_DRAFT", "superpowers:brainstorming"),
    Stage("S1_EXPECTED_MOCK_V1", "superpowers:brainstorming"),
    Stage("S1_SOTA", "superpowers:brainstorming+WebSearch"),
    Stage("S1_REVISE_DISCUSS", "superpowers:brainstorming"),
    Stage("S1_SPEC_FINAL", "superpowers:brainstorming"),
    Stage("S1_EXPECTED_MOCK_V2", "superpowers:brainstorming"),
    Stage("S2_VERIFICATION_PLAN", "superpowers:writing-verification-plans"),
    Stage("S3_IMPLEMENTATION_PLAN", "superpowers:writing-plans"),
    Stage("S4_BUILD", "superpowers:executing-plans"),
    Stage("S5_VERIFY_ARCH", "superpowers:verify-arch, if multi-entry"),
    Stage("S5_VERIFY_SPEC", "superpowers:verify-spec"),
    Stage("S5_FIX_LOOP", "superpowers:systematic-debugging, if failed"),
    Stage("S6_RELEASE", "superpowers:verification-before-completion"),
]

_GATE_INDEX: dict[str, int] = {s.gate: i for i, s in enumerate(STAGES)}

_FORBIDDEN_JOB_PREFIXES = (
    "docs/superpowers/specs/",
    "docs/superpowers/plans/",
    ".superpowers/verify/",
    ".superpowers/orch/release",
)


def _validate_builder_session(session: object) -> list[str]:
    defects: list[str] = []
    if not isinstance(session, dict):
        return ["builder job requires user-specified Claude web session"]

    if session.get("type") != "claude_web":
        defects.append("builder_session.type must be claude_web")
    if not session.get("session_name"):
        defects.append("builder_session.session_name is required")
    if session.get("user_specified") is not True:
        defects.append("builder_session.user_specified must be true")
    if session.get("handoff_channel") != "chrome":
        defects.append("builder_session.handoff_channel must be chrome")
    if session.get("fallback_allowed") is True:
        defects.append("builder_session.fallback_allowed must not be true")
    return defects


def _index(gate: str) -> int:
    try:
        return _GATE_INDEX[gate]
    except KeyError:
        raise ValueError(f"unknown Superpower gate: {gate}")


def _fmt(stage: Stage, owner: str | None = None) -> str:
    suffix = f" @{owner}" if owner else ""
    return f"{stage.gate}({stage.skill}{suffix})"


def remaining_flow(current_gate: str, *, owner_by_gate: dict[str, str] | None = None) -> list[str]:
    owners = owner_by_gate or {}
    idx = _index(current_gate)
    return [_fmt(stage, owners.get(stage.gate)) for stage in STAGES[idx + 1:]]


def compact_progress(
    current_gate: str,
    skill: str,
    *,
    owner: str | None = None,
    owner_by_gate: dict[str, str] | None = None,
) -> str:
    now_owner = f" @{owner}" if owner else ""
    now = f"{current_gate}({skill}{now_owner})"
    rest = " > ".join(remaining_flow(current_gate, owner_by_gate=owner_by_gate))
    tail = rest if rest else "done"
    return f"Superpower: now={now}; next={tail}"


def validate_owner_boundary(gate: str, owner: str | None) -> list[str]:
    if not owner:
        return []
    if owner.startswith("Claude:") or owner.startswith("builder:"):
        if gate != "S4_BUILD":
            return [f"external builder may own only S4_BUILD, got {gate}"]
    return []


def validate_gate_prerequisites(target_gate: str, artifacts: dict) -> list[str]:
    defects: list[str] = []
    if target_gate == "S3_IMPLEMENTATION_PLAN":
        if not (artifacts.get("verification_plan") and artifacts.get("test_design")):
            defects.append(
                "S3_IMPLEMENTATION_PLAN requires verification_plan and test_design artifacts"
            )
    if target_gate == "S4_BUILD":
        if not artifacts.get("implementation_plan_approved"):
            defects.append("S4_BUILD requires approved implementation plan")
        if not artifacts.get("test_design_clean"):
            defects.append("S4_BUILD requires locked/clean S2 test-design artifacts")
    return defects


def validate_builder_job(job: dict) -> list[str]:
    defects: list[str] = []
    if job.get("stage") != "S4_BUILD":
        defects.append("builder job stage must be S4_BUILD")
    if job.get("stage") == "S4_BUILD":
        defects.extend(_validate_builder_session(job.get("builder_session")))
    for path in job.get("touched_paths", []):
        normalised = str(path).replace("\\", "/")
        if any(normalised.startswith(p) for p in _FORBIDDEN_JOB_PREFIXES):
            defects.append(
                "builder job cannot touch orchestration/spec/verification/release paths"
            )
            break
    return defects
