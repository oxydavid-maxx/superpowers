param([switch]$Child)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $root "scripts\local-fork-security.ps1")
$commit = (& git -C $root rev-parse HEAD).Trim()
$digest = (Get-SPCommitPackageInfo $root $commit).Digest

if ($Child) {
  Write-Output $digest
  exit 0
}

$windowsPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
$legacyDigest = (& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Child).Trim()
if ($LASTEXITCODE -ne 0) {
  throw "Windows PowerShell digest probe failed with exit $LASTEXITCODE"
}
if ($digest -ne $legacyDigest) {
  throw "package digest differs across PowerShell engines: pwsh=$digest windows-powershell=$legacyDigest"
}
if ($digest -ne (Get-SPApprovedPackageDigest)) {
  throw "approved package digest does not match deterministic commit package digest: $digest"
}

Write-Host "PASS: package digest is deterministic across PowerShell engines ($digest)"
