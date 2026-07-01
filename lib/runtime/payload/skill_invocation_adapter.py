"""Runtime-aware skill invocation adapter.
Codex must use filesystem-backed SKILL.md; Claude may use the Skill tool.
Pure functions; no I/O.
"""
from __future__ import annotations

_CONTRACTS: dict[str, dict] = {
    "claude": {
        "runtime": "claude",
        "guidance": (
            "Invoke the relevant skill via the `Skill` tool. "
            "When you invoke a skill, its content is loaded and presented to you — follow it directly."
        ),
        "may_use_skill_callable": True,
    },
    "codex": {
        "runtime": "codex",
        "guidance": (
            "Skills load natively in this environment; follow the active skill instructions. "
            "If the skill is file-backed, read the active SKILL.md as the activation equivalent. "
            "Use progressive disclosure: the model sees skill metadata first, "
            "then loads the full SKILL.md when using the skill."
        ),
        "may_use_skill_callable": False,
    },
    "unknown": {
        "runtime": "unknown",
        "guidance": (
            "Use this runtime's documented skill activation mechanism; "
            "do not assume Claude Code's `Skill` tool exists."
        ),
        "may_use_skill_callable": False,
    },
}

_CLAUDE_ONLY_PATTERN = "Skill("


def invocation_contract(runtime: str) -> dict:
    """Return the per-runtime skill invocation contract dict."""
    return _CONTRACTS.get(runtime.lower(), _CONTRACTS["unknown"])


def validate_skill_invocation_guidance(runtime: str, text: str) -> list[str]:
    """Return defect strings ([] = clean).

    For Codex: the guidance text must not mention or require the Claude-only Skill() callable.
    """
    defects: list[str] = []
    contract = invocation_contract(runtime)
    if not contract.get("may_use_skill_callable"):
        if _CLAUDE_ONLY_PATTERN in text:
            defects.append(
                f"runtime={runtime!r}: guidance text contains '{_CLAUDE_ONLY_PATTERN}'"
                " which is a Claude-only callable not available in this runtime"
            )
    return defects
