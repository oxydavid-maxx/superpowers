<#
.SYNOPSIS
  Pin the local Claude + Codex Superpowers install to this fork (oxydavid-maxx/superpowers)
  at the source repo's current version/HEAD. Idempotent and temp-home-friendly.

.DESCRIPTION
  Durable replacement for one-off manual cache surgery (UPG-F1). For the Claude home and the
  Codex home it:
    * (re)creates a versioned fork cache  cache/superpowers-dev/superpowers/<version>  as a
      git checkout of the source at HEAD (so cache HEAD == source HEAD);
    * switches a stable  cache/superpowers-dev/superpowers/current  pointer to that versioned
      cache, then marks ONLY the resolved active cache .in_use;
    * QUARANTINES (moves, never deletes) stale fork caches + any official-marketplace
      Superpowers caches into plugins/.quarantine-superpowers-<ts>/;
    * for Claude: backs up installed_plugins.json, removes a superpowers@claude-plugins-official
      entry if present, and points superpowers@superpowers-dev at the stable current pointer
      (version + gitCommitSha updated). Other plugins and known_marketplaces.json are untouched.
  Then runs verify-local-fork-install.ps1 unless -SkipVerify.

  Safe to re-run: a cache already at HEAD is left in place; an absent official entry is a no-op.

.NOTES
  Only disables/quarantines official *Superpowers* artifacts — it never removes the official
  marketplace registration (known_marketplaces.json is not touched).
#>
param(
  [string]$ClaudeHome = "$env:USERPROFILE\.claude",
  [string]$CodexHome  = "$env:USERPROFILE\.codex",
  [string]$SourceRepo = "",
  [string]$ExpectedVersion = "",
  [switch]$SkipVerify,
  [ValidateSet("None", "AfterClaude", "AfterCodex", "BeforeVerify")]
  [string]$InjectFailureAt = "None"
)
$ErrorActionPreference = "Stop"

function Read-ManifestAtHead([string]$relativePath, [string]$commit) {
  $spec = "{0}:{1}" -f $commit, $relativePath
  $raw = @(& git -C $SourceRepo show $spec 2>$null)
  if ($LASTEXITCODE -ne 0) {
    throw "cannot read $relativePath from source commit $commit"
  }
  return (($raw -join [Environment]::NewLine) | ConvertFrom-Json)
}

if (-not $SourceRepo) { $SourceRepo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$SourceRepo = (Resolve-Path -LiteralPath $SourceRepo).Path
$headOutput = @(& git -C $SourceRepo rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or $headOutput.Count -eq 0) {
  throw "cannot resolve source HEAD: $SourceRepo"
}
$sourceHead = $headOutput[0].Trim()
$sourceClaudeManifest = Read-ManifestAtHead ".claude-plugin/plugin.json" $sourceHead
$sourceCodexManifest = Read-ManifestAtHead ".codex-plugin/plugin.json" $sourceHead
$sourceVersion = [string]$sourceClaudeManifest.version
if (-not $sourceVersion -or $sourceCodexManifest.version -ne $sourceVersion) {
  throw "source commit $sourceHead has inconsistent Claude/Codex manifest versions"
}
if (-not $ExpectedVersion) {
  $ExpectedVersion = $sourceVersion
} elseif ($ExpectedVersion -ne $sourceVersion) {
  throw "ExpectedVersion '$ExpectedVersion' does not match source version '$sourceVersion' at $sourceHead"
}

$runId = [guid]::NewGuid().ToString("N").Substring(0, 8)
$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ") + "-" + $runId
$linkMarkerName = ".pin-link-state-" + $runId + ".json"
$result = [ordered]@{ version = $ExpectedVersion; source_head = $sourceHead;
                      claude_active_path = $null; codex_cache_path = $null;
                      quarantine_paths = @(); backup_paths = @() }
$temporaryPaths = New-Object System.Collections.Generic.List[string]

function Log($m) { Write-Host "[pin] $m" }

function Get-PathItem([string]$path) {
  return Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}

function Remove-PathNoFollow([string]$path) {
  $item = Get-PathItem $path
  if ($null -eq $item) { return }
  if ($item.LinkType -eq "Junction" -or $item.LinkType -eq "SymbolicLink") {
    if ($item.PSIsContainer) {
      [System.IO.Directory]::Delete($path, $false)
    } else {
      Remove-Item -LiteralPath $path -Force
    }
    return
  }
  if ($item.PSIsContainer) {
    foreach ($child in @(Get-ChildItem -LiteralPath $path -Force)) {
      Remove-PathNoFollow $child.FullName
    }
    [System.IO.Directory]::Delete($path, $false)
    return
  }
  Remove-Item -LiteralPath $path -Force
}

function Restore-SnapshotLink([string]$destination, $state) {
  $target = [string]$state.target
  $linkType = [string]$state.linkType
  if ($null -ne (Get-PathItem $target)) {
    New-Item -ItemType $linkType -Path $destination -Target $target | Out-Null
    return
  }
  if ($destination.Contains('"') -or $target.Contains('"')) {
    throw "cannot restore dangling link containing a quote: $destination"
  }
  $switch = ""
  if ($linkType -eq "Junction") {
    $switch = "/J "
  } elseif ($linkType -eq "SymbolicLink" -and [bool]$state.isContainer) {
    $switch = "/D "
  } elseif ($linkType -ne "SymbolicLink") {
    throw "unsupported snapshot link type: $linkType"
  }
  $commandLine = 'mklink {0}"{1}" "{2}"' -f $switch, $destination, $target
  $commandProcessor = $env:ComSpec
  if (-not $commandProcessor) { $commandProcessor = "cmd.exe" }
  & $commandProcessor /d /c $commandLine | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "cannot restore dangling $linkType '$destination' -> '$target'"
  }
}

function Copy-PathPreservingLinks([string]$source, [string]$destination) {
  $item = Get-PathItem $source
  if ($null -eq $item) { throw "snapshot source disappeared: $source" }
  $parent = Split-Path -Parent $destination
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $linkMarker = Join-Path $source $linkMarkerName
  if ($item.PSIsContainer -and -not $item.LinkType -and (Test-Path -LiteralPath $linkMarker -PathType Leaf)) {
    $state = Get-Content -Raw -LiteralPath $linkMarker -Encoding utf8 | ConvertFrom-Json
    Restore-SnapshotLink $destination $state
    return
  }
  if ($item.LinkType -eq "Junction" -or $item.LinkType -eq "SymbolicLink") {
    $target = @($item.Target)[0]
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    [ordered]@{
      schema_version = "1.0"
      linkType = [string]$item.LinkType
      target = [string]$target
      isContainer = [bool]$item.PSIsContainer
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $destination $linkMarkerName) -Encoding utf8
    return
  }
  if ($item.PSIsContainer) {
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    foreach ($child in @(Get-ChildItem -LiteralPath $source -Force | Sort-Object Name)) {
      Copy-PathPreservingLinks $child.FullName (Join-Path $destination $child.Name)
    }
    return
  }
  Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Capture-PathState([string]$path, [string]$snapshotDir, [string]$name) {
  $item = Get-PathItem $path
  $backup = Join-Path $snapshotDir $name
  if ($null -ne $item) {
    Copy-PathPreservingLinks $path $backup
  }
  return [pscustomobject]@{
    path = $path
    existed = ($null -ne $item)
    backup = $backup
  }
}

function Capture-HomeState([string]$homeDir, [string]$name, [bool]$includeClaudeFiles, [string]$transactionRoot) {
  $snapshotDir = Join-Path $transactionRoot $name
  New-Item -ItemType Directory -Force -Path $snapshotDir | Out-Null
  $paths = @(
    (Join-Path $homeDir "plugins\cache\superpowers-dev\superpowers"),
    (Join-Path $homeDir "plugins\cache\claude-plugins-official\superpowers")
  )
  if ($includeClaudeFiles) {
    $paths += (Join-Path $homeDir "plugins\installed_plugins.json")
    $paths += (Join-Path $homeDir "skills\registry.yaml")
  }
  $entries = @()
  for ($i = 0; $i -lt $paths.Count; $i++) {
    $entries += Capture-PathState $paths[$i] $snapshotDir ("path-" + $i)
  }
  $parents = @(
    $homeDir,
    (Join-Path $homeDir "plugins"),
    (Join-Path $homeDir "plugins\cache"),
    (Join-Path $homeDir "plugins\cache\superpowers-dev"),
    (Join-Path $homeDir "plugins\cache\claude-plugins-official")
  )
  if ($includeClaudeFiles) { $parents += (Join-Path $homeDir "skills") }
  $parentStates = @()
  foreach ($parentPath in $parents) {
    $parentStates += [pscustomobject]@{
      path = $parentPath
      existed = ($null -ne (Get-PathItem $parentPath))
    }
  }
  return [pscustomobject]@{
    paths = $entries
    parents = $parentStates
  }
}

function Restore-HomeState($state) {
  foreach ($entry in @($state.paths)) {
    Remove-PathNoFollow $entry.path
    if ($entry.existed) {
      Copy-PathPreservingLinks $entry.backup $entry.path
    }
  }
  for ($i = $state.parents.Count - 1; $i -ge 0; $i--) {
    $parent = $state.parents[$i]
    if (-not $parent.existed) {
      $item = Get-PathItem $parent.path
      if ($null -ne $item -and $item.PSIsContainer -and -not $item.LinkType) {
        if (@(Get-ChildItem -LiteralPath $parent.path -Force).Count -eq 0) {
          [System.IO.Directory]::Delete($parent.path, $false)
        }
      }
    }
  }
}

function Invoke-InjectedFailure([string]$point) {
  if ($InjectFailureAt -eq $point) {
    throw "Injected failure at $point"
  }
}

# (re)create cache/superpowers-dev/superpowers/<version> as a git checkout of source@HEAD.
function Ensure-ForkCache([string]$cacheBase) {
  $dest = Join-Path $cacheBase $ExpectedVersion
  $fresh = $true
  if (Test-Path -LiteralPath (Join-Path $dest ".git")) {
    $head = @(& git -C $dest rev-parse HEAD 2>$null)
    $headOk = ($LASTEXITCODE -eq 0 -and $head.Count -gt 0 -and $head[0].Trim() -eq $sourceHead)
    $localAutoCrlf = @(& git -C $dest config --local --get core.autocrlf 2>$null)
    $byteExactConfig = ($LASTEXITCODE -eq 0 -and $localAutoCrlf.Count -gt 0 -and $localAutoCrlf[0].Trim() -eq "false")
    if ($headOk -and $byteExactConfig) {
      $trackedChanges = @(& git -C $dest status --porcelain --untracked-files=no 2>$null)
      if ($LASTEXITCODE -eq 0 -and $trackedChanges.Count -eq 0) {
        $fresh = $false
      }
    }
  }
  if ($fresh) {
    Remove-PathNoFollow $dest
    New-Item -ItemType Directory -Force -Path $cacheBase | Out-Null
    & git clone --local --quiet -- "$SourceRepo" "$dest" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git clone failed for $SourceRepo -> $dest" }
    & git -C "$dest" config --local core.autocrlf false
    if ($LASTEXITCODE -ne 0) { throw "cannot set byte-exact checkout policy for $dest" }
    & git -C "$dest" -c core.autocrlf=false checkout --quiet $sourceHead | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git checkout failed for $dest@$sourceHead" }
    & git -C "$dest" -c core.autocrlf=false checkout-index --all --force
    if ($LASTEXITCODE -ne 0) { throw "byte-exact checkout-index failed for $dest@$sourceHead" }
    Log "created fork cache $dest @ $sourceHead"
  } else {
    Log "fork cache already at HEAD: $dest"
  }
  New-Item -ItemType File -Force -Path (Join-Path $dest ".in_use") | Out-Null
  return $dest
}

function Write-ActiveMetadata([string]$versionedPath) {
  $meta = [ordered]@{
    schema_version = "1.0"
    version = $ExpectedVersion
    gitCommitSha = $sourceHead
    sourceRepo = $SourceRepo
    activatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    pointer = "current"
    target = $versionedPath
  }
  $meta | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $versionedPath ".superpowers-active.json") -Encoding utf8
}

function Set-CurrentPointer([string]$cacheBase, [string]$versionedPath) {
  $current = Join-Path $cacheBase "current"
  if (Test-Path -LiteralPath $current) {
    $item = Get-Item -LiteralPath $current -Force
    # Fail-soft on a DANGLING junction: if the recorded target no longer exists (it was
    # quarantined/removed), resolve to "" so it won't match and we fall through to rebuild
    # below. -ErrorAction SilentlyContinue is scoped to THIS resolve only — a non-link
    # `current` still throws at the explicit guard below, so real failures aren't masked.
    $target = ""
    if ($item.LinkType -and $item.Target) {
      $resolved = Resolve-Path -LiteralPath $item.Target -ErrorAction SilentlyContinue
      if ($resolved) { $target = $resolved.Path }
    }
    if ($target -ne "" -and $target -eq (Resolve-Path -LiteralPath $versionedPath).Path) {
      Write-ActiveMetadata $versionedPath
      New-Item -ItemType File -Force -Path (Join-Path $current ".in_use") | Out-Null
      return $current
    }
    if (-not $item.LinkType) {
      throw "current path exists but is not a link/junction: $current"
    }
    [System.IO.Directory]::Delete($current, $false)
  }
  New-Item -ItemType Junction -Path $current -Target $versionedPath | Out-Null
  Write-ActiveMetadata $versionedPath
  New-Item -ItemType File -Force -Path (Join-Path $current ".in_use") | Out-Null
  return $current
}

# Move stale fork caches (version != expected) + official Superpowers caches to quarantine.
function Quarantine-Superpowers([string]$homeDir) {
  $qroot = Join-Path $homeDir "plugins\.quarantine-superpowers-$ts"
  $cacheRoot = Join-Path $homeDir "plugins\cache"
  $forkBase = Join-Path $cacheRoot "superpowers-dev\superpowers"
  if (Test-Path -LiteralPath $forkBase) {
    Get-ChildItem -LiteralPath $forkBase -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $ExpectedVersion -and $_.Name -ne "current" } | ForEach-Object {
      New-Item -ItemType Directory -Force -Path $qroot | Out-Null
      $d = Join-Path $qroot ("fork-" + $_.Name)
      Move-Item -LiteralPath $_.FullName -Destination $d -Force
      $script:result.quarantine_paths += $d
      Log "quarantined stale fork cache -> $d"
    }
  }
  $official = Join-Path $cacheRoot "claude-plugins-official\superpowers"
  if (Test-Path -LiteralPath $official) {
    New-Item -ItemType Directory -Force -Path $qroot | Out-Null
    $d = Join-Path $qroot "official-superpowers"
    Move-Item -LiteralPath $official -Destination $d -Force
    $script:result.quarantine_paths += $d
    Log "quarantined OFFICIAL Superpowers cache -> $d (official marketplace registration left intact)"
  }
}

# Surgically repin Claude installed_plugins.json (py -3 = reliable JSON; preserves other plugins).
function Repin-ClaudeManifest([string]$homeDir, [string]$activePath) {
  $ipj = Join-Path $homeDir "plugins\installed_plugins.json"
  if (-not (Test-Path -LiteralPath $ipj)) {
    $seed = '{ "version": 2, "plugins": {} }'
    New-Item -ItemType Directory -Force -Path (Split-Path $ipj) | Out-Null
    Set-Content -LiteralPath $ipj -Value $seed -Encoding utf8
  }
  $bak = "$ipj.bak-$ts"
  Copy-Item -LiteralPath $ipj -Destination $bak -Force
  $script:result.backup_paths += $bak
  $py = @'
import json, sys, time
ipj, active, version, sha = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = json.load(open(ipj, encoding="utf-8-sig"))   # tolerate a UTF-8 BOM if present
plugins = d.setdefault("plugins", {})
plugins.pop("superpowers@claude-plugins-official", None)   # disable official; keep other plugins
existing = plugins.get("superpowers@superpowers-dev") or [{}]
e = existing[0] if isinstance(existing, list) and existing else {}
e.setdefault("scope", "user")
e.setdefault("installedAt", time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()))
e["installPath"] = active
e["version"] = version
e["gitCommitSha"] = sha
e["lastUpdated"] = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
plugins["superpowers@superpowers-dev"] = [e]
json.dump(d, open(ipj, "w", encoding="utf-8"), indent=1)
print("repinned", version)
'@
  $tmp = Join-Path $env:TEMP "pin-ipj-$ts.py"
  $temporaryPaths.Add($tmp) | Out-Null
  Set-Content -LiteralPath $tmp -Value $py -Encoding utf8
  & py -3 $tmp $ipj $activePath $ExpectedVersion $sourceHead | Out-Null
  $rc = $LASTEXITCODE
  Remove-Item -LiteralPath $tmp -Force
  $temporaryPaths.Remove($tmp) | Out-Null
  if ($rc -ne 0) { throw "repin installed_plugins.json (py) failed with exit $rc" }
  Log "repinned Claude installed_plugins.json -> $ExpectedVersion ($sourceHead)"
}

function Repin-ClaudeSkillRegistry([string]$homeDir, [string]$activePath) {
  $registry = Join-Path $homeDir "skills\registry.yaml"
  if (-not (Test-Path -LiteralPath $registry)) { return }

  $bak = "$registry.bak-$ts"
  Copy-Item -LiteralPath $registry -Destination $bak -Force
  $script:result.backup_paths += $bak

  $content = Get-Content -Raw -LiteralPath $registry -Encoding utf8
  $escapedHome = [regex]::Escape($homeDir)
  $pattern = "${escapedHome}\\plugins\\cache\\superpowers-dev\\superpowers\\[^\\`r`n]+?\\skills\\"
  $replacement = $activePath + "\skills\"
  $updated = [regex]::Replace($content, $pattern, $replacement)
  Set-Content -LiteralPath $registry -Value $updated -Encoding utf8
  Log "repinned Claude skills\registry.yaml entries -> superpowers-dev\superpowers\current"
}

$transactionRoot = Join-Path $env:TEMP ("pin-superpowers-transaction-" + $ts)
New-Item -ItemType Directory -Force -Path $transactionRoot | Out-Null
try {
  $claudeSnapshot = Capture-HomeState $ClaudeHome "claude" $true $transactionRoot
  $codexSnapshot = Capture-HomeState $CodexHome "codex" $false $transactionRoot
} catch {
  Remove-PathNoFollow $transactionRoot
  throw
}

try {
  # ---- Claude ----
  Log "pinning Claude home: $ClaudeHome"
  $claudeBase = Join-Path $ClaudeHome "plugins\cache\superpowers-dev\superpowers"
  $claudeVersioned = Ensure-ForkCache $claudeBase
  $claudeActive = Set-CurrentPointer $claudeBase $claudeVersioned
  $result.claude_active_path = $claudeActive
  Quarantine-Superpowers $ClaudeHome
  Repin-ClaudeManifest $ClaudeHome $claudeActive
  Repin-ClaudeSkillRegistry $ClaudeHome $claudeActive
  Invoke-InjectedFailure "AfterClaude"

  # ---- Codex ----
  Log "pinning Codex home: $CodexHome"
  $codexBase = Join-Path $CodexHome "plugins\cache\superpowers-dev\superpowers"
  $codexVersioned = Ensure-ForkCache $codexBase
  $codexActive = Set-CurrentPointer $codexBase $codexVersioned
  $result.codex_cache_path = $codexActive
  Quarantine-Superpowers $CodexHome
  Invoke-InjectedFailure "AfterCodex"

  # ---- verify ----
  Invoke-InjectedFailure "BeforeVerify"
  if (-not $SkipVerify) {
    & (Join-Path $PSScriptRoot "verify-local-fork-install.ps1") -ClaudeHome $ClaudeHome -CodexHome $CodexHome -SourceRepo $SourceRepo -ExpectedVersion $ExpectedVersion
    if ($LASTEXITCODE -ne 0) { throw "verify-local-fork-install.ps1 failed after pin" }
  }

  Remove-PathNoFollow $transactionRoot
} catch {
  $originalError = $_.Exception
  $rollbackErrors = New-Object System.Collections.Generic.List[string]
  foreach ($artifact in @($result.backup_paths)) {
    try { Remove-PathNoFollow $artifact } catch { $rollbackErrors.Add($_.Exception.Message) | Out-Null }
  }
  foreach ($homeDir in @($ClaudeHome, $CodexHome)) {
    $qroot = Join-Path $homeDir "plugins\.quarantine-superpowers-$ts"
    try { Remove-PathNoFollow $qroot } catch { $rollbackErrors.Add($_.Exception.Message) | Out-Null }
  }
  try { Restore-HomeState $codexSnapshot } catch { $rollbackErrors.Add("Codex rollback: " + $_.Exception.Message) | Out-Null }
  try { Restore-HomeState $claudeSnapshot } catch { $rollbackErrors.Add("Claude rollback: " + $_.Exception.Message) | Out-Null }
  foreach ($temporaryPath in @($temporaryPaths)) {
    try { Remove-PathNoFollow $temporaryPath } catch { $rollbackErrors.Add($_.Exception.Message) | Out-Null }
  }
  try { Remove-PathNoFollow $transactionRoot } catch { $rollbackErrors.Add($_.Exception.Message) | Out-Null }
  if ($rollbackErrors.Count -gt 0) {
    throw "Pin failed: $($originalError.Message); rollback failed: $($rollbackErrors -join '; ')"
  }
  throw $originalError
}

$result | ConvertTo-Json -Depth 6
