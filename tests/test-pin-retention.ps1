<#
  Regression (2026-07-01 audit fix): every pin/repin run leaves a permanent
  .quarantine-superpowers-<ts> dir + installed_plugins.json.bak-<ts> file behind, and
  NOTHING ever prunes them -- unbounded disk/directory-listing growth. This proves
  pin-local-fork-install.ps1 keeps only the N most recent of each (default 3),
  including the ones the run itself just created. Temp homes only.
#>
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$pin = Join-Path $root "scripts\pin-local-fork-install.ps1"
$expected = (Get-Content -Raw -LiteralPath (Join-Path $root ".claude-plugin\plugin.json") | ConvertFrom-Json).version
$fails = New-Object System.Collections.Generic.List[string]
function Check($cond, $msg) { if (-not $cond) { $fails.Add($msg) | Out-Null; Write-Host "  FAIL: $msg" } }

$tmp = Join-Path $env:TEMP ("pinfork-retention-" + (Get-Random))
$claude = Join-Path $tmp "claude"
$codex = Join-Path $tmp "codex"
try {
  # --- seed 5 pre-existing quarantine dirs + 5 pre-existing .bak files in the Claude home ---
  $pluginsDir = Join-Path $claude "plugins"
  New-Item -ItemType Directory -Force -Path $pluginsDir | Out-Null
  $stamps = @("20260601T000000Z","20260602T000000Z","20260603T000000Z","20260604T000000Z","20260605T000000Z")
  foreach ($s in $stamps) {
    New-Item -ItemType Directory -Force -Path (Join-Path $pluginsDir ".quarantine-superpowers-$s") | Out-Null
  }
  $ipj = Join-Path $pluginsDir "installed_plugins.json"
  '{ "version": 2, "plugins": {} }' | Set-Content -LiteralPath $ipj -Encoding utf8
  foreach ($s in $stamps) {
    Copy-Item -LiteralPath $ipj -Destination (Join-Path $pluginsDir "installed_plugins.json.bak-$s") -Force
  }
  # seed a stale fork cache so this pin run ALSO creates its own new quarantine dir
  New-Item -ItemType Directory -Force -Path (Join-Path $claude "plugins\cache\superpowers-dev\superpowers\6.0.3-vmodel.0-stale") | Out-Null

  # --- run pin (creates a 6th quarantine dir + a 6th .bak, then must prune to retention) ---
  & $pin -ClaudeHome $claude -CodexHome $codex -SourceRepo $root -ExpectedVersion $expected -SkipVerify | Out-Null
  Check ($LASTEXITCODE -eq 0) "pin run exited $LASTEXITCODE"

  $qDirs = Get-ChildItem -Path $pluginsDir -Directory -Filter ".quarantine-superpowers-*" -ErrorAction SilentlyContinue
  $bakFiles = Get-ChildItem -Path $pluginsDir -File -Filter "installed_plugins.json.bak-*" -ErrorAction SilentlyContinue
  Check ($qDirs.Count -le 3) "expected <=3 quarantine dirs retained, found $($qDirs.Count): $($qDirs.Name -join ', ')"
  Check ($bakFiles.Count -le 3) "expected <=3 .bak files retained, found $($bakFiles.Count): $($bakFiles.Name -join ', ')"
  # the newest pre-existing stamp (...05) and the brand-new run's own artifacts must survive; the oldest (...01/02/03) must be gone
  Check (-not (Test-Path (Join-Path $pluginsDir ".quarantine-superpowers-20260601T000000Z"))) "oldest quarantine dir was not pruned"
  Check (-not (Test-Path (Join-Path $pluginsDir "installed_plugins.json.bak-20260601T000000Z"))) "oldest .bak file was not pruned"
}
finally {
  Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}

if ($fails.Count -gt 0) { Write-Host "FAIL: $($fails.Count) check(s) failed"; exit 1 }
Write-Host "PASS: pin-local-fork-install prunes quarantine dirs + .bak files to the retention limit"
exit 0
