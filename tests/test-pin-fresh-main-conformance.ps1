$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pinText = Get-Content -Raw -LiteralPath (Join-Path $root "scripts\pin-local-fork-install.ps1")
. (Join-Path $root "scripts\local-fork-security.ps1")

$tempBase = if (Test-Path -LiteralPath "C:\tmp" -PathType Container) { "C:\tmp" } else { $env:TEMP }
$tmp = Join-Path $tempBase ("sp-fresh-main-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$bare = Join-Path $tmp "origin.git"
$seed = Join-Path $tmp "seed"
$consumer = Join-Path $tmp "consumer"
$advancer = Join-Path $tmp "advancer"
$sentinel = Join-Path $tmp "active-current-sentinel.bin"

function Commit-File([string]$repo, [string]$name, [string]$content, [string]$message) {
  Set-Content -LiteralPath (Join-Path $repo $name) -Value $content -Encoding utf8
  & git -C $repo add $name
  & git -C $repo commit --quiet -m $message
  return (& git -C $repo rev-parse HEAD).Trim()
}

try {
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  & git init --bare --quiet $bare
  & git init --quiet $seed
  & git -C $seed config user.email "fresh-main@example.invalid"
  & git -C $seed config user.name "Fresh Main Test"
  $base = Commit-File $seed "base.txt" "base" "base"
  & git -C $seed branch -M main
  & git -C $seed remote add origin $bare
  & git -C $seed push --quiet -u origin main
  & git --git-dir=$bare symbolic-ref HEAD refs/heads/main

  & git clone --quiet $bare $consumer
  & git -C $consumer config user.email "fresh-main@example.invalid"
  & git -C $consumer config user.name "Fresh Main Test"
  & git -C $consumer checkout --quiet -b candidate $base
  $staleCandidate = Commit-File $consumer "candidate.txt" "candidate" "stale candidate"

  & git clone --quiet $bare $advancer
  & git -C $advancer config user.email "fresh-main@example.invalid"
  & git -C $advancer config user.name "Fresh Main Test"
  $freshMain = Commit-File $advancer "remote-main.txt" "advanced" "advance remote main"
  & git -C $advancer push --quiet origin main

  $staleTracking = Get-SPCanonicalIntegrationBase $consumer
  if ($staleTracking -ne $base) { throw "test setup did not preserve a stale local origin/main" }
  Assert-SPPromotionLineage $consumer $staleCandidate $staleTracking @()

  [IO.File]::WriteAllBytes($sentinel, [byte[]](2, 0, 2, 6, 255))
  $before = (Get-FileHash -Algorithm SHA256 -LiteralPath $sentinel).Hash.ToLowerInvariant()

  if (-not (Get-Command Get-SPFreshCanonicalIntegrationBase -ErrorAction SilentlyContinue)) {
    throw "pin authority is missing fresh canonical-main proof"
  }
  $proof = Get-SPFreshCanonicalIntegrationBase $consumer
  if ($proof.Commit -ne $freshMain -or $proof.Method -ne "git-fetch-origin-main") {
    throw "fresh canonical-main proof did not bind exact remote main"
  }
  $rejected = $false
  try { Assert-SPPromotionLineage $consumer $staleCandidate $proof.Commit @() }
  catch { $rejected = $_.Exception.Message -like "*canonical integration base*" }
  if (-not $rejected) { throw "candidate descending only stale origin/main was accepted" }
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $sentinel).Hash.ToLowerInvariant() -ne $before) {
    throw "fresh-main rejection mutated the active-current sentinel"
  }

  & git -C $consumer checkout --quiet -b fresh-descendant $proof.Commit
  $freshDescendant = Commit-File $consumer "fresh-candidate.txt" "fresh" "fresh descendant"
  Assert-SPPromotionLineage $consumer $freshDescendant $proof.Commit @()

  $proofIndex = $pinText.IndexOf("Get-SPFreshCanonicalIntegrationBase")
  $assetIndex = $pinText.IndexOf('$runId = [DateTime]::UtcNow')
  if ($proofIndex -lt 0 -or $assetIndex -lt 0 -or $proofIndex -gt $assetIndex) {
    throw "production pin must bind fresh remote main before transaction assets"
  }

  Write-Host "PASS: stale tracking ref rejected after one fresh remote-main proof"
} finally {
  if (Test-Path -LiteralPath $tmp) { Remove-Item -Recurse -Force -LiteralPath $tmp }
}
