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

$pin = Get-Content -Raw -LiteralPath (Join-Path $Root "scripts\pin-local-fork-install.ps1")
Assert-Contains $pin "current" "pin-local-fork-install must maintain a stable current pointer"
Assert-Contains $pin "Junction" "pin-local-fork-install must use a Windows-safe directory junction for current"
Assert-Contains $pin "\.superpowers-active\.json" "pin-local-fork-install must write resolved active metadata"

$verify = Get-Content -Raw -LiteralPath (Join-Path $Root "scripts\verify-local-fork-install.ps1")
Assert-Contains $verify "\\superpowers-dev\\superpowers\\current" "verify-local-fork-install must require installPath to point at current"
Assert-Contains $verify "Resolve-PluginTarget" "verify-local-fork-install must verify the resolved current target"
Assert-Contains $verify "\.superpowers-active\.json" "verify-local-fork-install must verify active metadata"

$writingSkills = Get-Content -Raw -LiteralPath (Join-Path $Root "skills\writing-skills\SKILL.md")
Assert-Contains $writingSkills "stable current pointer" "writing-skills must broadcast the release model to all skill/plugin development"
Assert-Contains $writingSkills "pin-local-fork-install" "writing-skills must route plugin skill releases through the pin verifier"

$maintenance = Get-Content -Raw -LiteralPath (Join-Path $Root "FORK-MAINTENANCE.md")
Assert-Contains $maintenance "stable .*current.* pointer" "FORK-MAINTENANCE must document stable current pointer releases"
Assert-Contains $maintenance "resolved metadata" "FORK-MAINTENANCE must document resolved metadata proof"

$claudeHook = Get-Content -Raw -LiteralPath (Join-Path $Root "hooks\session-start")
$codexHook = Get-Content -Raw -LiteralPath (Join-Path $Root "hooks\session-start-codex")
Assert-Contains $claudeHook "Superpowers active" "Claude session-start must broadcast active Superpowers version"
Assert-Contains $codexHook "Superpowers active" "Codex session-start must broadcast active Superpowers version"

Write-Output "current pointer contracts passed"
