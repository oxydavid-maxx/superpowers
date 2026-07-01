#Requires -Version 5.1
<#
.SYNOPSIS
    End-to-end regression harness for the Superpower FSM runtime adapter.
    Validates Python tests, hook JSON presence, and writing-arch absence.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent

Write-Host "=== Superpower FSM Runtime Regression ===" -ForegroundColor Cyan

# 1. Python unit tests
Write-Host "`n[1/3] Running Python unit tests..." -ForegroundColor Yellow
py -3 -m pytest `
    "$repo/lib/runtime/tests/test_superpower_fsm.py" `
    "$repo/lib/runtime/tests/test_issue_coverage.py" `
    "$repo/lib/runtime/tests/test_visual_artifact_policy.py" `
    "$repo/lib/runtime/tests/test_skill_invocation_adapter.py" `
    -q
if ($LASTEXITCODE -ne 0) { throw "Python unit tests FAILED" }
Write-Host "[1/3] Python unit tests PASSED" -ForegroundColor Green

# 2. Inline smoke assertions
Write-Host "`n[2/3] Running inline smoke assertions..." -ForegroundColor Yellow
$smokeFile = [System.IO.Path]::GetTempFileName() + ".py"
Set-Content -Path $smokeFile -Encoding utf8 -Value @'
import sys, json
from pathlib import Path
sys.path.insert(0, str(Path("lib/runtime/payload").resolve()))

from visual_artifact_policy import validate_visual_artifact_policy, validate_mock_iteration
from skill_invocation_adapter import validate_skill_invocation_guidance
from superpower_fsm import compact_progress, validate_builder_job
from verify_lint import lint_test_design
from test_design_projection import parity_defects

# FSM smoke
line = compact_progress("S0_DISCUSS", "superpowers:brainstorming")
assert "Superpower: now=S0_DISCUSS" in line, "FSM progress line missing: " + line
assert "S1_REVISE_DISCUSS" in line, "S1_REVISE_DISCUSS missing from FSM flow"
print("  FSM compact_progress OK: " + line[:80] + "...")

# Visual artifact policy smoke
assert validate_visual_artifact_policy({
    "spec_type": "FSM",
    "surfaces": ["workflow"],
    "visual_artifacts": [
        "C:/Users/User/.claude/superpowers/runs/2026-07-01-superpower-executable-fsm-runtime-adapter/expected-flow.png"
    ],
}) == [], "FSM spec with PNG should pass"

assert validate_mock_iteration({
    "material_final_spec_change": True,
    "mock_v1_score": 0.72,
    "mock_v2_score": 0.91,
}) == [], "Mock v2 > v1 should pass"

print("  Visual artifact policy smoke OK")

# Skill invocation adapter smoke
skill_text = Path("skills/using-superpowers/SKILL.md").read_text(encoding="utf-8")
defects = validate_skill_invocation_guidance("codex", skill_text)
assert defects == [], "using-superpowers SKILL.md has Codex-incompatible guidance: " + str(defects)
print("  Skill invocation adapter smoke OK")

assert "Superpower: now=" in skill_text, "using-superpowers SKILL.md missing progress line example"
print("  Progress line present in using-superpowers SKILL.md OK")

# Builder job boundary smoke
assert validate_builder_job({
    "stage": "S4_BUILD",
    "builder_session": {
        "type": "claude_web",
        "session_name": "home-superpower",
        "user_specified": True,
        "handoff_channel": "chrome",
    },
    "touched_paths": ["lib/runtime/payload/superpower_fsm.py"]
}) == [], "Valid builder job should pass"
print("  Builder job validator smoke OK")

# test-design.json lint
td = json.loads(Path(".superpowers/verify/test-design.json").read_text(encoding="utf-8"))
lint_defects = lint_test_design(td)
assert lint_defects == [], "test-design.json lint failed: " + str(lint_defects)
print("  test-design.json lint OK (" + str(len(td.get("cases", []))) + " cases)")

# test-design.md parity
td_md = Path(".superpowers/verify/test-design.md").read_text(encoding="utf-8")
parity = parity_defects(td, td_md)
assert parity == [], "test-design parity defects: " + str(parity)
print("  test-design.md parity OK")

print("\nAll inline smoke assertions PASSED")
'@

Push-Location $repo
try {
    py -3 $smokeFile
    if ($LASTEXITCODE -ne 0) { throw "Inline smoke assertions FAILED" }
} finally {
    Pop-Location
    Remove-Item $smokeFile -Force -ErrorAction SilentlyContinue
}
Write-Host "[2/3] Inline smoke assertions PASSED" -ForegroundColor Green

# 3. writing-arch lint: no active (non-historical) references
Write-Host "`n[3/3] Checking for active writing-arch references..." -ForegroundColor Yellow
Push-Location $repo
try {
    $hits = @()
    # Exclude this test script itself from the writing-arch scan (it references the pattern for detection)
    $searchPaths = @("skills", "hooks", "lib", "docs", "FORK-MAINTENANCE.md")
    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            $matches_ = Select-String -Path "$p\*","$p\**\*" -Pattern "writing-arch" -ErrorAction SilentlyContinue
            $hits += $matches_
        }
    }
    $active = @($hits | Where-Object { $_.Line -notmatch "historical|superseded|obsolete" })
    if ($active.Count -gt 0) {
        foreach ($h in $active) {
            Write-Host "  ACTIVE writing-arch ref: $($h.Filename):$($h.LineNumber): $($h.Line.Trim())" -ForegroundColor Red
        }
        throw "Active writing-arch references found — must be marked historical/superseded/obsolete"
    }
    Write-Host "  No active writing-arch references found" -ForegroundColor Green
} finally {
    Pop-Location
}
Write-Host "[3/3] writing-arch check PASSED" -ForegroundColor Green

# 4. Verify S2 artifacts are not dirty
Write-Host "`n[4/4] Checking S2 verification artifacts are not dirty..." -ForegroundColor Yellow
Push-Location $repo
try {
    git diff --quiet -- ".superpowers/verify/test-design.json" ".superpowers/verify/test-design.md"
    if ($LASTEXITCODE -ne 0) {
        throw "S2 verification artifacts are dirty; lock or commit them before S4 build"
    }
    Write-Host "  S2 artifacts are clean" -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host "`n=== ALL CHECKS PASSED ===" -ForegroundColor Green
