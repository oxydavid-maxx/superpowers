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
  [switch]$SkipVerify
)
$ErrorActionPreference = "Stop"

if (-not $SourceRepo)      { $SourceRepo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$claudeManifest = Join-Path $SourceRepo ".claude-plugin\plugin.json"
if (-not $ExpectedVersion) { $ExpectedVersion = (Get-Content -Raw -LiteralPath $claudeManifest | ConvertFrom-Json).version }
$sourceHead = (& git -C $SourceRepo rev-parse HEAD).Trim()
$ts = Get-Date -Format "yyyyMMddTHHmmssZ"
$result = [ordered]@{ version = $ExpectedVersion; source_head = $sourceHead;
                      claude_active_path = $null; codex_cache_path = $null;
                      quarantine_paths = @(); backup_paths = @() }

function Log($m) { Write-Host "[pin] $m" }

# (re)create cache/superpowers-dev/superpowers/<version> as a git checkout of source@HEAD.
function Ensure-ForkCache([string]$cacheBase) {
  $dest = Join-Path $cacheBase $ExpectedVersion
  $fresh = $true
  if (Test-Path -LiteralPath (Join-Path $dest ".git")) {
    $h = (& git -C $dest rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and ($h.Trim() -eq $sourceHead)) { $fresh = $false }
  }
  if ($fresh) {
    if (Test-Path -LiteralPath $dest) { Remove-Item -Recurse -Force -LiteralPath $dest }
    New-Item -ItemType Directory -Force -Path $cacheBase | Out-Null
    & git clone --local --quiet -- "$SourceRepo" "$dest" | Out-Null
    & git -C "$dest" checkout --quiet $sourceHead | Out-Null
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
    $target = if ($item.LinkType -and $item.Target) { (Resolve-Path -LiteralPath $item.Target).Path } else { "" }
    if ($target -eq (Resolve-Path -LiteralPath $versionedPath).Path) {
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
  Set-Content -LiteralPath $tmp -Value $py -Encoding utf8
  & py -3 $tmp $ipj $activePath $ExpectedVersion $sourceHead | Out-Null
  $rc = $LASTEXITCODE
  Remove-Item -LiteralPath $tmp -Force
  if ($rc -ne 0) { throw "repin installed_plugins.json (py) failed with exit $rc" }
  Log "repinned Claude installed_plugins.json -> $ExpectedVersion ($sourceHead)"
}

# ---- Claude ----
Log "pinning Claude home: $ClaudeHome"
$claudeBase = Join-Path $ClaudeHome "plugins\cache\superpowers-dev\superpowers"
$claudeVersioned = Ensure-ForkCache $claudeBase
$claudeActive = Set-CurrentPointer $claudeBase $claudeVersioned
$result.claude_active_path = $claudeActive
Quarantine-Superpowers $ClaudeHome
Repin-ClaudeManifest $ClaudeHome $claudeActive

# ---- Codex ----
Log "pinning Codex home: $CodexHome"
$codexBase = Join-Path $CodexHome "plugins\cache\superpowers-dev\superpowers"
$codexVersioned = Ensure-ForkCache $codexBase
$codexActive = Set-CurrentPointer $codexBase $codexVersioned
$result.codex_cache_path = $codexActive
Quarantine-Superpowers $CodexHome

# ---- verify ----
if (-not $SkipVerify) {
  & (Join-Path $PSScriptRoot "verify-local-fork-install.ps1") -ClaudeHome $ClaudeHome -CodexHome $CodexHome -ExpectedVersion $ExpectedVersion
  if ($LASTEXITCODE -ne 0) { throw "verify-local-fork-install.ps1 failed after pin" }
}

$result | ConvertTo-Json -Depth 6
