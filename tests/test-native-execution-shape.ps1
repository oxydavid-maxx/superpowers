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

function Assert-Stage-Prefix([string]$text, [string[]]$expected) {
  $actual = @(
    [regex]::Matches($text, '(?m)^\|\s*(S[0-9]_[A-Z0-9_]+)\s*\|') |
      ForEach-Object { $_.Groups[1].Value }
  )
  if ($actual.Count -lt $expected.Count) {
    throw "using-superpowers stage table is incomplete: $($actual -join ' -> ')"
  }
  for ($i = 0; $i -lt $expected.Count; $i++) {
    if ($actual[$i] -ne $expected[$i]) {
      throw "using-superpowers stage order mismatch at ${i}: expected $($expected[$i]), got $($actual[$i])"
    }
  }
}

$brain = Read-Skill "brainstorming"
$plans = Read-Skill "writing-plans"
$exec = Read-Skill "executing-plans"
$sdd = Read-Skill "subagent-driven-development"
$parallel = Read-Skill "dispatching-parallel-agents"
$entry = Read-Skill "using-superpowers"
$arch = Read-Skill "verify-arch"
$review = Read-Skill "requesting-code-review"
$skillAuthoring = Read-Skill "writing-skills"

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
Assert-Absent $sdd @("Always specify the model explicitly", "Requested model", "actual_served_model", "with the same model", "with a more capable model", "force the same model") "subagent-driven-development"
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
Assert-Stage-Prefix $entry @(
  "S0_DISCUSS",
  "S0_DRAFT0",
  "S0_MOCK0",
  "S0_SOTA",
  "S0_APPROVE",
  "S1_DISCUSS",
  "S1_DRAFT1",
  "S1_MOCK1",
  "S1_APPROVE",
  "S2_TEST_DESIGN_REVIEW"
)
if ($entry.Contains("Authoritative runtime pathAuthoritative runtime path")) {
  throw "using-superpowers duplicates the authoritative runtime label"
}
$humanGateRows = @(
  [regex]::Matches($entry, '(?im)^\|\s*(S[0-9]_[A-Z0-9_]+)\s*\|[^\r\n]*human approval[^\r\n]*$') |
    ForEach-Object { $_.Groups[1].Value }
)
$humanGateDelta = @(Compare-Object @("S0_APPROVE", "S1_APPROVE") $humanGateRows)
if ($humanGateDelta.Count -ne 0) {
  throw "using-superpowers human gates must be exactly S0_APPROVE and S1_APPROVE"
}

foreach ($contract in @(
  @{ Name = "writing-plans"; Text = $plans },
  @{ Name = "executing-plans"; Text = $exec }
)) {
  if ($contract.Text -match '(?<![A-Za-z0-9_])T[0-3](?![A-Za-z0-9_])') {
    throw "$($contract.Name) contains retired active T0-T3 terminology: $($Matches[0])"
  }
  Assert-Absent $contract.Text @("TEST_TIER", "Require one bounded StartAck") $contract.Name
  foreach ($required in @("FOCUS =", "RC =", "RED", "GREEN", "affected proof", "exact integrated candidate")) {
    if (-not $contract.Text.Contains($required)) {
      throw "$($contract.Name) missing FOCUS-to-RC contract: $required"
    }
  }
}

Assert-Absent $review @(
  "Dispatch a code reviewer subagent",
  "Dispatch a ``general-purpose`` subagent",
  "[Dispatch code reviewer subagent]"
) "requesting-code-review"
foreach ($required in @("current native owner", "exact integrated candidate")) {
  if (-not $review.Contains($required)) { throw "requesting-code-review missing native RC wording: $required" }
}

Assert-Absent $skillAuthoring @(
  "pressure scenarios with subagents",
  "Pressure scenario with subagent",
  "Run pressure scenario with subagent",
  "Always use subagents",
  "single-shot subagent"
) "writing-skills"

$activeSkillRoots = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "..\skills") -Directory
foreach ($skillRoot in $activeSkillRoots) {
  if ($skillRoot.Name -in @("subagent-driven-development", "dispatching-parallel-agents")) { continue }
  $skillPath = Join-Path $skillRoot.FullName "SKILL.md"
  if (-not (Test-Path -LiteralPath $skillPath)) { continue }
  $activeText = Get-Content -Raw -LiteralPath $skillPath -Encoding utf8
  Assert-Absent $activeText @(
    "dispatch-policy.yaml",
    "critic-dispatch-r1.json",
    "Critic identity",
    "requested_model",
    "actual_served_model",
    "builder_session"
  ) "active skill $($skillRoot.Name)"
}

Assert-Absent $arch @("subagent-driven-development finishes the build") "verify-arch"

Write-Output "native execution shape tests passed"
