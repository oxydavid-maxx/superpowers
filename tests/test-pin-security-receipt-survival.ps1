param(
  [string]$ReceiptRoot = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$harnessPath = Join-Path $repoRoot "tests\test-pin-security-recovery.ps1"
$harness = Get-Content -Raw -LiteralPath $harnessPath -Encoding utf8

$persistMatch = [regex]::Match(
  $harness,
  '(?ms)^  \$receiptPath = Join-Path \$receipts "security-recovery-receipt\.json".*?(?=^  if \(\$fails\.Count -gt 0\))'
)
if (-not $persistMatch.Success) {
  throw "cannot locate the exact security receipt persistence block"
}
$cleanupMatch = [regex]::Match($harness, '(?ms)^\} finally \{\r?\n  if \(-not \$KeepArtifacts')
if (-not $cleanupMatch.Success) {
  throw "cannot locate the security harness disposable-root cleanup"
}
if ($persistMatch.Index -gt $cleanupMatch.Index) {
  throw "security receipt persistence occurs after disposable cleanup"
}

$testTemp = if (Test-Path -LiteralPath "C:\tmp" -PathType Container) { "C:\tmp" } else { $env:TEMP }
if (-not $ReceiptRoot) {
  $ReceiptRoot = Join-Path $testTemp ("sp-receipt-survival-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
}
if (Test-Path -LiteralPath $ReceiptRoot) {
  throw "ReceiptRoot must not already exist: $ReceiptRoot"
}

$tmp = New-Item -ItemType Directory -Force -Path $ReceiptRoot
$receipts = Join-Path $tmp "receipts"
New-Item -ItemType Directory -Force -Path $receipts | Out-Null
$KeepArtifacts = $false
$ReceiptOutput = ""
$fails = New-Object System.Collections.Generic.List[string]
$receipt = [ordered]@{
  schema_version = "1.0"
  receipt_harness_iteration = "focus-attempt-9-durable-bound"
  finding_failures = @()
}

try {
  # Execute the harness's actual persistence block, then its exact disposable-root cleanup effect.
  . ([scriptblock]::Create($persistMatch.Value))
  if ($reportedReceiptPath -eq $receiptPath) {
    throw "harness reported the disposable receipt path"
  }
  $reportedFull = [IO.Path]::GetFullPath($reportedReceiptPath)
  $tmpFull = [IO.Path]::GetFullPath([string]$tmp)
  if ($reportedFull.StartsWith($tmpFull + "\", [StringComparison]::OrdinalIgnoreCase)) {
    throw "harness reported receipt remains inside disposable ReceiptRoot"
  }
  if (-not (Test-Path -LiteralPath $reportedFull -PathType Leaf)) {
    throw "durable receipt was not written before cleanup"
  }
  Remove-Item -Recurse -Force -LiteralPath $tmp
  if (Test-Path -LiteralPath $tmp) {
    throw "disposable ReceiptRoot cleanup did not complete"
  }
  if (-not (Test-Path -LiteralPath $reportedFull -PathType Leaf)) {
    throw "printed receipt did not survive disposable ReceiptRoot cleanup"
  }
  $survived = Get-Content -Raw -LiteralPath $reportedFull -Encoding utf8 | ConvertFrom-Json
  if ($survived.receipt_harness_iteration -ne "focus-attempt-9-durable-bound") {
    throw "surviving receipt has wrong harness iteration"
  }
  Write-Host "PASS: security receipt survives default cleanup"
  Write-Host "RECEIPT: $reportedFull"
} finally {
  if (Test-Path -LiteralPath $tmp) {
    Remove-Item -Recurse -Force -LiteralPath $tmp
  }
}
