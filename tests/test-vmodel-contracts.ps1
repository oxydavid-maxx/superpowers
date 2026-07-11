$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Pattern,
    [string]$Message
  )
  if ($Text -notmatch $Pattern) {
    throw $Message
  }
}

$writingVerificationSkill = Join-Path $Root "skills\writing-verification-plans\SKILL.md"
if (-not (Test-Path -LiteralPath $writingVerificationSkill)) {
  throw "missing callable skill: skills/writing-verification-plans/SKILL.md"
}

$wv = Get-Content -Raw -LiteralPath $writingVerificationSkill
Assert-Contains $wv "test-design\.json" "writing-verification-plans must produce .superpowers/verify/test-design.json"
Assert-Contains $wv "Capability Registry" "writing-verification-plans must read the Capability Registry"
Assert-Contains $wv "independent" "writing-verification-plans must require independent verifier attestation"

$brainstorming = Get-Content -Raw -LiteralPath (Join-Path $Root "skills\brainstorming\SKILL.md")
Assert-Contains $brainstorming "expected mock v1" "brainstorming must require expected mock v1 after Spec Draft"
Assert-Contains $brainstorming "expected mock v2" "brainstorming must require expected mock v2 after Spec Final"
Assert-Contains $brainstorming "non-UI" "brainstorming mock policy must cover non-UI specs"
Assert-Contains $brainstorming "S0_DISCUSS" "brainstorming must define the SPG S0_DISCUSS station"
Assert-Contains $brainstorming "stakeholder-needs\.json" "S0_DISCUSS must emit stakeholder-needs.json"
Assert-Contains $brainstorming "material-unknowns\.json" "S0_DISCUSS must emit material-unknowns.json"
Assert-Contains $brainstorming "token-bound" "S0_DISCUSS must preserve token-bound artifacts on re-entry"
Assert-Contains $brainstorming "cumulative handoff" "S0_DISCUSS must maintain one cumulative handoff"

# --- Task 5 S0 handoff contract: structural assertions, not prose-only presence ---
Assert-Contains $brainstorming "spg start <topic> --dir <project>" "S0_DISCUSS must provide the exact spg start command"
Assert-Contains $brainstorming "spg s0-check <run_dir>" "S0_DISCUSS must provide the exact s0-check command"
foreach ($artifact in @(
  "stakeholder-needs\.json",
  "material-unknowns\.json",
  "decision-log\.md",
  "clarification-log\.json",
  "issue-coverage\.json",
  "dispatch-policy\.yaml",
  "spec-draft0\.md",
  "mock-v0/index\.html",
  "elicitation-critic\.json",
  "critic-dispatch-r1\.json"
)) {
  Assert-Contains $brainstorming $artifact "S0 artifact list must include $artifact"
}
foreach ($bound in @(
  "stakeholder-needs\.json",
  "material-unknowns\.json",
  "decision-log\.md",
  "clarification-log\.json",
  "dispatch-policy\.yaml",
  "spec-draft0\.md",
  "mock-v0/index\.html",
  "elicitation-critic\.json",
  "critic-dispatch-r1\.json"
)) {
  Assert-Contains $brainstorming $bound "token-bound list must include $bound"
}
Assert-Contains $brainstorming "Get-FileHash.*-Algorithm SHA256" "S0 approval must compute SHA-256 digests"
Assert-Contains $brainstorming "path -> sha256" "handoff must use the sorted path -> sha256 table"
Assert-Contains $brainstorming "stakeholder-needs\.json.*material-unknowns\.json.*decision-log\.md" "S0 schema must identify the emitted artifact fields"
Assert-Contains $brainstorming "session.*created.*now.*next.*remaining work.*takeover instructions" "handoff schema must contain fixed fields in order"
Assert-Contains $brainstorming "handoffs/YYYY-MM-DD--<session-name>--handoff\.md" "handoff filename must be deterministic"
Assert-Contains $brainstorming "lowercase hyphen slug" "handoff session names must be sanitized deterministically"
Assert-Contains $brainstorming "exactly one" "handoff contract must forbid one-file-per-station output"
Assert-Contains $brainstorming "git check-ignore -q <run_dir>" "S0 must verify the target run is ignored before writing handoff"
Assert-Contains $brainstorming "none of the bound files may be overwritten" "token-bound artifacts must be immutable after token issuance"
Assert-Contains $brainstorming "append.*clarification-log\.json.*decision-log\.md" "re-entry may append only the two mutable logs"
Assert-Contains $brainstorming "re-run approval/binding" "changed mutable-log digests must invalidate the old token"
Assert-Contains $brainstorming "next three stations" "handoff must list exactly three ordered next stations when available"

function Assert-S0ContractComplete {
  param([string]$Text)
  $match = [regex]::Match($Text, "(?s)## SPG S0_DISCUSS station\s+(.*?)\s+## Checklist")
  if (-not $match.Success) { throw "S0_DISCUSS must be one bounded contract section" }
  $section = $match.Groups[1].Value
  foreach ($required in @(
    "spg start <topic> --dir <project>",
    "S0_ARTIFACTS = [stakeholder-needs.json, material-unknowns.json, decision-log.md, clarification-log.json, issue-coverage.json, dispatch-policy.yaml, spec-draft0.md, mock-v0/index.html, elicitation-critic.json, critic-dispatch-r1.json]",
    "TOKEN_BOUND = [stakeholder-needs.json, material-unknowns.json, decision-log.md, clarification-log.json, dispatch-policy.yaml, spec-draft0.md, mock-v0/index.html, elicitation-critic.json, critic-dispatch-r1.json]",
    "git check-ignore -q <run_dir>",
    "handoffs/YYYY-MM-DD--<session-name>--handoff.md",
    "session | created | now | next | remaining work | takeover instructions",
    "spg s0-check <run_dir>"
  )) {
    if (-not $section.Contains($required)) { throw "S0_DISCUSS bounded contract missing: $required" }
  }
}

Assert-S0ContractComplete $brainstorming
foreach ($required in @(
  "spg start <topic> --dir <project>",
  "S0_ARTIFACTS = [stakeholder-needs.json, material-unknowns.json, decision-log.md, clarification-log.json, issue-coverage.json, dispatch-policy.yaml, spec-draft0.md, mock-v0/index.html, elicitation-critic.json, critic-dispatch-r1.json]",
  "TOKEN_BOUND = [stakeholder-needs.json, material-unknowns.json, decision-log.md, clarification-log.json, dispatch-policy.yaml, spec-draft0.md, mock-v0/index.html, elicitation-critic.json, critic-dispatch-r1.json]",
  "git check-ignore -q <run_dir>",
  "handoffs/YYYY-MM-DD--<session-name>--handoff.md",
  "session | created | now | next | remaining work | takeover instructions",
  "spg s0-check <run_dir>"
)) {
  $failed = $false
  try { Assert-S0ContractComplete ($brainstorming.Replace($required, "")) } catch { $failed = $true }
  if (-not $failed) { throw "S0 contract mutation survived removal: $required" }
}

$usingSuperpowers = Get-Content -Raw -LiteralPath (Join-Path $Root "skills\using-superpowers\SKILL.md")
Assert-Contains $usingSuperpowers "complete stage-order" "using-superpowers must require a complete stage-order recap"
Assert-Contains $usingSuperpowers "S0_DISCUSS" "using-superpowers must name S0_DISCUSS"
Assert-Contains $usingSuperpowers "S2_VERIFICATION_PLAN" "using-superpowers must name S2_VERIFICATION_PLAN"
Assert-Contains $usingSuperpowers "S4_BUILD executor" "using-superpowers must define S4_BUILD executor"
Assert-Contains $usingSuperpowers "current session" "using-superpowers must use current session as the default owner/executor wording"
Assert-Contains $usingSuperpowers "fixed boilerplate" "using-superpowers must reject boilerplate-only entry responses"
Assert-Contains $usingSuperpowers "superpowers:writing-verification-plans" "using-superpowers must map S2 to writing-verification-plans"
Assert-Contains $usingSuperpowers "superpowers:verify-spec" "using-superpowers must map S5_VERIFY_SPEC to verify-spec"
if ($usingSuperpowers -match "Owner:\s*(Codex|Claude)") {
  throw "using-superpowers must not hardcode Codex or Claude as default owner"
}

$verifyArch = Get-Content -Raw -LiteralPath (Join-Path $Root "skills\verify-arch\SKILL.md")
Assert-Contains $verifyArch "verify-arch: N/A" "verify-arch must document single-entry N/A verdict"
Assert-Contains $verifyArch "single-entry" "verify-arch must be conditional on multi-entry projects"

$verifySpec = Get-Content -Raw -LiteralPath (Join-Path $Root "skills\verify-spec\SKILL.md")
Assert-Contains $verifySpec "skill-ui-human" "verify-spec must depend on skill-ui-human for UI caps"
Assert-Contains $verifySpec "ui_human_evidence" "verify-spec must require runtime UI-human evidence in UI MATCHES verdicts"

$jobSchema = Join-Path $Root "docs\orch\builder-job.schema.json"
$ackSchema = Join-Path $Root "docs\orch\builder-ack.schema.json"
if (-not (Test-Path -LiteralPath $jobSchema)) {
  throw "missing docs/orch/builder-job.schema.json"
}
if (-not (Test-Path -LiteralPath $ackSchema)) {
  throw "missing docs/orch/builder-ack.schema.json"
}

$job = Get-Content -Raw -LiteralPath $jobSchema
Assert-Contains $job "builder_session" "builder job schema must require runtime-provided builder_session"
Assert-Contains $job "claude_web" "builder job schema must require Claude web session handoff for external S4 builder"
Assert-Contains $job "user_specified" "builder job schema must record that the builder session was user-specified"
Assert-Contains $job "handoff_channel" "builder job schema must require explicit handoff channel"
Assert-Contains $job "chrome" "builder job schema must require Chrome handoff for Claude web sessions"
Assert-Contains $job "fallback_allowed" "builder job schema must explicitly forbid fallback substitution"
if ($job -match "home-superpower") {
  throw "builder job schema must not hardcode home-superpower"
}

$ack = Get-Content -Raw -LiteralPath $ackSchema
Assert-Contains $ack "touched_files" "builder ack schema must report touched_files"
Assert-Contains $ack "forbidden_paths" "builder ack schema must define forbidden paths for spec/verify/release ownership"

$pinScript = Get-Content -Raw -LiteralPath (Join-Path $Root "scripts\pin-local-fork-install.ps1")
Assert-Contains $pinScript "Repin-ClaudeSkillRegistry" "pin-local-fork-install must repin Claude skills registry entries"
Assert-Contains $pinScript "skills\\registry.yaml" "pin-local-fork-install must update Claude skills/registry.yaml"
Assert-Contains $pinScript "superpowers-dev\\superpowers\\current" "pin-local-fork-install must route registry entries through current"

$verifyInstall = Get-Content -Raw -LiteralPath (Join-Path $Root "scripts\verify-local-fork-install.ps1")
Assert-Contains $verifyInstall "skills\\registry.yaml" "verify-local-fork-install must inspect Claude skills registry"
Assert-Contains $verifyInstall "hard-pins" "verify-local-fork-install must reject hard-pinned Superpower registry entries"
Assert-Contains $verifyInstall "superpowers-dev\\superpowers\\current" "verify-local-fork-install must require current pointer in registry entries"

# --- maturity feedback-loop contracts (job 2026-06-30-superpower-maturity-feedback-loop) ---
Assert-Contains $brainstorming "stakeholder-needs\.json" "brainstorming must require SYS.1 stakeholder-needs.json before Spec Draft"
Assert-Contains $brainstorming "material-unknowns\.json" "brainstorming must require material-unknowns.json (zero unresolved before Spec Draft)"
Assert-Contains $brainstorming "decision-log\.md" "brainstorming must require decision-log.md"
Assert-Contains $brainstorming "need_ids" "brainstorming must require Need-ID -> Cap-ID traceability"
Assert-Contains $wv "test-design\.md" "writing-verification-plans must also emit test-design.md"
Assert-Contains $wv "projection" "writing-verification-plans must define test-design.md as a deterministic projection of the JSON"

$payload = Join-Path $Root "lib\runtime\payload"
foreach ($m in @("sys1_elicitation.py", "test_design_projection.py", "verification_feedback.py", "autoapply_safety.py")) {
  if (-not (Test-Path -LiteralPath (Join-Path $payload $m))) { throw "missing runtime module: lib/runtime/payload/$m" }
}

Write-Output "vmodel contract tests passed"
