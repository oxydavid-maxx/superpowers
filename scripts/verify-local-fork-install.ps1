param(
  [string]$ClaudeHome = "$env:USERPROFILE\.claude",
  [string]$CodexHome = "$env:USERPROFILE\.codex",
  [string]$ExpectedVersion = ""
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$forkUrl = "https://github.com/oxydavid-maxx/superpowers"
$sourceClaudeManifest = Join-Path $root ".claude-plugin\plugin.json"
$sourceCodexManifest = Join-Path $root ".codex-plugin\plugin.json"

if (-not $ExpectedVersion) {
  $ExpectedVersion = (Get-Content -Raw -LiteralPath $sourceClaudeManifest | ConvertFrom-Json).version
}

$errors = New-Object System.Collections.Generic.List[string]

function Add-Error([string]$message) {
  $script:errors.Add($message) | Out-Null
}

function Read-Json([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) {
    Add-Error "missing file: $path"
    return $null
  }
  return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
}

function Check-ManifestField([string]$path, [string]$fieldPath, [string]$expected) {
  $json = Read-Json $path
  if ($null -eq $json) { return }
  $cur = $json
  foreach ($segment in $fieldPath.Split(".")) {
    if ($null -eq $cur.PSObject.Properties[$segment]) {
      Add-Error "$path missing field $fieldPath"
      return
    }
    $cur = $cur.$segment
  }
  if ($cur -ne $expected) {
    Add-Error "$path $fieldPath expected '$expected', got '$cur'"
  }
}

function Git-Head([string]$path) {
  if (-not (Test-Path -LiteralPath (Join-Path $path ".git"))) {
    return ""
  }
  $head = & git -C $path rev-parse HEAD 2>$null
  if ($LASTEXITCODE -ne 0) { return "" }
  return ($head | Select-Object -First 1)
}

Check-ManifestField $sourceClaudeManifest "repository" $forkUrl
Check-ManifestField $sourceCodexManifest "repository" $forkUrl
Check-ManifestField $sourceCodexManifest "interface.websiteURL" $forkUrl

$sourceHead = Git-Head $root

$installedPath = Join-Path $ClaudeHome "plugins\installed_plugins.json"
$installed = Read-Json $installedPath
if ($null -ne $installed) {
  $names = @($installed.plugins.PSObject.Properties.Name)
  if ($names -contains "superpowers@claude-plugins-official") {
    Add-Error "Claude still has superpowers@claude-plugins-official installed"
  }
  if (-not ($names -contains "superpowers@superpowers-dev")) {
    Add-Error "Claude is missing superpowers@superpowers-dev"
  } else {
    $entry = @($installed.plugins."superpowers@superpowers-dev")[0]
    if ($entry.version -ne $ExpectedVersion) {
      Add-Error "Claude superpowers-dev version expected $ExpectedVersion, got $($entry.version)"
    }
    if ($entry.installPath -notmatch "\\superpowers-dev\\superpowers\\$([regex]::Escape($ExpectedVersion))$") {
      Add-Error "Claude superpowers-dev installPath does not point at versioned fork cache: $($entry.installPath)"
    }
    if (-not (Test-Path -LiteralPath $entry.installPath)) {
      Add-Error "Claude superpowers-dev installPath missing: $($entry.installPath)"
    } else {
      Check-ManifestField (Join-Path $entry.installPath ".claude-plugin\plugin.json") "repository" $forkUrl
      $claudeHead = Git-Head $entry.installPath
      if ($sourceHead -and $claudeHead -and $sourceHead -ne $claudeHead) {
        Add-Error "Claude cache HEAD $claudeHead does not match source HEAD $sourceHead"
      }
    }
  }
}

$officialInUse = Get-ChildItem -LiteralPath (Join-Path $ClaudeHome "plugins\cache\claude-plugins-official\superpowers") -Recurse -Force -Filter ".in_use" -ErrorAction SilentlyContinue
if ($officialInUse) {
  Add-Error "official Claude Superpowers cache still has .in_use marker(s): $($officialInUse.FullName -join '; ')"
}

$codexOfficial = Join-Path $CodexHome "plugins\cache\claude-plugins-official\superpowers"
if (Test-Path -LiteralPath $codexOfficial) {
  Add-Error "Codex official Superpowers cache exists: $codexOfficial"
}

$codexCache = Join-Path $CodexHome "plugins\cache\superpowers-dev\superpowers\$ExpectedVersion"
if (-not (Test-Path -LiteralPath $codexCache)) {
  Add-Error "Codex fork cache missing: $codexCache"
} else {
  $codexManifest = Join-Path $codexCache ".codex-plugin\plugin.json"
  Check-ManifestField $codexManifest "version" $ExpectedVersion
  Check-ManifestField $codexManifest "repository" $forkUrl
  Check-ManifestField $codexManifest "interface.websiteURL" $forkUrl
  $codexHead = Git-Head $codexCache
  if ($sourceHead -and $codexHead -and $sourceHead -ne $codexHead) {
    Add-Error "Codex cache HEAD $codexHead does not match source HEAD $sourceHead"
  }
}

if ($errors.Count -gt 0) {
  Write-Host "FAIL: local Superpowers install is not pinned to the fork"
  foreach ($err in $errors) {
    Write-Host "  - $err"
  }
  exit 1
}

Write-Host "PASS: local Claude/Codex Superpowers installs are pinned to $forkUrl@$ExpectedVersion"
