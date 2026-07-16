$ErrorActionPreference = "Stop"

function Read-Skill([string]$name) {
  return Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\skills\$name\SKILL.md") -Encoding utf8
}

function Assert-Absent([string]$text, [string[]]$phrases, [string]$label) {
  foreach ($phrase in $phrases) {
    if ($text.Contains($phrase)) { throw "$label contains retired authority: $phrase" }
  }
}

function Artifact-List([string]$text, [string]$name) {
  $match = [regex]::Match($text, "$name = \[([^\]]+)\]")
  if (-not $match.Success) { throw "missing $name" }
  return @($match.Groups[1].Value.Split(',') | ForEach-Object { $_.Trim() })
}

$brain = Read-Skill "brainstorming"
$plans = Read-Skill "writing-plans"
$exec = Read-Skill "executing-plans"
$sdd = Read-Skill "subagent-driven-development"
$parallel = Read-Skill "dispatching-parallel-agents"
$entry = Read-Skill "using-superpowers"
$arch = Read-Skill "verify-arch"

$expected = @(
  "stakeholder-needs.json",
  "material-unknowns.json",
  "decision-log.md",
  "clarification-log.json",
  "issue-coverage.json",
  "spec-draft0.md",
  "mock-v0/index.html"
)
foreach ($name in @("S0_ARTIFACTS", "TOKEN_BOUND")) {
  $actual = Artifact-List $brain $name
  $delta = @(Compare-Object $expected $actual)
  if ($delta.Count -ne 0) { throw "$name is not the exact seven-artifact S0 contract: $($delta | Out-String)" }
}

Assert-Absent $brain @(
  "dispatch-policy.yaml",
  "elicitation-critic.json",
  "critic-dispatch-r1.json",
  "Critic identity"
) "brainstorming"
foreach ($required in @(
  "Exhaustively elicit stakeholder needs",
  "material-unknowns.json",
  "issue-coverage.json",
  "SOTA research",
  "Get-FileHash -Algorithm SHA256",
  "Cloudflare Quick Tunnel"
)) {
  if (-not $brain.Contains($required)) { throw "brainstorming lost S0/S1 know-how: $required" }
}

Assert-Absent $plans @(
  "PostToolUse ``executor_select``",
  "Recommended executor",
  "Fresh subagent per task + two-stage review",
  "REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development",
  "Hand off to the ``/workflow`` tool",
  "External S4 Builder Handoff SOP",
  "builder_session"
) "writing-plans"
foreach ($required in @("current native owner", "complete release candidate", "one integrated release review")) {
  if (-not $plans.Contains($required)) { throw "writing-plans missing native-owner contract: $required" }
}

Assert-Absent $exec @(
  "works much better with access to subagents",
  "use superpowers:subagent-driven-development instead",
  "builder_session"
) "executing-plans"
if (-not $exec.Contains("complete release candidate")) { throw "executing-plans is not complete-candidate ownership" }

if ($sdd -notmatch '(?i)explicit user request') { throw "subagent-driven-development is not explicit-request-only" }
Assert-Absent $sdd @("Always specify the model explicitly", "Requested model", "actual_served_model") "subagent-driven-development"
if ($parallel -notmatch '(?i)explicit user request') { throw "dispatching-parallel-agents is not explicit-request-only" }

Assert-Absent $entry @(
  "dispatch-policy.yaml",
  "fleet execution",
  "Codex/OpenRouter runner selection",
  "builder_session",
  "user-specified Claude web session"
) "using-superpowers"
foreach ($required in @("S2_TEST_DESIGN_REVIEW", "current host session", "host-native")) {
  if (-not $entry.Contains($required)) { throw "using-superpowers missing native lifecycle wording: $required" }
}

Assert-Absent $arch @("subagent-driven-development finishes the build") "verify-arch"

Write-Output "native execution shape tests passed"
