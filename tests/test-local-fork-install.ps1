<#
  Temp-home regression for pin-local-fork-install.ps1 (UPG-F2). Seeds a DIRTY install
  (official Superpowers entry + stale fork cache + official cache + a second unrelated
  plugin), runs the pin workflow against TEMP homes, and proves the falsification set is
  closed: official removed, stale/official caches quarantined (moved, not deleted), installPath
  is the stable current pointer, current resolves to the versioned cache, version/HEAD metadata
  matches, unrelated plugin preserved, and re-run is idempotent. Never touches the real ~/.claude
  or ~/.codex.
#>
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$pin    = Join-Path $root "scripts\pin-local-fork-install.ps1"
$expected = (Get-Content -Raw -LiteralPath (Join-Path $root ".claude-plugin\plugin.json") | ConvertFrom-Json).version
$sourceHead = (& git -C $root rev-parse HEAD).Trim()
$fails = New-Object System.Collections.Generic.List[string]
function Check($cond, $msg) { if (-not $cond) { $fails.Add($msg) | Out-Null; Write-Host "  FAIL: $msg" } }
function ResolvedTarget([string]$path) {
  $item = Get-Item -LiteralPath $path -Force
  if ($item.LinkType -and $item.Target) {
    return (Resolve-Path -LiteralPath $item.Target).Path
  }
  return (Resolve-Path -LiteralPath $path).Path
}

$tmp = Join-Path $env:TEMP ("pinfork-test-" + (Get-Random))
$claude = Join-Path $tmp "claude"
$codex  = Join-Path $tmp "codex"
try {
  # --- seed a DIRTY install ---
  New-Item -ItemType Directory -Force -Path (Join-Path $claude "plugins\cache\superpowers-dev\superpowers\6.0.3-vmodel.0") | Out-Null
  New-Item -ItemType File -Force -Path (Join-Path $claude "plugins\cache\superpowers-dev\superpowers\6.0.3-vmodel.0\.in_use") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $claude "plugins\cache\claude-plugins-official\superpowers\6.0.3") | Out-Null
  New-Item -ItemType File -Force -Path (Join-Path $claude "plugins\cache\claude-plugins-official\superpowers\6.0.3\.in_use") | Out-Null
  $ipj = Join-Path $claude "plugins\installed_plugins.json"
  @'
{ "version": 2, "plugins": {
  "superpowers@claude-plugins-official": [ { "scope": "user", "installPath": "x", "version": "6.0.3" } ],
  "superpowers@superpowers-dev": [ { "scope": "user", "installPath": "old", "version": "6.0.3-vmodel.0" } ],
  "other-plugin@somewhere": [ { "scope": "user", "installPath": "keepme", "version": "1.0.0" } ]
} }
'@ | Set-Content -LiteralPath $ipj -Encoding utf8
  New-Item -ItemType Directory -Force -Path (Join-Path $codex "plugins\cache\superpowers-dev\superpowers\6.0.3-vmodel.0") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $codex "plugins\cache\claude-plugins-official\superpowers") | Out-Null

  # --- run pin (it calls the verifier internally) ---
  & $pin -ClaudeHome $claude -CodexHome $codex -SourceRepo $root -ExpectedVersion $expected | Out-Null
  Check ($LASTEXITCODE -eq 0) "pin run #1 (with internal verify) exited $LASTEXITCODE"

  $d = Get-Content -Raw -LiteralPath $ipj | ConvertFrom-Json
  $names = @($d.plugins.PSObject.Properties.Name)
  Check (-not ($names -contains "superpowers@claude-plugins-official")) "official entry still in installed_plugins.json"
  Check ($names -contains "other-plugin@somewhere") "unrelated plugin was dropped (must be preserved)"
  $entry = @($d.plugins."superpowers@superpowers-dev")[0]
  Check ($entry.version -eq $expected) "fork version not $expected (got $($entry.version))"
  Check ($entry.installPath -match "\\current$") "installPath not the stable current pointer: $($entry.installPath)"
  Check ($entry.gitCommitSha -eq $sourceHead) "gitCommitSha not source HEAD"

  $active = Join-Path $claude "plugins\cache\superpowers-dev\superpowers\$expected"
  $current = Join-Path $claude "plugins\cache\superpowers-dev\superpowers\current"
  Check (Test-Path -LiteralPath $current) "Claude current pointer missing"
  Check ((ResolvedTarget $current) -eq (Resolve-Path -LiteralPath $active).Path) "Claude current pointer does not resolve to active version"
  Check (Test-Path (Join-Path $current ".in_use")) "active current pointer missing .in_use"
  $activeMeta = Get-Content -Raw -LiteralPath (Join-Path $current ".superpowers-active.json") | ConvertFrom-Json
  Check ($activeMeta.version -eq $expected) "active metadata version mismatch"
  Check ($activeMeta.gitCommitSha -eq $sourceHead) "active metadata gitCommitSha mismatch"
  Check (-not (Test-Path (Join-Path $claude "plugins\cache\superpowers-dev\superpowers\6.0.3-vmodel.0"))) "stale fork cache not quarantined (still under cache)"
  Check (-not (Test-Path (Join-Path $claude "plugins\cache\claude-plugins-official\superpowers\6.0.3"))) "official cache not quarantined"
  $q = Get-ChildItem -Path $claude -Filter ".quarantine-superpowers-*" -Directory -Recurse -ErrorAction SilentlyContinue
  Check ($q.Count -ge 1) "no quarantine dir created (caches should be moved, not deleted)"
  $cacheHead = (& git -C $active rev-parse HEAD 2>$null).Trim()
  Check ($cacheHead -eq $sourceHead) "active cache HEAD ($cacheHead) != source HEAD ($sourceHead)"

  $codexCurrent = Join-Path $codex "plugins\cache\superpowers-dev\superpowers\current"
  $codexActive = Join-Path $codex "plugins\cache\superpowers-dev\superpowers\$expected"
  Check (Test-Path -LiteralPath $codexCurrent) "Codex current pointer missing"
  Check ((ResolvedTarget $codexCurrent) -eq (Resolve-Path -LiteralPath $codexActive).Path) "Codex current pointer does not resolve to active version"

  # --- idempotency: re-run must still verify green and not throw ---
  & $pin -ClaudeHome $claude -CodexHome $codex -SourceRepo $root -ExpectedVersion $expected | Out-Null
  Check ($LASTEXITCODE -eq 0) "pin run #2 (idempotent) exited $LASTEXITCODE"
  & (Join-Path $root "scripts\verify-local-fork-install.ps1") -ClaudeHome $claude -CodexHome $codex -ExpectedVersion $expected | Out-Null
  Check ($LASTEXITCODE -eq 0) "verifier after idempotent re-run exited $LASTEXITCODE"
}
finally {
  Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}

if ($fails.Count -gt 0) { Write-Host "FAIL: $($fails.Count) check(s) failed"; exit 1 }
Write-Host "PASS: pin-local-fork-install temp-home regression ($expected @ $sourceHead) — official removed, stable current pointer active, caches quarantined, idempotent"
exit 0
