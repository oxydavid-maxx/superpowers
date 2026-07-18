$script:SPApprovedPackageDigest = "2f686cf09aff6d76b0416df01fb7e0cd71b949a2b7542b46984c1f908a9d29e3"
$script:SPForkUrl = "https://github.com/oxydavid-maxx/superpowers"

function Get-SPApprovedPackageDigest {
  return $script:SPApprovedPackageDigest
}

function Get-SPForkUrl {
  return $script:SPForkUrl
}

function Get-SPCanonicalPath([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path)) { throw "path is required" }
  if ($path.StartsWith("\\?\") -or $path.StartsWith("\\.\") -or $path.StartsWith("\??\")) {
    throw "alternate Win32 device path form is not allowed: $path"
  }
  $full = [System.IO.Path]::GetFullPath($path)
  $root = [System.IO.Path]::GetPathRoot($full)
  if ($full.Length -gt $root.Length) {
    $full = $full.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  }
  return $full
}

if (-not ("SPFinalPath" -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class SPFinalPath {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern SafeFileHandle CreateFile(
    string name, uint access, uint share, IntPtr security, uint creation,
    uint flags, IntPtr template);

  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern uint GetFinalPathNameByHandle(
    SafeFileHandle handle, StringBuilder path, uint length, uint flags);

  public static string Resolve(string path) {
    const uint shareAll = 1u | 2u | 4u;
    const uint openExisting = 3u;
    const uint backupSemantics = 0x02000000u;
    using (SafeFileHandle handle = CreateFile(path, 0u, shareAll, IntPtr.Zero, openExisting, backupSemantics, IntPtr.Zero)) {
      if (handle.IsInvalid) { throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot open path for final-name resolution: " + path); }
      StringBuilder buffer = new StringBuilder(32768);
      uint length = GetFinalPathNameByHandle(handle, buffer, (uint)buffer.Capacity, 0u);
      if (length == 0u || length >= (uint)buffer.Capacity) {
        throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot resolve final path: " + path);
      }
      string value = buffer.ToString();
      if (value.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) { return @"\\" + value.Substring(8); }
      if (value.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase)) { return value.Substring(4); }
      return value;
    }
  }
}
'@
}

function Get-SPPhysicalCanonicalPath([string]$path) {
  $lexical = Get-SPCanonicalPath $path
  $probe = $lexical
  $suffix = New-Object System.Collections.Generic.List[string]
  while ($null -eq (Get-SPItem $probe)) {
    $leaf = Split-Path -Leaf $probe
    $parent = Split-Path -Parent $probe
    if ([string]::IsNullOrWhiteSpace($leaf) -or [string]::IsNullOrWhiteSpace($parent) -or $parent -eq $probe) {
      throw "cannot resolve an existing ancestor for path: $path"
    }
    $suffix.Insert(0, $leaf)
    $probe = $parent
  }
  $resolved = [SPFinalPath]::Resolve($probe)
  foreach ($leaf in $suffix) { $resolved = Join-Path $resolved $leaf }
  return Get-SPCanonicalPath $resolved
}

function Test-SPPathContained([string]$root, [string]$path, [bool]$allowRoot = $false) {
  $canonicalRoot = Get-SPCanonicalPath $root
  $canonicalPath = Get-SPCanonicalPath $path
  if ($allowRoot -and $canonicalPath.Equals($canonicalRoot, [StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }
  return $canonicalPath.StartsWith($canonicalRoot + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-SPContained([string]$root, [string]$path, [string]$label, [bool]$allowRoot = $false) {
  if (-not (Test-SPPathContained $root $path $allowRoot)) {
    throw "$label escapes configured root '$root': $path"
  }
}

function Get-SPItem([string]$path) {
  return Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
}

function Test-SPReparseItem($item) {
  if ($null -eq $item) { return $false }
  return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.LinkType -eq "Junction" -or $item.LinkType -eq "SymbolicLink")
}

function Assert-SPNoReparseAncestors([string]$path, [string]$label) {
  $canonical = Get-SPCanonicalPath $path
  $volumeRoot = [System.IO.Path]::GetPathRoot($canonical)
  $current = $volumeRoot
  $relative = $canonical.Substring($volumeRoot.Length)
  $segments = @($relative.Split(@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar), [StringSplitOptions]::RemoveEmptyEntries))
  for ($index = 0; $index -lt $segments.Count; $index++) {
    $current = Join-Path $current $segments[$index]
    $item = Get-SPItem $current
    if ($null -eq $item) { continue }
    if (Test-SPReparseItem $item) {
      throw "$label contains reparse point: $current"
    }
    if ($index -lt ($segments.Count - 1) -and -not $item.PSIsContainer) {
      throw "$label has non-directory ancestor: $current"
    }
  }
}

function Assert-SPSingleLinkFile([string]$path, [string]$label) {
  $item = Get-SPItem $path
  if ($null -eq $item) { return }
  if ($item.PSIsContainer) { throw "$label must be a regular file: $path" }
  if (Test-SPReparseItem $item) { throw "$label contains reparse point: $path" }
  if ($item.LinkType -eq "HardLink") {
    throw "$label has multi-hardlink identity: $path"
  }
}

function Assert-SPPlainTree([string]$path, [string]$label) {
  $rootItem = Get-SPItem $path
  if ($null -eq $rootItem) { return }
  $stack = New-Object System.Collections.Generic.Stack[string]
  $stack.Push($path)
  while ($stack.Count -gt 0) {
    $current = $stack.Pop()
    $item = Get-SPItem $current
    if ($null -eq $item) { throw "$label changed during validation: $current" }
    if (Test-SPReparseItem $item) { throw "$label contains reparse point: $current" }
    if (-not $item.PSIsContainer -and $item.LinkType -eq "HardLink") {
      throw "$label contains multi-hardlink file: $current"
    }
    if ($item.PSIsContainer) {
      foreach ($child in @(Get-ChildItem -LiteralPath $current -Force)) {
        $stack.Push($child.FullName)
      }
    }
  }
}

function Assert-SPDistinctHomes([string]$claudeHome, [string]$codexHome) {
  $claudeLexical = Get-SPCanonicalPath $claudeHome
  $codexLexical = Get-SPCanonicalPath $codexHome
  Assert-SPNoReparseAncestors $claudeLexical "Claude home"
  Assert-SPNoReparseAncestors $codexLexical "Codex home"
  $claude = Get-SPPhysicalCanonicalPath $claudeLexical
  $codex = Get-SPPhysicalCanonicalPath $codexLexical
  if ($claude.Equals($codex, [StringComparison]::OrdinalIgnoreCase) -or
      $claude.StartsWith($codex + "\", [StringComparison]::OrdinalIgnoreCase) -or
      $codex.StartsWith($claude + "\", [StringComparison]::OrdinalIgnoreCase)) {
    throw "configured homes overlap physically: '$claude' and '$codex'"
  }
  if ($claude.Equals([System.IO.Path]::GetPathRoot($claude), [StringComparison]::OrdinalIgnoreCase) -or
      $codex.Equals([System.IO.Path]::GetPathRoot($codex), [StringComparison]::OrdinalIgnoreCase)) {
    throw "configured home cannot be a volume root"
  }
  return [pscustomobject]@{ Claude = $claude; Codex = $codex }
}

function Assert-SPValidVersion([string]$version) {
  if ([string]::IsNullOrWhiteSpace($version) -or $version.Length -gt 64) {
    throw "invalid package version: '$version'"
  }
  $pattern = "^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-[a-z][a-z0-9-]*\.(0|[1-9][0-9]*)$"
  if (-not [regex]::IsMatch($version, $pattern, [Text.RegularExpressions.RegexOptions]::CultureInvariant)) {
    throw "invalid package version: '$version'"
  }
  if ($version.Contains("/") -or $version.Contains("\") -or $version.Contains("..") -or $version.TrimEnd(" ", ".") -ne $version) {
    throw "invalid package version: '$version'"
  }
}

function Invoke-SPGit([string]$repo, [string[]]$arguments, [switch]$AllowFailure) {
  $output = @(& git --no-replace-objects -C $repo @arguments 2>&1)
  $exitCode = $LASTEXITCODE
  if ($exitCode -ne 0 -and -not $AllowFailure) {
    throw "git failed ($exitCode) in '$repo': $($arguments -join ' ') :: $($output -join ' ')"
  }
  return [pscustomobject]@{ ExitCode = $exitCode; Output = $output }
}
function Assert-SPApprovedRemote([string]$repo, [int]$depth = 0) {
  if ($depth -gt 3) { throw "source remote identity chain is too deep" }
  $remoteResult = Invoke-SPGit $repo @("remote", "get-url", "origin") -AllowFailure
  if ($remoteResult.ExitCode -ne 0 -or $remoteResult.Output.Count -eq 0) {
    throw "source repository has no origin remote identity"
  }
  $remote = ([string]$remoteResult.Output[0]).Trim()
  $normalized = $remote.TrimEnd("/")
  if ($normalized.EndsWith(".git", [StringComparison]::OrdinalIgnoreCase)) {
    $normalized = $normalized.Substring(0, $normalized.Length - 4)
  }
  $approved = @(
    $script:SPForkUrl,
    "git@github.com:oxydavid-maxx/superpowers",
    "ssh://git@github.com/oxydavid-maxx/superpowers"
  )
  if (@($approved | Where-Object { $normalized.Equals($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
    return
  }
  $local = $remote
  if ($remote.StartsWith("file://", [StringComparison]::OrdinalIgnoreCase)) {
    try { $local = ([Uri]$remote).LocalPath } catch { throw "source origin remote is not approved: $remote" }
  } elseif (-not [System.IO.Path]::IsPathRooted($remote)) {
    $local = Join-Path $repo $remote
  }
  if (-not (Test-Path -LiteralPath $local -PathType Container)) {
    throw "source origin remote is not approved: $remote"
  }
  $localRoot = Get-SPCanonicalPath $local
  Assert-SPNoReparseAncestors $localRoot "source origin repository"
  Assert-SPApprovedRemote $localRoot ($depth + 1)
}


function Get-SPStringSha256([string]$text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-SPCommitPackageInfo([string]$repo, [string]$commit) {
  $pathsResult = Invoke-SPGit $repo @("ls-tree", "-r", "--name-only", $commit, "--", ".claude-plugin/plugin.json", ".codex-plugin/plugin.json", "skills")
  $paths = @($pathsResult.Output | ForEach-Object { [string]$_ } | Sort-Object)
  if ($paths.Count -eq 0) { throw "source commit has no package content: $commit" }
  $records = New-Object System.Collections.Generic.List[string]
  foreach ($relative in $paths) {
    $spec = "{0}:{1}" -f $commit, $relative
    $objectId = [string](Invoke-SPGit $repo @("rev-parse", $spec)).Output[0]
    $records.Add("$relative|$($objectId.Trim())") | Out-Null
  }
  return [pscustomobject]@{
    Digest = Get-SPStringSha256 ($records -join [Environment]::NewLine)
    Paths = $paths
  }
}

function Read-SPCommitJson([string]$repo, [string]$commit, [string]$relative) {
  $spec = "{0}:{1}" -f $commit, $relative
  $raw = @((Invoke-SPGit $repo @("show", $spec)).Output)
  return (($raw -join [Environment]::NewLine) | ConvertFrom-Json)
}

function Get-SPSourceIdentity(
  [string]$sourceRepo,
  [string]$expectedVersion,
  [string]$expectedSourceCommit,
  [string]$expectedPackageDigest
) {
  if ($expectedSourceCommit -notmatch "^[0-9a-fA-F]{40,64}$") {
    throw "ExpectedSourceCommit is required and must be a full source commit"
  }
  if ($expectedPackageDigest -ne $script:SPApprovedPackageDigest) {
    throw "ExpectedPackageDigest must equal approved package digest $($script:SPApprovedPackageDigest)"
  }
  $source = Get-SPCanonicalPath $sourceRepo
  Assert-SPNoReparseAncestors $source "source repository"
  $top = [string](Invoke-SPGit $source @("rev-parse", "--show-toplevel")).Output[0]
  if (-not (Get-SPCanonicalPath $top).Equals($source, [StringComparison]::OrdinalIgnoreCase)) {
    throw "SourceRepo must be the exact repository root: $source"
  }
  Assert-SPApprovedRemote $source
  $head = ([string](Invoke-SPGit $source @("rev-parse", "HEAD")).Output[0]).Trim().ToLowerInvariant()
  if ($head -ne $expectedSourceCommit.ToLowerInvariant()) {
    throw "source commit mismatch: expected $expectedSourceCommit, got $head"
  }
  # ExpectedSourceCommit is an external approval token for the entire tracked Git tree,
  # including hooks and other executable surfaces; remote reachability is not inferred here.
  $tree = ([string](Invoke-SPGit $source @("rev-parse", ($head + "^{tree}"))).Output[0]).Trim().ToLowerInvariant()
  $dirty = @((Invoke-SPGit $source @("status", "--porcelain", "--untracked-files=no")).Output)
  if ($dirty.Count -gt 0) { throw "source repository must have a clean tracked tree" }
  $claudeManifest = Read-SPCommitJson $source $head ".claude-plugin/plugin.json"
  $codexManifest = Read-SPCommitJson $source $head ".codex-plugin/plugin.json"
  $version = [string]$claudeManifest.version
  Assert-SPValidVersion $version
  if ($codexManifest.version -ne $version) { throw "source manifests disagree on package version" }
  if ($expectedVersion -ne $version) { throw "ExpectedVersion '$expectedVersion' does not match source version '$version'" }
  if ($claudeManifest.repository -ne $script:SPForkUrl -or $codexManifest.repository -ne $script:SPForkUrl -or $codexManifest.interface.websiteURL -ne $script:SPForkUrl) {
    throw "source repository identity does not match approved fork"
  }
  $package = Get-SPCommitPackageInfo $source $head
  if ($package.Digest -ne $script:SPApprovedPackageDigest -or $package.Digest -ne $expectedPackageDigest) {
    throw "source package digest mismatch: expected $expectedPackageDigest, got $($package.Digest)"
  }
  return [pscustomobject]@{
    SourceRepo = $source
    Commit = $head
    Tree = $tree
    Version = $version
    PackageDigest = $package.Digest
    PackagePaths = @($package.Paths)
  }
}

function Get-SPTreeFingerprint([string]$path) {
  $item = Get-SPItem $path
  if ($null -eq $item) { return Get-SPStringSha256 "ABSENT" }
  Assert-SPPlainTree $path "CAS path"
  $root = Get-SPCanonicalPath $path
  $records = New-Object System.Collections.Generic.List[string]
  $stack = New-Object System.Collections.Generic.Stack[string]
  $stack.Push($root)
  while ($stack.Count -gt 0) {
    $current = $stack.Pop()
    $currentItem = Get-SPItem $current
    $relative = $current.Substring($root.Length).TrimStart("\").Replace("\", "/")
    if ($currentItem.PSIsContainer) {
      $records.Add("D|$relative") | Out-Null
      foreach ($child in @(Get-ChildItem -LiteralPath $current -Force | Sort-Object Name -Descending)) {
        $stack.Push($child.FullName)
      }
    } else {
      $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $current).Hash.ToLowerInvariant()
      $records.Add("F|$relative|$($currentItem.Length)|$hash") | Out-Null
    }
  }
  return Get-SPStringSha256 (($records | Sort-Object) -join [Environment]::NewLine)
}

function Remove-SPTree([string]$path, [string]$allowedRoot) {
  Assert-SPContained $allowedRoot $path "delete path"
  $item = Get-SPItem $path
  if ($null -eq $item) { return }
  Assert-SPPlainTree $path "delete tree"
  function Remove-Node([string]$node) {
    $nodeItem = Get-SPItem $node
    if ($nodeItem.PSIsContainer) {
      foreach ($child in @(Get-ChildItem -LiteralPath $node -Force)) { Remove-Node $child.FullName }
      [System.IO.Directory]::Delete($node, $false)
    } else {
      Remove-Item -LiteralPath $node -Force
    }
  }
  Remove-Node $path
}

function Write-SPDurableBytes([string]$path, [byte[]]$bytes) {
  $parent = Split-Path -Parent $path
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  Assert-SPNoReparseAncestors $parent "durable write"
  Assert-SPSingleLinkFile $path "durable target"
  $temporary = Join-Path $parent (".durable-" + [guid]::NewGuid().ToString("N") + ".tmp")
  $options = [System.IO.FileOptions]::WriteThrough
  $stream = New-Object System.IO.FileStream($temporary, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 4096, $options)
  try {
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
  } finally {
    $stream.Dispose()
  }
  if (Test-Path -LiteralPath $path) {
    $backup = $path + ".durable-backup"
    Assert-SPSingleLinkFile $backup "durable backup"
    if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
    [System.IO.File]::Replace($temporary, $path, $backup, $true)
    Assert-SPSingleLinkFile $backup "durable backup"
    if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Force }
  } else {
    [System.IO.File]::Move($temporary, $path)
  }
}

function Write-SPDurableText([string]$path, [string]$text) {
  Write-SPDurableBytes $path ([System.Text.UTF8Encoding]::new($false).GetBytes($text))
}

function Write-SPDurableJson([string]$path, $value) {
  Write-SPDurableText $path ($value | ConvertTo-Json -Depth 30)
}

function Get-SPCheckoutInfo(
  [string]$path,
  [string]$expectedCommit,
  [string]$expectedDigest,
  [string]$expectedVersion,
  [bool]$requireMetadata = $false,
  [string]$expectedActiveTarget = ""
) {
  $checkout = Get-SPCanonicalPath $path
  Assert-SPNoReparseAncestors $checkout "checkout"
  Assert-SPPlainTree $checkout "checkout"
  $gitDir = Join-Path $checkout ".git"
  if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) { throw "checkout has no valid .git directory: $checkout" }
  $head = ([string](Invoke-SPGit $checkout @("rev-parse", "HEAD")).Output[0]).Trim().ToLowerInvariant()
  if ($head -ne $expectedCommit.ToLowerInvariant()) { throw "checkout source commit mismatch at $checkout" }
  $indexLines = @((Invoke-SPGit $checkout @("ls-files", "-s")).Output)
  if ($indexLines.Count -eq 0) { throw "checkout has no tracked content: $checkout" }
  $indexOids = @{}
  foreach ($line in $indexLines) {
    $parts = ([string]$line).Split(@("`t"), 2, [StringSplitOptions]::None)
    if ($parts.Count -ne 2) { throw "checkout index has an unsupported path record" }
    $metadata = $parts[0].Split(@(" "), [StringSplitOptions]::RemoveEmptyEntries)
    if ($metadata.Count -lt 3 -or $metadata[2] -ne "0") { throw "checkout index contains non-stage-zero entry" }
    $relative = $parts[1].Replace("\", "/")
    if ($indexOids.ContainsKey($relative)) { throw "checkout index contains duplicate path: $relative" }
    $indexOids[$relative] = $metadata[1]
  }
  $tracked = @($indexOids.Keys | Sort-Object)
  if ($tracked.Count -eq 0) { throw "checkout has no tracked content: $checkout" }
  $expectedTree = ([string](Invoke-SPGit $checkout @("rev-parse", ($expectedCommit + "^{tree}"))).Output[0]).Trim()
  $indexTree = ([string](Invoke-SPGit $checkout @("write-tree")).Output[0]).Trim()
  if ($indexTree -ne $expectedTree) {
    throw "checkout index tree differs from source commit"
  }
  foreach ($relative in $tracked) {
    $file = Join-Path $checkout ($relative.Replace("/", "\"))
    $item = Get-SPItem $file
    if ($null -eq $item -or $item.PSIsContainer -or (Test-SPReparseItem $item)) { throw "tracked checkout file is missing or non-regular: $relative" }
    if ($item.LinkType -eq "HardLink") { throw "tracked checkout file has multi-hardlink identity: $relative" }
  }
  for ($offset = 0; $offset -lt $tracked.Count; $offset += 128) {
    $end = [Math]::Min($offset + 127, $tracked.Count - 1)
    $chunk = @($tracked[$offset..$end])
    $actualHashes = @($chunk | & git --no-replace-objects -C $checkout hash-object --no-filters --stdin-paths 2>&1)
    if ($LASTEXITCODE -ne 0) {
      throw "batch checkout byte hashing failed: $($actualHashes -join ' ')"
    }
    if ($actualHashes.Count -ne $chunk.Count) {
      throw "batch checkout byte hashing returned an incomplete result"
    }
    for ($chunkIndex = 0; $chunkIndex -lt $chunk.Count; $chunkIndex++) {
      $relative = $chunk[$chunkIndex]
      $actual = ([string]$actualHashes[$chunkIndex]).Trim()
      $expected = [string]$indexOids[$relative]
      if ($actual -ne $expected) { throw "tracked checkout bytes differ from source commit: $relative" }
    }
  }
  $allowedUntracked = if ($requireMetadata) { @(".in_use", ".superpowers-active.json") } else { @() }
  $files = New-Object System.Collections.Generic.List[string]
  foreach ($file in @(Get-ChildItem -LiteralPath $checkout -Recurse -Force -File)) {
    $relative = $file.FullName.Substring($checkout.Length).TrimStart("\").Replace("\", "/")
    if ($relative.StartsWith(".git/", [StringComparison]::OrdinalIgnoreCase)) { continue }
    $files.Add($relative) | Out-Null
  }
  $expectedFiles = @($tracked + $allowedUntracked | Sort-Object -Unique)
  $actualFiles = @($files | Sort-Object -Unique)
  if (($expectedFiles -join [char]0) -ne ($actualFiles -join [char]0)) {
    $rogue = @($actualFiles | Where-Object { $expectedFiles -notcontains $_ })
    $missing = @($expectedFiles | Where-Object { $actualFiles -notcontains $_ })
    throw "checkout content enumeration mismatch; rogue=[$($rogue -join ',')], missing=[$($missing -join ',')]"
  }
  $package = Get-SPCommitPackageInfo $checkout $expectedCommit
  if ($package.Digest -ne $expectedDigest -or $package.Digest -ne $script:SPApprovedPackageDigest) {
    throw "checkout package digest mismatch at $checkout"
  }
  $claudeManifest = Get-Content -Raw -LiteralPath (Join-Path $checkout ".claude-plugin\plugin.json") -Encoding utf8 | ConvertFrom-Json
  $codexManifest = Get-Content -Raw -LiteralPath (Join-Path $checkout ".codex-plugin\plugin.json") -Encoding utf8 | ConvertFrom-Json
  if ($claudeManifest.version -ne $expectedVersion -or $codexManifest.version -ne $expectedVersion) { throw "checkout manifest version mismatch" }
  if ($claudeManifest.repository -ne $script:SPForkUrl -or $codexManifest.repository -ne $script:SPForkUrl -or $codexManifest.interface.websiteURL -ne $script:SPForkUrl) {
    throw "checkout repository identity mismatch"
  }
  foreach ($required in @(
    "skills\using-superpowers\SKILL.md",
    "skills\brainstorming\SKILL.md",
    "skills\writing-plans\SKILL.md",
    "skills\subagent-driven-development\SKILL.md"
  )) {
    if (-not (Test-Path -LiteralPath (Join-Path $checkout $required) -PathType Leaf)) { throw "checkout missing required active skill: $required" }
  }
  $using = Get-Content -Raw -LiteralPath (Join-Path $checkout "skills\using-superpowers\SKILL.md") -Encoding utf8
  $brainstorming = Get-Content -Raw -LiteralPath (Join-Path $checkout "skills\brainstorming\SKILL.md") -Encoding utf8
  $writing = Get-Content -Raw -LiteralPath (Join-Path $checkout "skills\writing-plans\SKILL.md") -Encoding utf8
  if (-not $using.Contains("current host session") -or -not $brainstorming.Contains("never by a required reviewer persona") -or -not $writing.Contains("FOCUS =") -or -not $writing.Contains("RC =")) {
    throw "checkout required active skill semantics mismatch"
  }
  if ($requireMetadata) {
    $metadataPath = Join-Path $checkout ".superpowers-active.json"
    $markerPath = Join-Path $checkout ".in_use"
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw "active checkout missing .in_use marker" }
    $metadata = Get-Content -Raw -LiteralPath $metadataPath -Encoding utf8 | ConvertFrom-Json
    if ($metadata.version -ne $expectedVersion -or $metadata.gitCommitSha -ne $expectedCommit -or
        $metadata.gitTreeSha -ne $expectedTree -or $metadata.packageDigest -ne $expectedDigest) {
      throw "active checkout metadata identity mismatch"
    }
    $activeTarget = if ($expectedActiveTarget) { Get-SPCanonicalPath $expectedActiveTarget } else { $checkout }
    if (-not (Get-SPCanonicalPath ([string]$metadata.target)).Equals($activeTarget, [StringComparison]::OrdinalIgnoreCase)) {
      throw "active checkout metadata target mismatch"
    }
  }
  return [pscustomobject]@{
    Path = $checkout
    Commit = $head
    Tree = $expectedTree
    PackageDigest = $package.Digest
    Content = $actualFiles
  }
}

function New-SPExactCheckout(
  [string]$sourceRepo,
  [string]$destination,
  [string]$expectedCommit,
  [string]$expectedDigest,
  [string]$expectedVersion
) {
  if (Test-Path -LiteralPath $destination) { throw "staging destination already exists: $destination" }
  $parent = Split-Path -Parent $destination
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  Assert-SPNoReparseAncestors $parent "staging parent"
  $result = @(& git --no-replace-objects -c core.longpaths=true clone --no-checkout --no-local --no-hardlinks --quiet -- "$sourceRepo" "$destination" 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "exact staging clone failed: $($result -join ' ')" }
  Invoke-SPGit $destination @("config", "--local", "core.autocrlf", "false") | Out-Null
  Invoke-SPGit $destination @("config", "--local", "core.longpaths", "true") | Out-Null
  Invoke-SPGit $destination @("checkout", "--quiet", $expectedCommit) | Out-Null
  return Get-SPCheckoutInfo $destination $expectedCommit $expectedDigest $expectedVersion $false
}

function Set-SPActiveMetadata(
  [string]$checkout,
  [string]$version,
  [string]$commit,
  [string]$tree,
  [string]$digest,
  [string]$sourceRepo,
  [string]$activeTarget = ""
) {
  Write-SPDurableBytes (Join-Path $checkout ".in_use") ([byte[]]@())
  $metadata = [ordered]@{
    schema_version = "2.0"
    version = $version
    gitCommitSha = $commit
    gitTreeSha = $tree
    packageDigest = $digest
    sourceRepo = $sourceRepo
    activatedAt = [DateTime]::UtcNow.ToString("o")
    target = if ($activeTarget) { Get-SPCanonicalPath $activeTarget } else { Get-SPCanonicalPath $checkout }
  }
  Write-SPDurableJson (Join-Path $checkout ".superpowers-active.json") $metadata
}
