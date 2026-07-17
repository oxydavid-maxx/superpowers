<#
  Focused security regression for the one legacy shape accepted by pin-local-fork-install:
  `current` may be a Junction only when it resolves to a plain direct sibling in the same fork
  base. External, cross-home, nested, and otherwise unexpected link/hardlink shapes stay closed.
#>

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pin = Join-Path $root "scripts\pin-local-fork-install.ps1"
$expected = (Get-Content -Raw -LiteralPath (Join-Path $root ".claude-plugin\plugin.json") | ConvertFrom-Json).version
$approvedDigest = "b070d6682ffd64fc21cd3e507c77be3661cfbe309a49dafd82814f5f676bfdcf"
$fails = New-Object System.Collections.Generic.List[string]

function Check([bool]$condition, [string]$message) {
  if (-not $condition) {
    $script:fails.Add($message) | Out-Null
    Write-Host "  FAIL: $message"
  }
}

function New-PlainTarget([string]$forkBase, [string]$leaf = "6.0.3-vmodel.17") {
  $target = Join-Path $forkBase $leaf
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $target "legacy.bin"), [byte[]](0, 1, 2, 253, 254, 255))
  return $target
}

function Assert-PinRejected([string]$name, [string]$claude, [string]$codex, [string]$pattern) {
  $accepted = $false
  $message = ""
  try {
    & $pin -ClaudeHome $claude -CodexHome $codex -SourceRepo $script:source `
      -ExpectedVersion $expected -ExpectedSourceCommit $script:sourceHead `
      -ExpectedPackageDigest $approvedDigest | Out-Null
    $accepted = $true
  } catch {
    $message = $_.Exception.Message
  }
  Check (-not $accepted) "$name was accepted"
  Check ($message -match $pattern) "$name failed for the wrong reason: $message"
  Check (-not (Test-Path -LiteralPath (Join-Path $claude ".superpowers-pin"))) "$name mutated Claude transaction state"
  Check (-not (Test-Path -LiteralPath (Join-Path $codex ".superpowers-pin"))) "$name mutated Codex transaction state"
}

$testTemp = if (Test-Path -LiteralPath "C:\tmp" -PathType Container) { "C:\tmp" } else { $env:TEMP }
$tmp = Join-Path $testTemp ("sp-legacy-security-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

try {
  $script:source = Join-Path $tmp "source"
  & git -c core.autocrlf=false -c core.longpaths=true clone --no-local --no-hardlinks --quiet -- "$root" $script:source
  if ($LASTEXITCODE -ne 0) { throw "cannot clone clean source" }
  $script:sourceHead = (& git --no-replace-objects -C $script:source rev-parse HEAD).Trim()

  $externalRoot = Join-Path $tmp "external-target"
  $externalClaude = Join-Path $externalRoot "claude"
  $externalCodex = Join-Path $externalRoot "codex"
  $externalBase = Join-Path $externalClaude "plugins\cache\superpowers-dev\superpowers"
  $externalTarget = Join-Path $externalRoot "outside"
  New-Item -ItemType Directory -Force -Path $externalBase, $externalCodex, $externalTarget | Out-Null
  [IO.File]::WriteAllText((Join-Path $externalTarget "sentinel.txt"), "external-safe")
  New-Item -ItemType Junction -Path (Join-Path $externalBase "current") -Target $externalTarget | Out-Null
  Assert-PinRejected "external current Junction" $externalClaude $externalCodex "direct contained sibling"
  Check ([IO.File]::ReadAllText((Join-Path $externalTarget "sentinel.txt")) -eq "external-safe") "external current target bytes changed"

  $crossRoot = Join-Path $tmp "cross-home"
  $crossClaude = Join-Path $crossRoot "claude"
  $crossCodex = Join-Path $crossRoot "codex"
  $crossClaudeBase = Join-Path $crossClaude "plugins\cache\superpowers-dev\superpowers"
  $crossCodexBase = Join-Path $crossCodex "plugins\cache\superpowers-dev\superpowers"
  $crossTarget = New-PlainTarget $crossCodexBase
  New-Item -ItemType Directory -Force -Path $crossClaudeBase | Out-Null
  New-Item -ItemType Junction -Path (Join-Path $crossClaudeBase "current") -Target $crossTarget | Out-Null
  Assert-PinRejected "cross-home current Junction" $crossClaude $crossCodex "direct contained sibling"

  $nestedRoot = Join-Path $tmp "nested-target"
  $nestedClaude = Join-Path $nestedRoot "claude"
  $nestedCodex = Join-Path $nestedRoot "codex"
  $nestedBase = Join-Path $nestedClaude "plugins\cache\superpowers-dev\superpowers"
  $nestedTarget = New-PlainTarget (Join-Path $nestedBase "container")
  New-Item -ItemType Directory -Force -Path $nestedCodex | Out-Null
  New-Item -ItemType Junction -Path (Join-Path $nestedBase "current") -Target $nestedTarget | Out-Null
  Assert-PinRejected "nested contained current Junction" $nestedClaude $nestedCodex "direct contained sibling"

  $nestedReparseRoot = Join-Path $tmp "nested-reparse"
  $nestedReparseClaude = Join-Path $nestedReparseRoot "claude"
  $nestedReparseCodex = Join-Path $nestedReparseRoot "codex"
  $nestedReparseBase = Join-Path $nestedReparseClaude "plugins\cache\superpowers-dev\superpowers"
  $nestedReparseTarget = New-PlainTarget $nestedReparseBase
  $nestedReparseOutside = Join-Path $nestedReparseRoot "outside"
  New-Item -ItemType Directory -Force -Path $nestedReparseCodex, $nestedReparseOutside | Out-Null
  New-Item -ItemType Junction -Path (Join-Path $nestedReparseTarget "nested") -Target $nestedReparseOutside | Out-Null
  New-Item -ItemType Junction -Path (Join-Path $nestedReparseBase "current") -Target $nestedReparseTarget | Out-Null
  Assert-PinRejected "nested reparse in legacy target" $nestedReparseClaude $nestedReparseCodex "reparse"

  $hardlinkRoot = Join-Path $tmp "nested-hardlink"
  $hardlinkClaude = Join-Path $hardlinkRoot "claude"
  $hardlinkCodex = Join-Path $hardlinkRoot "codex"
  $hardlinkBase = Join-Path $hardlinkClaude "plugins\cache\superpowers-dev\superpowers"
  $hardlinkTarget = New-PlainTarget $hardlinkBase
  $hardlinkPeer = Join-Path $hardlinkRoot "outside.bin"
  New-Item -ItemType Directory -Force -Path $hardlinkCodex | Out-Null
  [IO.File]::WriteAllBytes($hardlinkPeer, [byte[]](5, 4, 3, 2, 1, 0))
  New-Item -ItemType HardLink -Path (Join-Path $hardlinkTarget "nested-hardlink.bin") -Target $hardlinkPeer | Out-Null
  New-Item -ItemType Junction -Path (Join-Path $hardlinkBase "current") -Target $hardlinkTarget | Out-Null
  Assert-PinRejected "hardlink in legacy target" $hardlinkClaude $hardlinkCodex "hardlink"

  $unexpectedRoot = Join-Path $tmp "unexpected-reparse"
  $unexpectedClaude = Join-Path $unexpectedRoot "claude"
  $unexpectedCodex = Join-Path $unexpectedRoot "codex"
  $unexpectedBase = Join-Path $unexpectedClaude "plugins\cache\superpowers-dev\superpowers"
  $unexpectedOutside = Join-Path $unexpectedRoot "outside"
  New-Item -ItemType Directory -Force -Path $unexpectedBase, $unexpectedCodex, $unexpectedOutside | Out-Null
  New-Item -ItemType Junction -Path (Join-Path $unexpectedBase "rogue") -Target $unexpectedOutside | Out-Null
  Assert-PinRejected "unexpected managed-cache Junction" $unexpectedClaude $unexpectedCodex "reparse"

  if ($fails.Count -gt 0) {
    Write-Host "FAIL: $($fails.Count) legacy current security check(s) failed"
    exit 1
  }
  Write-Host "PASS: legacy current migration accepts no external, cross-home, nested, hardlinked, or unexpected reparse shape"
} finally {
  if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
}
