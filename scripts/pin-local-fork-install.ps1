<#
.SYNOPSIS
  Transactionally pin Claude and Codex Superpowers installs to one approved fork commit.

.DESCRIPTION
  The source identity is validated before either configured home is created. Both active
  checkouts are staged byte-exactly before deployment. Deployment is protected by per-home
  exclusive locks, preimage compare-and-swap fingerprints, and a mirrored durable journal
  outside plugin caches. A later invocation rolls any prepared/deploying/rolling-back journal
  back before beginning a new transaction. Recovery assets are retained until exact validation.

  Residual non-goals: this script does not preserve or compare ACLs, alternate data streams,
  hardlink topology, or timestamps. Those properties are intentionally outside the content-
  identity receipt and must be controlled separately when they matter.
#>
param(
  [string]$ClaudeHome = "$env:USERPROFILE\.claude",
  [string]$CodexHome = "$env:USERPROFILE\.codex",
  [string]$SourceRepo = "",
  [string]$ExpectedVersion = "",
  [string]$ExpectedSourceCommit = "",
  [string]$ExpectedPackageDigest = "",
  [ValidateSet("None", "AfterClaude", "AfterCodex", "BeforeVerify")]
  [string]$InjectFailureAt = "None",
  [ValidateSet("None", "AfterClaudeBeforeCodex", "AfterPointerRemoval", "AfterVerifiedBeforeFinalize", "DuringFinalize")]
  [string]$HardKillAt = "None",
  [ValidateRange(0, 30000)]
  [int]$HoldLockMilliseconds = 0
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-fork-security.ps1")

if (-not $SourceRepo) { $SourceRepo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }

function Invoke-InjectedFailure([string]$point) {
  if ($InjectFailureAt -eq $point) { throw "Injected failure at $point" }
}

function Invoke-HardKill([string]$point) {
  if ($HardKillAt -ne $point) { return }
  [Console]::Error.WriteLine("Hard-kill injection at $point")
  try { Stop-Process -Id $PID -Force -ErrorAction Stop } catch { [Environment]::Exit(197) }
  [Environment]::Exit(197)
}

function Test-SPForkBaseRecordName([string]$name) {
  return @("claude-fork-base", "codex-fork-base") -contains $name
}

function Assert-SPManagedForkTree(
  [string]$forkBase,
  [string]$expectedLegacyTarget = "",
  [bool]$allowDanglingLegacy = $false,
  [bool]$allowMissingLegacy = $false
) {
  $base = Get-SPCanonicalPath $forkBase
  $baseItem = Get-SPItem $base
  if ($null -eq $baseItem) {
    if (-not [string]::IsNullOrWhiteSpace($expectedLegacyTarget)) {
      throw "managed cache lost its legacy current junction: $base"
    }
    return ""
  }
  if (-not $baseItem.PSIsContainer -or (Test-SPReparseItem $baseItem)) {
    throw "managed cache root must be a plain directory: $base"
  }

  $current = Join-Path $base "current"
  $currentItem = Get-SPItem $current
  $legacyTarget = ""
  if ($null -ne $currentItem -and (Test-SPReparseItem $currentItem)) {
    if ([string]$currentItem.LinkType -cne "Junction") {
      throw "managed cache current reparse point must be a Junction: $current"
    }
    $targets = @($currentItem.Target)
    if ($targets.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$targets[0])) {
      throw "managed cache current Junction has no exact target: $current"
    }
    try {
      $legacyTarget = Get-SPCanonicalPath ([string]$targets[0])
    } catch {
      throw "managed cache current Junction target is invalid: $current"
    }

    if (-not [string]::IsNullOrWhiteSpace($expectedLegacyTarget)) {
      $expected = Get-SPCanonicalPath $expectedLegacyTarget
      if (-not $legacyTarget.Equals($expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw "managed cache current Junction target changed: $current"
      }
    } elseif (-not (Split-Path -Parent $legacyTarget).Equals($base, [StringComparison]::OrdinalIgnoreCase)) {
      throw "managed cache current Junction target is not a direct contained sibling: $current"
    }

    if ((Split-Path -Leaf $legacyTarget).Equals("current", [StringComparison]::OrdinalIgnoreCase)) {
      throw "managed cache current Junction cannot target itself: $current"
    }
    if (-not $allowDanglingLegacy) {
      $targetItem = Get-SPItem $legacyTarget
      if ($null -eq $targetItem -or -not $targetItem.PSIsContainer) {
        throw "managed cache current Junction reparse point is dangling: $current"
      }
      $physicalTarget = Get-SPPhysicalCanonicalPath $legacyTarget
      $physicalCurrent = Get-SPPhysicalCanonicalPath $current
      if (-not $physicalCurrent.Equals($physicalTarget, [StringComparison]::OrdinalIgnoreCase)) {
        throw "managed cache current Junction does not resolve to its declared target: $current"
      }
    }
  } elseif (-not [string]::IsNullOrWhiteSpace($expectedLegacyTarget) -and -not $allowMissingLegacy) {
    throw "managed cache lost its legacy current Junction: $current"
  } elseif (-not [string]::IsNullOrWhiteSpace($expectedLegacyTarget) -and $null -ne $currentItem) {
    throw "managed cache replaced its legacy current Junction with an unexpected item: $current"
  }

  foreach ($child in @(Get-ChildItem -LiteralPath $base -Force)) {
    if (-not [string]::IsNullOrWhiteSpace($legacyTarget) -and
        (Get-SPCanonicalPath $child.FullName).Equals($current, [StringComparison]::OrdinalIgnoreCase)) {
      continue
    }
    Assert-SPPlainTree $child.FullName "managed cache"
  }
  return $legacyTarget
}

function Get-SPManagedForkTreeFingerprint(
  [string]$forkBase,
  [string]$expectedLegacyTarget,
  [bool]$allowDanglingLegacy = $false,
  [bool]$allowMissingLegacy = $false
) {
  $item = Get-SPItem $forkBase
  if ($null -eq $item) { return Get-SPStringSha256 "ABSENT" }
  $legacyTarget = Assert-SPManagedForkTree $forkBase $expectedLegacyTarget $allowDanglingLegacy $allowMissingLegacy
  $current = Get-SPCanonicalPath (Join-Path $forkBase "current")
  $records = New-Object System.Collections.Generic.List[string]
  $records.Add("D|") | Out-Null
  foreach ($child in @(Get-ChildItem -LiteralPath $forkBase -Force | Sort-Object Name)) {
    if (-not [string]::IsNullOrWhiteSpace($legacyTarget) -and
        (Get-SPCanonicalPath $child.FullName).Equals($current, [StringComparison]::OrdinalIgnoreCase)) {
      continue
    }
    $records.Add("C|$($child.Name)|$(Get-SPTreeFingerprint $child.FullName)") | Out-Null
  }
  return Get-SPStringSha256 ($records -join [Environment]::NewLine)
}

function Get-SPRecordLegacyCurrentTarget($record) {
  return [string]$record.legacy_current_target
}

function Get-SPRecordFingerprint(
  $record,
  [string]$path,
  [bool]$allowDanglingLegacy = $false,
  [bool]$allowMissingLegacy = $false
) {
  $legacyTarget = Get-SPRecordLegacyCurrentTarget $record
  if ([string]::IsNullOrWhiteSpace($legacyTarget)) { return Get-SPTreeFingerprint $path }
  return Get-SPManagedForkTreeFingerprint $path $legacyTarget $allowDanglingLegacy $allowMissingLegacy
}

function Move-SPRecordPreimage(
  $record,
  [string]$source,
  [string]$destination,
  [bool]$allowDanglingLegacy = $false
) {
  $legacyTarget = Get-SPRecordLegacyCurrentTarget $record
  if ([string]::IsNullOrWhiteSpace($legacyTarget)) {
    Move-Checked $source $destination ([string]$record.home)
    return
  }
  Assert-SPContained ([string]$record.home) $source "move source"
  Assert-SPContained ([string]$record.home) $destination "move destination"
  Assert-SPNoReparseAncestors $source "move source"
  Assert-SPNoReparseAncestors (Split-Path -Parent $destination) "move destination"
  Assert-SPManagedForkTree $source $legacyTarget $allowDanglingLegacy $false | Out-Null
  if ($null -ne (Get-SPItem $destination)) { throw "move destination already exists: $destination" }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
  Move-Item -LiteralPath $source -Destination $destination
}

function Remove-SPVerifiedLegacyCurrent($record, [string]$forkBase) {
  $legacyTarget = Get-SPRecordLegacyCurrentTarget $record
  if ([string]::IsNullOrWhiteSpace($legacyTarget)) { return }
  Assert-SPManagedForkTree $forkBase $legacyTarget $true $true | Out-Null
  $current = Join-Path $forkBase "current"
  $currentItem = Get-SPItem $current
  if ($null -ne $currentItem) {
    if ([string]$currentItem.LinkType -cne "Junction") {
      throw "verified legacy current is no longer a Junction: $current"
    }
    [System.IO.Directory]::Delete($current, $false)
  }
  Assert-SPPlainTree $forkBase "verified legacy archive"
}

function Get-ControlPaths([string]$claude, [string]$codex) {
  return @(
    (Join-Path $claude ".superpowers-pin"),
    (Join-Path $codex ".superpowers-pin")
  )
}

function Assert-ScopedExistingState([string]$homePath, [bool]$isClaude) {
  $forkBase = Join-Path $homePath "plugins\cache\superpowers-dev\superpowers"
  $official = Join-Path $homePath "plugins\cache\claude-plugins-official\superpowers"
  Assert-SPNoReparseAncestors $forkBase "managed cache path"
  Assert-SPManagedForkTree $forkBase | Out-Null
  Assert-SPNoReparseAncestors $official "managed cache path"
  if ($null -ne (Get-SPItem $official)) { Assert-SPPlainTree $official "managed cache" }
  if ($isClaude) {
    foreach ($file in @(
      (Join-Path $homePath "plugins\installed_plugins.json"),
      (Join-Path $homePath "skills\registry.yaml")
    )) {
      Assert-SPNoReparseAncestors $file "managed metadata path"
      Assert-SPSingleLinkFile $file "managed metadata"
    }
  }
}

function Open-TransactionLocks([string[]]$controlPaths) {
  $streams = New-Object System.Collections.Generic.List[System.IO.FileStream]
  try {
    foreach ($control in @($controlPaths | Sort-Object)) {
      New-Item -ItemType Directory -Force -Path $control | Out-Null
      Assert-SPNoReparseAncestors $control "transaction control directory"
      $lockPath = Join-Path $control "transaction.lock"
      Assert-SPSingleLinkFile $lockPath "transaction lock"
      try {
        $stream = New-Object System.IO.FileStream(
          $lockPath,
          [System.IO.FileMode]::OpenOrCreate,
          [System.IO.FileAccess]::ReadWrite,
          [System.IO.FileShare]::None,
          64,
          [System.IO.FileOptions]::WriteThrough
        )
      } catch {
        throw "exclusive transaction lock is held or unsafe: $lockPath"
      }
      $streams.Add($stream) | Out-Null
    }
    return $streams
  } catch {
    foreach ($stream in @($streams)) { $stream.Dispose() }
    throw
  }
}

function Close-TransactionLocks($streams) {
  foreach ($stream in @($streams)) {
    if ($null -ne $stream) { $stream.Dispose() }
  }
}

function Get-JournalPaths([string[]]$controlPaths) {
  return @($controlPaths | ForEach-Object { Join-Path $_ "transaction.json" })
}

function Write-TransactionJournal($journal, [string[]]$journalPaths) {
  $journal.sequence = [int64]$journal.sequence + 1
  $journal.updated_at = [DateTime]::UtcNow.ToString("o")
  foreach ($path in $journalPaths) {
    Assert-SPSingleLinkFile $path "transaction journal"
    Write-SPDurableJson $path $journal
  }
}

function Remove-TransactionJournals([string[]]$journalPaths) {
  foreach ($path in $journalPaths) {
    Assert-SPSingleLinkFile $path "transaction journal"
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
  }
}

function Assert-SPExactPath([string]$actual, [string]$expected, [string]$label) {
  if (-not (Get-SPCanonicalPath $actual).Equals((Get-SPCanonicalPath $expected), [StringComparison]::OrdinalIgnoreCase)) {
    throw "durable journal $label is outside its exact managed path"
  }
}

function Assert-TransactionJournalShape($journal, [string]$claude, [string]$codex, [string[]]$controlPaths) {
  if ([string]$journal.schema_version -ne "2.0") { throw "durable journal schema is not exactly 2.0" }
  if ([string]$journal.transaction_id -notmatch "^[0-9]{8}T[0-9]{9}Z-[0-9a-f]{8}$") { throw "durable journal transaction id is invalid" }
  $sequence = [int64]0
  if (-not [int64]::TryParse([string]$journal.sequence, [ref]$sequence) -or $sequence -lt 0) { throw "durable journal sequence is invalid" }
  if (@("prepared", "deploying", "rolling-back", "verified") -notcontains [string]$journal.state) { throw "durable journal state is invalid" }
  if ([string]$journal.source_commit -notmatch "^[0-9a-f]{40,64}$" -or [string]$journal.source_tree -notmatch "^[0-9a-f]{40,64}$") {
    throw "durable journal source binding is invalid"
  }
  if ([string]$journal.package_digest -ne (Get-SPApprovedPackageDigest)) { throw "durable journal package digest is invalid" }
  Assert-SPExactPath ([string]$journal.claude_home) $claude "Claude home"
  Assert-SPExactPath ([string]$journal.codex_home) $codex "Codex home"
  Assert-SPExactPath $controlPaths[0] (Join-Path $claude ".superpowers-pin") "Claude control root"
  Assert-SPExactPath $controlPaths[1] (Join-Path $codex ".superpowers-pin") "Codex control root"

  $declaredAssets = @($journal.asset_roots)
  if ($declaredAssets.Count -ne 2) { throw "durable journal must declare exactly two asset roots" }
  $assetByControl = @{}
  for ($assetIndex = 0; $assetIndex -lt 2; $assetIndex++) {
    $asset = Get-SPCanonicalPath ([string]$declaredAssets[$assetIndex])
    $control = Get-SPCanonicalPath $controlPaths[$assetIndex]
    if (-not (Split-Path -Parent $asset).Equals($control, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $asset) -notmatch "^a-[0-9a-f]{8}$") {
      throw "durable journal asset root is not a direct transaction-control child"
    }
    Assert-SPNoReparseAncestors $asset "durable journal asset root"
    $assetByControl[$control] = $asset
  }
  if (-not (Split-Path -Leaf $declaredAssets[0]).Equals((Split-Path -Leaf $declaredAssets[1]), [StringComparison]::OrdinalIgnoreCase)) {
    throw "durable journal mirrored asset roots disagree"
  }

  $definitions = @{
    "claude-fork-base" = [pscustomobject]@{ Home = $claude; Control = $controlPaths[0]; Target = Join-Path $claude "plugins\cache\superpowers-dev\superpowers"; StagedLeaf = "s" }
    "codex-fork-base" = [pscustomobject]@{ Home = $codex; Control = $controlPaths[1]; Target = Join-Path $codex "plugins\cache\superpowers-dev\superpowers"; StagedLeaf = "s" }
    "claude-official" = [pscustomobject]@{ Home = $claude; Control = $controlPaths[0]; Target = Join-Path $claude "plugins\cache\claude-plugins-official\superpowers"; StagedLeaf = "" }
    "codex-official" = [pscustomobject]@{ Home = $codex; Control = $controlPaths[1]; Target = Join-Path $codex "plugins\cache\claude-plugins-official\superpowers"; StagedLeaf = "" }
    "claude-manifest" = [pscustomobject]@{ Home = $claude; Control = $controlPaths[0]; Target = Join-Path $claude "plugins\installed_plugins.json"; StagedLeaf = "stage-installed_plugins.json" }
    "claude-registry" = [pscustomobject]@{ Home = $claude; Control = $controlPaths[0]; Target = Join-Path $claude "skills\registry.yaml"; StagedLeaf = "stage-registry.yaml" }
  }
  $records = @($journal.records)
  if ($records.Count -notin @(5, 6)) { throw "durable journal record count is invalid" }
  $expectedNames = @("claude-fork-base", "codex-fork-base", "claude-official", "codex-official", "claude-manifest")
  if ($records.Count -eq 6) { $expectedNames += "claude-registry" }
  for ($recordIndex = 0; $recordIndex -lt $records.Count; $recordIndex++) {
    $record = $records[$recordIndex]
    $name = [string]$record.name
    if ($name -cne $expectedNames[$recordIndex] -or -not $definitions.ContainsKey($name)) {
      throw "durable journal record name/order is invalid"
    }
    $definition = $definitions[$name]
    $control = Get-SPCanonicalPath ([string]$definition.Control)
    $asset = [string]$assetByControl[$control]
    Assert-SPExactPath ([string]$record.home) ([string]$definition.Home) "record home"
    Assert-SPExactPath ([string]$record.target) ([string]$definition.Target) "record target"
    Assert-SPExactPath ([string]$record.asset_root) $asset "record asset root"
    Assert-SPExactPath ([string]$record.backup) (Join-Path $asset ("backup-" + $name)) "record backup"
    if ([string]::IsNullOrWhiteSpace([string]$definition.StagedLeaf)) {
      if (-not [string]::IsNullOrWhiteSpace([string]$record.staged)) { throw "durable journal removal record has a staged path" }
    } else {
      Assert-SPExactPath ([string]$record.staged) (Join-Path $asset ([string]$definition.StagedLeaf)) "record stage"
    }
    if ([string]$record.preimage_fingerprint -notmatch "^[0-9a-f]{64}$" -or [string]$record.replacement_fingerprint -notmatch "^[0-9a-f]{64}$") {
      throw "durable journal record fingerprint is invalid"
    }
    $legacyTarget = [string]$record.legacy_current_target
    if (Test-SPForkBaseRecordName $name) {
      if (-not [string]::IsNullOrWhiteSpace($legacyTarget)) {
        $legacyTarget = Get-SPCanonicalPath $legacyTarget
        $forkBase = Get-SPCanonicalPath ([string]$definition.Target)
        if (-not (Split-Path -Parent $legacyTarget).Equals($forkBase, [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path -Leaf $legacyTarget).Equals("current", [StringComparison]::OrdinalIgnoreCase)) {
          throw "durable journal legacy current target is not a direct contained sibling"
        }
      }
    } elseif (-not [string]::IsNullOrWhiteSpace($legacyTarget)) {
      throw "durable journal non-fork record declares a legacy current target"
    }
    if (@("prepared", "removing", "removed", "installed", "rolled-back", "finalized") -notcontains [string]$record.phase) {
      throw "durable journal record phase is invalid"
    }
  }
}
function Read-PendingJournal([string[]]$journalPaths, [string]$claude, [string]$codex, [string[]]$controlPaths) {
  $candidates = New-Object System.Collections.Generic.List[object]
  foreach ($path in $journalPaths) {
    Assert-SPNoReparseAncestors $path "transaction journal"
    Assert-SPSingleLinkFile $path "transaction journal"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $raw = Get-Content -Raw -LiteralPath $path -Encoding utf8
      $value = $raw | ConvertFrom-Json
      $candidates.Add([pscustomobject]@{ Path = $path; Raw = $raw; Value = $value; Sequence = [int64]$value.sequence }) | Out-Null
    }
  }
  if ($candidates.Count -eq 0) { return $null }
  $ids = @($candidates | ForEach-Object { [string]$_.Value.transaction_id } | Sort-Object -Unique)
  if ($ids.Count -ne 1) { throw "conflicting durable transaction journals" }
  $highestSequence = [int64](@($candidates | Sort-Object Sequence -Descending)[0].Sequence)
  $latest = @($candidates | Where-Object { [int64]$_.Sequence -eq $highestSequence })
  if ($latest.Count -gt 1) {
    $firstRaw = [string]$latest[0].Raw
    foreach ($candidate in $latest) {
      if ([string]$candidate.Raw -cne $firstRaw) { throw "conflicting same-sequence durable transaction journals" }
    }
  }
  $journal = $latest[0].Value
  Assert-TransactionJournalShape $journal $claude $codex $controlPaths
  return $journal
}

function Move-Checked([string]$source, [string]$destination, [string]$allowedRoot) {
  Assert-SPContained $allowedRoot $source "move source"
  Assert-SPContained $allowedRoot $destination "move destination"
  Assert-SPNoReparseAncestors $source "move source"
  Assert-SPNoReparseAncestors (Split-Path -Parent $destination) "move destination"
  Assert-SPPlainTree $source "move source"
  if ($null -ne (Get-SPItem $destination)) { throw "move destination already exists: $destination" }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
  Move-Item -LiteralPath $source -Destination $destination
}

function Remove-AssetRoots($journal, [string[]]$controlPaths) {
  foreach ($asset in @($journal.asset_roots)) {
    $assetPath = Get-SPCanonicalPath ([string]$asset)
    $owner = @($controlPaths | Where-Object { Test-SPPathContained $_ $assetPath $false })
    if ($owner.Count -ne 1) { throw "journal asset root is outside transaction control: $assetPath" }
    if ($null -ne (Get-SPItem $assetPath)) { Remove-SPTree $assetPath $owner[0] }
  }
}

function Recover-Transaction($journal, [string[]]$journalPaths, [string[]]$controlPaths) {
  $claude = Split-Path -Parent $controlPaths[0]
  $codex = Split-Path -Parent $controlPaths[1]
  Assert-TransactionJournalShape $journal $claude $codex $controlPaths
  if ([string]$journal.state -eq "verified") {
    Finalize-VerifiedTransaction $journal $journalPaths $controlPaths $null
    return
  }
  if (@("prepared", "deploying", "rolling-back") -notcontains [string]$journal.state) {
    throw "unsupported durable journal state: $($journal.state)"
  }
  $journal.state = "rolling-back"
  Write-TransactionJournal $journal $journalPaths
  $records = @($journal.records)
  for ($index = $records.Count - 1; $index -ge 0; $index--) {
    $record = $records[$index]
    $target = Get-SPCanonicalPath ([string]$record.target)
    $backup = Get-SPCanonicalPath ([string]$record.backup)
    $assetRoot = Get-SPCanonicalPath ([string]$record.asset_root)
    Assert-SPContained ([string]$record.home) $target "recovery target"
    Assert-SPContained $assetRoot $backup "recovery backup"
    $targetExists = $null -ne (Get-SPItem $target)
    $backupExists = $null -ne (Get-SPItem $backup)
    if ($backupExists) {
      if ($targetExists) {
        $actual = Get-SPTreeFingerprint $target
        if ($actual -ne [string]$record.replacement_fingerprint) {
          throw "recovery CAS rejected changed replacement: $target"
        }
        $discard = Join-Path $assetRoot ("discard-" + $index)
        Move-Checked $target $discard ([string]$record.home)
      }
      Move-SPRecordPreimage $record $backup $target $true
    } elseif ($targetExists) {
      $actual = Get-SPRecordFingerprint $record $target $false $false
      if ([string]$record.preimage_fingerprint -eq (Get-SPStringSha256 "ABSENT")) {
        if ($actual -ne [string]$record.replacement_fingerprint) {
          throw "recovery CAS rejected changed new target: $target"
        }
        $discard = Join-Path $assetRoot ("discard-" + $index)
        Move-Checked $target $discard ([string]$record.home)
      } elseif ($actual -ne [string]$record.preimage_fingerprint) {
        throw "recovery CAS rejected changed preimage: $target"
      }
    } elseif ([string]$record.preimage_fingerprint -ne (Get-SPStringSha256 "ABSENT")) {
      throw "recovery lost both target and backup: $target"
    }
    if ((Get-SPRecordFingerprint $record $target $false $false) -ne [string]$record.preimage_fingerprint) {
      throw "recovery did not restore exact preimage: $target"
    }
    $record.phase = "rolled-back"
    Write-TransactionJournal $journal $journalPaths
  }
  Remove-AssetRoots $journal $controlPaths
  Remove-TransactionJournals $journalPaths
}

function New-ClaudeManifestStage([string]$homePath, [string]$destination, [string]$activePath, $identity) {
  $installed = Join-Path $homePath "plugins\installed_plugins.json"
  if (Test-Path -LiteralPath $installed -PathType Leaf) {
    $document = Get-Content -Raw -LiteralPath $installed -Encoding utf8 | ConvertFrom-Json
  } else {
    $document = [pscustomobject][ordered]@{ version = 2; plugins = [pscustomobject]@{} }
  }
  if ($null -eq $document.PSObject.Properties["plugins"] -or $null -eq $document.plugins) {
    $document | Add-Member -MemberType NoteProperty -Name plugins -Value ([pscustomobject]@{}) -Force
  }
  $document.plugins.PSObject.Properties.Remove("superpowers@claude-plugins-official")
  $existing = @($document.plugins."superpowers@superpowers-dev")
  $scope = if ($existing.Count -gt 0 -and $existing[0].scope) { [string]$existing[0].scope } else { "user" }
  $installedAt = if ($existing.Count -gt 0 -and $existing[0].installedAt) { [string]$existing[0].installedAt } else { [DateTime]::UtcNow.ToString("o") }
  $entry = [pscustomobject][ordered]@{
    scope = $scope
    installedAt = $installedAt
    installPath = $activePath
    version = $identity.Version
    gitCommitSha = $identity.Commit
    gitTreeSha = $identity.Tree
    packageDigest = $identity.PackageDigest
    lastUpdated = [DateTime]::UtcNow.ToString("o")
  }
  $document.plugins | Add-Member -MemberType NoteProperty -Name "superpowers@superpowers-dev" -Value @($entry) -Force
  Write-SPDurableJson $destination $document
}

function New-ClaudeRegistryStage([string]$homePath, [string]$destination, [string]$activePath) {
  $registry = Join-Path $homePath "skills\registry.yaml"
  if (-not (Test-Path -LiteralPath $registry -PathType Leaf)) { return $false }
  $content = Get-Content -Raw -LiteralPath $registry -Encoding utf8
  $escapedHome = [regex]::Escape($homePath)
  $pattern = "${escapedHome}\\plugins\\cache\\superpowers-dev\\superpowers\\[^\\`r`n]+?\\skills\\"
  $replacement = $activePath + "\skills\"
  Write-SPDurableText $destination ([regex]::Replace($content, $pattern, $replacement))
  return $true
}

function New-Record(
  [string]$name,
  [string]$homePath,
  [string]$target,
  [string]$staged,
  [string]$assetRoot
) {
  $backup = Join-Path $assetRoot ("backup-" + $name)
  $replacement = if ($staged -and $null -ne (Get-SPItem $staged)) { Get-SPTreeFingerprint $staged } else { Get-SPStringSha256 "ABSENT" }
  $legacyTarget = ""
  if (Test-SPForkBaseRecordName $name) {
    $legacyTarget = Assert-SPManagedForkTree $target
  }
  $preimage = if ([string]::IsNullOrWhiteSpace($legacyTarget)) {
    Get-SPTreeFingerprint $target
  } else {
    Get-SPManagedForkTreeFingerprint $target $legacyTarget $false $false
  }
  return [pscustomobject][ordered]@{
    name = $name
    home = $homePath
    target = $target
    staged = $staged
    asset_root = $assetRoot
    backup = $backup
    preimage_fingerprint = $preimage
    replacement_fingerprint = $replacement
    legacy_current_target = $legacyTarget
    phase = "prepared"
  }
}

function Deploy-Record($journal, $record, [string[]]$journalPaths, [bool]$isPointerRemovalSeam) {
  if ((Get-SPRecordFingerprint $record ([string]$record.target) $false $false) -ne [string]$record.preimage_fingerprint) {
    throw "preimage CAS rejected concurrent change: $($record.target)"
  }
  Assert-SPNoReparseAncestors ([string]$record.target) "deployment target"
  $record.phase = "removing"
  Write-TransactionJournal $journal $journalPaths
  if ($null -ne (Get-SPItem ([string]$record.target))) {
    Move-SPRecordPreimage $record ([string]$record.target) ([string]$record.backup) $false
  }
  $record.phase = "removed"
  Write-TransactionJournal $journal $journalPaths
  if ($isPointerRemovalSeam) { Invoke-HardKill "AfterPointerRemoval" }
  if ([string]$record.staged -and $null -ne (Get-SPItem ([string]$record.staged))) {
    Move-Checked ([string]$record.staged) ([string]$record.target) ([string]$record.home)
  }
  if ((Get-SPTreeFingerprint ([string]$record.target)) -ne [string]$record.replacement_fingerprint) {
    throw "deployment replacement fingerprint mismatch: $($record.target)"
  }
  $record.phase = "installed"
  Write-TransactionJournal $journal $journalPaths
}

function Assert-InstalledState([string]$claude, [string]$codex, $identity) {
  $claudeBase = Join-Path $claude "plugins\cache\superpowers-dev\superpowers"
  $codexBase = Join-Path $codex "plugins\cache\superpowers-dev\superpowers"
  $claudeCurrent = Join-Path $claudeBase "current"
  $codexCurrent = Join-Path $codexBase "current"
  $claudeVersioned = Join-Path $claudeBase $identity.Version
  $codexVersioned = Join-Path $codexBase $identity.Version
  Assert-SPPlainTree $claudeBase "Claude installed cache"
  Assert-SPPlainTree $codexBase "Codex installed cache"
  $claudeInfo = Get-SPCheckoutInfo $claudeCurrent $identity.Commit $identity.PackageDigest $identity.Version $true
  $codexInfo = Get-SPCheckoutInfo $codexCurrent $identity.Commit $identity.PackageDigest $identity.Version $true
  Get-SPCheckoutInfo $claudeVersioned $identity.Commit $identity.PackageDigest $identity.Version $false | Out-Null
  Get-SPCheckoutInfo $codexVersioned $identity.Commit $identity.PackageDigest $identity.Version $false | Out-Null
  foreach ($current in @($claudeCurrent, $codexCurrent)) {
    $meta = Get-Content -Raw -LiteralPath (Join-Path $current ".superpowers-active.json") -Encoding utf8 | ConvertFrom-Json
    if (-not (Get-SPCanonicalPath ([string]$meta.target)).Equals((Get-SPCanonicalPath $current), [StringComparison]::OrdinalIgnoreCase)) {
      throw "active metadata target mismatch: $current"
    }
  }
  $installedPath = Join-Path $claude "plugins\installed_plugins.json"
  Assert-SPSingleLinkFile $installedPath "Claude installed manifest"
  $installed = Get-Content -Raw -LiteralPath $installedPath -Encoding utf8 | ConvertFrom-Json
  $names = @($installed.plugins.PSObject.Properties.Name)
  if ($names -contains "superpowers@claude-plugins-official" -or $names -notcontains "superpowers@superpowers-dev") {
    throw "Claude installed manifest plugin identity mismatch"
  }
  $entries = @($installed.plugins."superpowers@superpowers-dev")
  if ($entries.Count -ne 1) { throw "Claude installed manifest must contain exactly one fork entry" }
  $entry = $entries[0]
  if (-not (Get-SPCanonicalPath ([string]$entry.installPath)).Equals((Get-SPCanonicalPath $claudeCurrent), [StringComparison]::OrdinalIgnoreCase) -or
      $entry.version -ne $identity.Version -or $entry.gitCommitSha -ne $identity.Commit -or
      $entry.gitTreeSha -ne $identity.Tree -or $entry.packageDigest -ne $identity.PackageDigest) {
    throw "Claude installed manifest pin mismatch"
  }
  foreach ($official in @(
    (Join-Path $claude "plugins\cache\claude-plugins-official\superpowers"),
    (Join-Path $codex "plugins\cache\claude-plugins-official\superpowers")
  )) {
    if ($null -ne (Get-SPItem $official)) { throw "official Superpowers cache remains active: $official" }
  }
  return [pscustomobject]@{ Claude = $claudeInfo; Codex = $codexInfo }
}

function Get-VerifiedArchivePath($journal, $record) {
  if ([string]$record.name -match "manifest|registry") {
    return ([string]$record.target) + ".bak-" + [string]$journal.transaction_id
  }
  $qroot = Join-Path ([string]$record.home) ("plugins\.quarantine-superpowers-" + [string]$journal.transaction_id)
  return Join-Path $qroot ([string]$record.name)
}

function Finalize-VerifiedTransaction($journal, [string[]]$journalPaths, [string[]]$controlPaths, $result) {
  $absentFingerprint = Get-SPStringSha256 "ABSENT"
  foreach ($record in @($journal.records)) {
    $backup = Get-SPCanonicalPath ([string]$record.backup)
    $archive = Get-SPCanonicalPath (Get-VerifiedArchivePath $journal $record)
    Assert-SPContained ([string]$record.home) $archive "verified archive"
    $backupExists = $null -ne (Get-SPItem $backup)
    $archiveExists = $null -ne (Get-SPItem $archive)
    if ([string]$record.preimage_fingerprint -eq $absentFingerprint) {
      if ($backupExists -or $archiveExists) { throw "verified finalization found archive for absent preimage: $($record.name)" }
    } else {
      if ($backupExists -and $archiveExists) { throw "verified finalization found duplicate preimage: $($record.name)" }
      if ($backupExists) {
        if ((Get-SPRecordFingerprint $record $backup $true $true) -ne [string]$record.preimage_fingerprint) {
          throw "verified finalization backup fingerprint mismatch: $($record.name)"
        }
        Remove-SPVerifiedLegacyCurrent $record $backup
        Move-Checked $backup $archive ([string]$record.home)
        Invoke-HardKill "DuringFinalize"
        $archiveExists = $true
      }
      if (-not $archiveExists) { throw "verified finalization lost preimage: $($record.name)" }
      if ((Get-SPRecordFingerprint $record $archive $true $true) -ne [string]$record.preimage_fingerprint) {
        throw "verified finalization archive fingerprint mismatch: $($record.name)"
      }
      if ($null -ne $result) {
        if ([string]$record.name -match "manifest|registry") { $result.backup_paths += $archive }
        else { $result.quarantine_paths += $archive }
      }
    }
    $record.phase = "finalized"
    Write-TransactionJournal $journal $journalPaths
  }
  Remove-AssetRoots $journal $controlPaths
  Remove-TransactionJournals $journalPaths
}

$identity = Get-SPSourceIdentity $SourceRepo $ExpectedVersion $ExpectedSourceCommit $ExpectedPackageDigest
$homes = Assert-SPDistinctHomes $ClaudeHome $CodexHome
$ClaudeHome = $homes.Claude
$CodexHome = $homes.Codex
Assert-ScopedExistingState $ClaudeHome $true
Assert-ScopedExistingState $CodexHome $false

$controlPaths = Get-ControlPaths $ClaudeHome $CodexHome
$journalPaths = Get-JournalPaths $controlPaths
$lockStreams = $null
$journal = $null
$transactionVerified = $false
$result = [ordered]@{
  version = $identity.Version
  source_head = $identity.Commit
  source_tree = $identity.Tree
  source_binding_scope = "entire-tracked-git-tree-including-executable-surfaces"
  package_digest = $identity.PackageDigest
  claude_active_path = Join-Path $ClaudeHome "plugins\cache\superpowers-dev\superpowers\current"
  codex_cache_path = Join-Path $CodexHome "plugins\cache\superpowers-dev\superpowers\current"
  claude_active_content = @()
  codex_active_content = @()
  complete_package_paths = @($identity.PackagePaths)
  quarantine_paths = @()
  backup_paths = @()
  residual_scope = @("ACLs", "alternate-data-streams", "hardlink-topology", "timestamps")
}

try {
  $lockStreams = Open-TransactionLocks $controlPaths
  if ($HoldLockMilliseconds -gt 0) { Start-Sleep -Milliseconds $HoldLockMilliseconds }
  $pending = Read-PendingJournal $journalPaths $ClaudeHome $CodexHome $controlPaths
  if ($null -ne $pending) { Recover-Transaction $pending $journalPaths $controlPaths }

  foreach ($control in $controlPaths) {
    foreach ($orphan in @(Get-ChildItem -LiteralPath $control -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^(assets-|a-)" })) {
      Assert-SPPlainTree $orphan.FullName "orphan transaction asset"
      Remove-SPTree $orphan.FullName $control
    }
  }

  $runId = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ") + "-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
  $assetLeaf = "a-" + [guid]::NewGuid().ToString("N").Substring(0, 8)
  $claudeAssets = Join-Path $controlPaths[0] $assetLeaf
  $codexAssets = Join-Path $controlPaths[1] $assetLeaf
  New-Item -ItemType Directory -Force -Path $claudeAssets, $codexAssets | Out-Null

  $claudeBaseTarget = Join-Path $ClaudeHome "plugins\cache\superpowers-dev\superpowers"
  $codexBaseTarget = Join-Path $CodexHome "plugins\cache\superpowers-dev\superpowers"
  $claudeBaseStage = Join-Path $claudeAssets "s"
  $codexBaseStage = Join-Path $codexAssets "s"
  $stages = @($claudeBaseStage, $codexBaseStage)
  $activeTargets = @($result.claude_active_path, $result.codex_cache_path)
  for ($stageIndex = 0; $stageIndex -lt $stages.Count; $stageIndex++) {
    $stage = $stages[$stageIndex]
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    New-SPExactCheckout $identity.SourceRepo (Join-Path $stage $identity.Version) $identity.Commit $identity.PackageDigest $identity.Version | Out-Null
    $current = Join-Path $stage "current"
    New-SPExactCheckout $identity.SourceRepo $current $identity.Commit $identity.PackageDigest $identity.Version | Out-Null
    Set-SPActiveMetadata $current $identity.Version $identity.Commit $identity.Tree $identity.PackageDigest $identity.SourceRepo $activeTargets[$stageIndex]
    Get-SPCheckoutInfo $current $identity.Commit $identity.PackageDigest $identity.Version $true $activeTargets[$stageIndex] | Out-Null
  }

  $manifestStage = Join-Path $claudeAssets "stage-installed_plugins.json"
  New-ClaudeManifestStage $ClaudeHome $manifestStage $result.claude_active_path $identity
  $registryStage = Join-Path $claudeAssets "stage-registry.yaml"
  $hasRegistry = New-ClaudeRegistryStage $ClaudeHome $registryStage $result.claude_active_path

  $records = New-Object System.Collections.Generic.List[object]
  $records.Add((New-Record "claude-fork-base" $ClaudeHome $claudeBaseTarget $claudeBaseStage $claudeAssets)) | Out-Null
  $records.Add((New-Record "codex-fork-base" $CodexHome $codexBaseTarget $codexBaseStage $codexAssets)) | Out-Null
  $records.Add((New-Record "claude-official" $ClaudeHome (Join-Path $ClaudeHome "plugins\cache\claude-plugins-official\superpowers") "" $claudeAssets)) | Out-Null
  $records.Add((New-Record "codex-official" $CodexHome (Join-Path $CodexHome "plugins\cache\claude-plugins-official\superpowers") "" $codexAssets)) | Out-Null
  $records.Add((New-Record "claude-manifest" $ClaudeHome (Join-Path $ClaudeHome "plugins\installed_plugins.json") $manifestStage $claudeAssets)) | Out-Null
  if ($hasRegistry) {
    $records.Add((New-Record "claude-registry" $ClaudeHome (Join-Path $ClaudeHome "skills\registry.yaml") $registryStage $claudeAssets)) | Out-Null
  }

  $journal = [pscustomobject][ordered]@{
    schema_version = "2.0"
    transaction_id = $runId
    sequence = [int64]0
    state = "prepared"
    updated_at = [DateTime]::UtcNow.ToString("o")
    claude_home = $ClaudeHome
    codex_home = $CodexHome
    source_commit = $identity.Commit
    source_tree = $identity.Tree
    package_digest = $identity.PackageDigest
    asset_roots = @($claudeAssets, $codexAssets)
    records = $records.ToArray()
  }
  Write-TransactionJournal $journal $journalPaths
  $journal.state = "deploying"
  Write-TransactionJournal $journal $journalPaths

  Deploy-Record $journal $records[0] $journalPaths $true
  Invoke-InjectedFailure "AfterClaude"
  Invoke-HardKill "AfterClaudeBeforeCodex"
  Deploy-Record $journal $records[1] $journalPaths $false
  Invoke-InjectedFailure "AfterCodex"
  for ($recordIndex = 2; $recordIndex -lt $records.Count; $recordIndex++) {
    Deploy-Record $journal $records[$recordIndex] $journalPaths $false
  }

  Invoke-InjectedFailure "BeforeVerify"
  $installedInfo = Assert-InstalledState $ClaudeHome $CodexHome $identity
  $verifyOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "verify-local-fork-install.ps1") `
    -ClaudeHome $ClaudeHome -CodexHome $CodexHome -ExpectedVersion $identity.Version `
    -ExpectedSourceCommit $identity.Commit -ExpectedPackageDigest $identity.PackageDigest 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "verify-local-fork-install.ps1 failed after pin: $($verifyOutput -join ' ')" }
  $journal.state = "verified"
  Write-TransactionJournal $journal $journalPaths
  Invoke-HardKill "AfterVerifiedBeforeFinalize"
  $transactionVerified = $true
  $result.claude_active_content = @($installedInfo.Claude.Content)
  $result.codex_active_content = @($installedInfo.Codex.Content)
  Finalize-VerifiedTransaction $journal $journalPaths $controlPaths $result
} catch {
  $original = $_.Exception
  if ($null -ne $journal -and -not $transactionVerified) {
    try { Recover-Transaction $journal $journalPaths $controlPaths } catch {
      throw "Pin failed: $($original.Message); durable rollback failed: $($_.Exception.Message)"
    }
  }
  throw
} finally {
  if ($null -ne $lockStreams) { Close-TransactionLocks $lockStreams }
}

$result | ConvertTo-Json -Depth 20
