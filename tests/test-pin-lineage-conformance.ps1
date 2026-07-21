$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$security = Join-Path $root "scripts\local-fork-security.ps1"
$pinText = Get-Content -Raw -LiteralPath (Join-Path $root "scripts\pin-local-fork-install.ps1")
. $security

if (-not (Get-Command Assert-SPPromotionLineage -ErrorAction SilentlyContinue)) {
  throw "pin authority is missing Assert-SPPromotionLineage"
}

$tempBase = if (Test-Path -LiteralPath "C:\tmp" -PathType Container) { "C:\tmp" } else { $env:TEMP }
$tmp = Join-Path $tempBase ("sp-lineage-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$repo = Join-Path $tmp "repo"
$sentinel = Join-Path $tmp "active-current-sentinel.bin"

try {
  New-Item -ItemType Directory -Force -Path $repo | Out-Null
  & git -C $repo init --quiet
  & git -C $repo config user.email "lineage-test@example.invalid"
  & git -C $repo config user.name "Lineage Test"
  Set-Content -LiteralPath (Join-Path $repo "base.txt") -Value "base" -Encoding utf8
  & git -C $repo add base.txt
  & git -C $repo commit --quiet -m "base"
  $base = (& git -C $repo rev-parse HEAD).Trim()

  & git -C $repo checkout --quiet -b canonical
  Set-Content -LiteralPath (Join-Path $repo "canonical.txt") -Value "central hooks" -Encoding utf8
  & git -C $repo add canonical.txt
  & git -C $repo commit --quiet -m "canonical integration base"
  $canonical = (& git -C $repo rev-parse HEAD).Trim()

  & git -C $repo checkout --quiet -b installed $base
  Set-Content -LiteralPath (Join-Path $repo "installed.txt") -Value "lifecycle release" -Encoding utf8
  & git -C $repo add installed.txt
  & git -C $repo commit --quiet -m "installed sibling"
  $installed = (& git -C $repo rev-parse HEAD).Trim()

  [IO.File]::WriteAllBytes($sentinel, [byte[]](1, 3, 3, 7, 255))
  $before = (Get-FileHash -Algorithm SHA256 -LiteralPath $sentinel).Hash.ToLowerInvariant()

  $rejected = $false
  try {
    Assert-SPPromotionLineage $repo $installed $canonical @($installed)
  } catch {
    $rejected = $_.Exception.Message -like "*canonical integration base*"
  }
  if (-not $rejected) { throw "stale sibling promotion was not rejected" }
  $afterReject = (Get-FileHash -Algorithm SHA256 -LiteralPath $sentinel).Hash.ToLowerInvariant()
  if ($afterReject -ne $before) { throw "lineage rejection mutated the active-current sentinel" }

  & git -C $repo checkout --quiet -b integrated $canonical
  & git -C $repo merge --quiet --no-ff $installed -m "integrated descendant"
  $integrated = (& git -C $repo rev-parse HEAD).Trim()
  Assert-SPPromotionLineage $repo $integrated $canonical @($installed)

  $callIndex = $pinText.IndexOf("Assert-SPPromotionLineage")
  $assetIndex = $pinText.IndexOf('$runId = [DateTime]::UtcNow')
  if ($callIndex -lt 0 -or $assetIndex -lt 0 -or $callIndex -gt $assetIndex) {
    throw "production pin must check promotion lineage before creating transaction assets"
  }

  Write-Host "PASS: stale sibling rejected before mutation; integrated descendant accepted"
} finally {
  if (Test-Path -LiteralPath $tmp) {
    Remove-Item -Recurse -Force -LiteralPath $tmp
  }
}
