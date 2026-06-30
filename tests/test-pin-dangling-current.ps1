<#
  Regression (orchestrator bugfix 2026-06-30): Set-CurrentPointer must FAIL-SOFT when the
  Codex `current` junction is DANGLING (its target was quarantined/removed). Before the fix,
  Resolve-Path on the missing junction target threw under $ErrorActionPreference=Stop and pin
  crashed. After the fix, pin rebuilds `current` -> the new versioned cache. Temp homes only.
#>
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$pin = Join-Path $root "scripts\pin-local-fork-install.ps1"
$expected = (Get-Content -Raw -LiteralPath (Join-Path $root ".claude-plugin\plugin.json") | ConvertFrom-Json).version
$fails = New-Object System.Collections.Generic.List[string]
function Check($cond, $msg) { if (-not $cond) { $fails.Add($msg) | Out-Null; Write-Host "  FAIL: $msg" } }
function ResolvedTarget([string]$path) {
  $item = Get-Item -LiteralPath $path -Force
  if ($item.LinkType -and $item.Target) { return (Resolve-Path -LiteralPath $item.Target).Path }
  return (Resolve-Path -LiteralPath $path).Path
}

$tmp = Join-Path $env:TEMP ("pinfork-dangling-" + (Get-Random))
$claude = Join-Path $tmp "claude"
$codex = Join-Path $tmp "codex"
try {
  # --- seed a DANGLING current junction in the Codex home ---
  $codexCache = Join-Path $codex "plugins\cache\superpowers-dev\superpowers"
  New-Item -ItemType Directory -Force -Path $codexCache | Out-Null
  $stale = Join-Path $codexCache "6.0.3-vmodel.0-stale"
  New-Item -ItemType Directory -Force -Path $stale | Out-Null
  $current = Join-Path $codexCache "current"
  New-Item -ItemType Junction -Path $current -Target $stale | Out-Null
  Remove-Item -Recurse -Force -LiteralPath $stale          # current now points at a missing target
  Check (Test-Path -LiteralPath $current) "precondition: dangling current junction should still exist as a reparse point"

  # --- run pin against temp homes (must not crash on the dangling junction) ---
  & $pin -ClaudeHome $claude -CodexHome $codex -SourceRepo $root -ExpectedVersion $expected -SkipVerify | Out-Null
  Check ($LASTEXITCODE -eq 0) "pin crashed on dangling current junction (exit $LASTEXITCODE)"

  # --- current must be rebuilt to the new versioned cache ---
  $active = Join-Path $codexCache $expected
  Check (Test-Path -LiteralPath $current) "current pointer missing after pin"
  Check (Test-Path -LiteralPath $active) "expected versioned cache missing after pin"
  Check ((ResolvedTarget $current) -eq (Resolve-Path -LiteralPath $active).Path) "current does not resolve to the new versioned cache"
}
finally {
  Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}

if ($fails.Count -gt 0) { Write-Host "FAIL: $($fails.Count) check(s) failed"; exit 1 }
Write-Host "PASS: pin-local-fork-install fails soft on a dangling current junction and rebuilds current -> $expected"
exit 0
