$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]

function Read-RepoFile([string]$relative) {
  return Get-Content -Raw -LiteralPath (Join-Path $root $relative) -Encoding utf8
}

function Require-Text([string]$text, [string]$needle, [string]$label) {
  if ($text.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
    $failures.Add("$label missing contract: $needle") | Out-Null
  }
}

function Reject-Text([string]$text, [string]$needle, [string]$label) {
  if ($text.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    $failures.Add("$label retains superseded contract: $needle") | Out-Null
  }
}

$verification = Read-RepoFile "skills\verification-before-completion\SKILL.md"
$finishing = Read-RepoFile "skills\finishing-a-development-branch\SKILL.md"
$maintenance = Read-RepoFile "FORK-MAINTENANCE.md"

foreach ($required in @(
  "exact action key",
  "result-affecting input binding",
  "remain valid across candidate commits",
  "rerun only the invalidated proof",
  "duplicate FOCUS execution",
  "cached PASS"
)) {
  Require-Text $verification $required "verification-before-completion"
}
foreach ($required in @(
  "one integrated RC",
  "bootstrap",
  "weekly canary",
  "named-high-risk:<reason>",
  "Normal publish or merge alone is not a full-suite trigger",
  "candidate drift",
  "input drift"
)) {
  Require-Text $finishing $required "finishing-a-development-branch"
}

Reject-Text $verification "If you haven't run the verification command in this message, you cannot claim it passes." "verification-before-completion"
Reject-Text $finishing "# Run project's test suite" "finishing-a-development-branch"
Reject-Text $finishing "# Verify tests on merged result`n<test command>" "finishing-a-development-branch"

Require-Text $maintenance "6.0.3-native.21" "FORK-MAINTENANCE"
Require-Text $maintenance "one integrated RC" "FORK-MAINTENANCE"
Require-Text $maintenance "normal publish or merge alone" "FORK-MAINTENANCE"

$registry = Read-RepoFile ".version-bump.json" | ConvertFrom-Json
$versions = foreach ($entry in $registry.files) {
  $value = Read-RepoFile $entry.path | ConvertFrom-Json
  foreach ($segment in $entry.field.Split(".")) {
    $value = if ($segment -match "^[0-9]+$") { $value[[int]$segment] } else { $value.$segment }
  }
  [string]$value
}
if (@($versions | Where-Object { $_ -ne "6.0.3-native.21" }).Count -ne 0) {
  $failures.Add("all .version-bump.json targets must equal immutable 6.0.3-native.21; got [$($versions -join ', ')]") | Out-Null
}

if ($failures.Count -gt 0) {
  throw "RC receipt reuse contract failures:`n - $($failures -join "`n - ")"
}

Write-Output "PASS: RC receipt reuse and immutable native.19 release contract"
