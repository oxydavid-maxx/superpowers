param(
  [string]$ReceiptRoot = "",
  [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pin = Join-Path $root "scripts\pin-local-fork-install.ps1"
$verify = Join-Path $root "scripts\verify-local-fork-install.ps1"
$expected = (Get-Content -Raw -LiteralPath (Join-Path $root ".claude-plugin\plugin.json") | ConvertFrom-Json).version
$approvedDigest = "6bf5e9a3d4bf019b8a136f21b6c378135d11c84ae5d864075652a906e2c6eb39"
$legacyVersion = "6.0.3-vmodel.17"
$legacyPackName = "pack-d42d000000000000000000000000000000000000.rev"
$fails = New-Object System.Collections.Generic.List[string]

function Check([bool]$condition, [string]$message) {
  if (-not $condition) {
    $script:fails.Add($message) | Out-Null
    Write-Host "  FAIL: $message"
  }
}

function Get-StringSha256([string]$text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-StateFingerprint([string]$homePath) {
  if (-not (Test-Path -LiteralPath $homePath)) { return Get-StringSha256 "ABSENT" }

  $records = New-Object System.Collections.Generic.List[string]
  function Walk([string]$path) {
    $item = Get-Item -LiteralPath $path -Force
    $relative = $path.Substring($homePath.Length).TrimStart("\").Replace("\", "/")
    if ($relative -eq ".superpowers-pin" -or $relative.StartsWith(".superpowers-pin/")) { return }
    if ($item.LinkType) {
      $target = @($item.Target) -join ";"
      $records.Add("L|$relative|$target") | Out-Null
      return
    }
    if ($item.PSIsContainer) {
      $records.Add("D|$relative") | Out-Null
      foreach ($child in @(Get-ChildItem -LiteralPath $path -Force | Sort-Object Name)) {
        Walk $child.FullName
      }
      return
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
    $records.Add("F|$relative|$($item.Length)|$hash") | Out-Null
  }

  Walk $homePath
  return Get-StringSha256 (($records | Sort-Object) -join [Environment]::NewLine)
}

function Resolve-Target([string]$path) {
  $item = Get-Item -LiteralPath $path -Force
  if ($item.LinkType -and $item.Target) {
    return (Resolve-Path -LiteralPath $item.Target).Path
  }
  return (Resolve-Path -LiteralPath $path).Path
}

function Seed-OldHome([string]$homePath, [bool]$isClaude, [string]$sharedGitObject) {
  $base = Join-Path $homePath "plugins\cache\superpowers-dev\superpowers"
  $old = Join-Path $base $legacyVersion
  New-Item -ItemType Directory -Force -Path (Join-Path $old "skills\using-superpowers") | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $old "old-package.bin"), [byte[]](0, 1, 2, 3, 254, 255))
  Set-Content -LiteralPath (Join-Path $old "skills\using-superpowers\SKILL.md") -Value "legacy-vmodel.17" -Encoding utf8
  New-Item -ItemType Directory -Force -Path (Join-Path $old ".claude-plugin") | Out-Null
  @{ name = "superpowers"; version = $legacyVersion } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $old ".claude-plugin\plugin.json") -Encoding utf8
  $packDir = Join-Path $old ".git\objects\pack"
  New-Item -ItemType Directory -Force -Path $packDir | Out-Null
  $packFile = Join-Path $packDir $legacyPackName
  New-Item -ItemType HardLink -Path $packFile -Target $sharedGitObject | Out-Null
  $current = Join-Path $base "current"
  New-Item -ItemType Junction -Path $current -Target $old | Out-Null
  [IO.File]::WriteAllBytes((Join-Path $current "current-sentinel.bin"), [byte[]](9, 8, 7, 6, 255))

  $official = Join-Path $homePath "plugins\cache\claude-plugins-official\superpowers\6.0.3"
  New-Item -ItemType Directory -Force -Path $official | Out-Null
  Set-Content -LiteralPath (Join-Path $official "official-sentinel.txt") -Value "official-preserve" -Encoding utf8

  if ($isClaude) {
    $plugins = [ordered]@{}
    $plugins["superpowers@superpowers-dev"] = @([ordered]@{
      scope = "user"
      installPath = $current
      version = $legacyVersion
      gitCommitSha = "legacy-sha"
    })
    $plugins["other-plugin@somewhere"] = @([ordered]@{
      scope = "user"
      installPath = "keepme"
      version = "1.0.0"
    })
    $installed = [ordered]@{ version = 2; plugins = $plugins }
    $ipj = Join-Path $homePath "plugins\installed_plugins.json"
    New-Item -ItemType Directory -Force -Path (Split-Path $ipj) | Out-Null
    $installed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ipj -Encoding utf8

    $registry = Join-Path $homePath "skills\registry.yaml"
    New-Item -ItemType Directory -Force -Path (Split-Path $registry) | Out-Null
    Set-Content -LiteralPath $registry -Value ("using-superpowers: " + (Join-Path $old "skills\using-superpowers\SKILL.md")) -Encoding utf8
  }

  return [ordered]@{
    current = $current
    old = $old
    pack_file = $packFile
    sentinel_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $old "old-package.bin")).Hash.ToLowerInvariant()
    pack_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $packFile).Hash.ToLowerInvariant()
    current_sentinel_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $current "current-sentinel.bin")).Hash.ToLowerInvariant()
  }
}

function Get-PackageDigest([string]$base, [string[]]$relativePaths) {
  $records = New-Object System.Collections.Generic.List[string]
  foreach ($relative in @($relativePaths | Sort-Object)) {
    $path = Join-Path $base ($relative.Replace("/", "\"))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      $records.Add("MISSING|$relative") | Out-Null
      continue
    }
    $objectId = @(& git -C $base hash-object --no-filters -- $path)
    if ($LASTEXITCODE -ne 0 -or $objectId.Count -eq 0) {
      $records.Add("HASH-FAILED|$relative") | Out-Null
      continue
    }
    $records.Add("$relative|$($objectId[0].Trim())") | Out-Null
  }
  return Get-StringSha256 ($records -join [Environment]::NewLine)
}

function Get-CommitPackageDigest([string]$repo, [string]$commit, [string[]]$relativePaths) {
  $records = New-Object System.Collections.Generic.List[string]
  foreach ($relative in @($relativePaths | Sort-Object)) {
    $spec = "{0}:{1}" -f $commit, $relative
    $objectId = @(& git -C $repo rev-parse $spec 2>$null)
    if ($LASTEXITCODE -ne 0 -or $objectId.Count -eq 0) {
      $records.Add("MISSING|$relative") | Out-Null
      continue
    }
    $records.Add("$relative|$($objectId[0].Trim())") | Out-Null
  }
  return Get-StringSha256 ($records -join [Environment]::NewLine)
}

function Invoke-PinJson([string]$claudeHome, [string]$codexHome) {
  $output = @(& $pin -ClaudeHome $claudeHome -CodexHome $codexHome -SourceRepo $script:sourceRepo -ExpectedVersion $expected -ExpectedSourceCommit $script:sourceHead -ExpectedPackageDigest $approvedDigest)
  return (($output -join [Environment]::NewLine) | ConvertFrom-Json)
}

if (-not $ReceiptRoot) {
  $testTemp = if (Test-Path -LiteralPath "C:\tmp" -PathType Container) { "C:\tmp" } else { $env:TEMP }
  $ReceiptRoot = Join-Path $testTemp ("sp-txn-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
}
if (Test-Path -LiteralPath $ReceiptRoot) {
  throw "ReceiptRoot must not already exist: $ReceiptRoot"
}
$tmp = New-Item -ItemType Directory -Force -Path $ReceiptRoot
$claude = Join-Path $tmp "claude-home"
$codex = Join-Path $tmp "codex-home"
$receipts = Join-Path $tmp "receipts"
New-Item -ItemType Directory -Force -Path $receipts | Out-Null

try {
  Check ($expected -eq "6.0.3-native.20") "source version is '$expected', expected 6.0.3-native.20"

  $sharedObject = Join-Path $tmp ("shared-git-objects\" + $legacyPackName)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sharedObject) | Out-Null
  [IO.File]::WriteAllBytes($sharedObject, [byte[]](12, 34, 56, 78, 90, 210, 254, 255))
  $sharedObjectSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sharedObject).Hash.ToLowerInvariant()
  $seedClaude = Seed-OldHome $claude $true $sharedObject
  $seedCodex = Seed-OldHome $codex $false $sharedObject
  $beforeClaude = Get-StateFingerprint $claude
  $script:sourceRepo = Join-Path $tmp "source"
  & git -c core.autocrlf=false -c core.longpaths=true clone --no-local --no-hardlinks --quiet -- "$root" "$script:sourceRepo"
  if ($LASTEXITCODE -ne 0) { throw "cannot clone clean source" }
  $script:sourceHead = (& git --no-replace-objects -C $script:sourceRepo rev-parse HEAD).Trim()

  $beforeCodex = Get-StateFingerprint $codex

  $failureMessage = ""
  try {
    & $pin -ClaudeHome $claude -CodexHome $codex -SourceRepo $script:sourceRepo -ExpectedVersion $expected -ExpectedSourceCommit $script:sourceHead -ExpectedPackageDigest $approvedDigest -InjectFailureAt AfterCodex | Out-Null
    Check $false "injected failure did not fail"
  } catch {
    $failureMessage = $_.Exception.Message
  }
  $afterFailureClaude = Get-StateFingerprint $claude
  $afterFailureCodex = Get-StateFingerprint $codex
  Check ($failureMessage -like "*Injected failure at AfterCodex*") "missing deterministic injected failure; got '$failureMessage'"
  Check ($afterFailureClaude -eq $beforeClaude) "Claude home bytes/pointer were not restored after injected failure"
  Check ($afterFailureCodex -eq $beforeCodex) "Codex home bytes/pointer were not restored after injected failure"
  Check ((Get-Item -LiteralPath $seedClaude.current -Force).LinkType -eq "Junction") "Claude legacy current junction identity changed during rollback"
  Check ((Get-Item -LiteralPath $seedCodex.current -Force).LinkType -eq "Junction") "Codex legacy current junction identity changed during rollback"
  Check ((Resolve-Target $seedClaude.current) -eq (Resolve-Path -LiteralPath $seedClaude.old).Path) "Claude legacy current target changed during rollback"
  Check ((Resolve-Target $seedCodex.current) -eq (Resolve-Path -LiteralPath $seedCodex.old).Path) "Codex legacy current target changed during rollback"
  Check ((Get-Item -LiteralPath $seedClaude.pack_file -Force).LinkType -eq "HardLink") "Claude legacy Git object hardlink identity was not restored"
  Check ((Get-Item -LiteralPath $seedCodex.pack_file -Force).LinkType -eq "HardLink") "Codex legacy Git object hardlink identity was not restored"
  Check ((Get-FileHash -Algorithm SHA256 -LiteralPath $sharedObject).Hash.ToLowerInvariant() -eq $sharedObjectSha256) "shared Git object changed during rollback"
  Check ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $seedClaude.current "current-sentinel.bin")).Hash.ToLowerInvariant() -eq $seedClaude.current_sentinel_sha256) "Claude current preimage bytes were not restored"
  Check ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $seedCodex.current "current-sentinel.bin")).Hash.ToLowerInvariant() -eq $seedCodex.current_sentinel_sha256) "Codex current preimage bytes were not restored"

  $failureReceipt = [ordered]@{
    injection = "AfterCodex"
    message = $failureMessage
    claude_before = $beforeClaude
    claude_after = $afterFailureClaude
    codex_before = $beforeCodex
    codex_after = $afterFailureCodex
  }
  $failureReceiptPath = Join-Path $receipts "failure-receipt.json"
  $failureReceipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $failureReceiptPath -Encoding utf8

  $mismatchClaude = Join-Path $tmp "mismatch-claude"
  $mismatchCodex = Join-Path $tmp "mismatch-codex"
  $mismatchBeforeClaude = Get-StateFingerprint $mismatchClaude
  $mismatchBeforeCodex = Get-StateFingerprint $mismatchCodex
  $mismatchMessage = ""
  try {
    & $pin -ClaudeHome $mismatchClaude -CodexHome $mismatchCodex -SourceRepo $script:sourceRepo -ExpectedVersion $legacyVersion -ExpectedSourceCommit $script:sourceHead -ExpectedPackageDigest $approvedDigest | Out-Null
    Check $false "version masquerade was accepted"
  } catch {
    $mismatchMessage = $_.Exception.Message
  }
  Check ($mismatchMessage -like "*does not match source version*") "version mismatch was not rejected from source identity; got '$mismatchMessage'"
  Check ((Get-StateFingerprint $mismatchClaude) -eq $mismatchBeforeClaude) "version mismatch mutated Claude home"
  Check ((Get-StateFingerprint $mismatchCodex) -eq $mismatchBeforeCodex) "version mismatch mutated Codex home"

  $first = Invoke-PinJson $claude $codex
  Check ($first.version -eq $expected) "pin result version mismatch"
  Check ($first.source_head -eq $script:sourceHead) "pin result source HEAD mismatch"

  & $verify -ClaudeHome $claude -CodexHome $codex -ExpectedVersion $expected -ExpectedSourceCommit $script:sourceHead -ExpectedPackageDigest $approvedDigest
  Check ($LASTEXITCODE -eq 0) "verifier failed after successful pin"

  $claudeCurrent = Join-Path $claude "plugins\cache\superpowers-dev\superpowers\current"
  $codexCurrent = Join-Path $codex "plugins\cache\superpowers-dev\superpowers\current"
  $claudeTarget = (Resolve-Path -LiteralPath $claudeCurrent).Path
  $codexTarget = (Resolve-Path -LiteralPath $codexCurrent).Path
  $claudeVersioned = Join-Path (Split-Path -Parent $claudeCurrent) $expected
  $codexVersioned = Join-Path (Split-Path -Parent $codexCurrent) $expected
  Check (-not (Get-Item -LiteralPath $claudeTarget -Force).LinkType) "Claude current is a reparse point"
  Check (-not (Get-Item -LiteralPath $codexTarget -Force).LinkType) "Codex current is a reparse point"
  Check ($claudeTarget -ne (Resolve-Path -LiteralPath $claudeVersioned).Path) "Claude current is not a distinct exact checkout"
  Check ($codexTarget -ne (Resolve-Path -LiteralPath $codexVersioned).Path) "Codex current is not a distinct exact checkout"
  Check ($claudeTarget -notmatch [regex]::Escape($legacyVersion)) "Claude legacy vmodel.17 is still current"
  Check ($codexTarget -notmatch [regex]::Escape($legacyVersion)) "Codex legacy vmodel.17 is still current"

  $tracked = @(& git -C $script:sourceRepo ls-files -- ".claude-plugin/plugin.json" ".codex-plugin/plugin.json" "skills")
  $sourceDigest = Get-CommitPackageDigest $script:sourceRepo $script:sourceHead $tracked
  $claudeDigest = Get-PackageDigest $claudeTarget $tracked
  $codexDigest = Get-PackageDigest $codexTarget $tracked
  Check ($claudeDigest -eq $sourceDigest) "Claude manifest/skills digest does not match source bytes"
  Check ($codexDigest -eq $sourceDigest) "Codex manifest/skills digest does not match source bytes"

  $claudeHead = (& git -C $claudeTarget rev-parse HEAD).Trim()
  $codexHead = (& git -C $codexTarget rev-parse HEAD).Trim()
  Check ($claudeHead -eq $script:sourceHead) "Claude cache HEAD mismatch"
  Check ($codexHead -eq $script:sourceHead) "Codex cache HEAD mismatch"

  $using = Get-Content -Raw -LiteralPath (Join-Path $claudeTarget "skills\using-superpowers\SKILL.md") -Encoding utf8
  $brainstorming = Get-Content -Raw -LiteralPath (Join-Path $claudeTarget "skills\brainstorming\SKILL.md") -Encoding utf8
  $writingPlans = Get-Content -Raw -LiteralPath (Join-Path $claudeTarget "skills\writing-plans\SKILL.md") -Encoding utf8
  Check ($brainstorming.Contains("never by a required reviewer persona")) "brainstorming lost native.18 reviewer-neutral semantics"
  Check ($using.Contains("current host session")) "using-superpowers lost native host ownership"
  Check ($using.IndexOf("| S0_APPROVE |") -lt $using.IndexOf("| S0_SOTA |")) "using-superpowers stage order drifted from canonical SPG"
  Check ($writingPlans.Contains("FOCUS =")) "writing-plans missing FOCUS"
  Check ($writingPlans.Contains("RC =")) "writing-plans missing RC"
  Check ($writingPlans -notmatch '(?<![A-Za-z0-9_])T[0-3](?![A-Za-z0-9_])') "writing-plans resurrected retired tiers"

  $forbidden = @(
    "dispatch-policy.yaml",
    "requested_model",
    "actual_served_model",
    "critic-dispatch-r1.json",
    "Critic identity",
    "builder_session",
    "Dispatch a code reviewer subagent",
    "Always use subagents",
    "Run pressure scenario with subagent"
  )
  $forbiddenPatterns = @(
    '\b(?:Agent|Task)\(',
    '(?i)\bSendMessage\b',
    '(?i)\b(?:thread_id|builder_session|resume)\s*=',
    '(?<![A-Za-z0-9_])T[0-3](?![A-Za-z0-9_])'
  )
  $activeForbiddenHits = New-Object System.Collections.Generic.List[string]
  foreach ($skillFile in @(Get-ChildItem -LiteralPath (Join-Path $claudeTarget "skills") -Filter "SKILL.md" -Recurse -File)) {
    $text = Get-Content -Raw -LiteralPath $skillFile.FullName -Encoding utf8
    foreach ($phrase in $forbidden) {
      if ($text.Contains($phrase)) {
        $activeForbiddenHits.Add("$($skillFile.FullName):$phrase") | Out-Null
      }
    }
    foreach ($pattern in $forbiddenPatterns) {
      if ($text -match $pattern) {
        $activeForbiddenHits.Add("$($skillFile.FullName):regex:$pattern") | Out-Null
      }
    }
  }
  $legacySdd = Get-Content -Raw -LiteralPath (Join-Path $claudeTarget "skills\subagent-driven-development\SKILL.md") -Encoding utf8
  Check ($activeForbiddenHits.Count -eq 0) "active forced-orchestration scan found: $($activeForbiddenHits -join '; ')"
  Check ($legacySdd -notmatch '(?i)\bmodel\b') "legacy explicit-request skill resurrected model pinning"

  $claudePreserved = @(Get-ChildItem -LiteralPath $claude -Recurse -File -Filter "old-package.bin" | Where-Object { $_.FullName -match "quarantine-superpowers" })
  $codexPreserved = @(Get-ChildItem -LiteralPath $codex -Recurse -File -Filter "old-package.bin" | Where-Object { $_.FullName -match "quarantine-superpowers" })
  Check ($claudePreserved.Count -eq 1) "Claude legacy package was not preserved exactly once in quarantine"
  Check ($codexPreserved.Count -eq 1) "Codex legacy package was not preserved exactly once in quarantine"
  if ($claudePreserved.Count -eq 1) {
    Check ((Get-FileHash -Algorithm SHA256 -LiteralPath $claudePreserved[0].FullName).Hash.ToLowerInvariant() -eq $seedClaude.sentinel_sha256) "Claude preserved legacy bytes changed"
  }
  if ($codexPreserved.Count -eq 1) {
    Check ((Get-FileHash -Algorithm SHA256 -LiteralPath $codexPreserved[0].FullName).Hash.ToLowerInvariant() -eq $seedCodex.sentinel_sha256) "Codex preserved legacy bytes changed"
  }

  $claudePackPreserved = @(Get-ChildItem -LiteralPath $claude -Recurse -File -Filter $legacyPackName | Where-Object { $_.FullName -match "quarantine-superpowers" })
  $codexPackPreserved = @(Get-ChildItem -LiteralPath $codex -Recurse -File -Filter $legacyPackName | Where-Object { $_.FullName -match "quarantine-superpowers" })
  Check ($claudePackPreserved.Count -eq 1) "Claude detached legacy Git object was not quarantined exactly once"
  Check ($codexPackPreserved.Count -eq 1) "Codex detached legacy Git object was not quarantined exactly once"
  foreach ($detached in @($claudePackPreserved) + @($codexPackPreserved)) {
    Check (-not (Get-Item -LiteralPath $detached.FullName -Force).LinkType) "quarantined legacy Git object retained external hardlink identity: $($detached.FullName)"
    Check ((Get-FileHash -Algorithm SHA256 -LiteralPath $detached.FullName).Hash.ToLowerInvariant() -eq $sharedObjectSha256) "detached legacy Git object bytes changed: $($detached.FullName)"
  }
  Check ((Get-FileHash -Algorithm SHA256 -LiteralPath $sharedObject).Hash.ToLowerInvariant() -eq $sharedObjectSha256) "external shared Git object changed during verified finalization"

  $firstClaudeTarget = $claudeTarget
  $firstCodexTarget = $codexTarget
  $firstClaudeDigest = $claudeDigest
  $firstCodexDigest = $codexDigest
  $second = Invoke-PinJson $claude $codex
  $secondClaudeTarget = Resolve-Target $claudeCurrent
  $secondCodexTarget = Resolve-Target $codexCurrent
  Check ($second.source_head -eq $script:sourceHead) "idempotent rerun source HEAD changed"
  Check ($secondClaudeTarget -eq $firstClaudeTarget) "idempotent rerun changed Claude current target"
  Check ($secondCodexTarget -eq $firstCodexTarget) "idempotent rerun changed Codex current target"
  Check ((Get-PackageDigest $secondClaudeTarget $tracked) -eq $firstClaudeDigest) "idempotent rerun changed Claude source bytes"
  Check ((Get-PackageDigest $secondCodexTarget $tracked) -eq $firstCodexDigest) "idempotent rerun changed Codex source bytes"

  $claudeMetaSource = Join-Path $claudeCurrent ".superpowers-active.json"
  $codexMetaSource = Join-Path $codexCurrent ".superpowers-active.json"
  $claudeManifestPath = Join-Path $receipts "claude-active-manifest.json"
  $codexManifestPath = Join-Path $receipts "codex-active-manifest.json"
  Copy-Item -LiteralPath $claudeMetaSource -Destination $claudeManifestPath -Force
  Copy-Item -LiteralPath $codexMetaSource -Destination $codexManifestPath -Force

  $receipt = [ordered]@{
    schema_version = "1.0"
    tested_source_head = $script:sourceHead
    version = $expected
    source_manifest_skills_sha256 = $sourceDigest
    claude_manifest_skills_sha256 = $claudeDigest
    codex_manifest_skills_sha256 = $codexDigest
    claude_current_target = $secondClaudeTarget
    codex_current_target = $secondCodexTarget
    claude_active_manifest = $claudeManifestPath
    codex_active_manifest = $codexManifestPath
    failure_receipt = $failureReceiptPath
    legacy_claude_preserved = @($claudePreserved.FullName)
    legacy_codex_preserved = @($codexPreserved.FullName)
    active_forbidden_hits = @($activeForbiddenHits)
    idempotent_rerun = $true
    version_mismatch_rejected = ($mismatchMessage -like "*does not match source version*")
    pin_result = $second
  }
  $receiptPath = Join-Path $receipts "phase1-receipt.json"
  $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath -Encoding utf8

  if ($fails.Count -gt 0) {
    Write-Host "FAIL: $($fails.Count) transactional pin check(s) failed"
    exit 1
  }

  Write-Host "PASS: transactional temp-home pin ($expected @ $script:sourceHead)"
  Write-Host "RECEIPT: $receiptPath"
  Write-Host "CLAUDE_MANIFEST: $claudeManifestPath"
  Write-Host "CODEX_MANIFEST: $codexManifestPath"
  Write-Host "FAILURE_RECEIPT: $failureReceiptPath"
} finally {
  if (-not $KeepArtifacts -and (Test-Path -LiteralPath $tmp)) {
    Remove-Item -Recurse -Force -LiteralPath $tmp
  }
}
