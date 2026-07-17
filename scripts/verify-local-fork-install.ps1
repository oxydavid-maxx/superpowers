<#
.SYNOPSIS
  Verify exact, contained, non-link-following Claude and Codex Superpowers installs.

.NOTES
  Verification covers Git commit identity, approved package digest, every tracked file byte,
  complete non-Git file enumeration, manifests, active metadata, and required skill semantics.
  It intentionally does not attest ACLs, alternate data streams, hardlink topology beyond
  rejecting multi-hardlink managed files, or timestamps.
#>
param(
  [string]$ClaudeHome = "$env:USERPROFILE\.claude",
  [string]$CodexHome = "$env:USERPROFILE\.codex",
  [string]$ExpectedVersion = "",
  [string]$ExpectedSourceCommit = "",
  [string]$ExpectedPackageDigest = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-fork-security.ps1")
$errors = New-Object System.Collections.Generic.List[string]

function Add-VerificationError([string]$message) {
  $script:errors.Add($message) | Out-Null
}

function Assert-ActiveMetadataTarget([string]$current) {
  $metadataPath = Join-Path $current ".superpowers-active.json"
  $metadata = Get-Content -Raw -LiteralPath $metadataPath -Encoding utf8 | ConvertFrom-Json
  if (-not (Get-SPCanonicalPath ([string]$metadata.target)).Equals((Get-SPCanonicalPath $current), [StringComparison]::OrdinalIgnoreCase)) {
    throw "active metadata target escapes or disagrees with current checkout: $current"
  }
}

try {
  Assert-SPValidVersion $ExpectedVersion
  if ($ExpectedSourceCommit -notmatch "^[0-9a-fA-F]{40,64}$") {
    throw "ExpectedSourceCommit is required and must be a full source commit approval token"
  }
  $ExpectedSourceCommit = $ExpectedSourceCommit.ToLowerInvariant()
  if ($ExpectedPackageDigest -ne (Get-SPApprovedPackageDigest)) {
    throw "ExpectedPackageDigest must equal approved package digest $(Get-SPApprovedPackageDigest)"
  }
  $homes = Assert-SPDistinctHomes $ClaudeHome $CodexHome
  $ClaudeHome = $homes.Claude
  $CodexHome = $homes.Codex

  $claudeBase = Join-Path $ClaudeHome "plugins\cache\superpowers-dev\superpowers"
  $codexBase = Join-Path $CodexHome "plugins\cache\superpowers-dev\superpowers"
  $claudeCurrent = Join-Path $claudeBase "current"
  $codexCurrent = Join-Path $codexBase "current"
  $claudeVersioned = Join-Path $claudeBase $ExpectedVersion
  $codexVersioned = Join-Path $codexBase $ExpectedVersion

  foreach ($base in @($claudeBase, $codexBase)) {
    Assert-SPNoReparseAncestors $base "installed cache"
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { throw "installed cache missing: $base" }
    Assert-SPPlainTree $base "installed cache"
  }
  foreach ($checkout in @($claudeCurrent, $codexCurrent, $claudeVersioned, $codexVersioned)) {
    $checkoutRoot = if ($checkout.StartsWith($claudeBase, [StringComparison]::OrdinalIgnoreCase)) { $claudeBase } else { $codexBase }
    Assert-SPContained $checkoutRoot $checkout "checkout containment"
    $item = Get-SPItem $checkout
    if ($null -eq $item -or -not $item.PSIsContainer -or (Test-SPReparseItem $item)) {
      throw "checkout must be a regular contained directory: $checkout"
    }
  }

  $claudeInfo = Get-SPCheckoutInfo $claudeCurrent $ExpectedSourceCommit $ExpectedPackageDigest $ExpectedVersion $true
  $codexInfo = Get-SPCheckoutInfo $codexCurrent $ExpectedSourceCommit $ExpectedPackageDigest $ExpectedVersion $true
  Get-SPCheckoutInfo $claudeVersioned $ExpectedSourceCommit $ExpectedPackageDigest $ExpectedVersion $false | Out-Null
  Get-SPCheckoutInfo $codexVersioned $ExpectedSourceCommit $ExpectedPackageDigest $ExpectedVersion $false | Out-Null
  Assert-ActiveMetadataTarget $claudeCurrent
  Assert-ActiveMetadataTarget $codexCurrent

  $installedPath = Join-Path $ClaudeHome "plugins\installed_plugins.json"
  Assert-SPNoReparseAncestors $installedPath "Claude installed manifest"
  Assert-SPSingleLinkFile $installedPath "Claude installed manifest"
  if (-not (Test-Path -LiteralPath $installedPath -PathType Leaf)) { throw "Claude installed manifest missing: $installedPath" }
  $installed = Get-Content -Raw -LiteralPath $installedPath -Encoding utf8 | ConvertFrom-Json
  if ($null -eq $installed.plugins) { throw "Claude installed manifest has no plugins object" }
  $pluginNames = @($installed.plugins.PSObject.Properties.Name)
  if ($pluginNames -contains "superpowers@claude-plugins-official") {
    throw "Claude still has official Superpowers installed"
  }
  if ($pluginNames -notcontains "superpowers@superpowers-dev") {
    throw "Claude is missing superpowers@superpowers-dev"
  }
  $entries = @($installed.plugins."superpowers@superpowers-dev")
  if ($entries.Count -ne 1) { throw "Claude fork manifest must contain exactly one install entry" }
  $entry = $entries[0]
  $expectedClaudeCurrent = Get-SPCanonicalPath $claudeCurrent
  if (-not (Get-SPCanonicalPath ([string]$entry.installPath)).Equals($expectedClaudeCurrent, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Claude installPath is outside the exact contained current checkout: $($entry.installPath)"
  }
  if ($entry.version -ne $ExpectedVersion -or $entry.gitCommitSha -ne $ExpectedSourceCommit -or
      $entry.gitTreeSha -ne $claudeInfo.Tree -or $entry.packageDigest -ne $ExpectedPackageDigest) {
    throw "Claude installed manifest identity mismatch"
  }

  foreach ($official in @(
    (Join-Path $ClaudeHome "plugins\cache\claude-plugins-official\superpowers"),
    (Join-Path $CodexHome "plugins\cache\claude-plugins-official\superpowers")
  )) {
    Assert-SPNoReparseAncestors $official "official cache"
    if ($null -ne (Get-SPItem $official)) { throw "official Superpowers cache remains: $official" }
  }

  $registry = Join-Path $ClaudeHome "skills\registry.yaml"
  Assert-SPNoReparseAncestors $registry "Claude skill registry"
  Assert-SPSingleLinkFile $registry "Claude skill registry"
  if (Test-Path -LiteralPath $registry -PathType Leaf) {
    $registryContent = Get-Content -Raw -LiteralPath $registry -Encoding utf8
    if ($registryContent -match "superpowers-dev\\superpowers\\(?!current\\)") {
      throw "Claude skill registry hard-pins a version instead of current"
    }
    if ($registryContent -notmatch "superpowers-dev\\superpowers\\current\\skills\\using-superpowers\\SKILL\.md") {
      throw "Claude skill registry does not point using-superpowers at current"
    }
  }
} catch {
  Add-VerificationError $_.Exception.Message
}

if ($errors.Count -gt 0) {
  Write-Host "FAIL: local Superpowers install failed exact verification"
  foreach ($errorMessage in $errors) { Write-Host "  - $errorMessage" }
  exit 1
}

Write-Host "PASS: exact Claude/Codex Superpowers install verified at $ExpectedSourceCommit ($ExpectedPackageDigest)"
exit 0
