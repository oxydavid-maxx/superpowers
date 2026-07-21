<#
  Security regression: a dangling `current` junction is still a reparse point and must be
  rejected before mutation. The pin never follows, removes, or repairs it because doing so
  would make an attacker-controlled link part of the mutation boundary. Temp homes only.
#>
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$pin = Join-Path $root "scripts\pin-local-fork-install.ps1"
$expected = (Get-Content -Raw -LiteralPath (Join-Path $root ".claude-plugin\plugin.json") | ConvertFrom-Json).version
$fails = New-Object System.Collections.Generic.List[string]
function Check($cond, $msg) { if (-not $cond) { $fails.Add($msg) | Out-Null; Write-Host "  FAIL: $msg" } }
$approvedDigest = "eb18a2e61ee38ba9d56ab9a5b83797f1b5a853618ff7c05a88938a8466b40593"

$testTemp = if (Test-Path -LiteralPath "C:\tmp" -PathType Container) { "C:\tmp" } else { $env:TEMP }
$tmp = Join-Path $testTemp ("pinfork-dangling-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$claude = Join-Path $tmp "claude"
$codex = Join-Path $tmp "codex"
try {
  # --- seed a DANGLING current junction in the Codex home ---
  $codexCache = Join-Path $codex "plugins\cache\superpowers-dev\superpowers"
  New-Item -ItemType Directory -Force -Path $codexCache | Out-Null
  $source = Join-Path $tmp "source"
  & git -c core.autocrlf=false -c core.longpaths=true clone --no-local --no-hardlinks --quiet -- "$root" "$source"
  if ($LASTEXITCODE -ne 0) { throw "cannot clone clean source" }
  $sourceHead = (& git --no-replace-objects -C $source rev-parse HEAD).Trim()

  $stale = Join-Path $codexCache "6.0.3-vmodel.0-stale"
  New-Item -ItemType Directory -Force -Path $stale | Out-Null
  $current = Join-Path $codexCache "current"
  New-Item -ItemType Junction -Path $current -Target $stale | Out-Null
  Remove-Item -Recurse -Force -LiteralPath $stale          # current now points at a missing target
  Check (Test-Path -LiteralPath $current) "precondition: dangling current junction should still exist as a reparse point"

  # --- reject before mutation; never resolve or repair the attacker-controlled link ---
  $message = ""
  try {
    & $pin -ClaudeHome $claude -CodexHome $codex -SourceRepo $source -ExpectedVersion $expected -ExpectedSourceCommit $sourceHead -ExpectedPackageDigest $approvedDigest | Out-Null
    Check $false "dangling reparse point was accepted"
  } catch {
    $message = $_.Exception.Message
  }
  Check ($message -match "reparse") "dangling current was not rejected by reparse guard: $message"
  $active = Join-Path $codexCache $expected
  Check (Test-Path -LiteralPath $current) "dangling current disappeared during rejected pin"
  Check ((Get-Item -LiteralPath $current -Force).LinkType -eq "Junction") "dangling current identity changed during rejected pin"
  Check (-not (Test-Path -LiteralPath $active)) "rejected pin created a versioned cache"
  Check (-not (Test-Path -LiteralPath $claude)) "rejected pin mutated the other configured home"
}
finally {
  Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}

if ($fails.Count -gt 0) { Write-Host "FAIL: $($fails.Count) check(s) failed"; exit 1 }
Write-Host "PASS: pin-local-fork-install rejects a dangling current reparse point before mutation"
exit 0
