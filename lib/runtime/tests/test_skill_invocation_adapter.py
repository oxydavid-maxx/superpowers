import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent / "payload"))

from skill_invocation_adapter import invocation_contract, validate_skill_invocation_guidance


def test_codex_contract_does_not_mention_skill_callable():
    contract = invocation_contract("codex")
    assert "Skill(" not in contract["guidance"]
    assert "Skill()" not in contract["guidance"]


def test_codex_contract_mentions_skill_md():
    contract = invocation_contract("codex")
    assert "SKILL.md" in contract["guidance"]


def test_codex_contract_may_not_use_callable():
    contract = invocation_contract("codex")
    assert contract["may_use_skill_callable"] is False


def test_validate_codex_guidance_with_skill_callable_fails():
    defects = validate_skill_invocation_guidance("codex", "...use the Skill() callable...")
    assert defects
    assert any("Skill(" in d for d in defects)


def test_validate_codex_guidance_with_skill_md_passes():
    defects = validate_skill_invocation_guidance("codex", "...read the active SKILL.md...")
    assert defects == []


def test_claude_contract_may_use_callable():
    contract = invocation_contract("claude")
    assert contract["may_use_skill_callable"] is True
    assert "Skill" in contract["guidance"]


def test_claude_guidance_with_skill_callable_passes():
    defects = validate_skill_invocation_guidance("claude", "Use the Skill() tool to invoke skills.")
    assert defects == []


def test_unknown_runtime_does_not_permit_callable():
    contract = invocation_contract("unknown")
    assert contract["may_use_skill_callable"] is False


def test_unknown_runtime_guidance_is_agnostic():
    contract = invocation_contract("unknown")
    assert "Skill(" not in contract["guidance"]
    assert "do not assume" in contract["guidance"]


def test_codex_contract_is_not_reused_for_claude():
    codex = invocation_contract("codex")
    claude = invocation_contract("claude")
    assert codex["guidance"] != claude["guidance"]


def test_case_insensitive_runtime_lookup():
    assert invocation_contract("Codex")["runtime"] == "codex"
    assert invocation_contract("CLAUDE")["runtime"] == "claude"
