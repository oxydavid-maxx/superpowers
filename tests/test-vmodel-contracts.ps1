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
if ($job -match "home-superpower") {
  throw "builder job schema must not hardcode home-superpower"
}

$ack = Get-Content -Raw -LiteralPath $ackSchema
Assert-Contains $ack "touched_files" "builder ack schema must report touched_files"
Assert-Contains $ack "forbidden_paths" "builder ack schema must define forbidden paths for spec/verify/release ownership"

Write-Output "vmodel contract tests passed"
