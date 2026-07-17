param(
  [string]$ReceiptRoot = "",
  [string]$ReceiptOutput = "",
  [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$pin = Join-Path $repoRoot "scripts\pin-local-fork-install.ps1"
$verify = Join-Path $repoRoot "scripts\verify-local-fork-install.ps1"
$approvedDigest = "b070d6682ffd64fc21cd3e507c77be3661cfbe309a49dafd82814f5f676bfdcf"
$expectedVersion = "6.0.3-native.18"
$fails = New-Object System.Collections.Generic.List[string]

function Check-Category([bool]$condition, [string]$name, [string]$detail) {
  if (-not $condition) {
    $script:fails.Add($name) | Out-Null
    Write-Host "  FAIL [$name]: $detail"
  } else {
    Write-Host "  PASS [$name]"
  }
}

function Invoke-Git([string]$repo, [string[]]$arguments) {
  $output = @(& git --no-replace-objects -C $repo @arguments)
  if ($LASTEXITCODE -ne 0) {
    throw ("git failed in {0}: {1}" -f $repo, ($arguments -join " "))
  }
  return $output
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

function Get-CommitPackageDigest([string]$repo, [string]$commit) {
  $paths = @(Invoke-Git $repo @("ls-tree", "-r", "--name-only", $commit, "--", ".claude-plugin/plugin.json", ".codex-plugin/plugin.json", "skills") | Sort-Object)
  $records = New-Object System.Collections.Generic.List[string]
  foreach ($relative in $paths) {
    $spec = "{0}:{1}" -f $commit, $relative
    $objectId = @(Invoke-Git $repo @("rev-parse", $spec))[0].Trim()
    $records.Add("$relative|$objectId") | Out-Null
  }
  return [pscustomobject]@{
    digest = Get-StringSha256 ($records -join [Environment]::NewLine)
    paths = $paths
  }
}

function Get-HomeFingerprint([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return Get-StringSha256 "ABSENT" }
  $records = New-Object System.Collections.Generic.List[string]
  function Walk([string]$itemPath) {
    $item = Get-Item -LiteralPath $itemPath -Force
    $relative = $itemPath.Substring($path.Length).TrimStart("\").Replace("\", "/")
    if ($item.LinkType) {
      $records.Add("L|$relative|$($item.LinkType)|$(@($item.Target) -join ';')") | Out-Null
      return
    }
    if ($item.PSIsContainer) {
      $records.Add("D|$relative") | Out-Null
      foreach ($child in @(Get-ChildItem -LiteralPath $itemPath -Force | Sort-Object Name)) {
        Walk $child.FullName
      }
      return
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $itemPath).Hash.ToLowerInvariant()
    $records.Add("F|$relative|$($item.Length)|$hash") | Out-Null
  }
  Walk $path
  return Get-StringSha256 (($records | Sort-Object) -join [Environment]::NewLine)
}

function New-CleanSource([string]$destination) {
  & git -c core.longpaths=true clone --no-local --no-hardlinks --quiet -- "$repoRoot" "$destination"
  if ($LASTEXITCODE -ne 0) { throw "cannot clone clean test source" }
  & git -C $destination config user.email "pin-security@test.invalid"
  & git -C $destination config user.name "Pin Security Test"
  & git -C $destination config core.autocrlf false
  & git -C $destination config core.longpaths true
  return (& git --no-replace-objects -C $destination rev-parse HEAD).Trim()
}

function Set-ManifestVersion([string]$source, [string]$version) {
  foreach ($relative in @(".claude-plugin\plugin.json", ".codex-plugin\plugin.json")) {
    $path = Join-Path $source $relative
    $json = Get-Content -Raw -LiteralPath $path -Encoding utf8 | ConvertFrom-Json
    $json.version = $version
    $json | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
  }
}

function Commit-All([string]$source, [string]$message) {
  & git -C $source add -A
  & git -C $source commit --quiet -m $message
  if ($LASTEXITCODE -ne 0) { throw "cannot create test source commit: $message" }
  return (& git --no-replace-objects -C $source rev-parse HEAD).Trim()
}

function Invoke-PinAttempt(
  [string]$claudeHome,
  [string]$codexHome,
  [string]$source,
  [string]$sourceCommit,
  [string]$packageDigest,
  [hashtable]$extra = @{}
) {
  $arguments = @{
    ClaudeHome = $claudeHome
    CodexHome = $codexHome
    SourceRepo = $source
    ExpectedVersion = $expectedVersion
    ExpectedSourceCommit = $sourceCommit
    ExpectedPackageDigest = $packageDigest
  }
  foreach ($key in $extra.Keys) { $arguments[$key] = $extra[$key] }
  try {
    $output = @(& $pin @arguments)
    return [pscustomobject]@{
      ok = $true
      message = ""
      output = $output
      json = if ($output.Count) { ($output -join [Environment]::NewLine) | ConvertFrom-Json } else { $null }
    }
  } catch {
    return [pscustomobject]@{
      ok = $false
      message = $_.Exception.Message
      output = @()
      json = $null
    }
  }
}

function Invoke-Verifier(
  [string]$claudeHome,
  [string]$codexHome,
  [string]$sourceCommit,
  [string]$packageDigest
) {
  $output = @(& $verify -ClaudeHome $claudeHome -CodexHome $codexHome -ExpectedVersion $expectedVersion -ExpectedSourceCommit $sourceCommit -ExpectedPackageDigest $packageDigest)
  return [pscustomobject]@{
    exitCode = $LASTEXITCODE
    output = $output -join [Environment]::NewLine
  }
}

function Seed-RegularCurrent([string]$homePath, [string]$label) {
  $current = Join-Path $homePath "plugins\cache\superpowers-dev\superpowers\current"
  New-Item -ItemType Directory -Force -Path $current | Out-Null
  [IO.File]::WriteAllText((Join-Path $current "legacy-sentinel.txt"), $label)
  return $current
}

function Get-PinChildArguments(
  [string]$claudeHome,
  [string]$codexHome,
  [string]$source,
  [string]$sourceCommit,
  [string]$hardKillAt = "None",
  [int]$holdLockMilliseconds = 0
) {
  return @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $pin,
    "-ClaudeHome", $claudeHome,
    "-CodexHome", $codexHome,
    "-SourceRepo", $source,
    "-ExpectedVersion", $expectedVersion,
    "-ExpectedSourceCommit", $sourceCommit,
    "-ExpectedPackageDigest", $approvedDigest,
    "-HardKillAt", $hardKillAt,
    "-HoldLockMilliseconds", [string]$holdLockMilliseconds
  )
}

function Wait-ProcessBounded($process, [int]$milliseconds = 60000) {
  if (-not $process.WaitForExit($milliseconds)) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    throw "child pin process timed out"
  }
  $process.WaitForExit()
  $process.Refresh()
}

$testTemp = if (Test-Path -LiteralPath "C:\tmp" -PathType Container) { "C:\tmp" } else { $env:TEMP }
if (-not $ReceiptRoot) {
  $ReceiptRoot = Join-Path $testTemp ("sp-pin-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
}
if (Test-Path -LiteralPath $ReceiptRoot) {
  throw "ReceiptRoot must not already exist: $ReceiptRoot"
}
$tmp = New-Item -ItemType Directory -Force -Path $ReceiptRoot
$receipts = Join-Path $tmp "receipts"
New-Item -ItemType Directory -Force -Path $receipts | Out-Null

try {
  $pinParameters = @((Get-Command $pin).Parameters.Keys)
  $verifyParameters = @((Get-Command $verify).Parameters.Keys)
  $requiredPinApi = @("ExpectedSourceCommit", "ExpectedPackageDigest", "HardKillAt", "HoldLockMilliseconds")
  $requiredVerifyApi = @("ExpectedSourceCommit", "ExpectedPackageDigest")
  $missingPinApi = @($requiredPinApi | Where-Object { $pinParameters -notcontains $_ })
  $missingVerifyApi = @($requiredVerifyApi | Where-Object { $verifyParameters -notcontains $_ })
  $unsafePinApi = @("SkipVerify" | Where-Object { $pinParameters -contains $_ })
  if ($missingPinApi.Count -gt 0 -or $missingVerifyApi.Count -gt 0 -or $unsafePinApi.Count -gt 0) {
    $detail = "missing pin API [$($missingPinApi -join ',')], verifier API [$($missingVerifyApi -join ',')], unsafe bypass API [$($unsafePinApi -join ',')]"
    foreach ($name in @("F1-version-containment", "F2-link-hardlink-roots", "F3-source-identity", "F4-idempotent-content", "F5-verifier-spoof", "F6-crash-concurrency")) {
      Check-Category $false $name $detail
    }
    Write-Host "RED: $($fails.Count) secure pin finding(s) unresolved"
    exit 1
  }

  $source = Join-Path $tmp "source"
  $baseCommit = New-CleanSource $source
  $baseTree = (& git --no-replace-objects -C $source rev-parse ($baseCommit + "^{tree}")).Trim().ToLowerInvariant()
  $basePackage = Get-CommitPackageDigest $source $baseCommit

  $f1Errors = New-Object System.Collections.Generic.List[string]
  $invalidVersions = @("..", "C:\absolute", "bad/sep", "bad\sep", "CON", ("6.0.3-native." + [char]1))
  foreach ($invalidVersion in $invalidVersions) {
    & git -C $source reset --hard --quiet $baseCommit
    & git -C $source clean -fdq
    Set-ManifestVersion $source $invalidVersion
    $invalidCommit = Commit-All $source ("invalid version " + ([guid]::NewGuid().ToString("N")))
    $caseRoot = Join-Path $tmp ("version-" + [guid]::NewGuid().ToString("N"))
    $claude = Join-Path $caseRoot "claude"
    $codex = Join-Path $caseRoot "codex"
    $outside = Join-Path $caseRoot "outside-sentinel.bin"
    New-Item -ItemType Directory -Force -Path $caseRoot | Out-Null
    [IO.File]::WriteAllBytes($outside, [byte[]](0, 1, 2, 253, 254, 255))
    $beforeOutside = (Get-FileHash -Algorithm SHA256 -LiteralPath $outside).Hash
    $attempt = Invoke-PinAttempt $claude $codex $source $invalidCommit $approvedDigest
    if ($attempt.ok -or $attempt.message -notmatch "invalid package version") {
      $f1Errors.Add("'$invalidVersion' was not rejected by version grammar: $($attempt.message)") | Out-Null
    }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $outside).Hash -ne $beforeOutside) {
      $f1Errors.Add("'$invalidVersion' changed outside sentinel") | Out-Null
    }
    if ((Test-Path -LiteralPath $claude) -or (Test-Path -LiteralPath $codex)) {
      $f1Errors.Add("'$invalidVersion' mutated a configured home") | Out-Null
    }
  }
  & git -C $source reset --hard --quiet $baseCommit
  & git -C $source clean -fdq
  Check-Category ($f1Errors.Count -eq 0) "F1-version-containment" ($f1Errors -join "; ")

  $f2Errors = New-Object System.Collections.Generic.List[string]
  $linkRoot = Join-Path $tmp "link-attacks"
  $externalJunction = Join-Path $linkRoot "junction-external"
  $junctionClaude = Join-Path $linkRoot "junction-claude"
  $junctionCodex = Join-Path $linkRoot "junction-codex"
  New-Item -ItemType Directory -Force -Path $externalJunction, $junctionClaude, $junctionCodex | Out-Null
  [IO.File]::WriteAllText((Join-Path $externalJunction "sentinel.txt"), "junction-safe")
  New-Item -ItemType Junction -Path (Join-Path $junctionClaude "plugins") -Target $externalJunction | Out-Null
  $attempt = Invoke-PinAttempt $junctionClaude $junctionCodex $source $baseCommit $approvedDigest
  if ($attempt.ok -or $attempt.message -notmatch "reparse") { $f2Errors.Add("junction ancestor was not rejected: $($attempt.message)") | Out-Null }
  if ([IO.File]::ReadAllText((Join-Path $externalJunction "sentinel.txt")) -ne "junction-safe") { $f2Errors.Add("junction target changed") | Out-Null }

  $externalSymlink = Join-Path $linkRoot "symlink-external"
  $symlinkClaude = Join-Path $linkRoot "symlink-claude"
  $symlinkCodex = Join-Path $linkRoot "symlink-codex"
  New-Item -ItemType Directory -Force -Path $externalSymlink, $symlinkClaude, $symlinkCodex | Out-Null
  try {
  $symlinkCoverage = "symbolic-link"
    New-Item -ItemType SymbolicLink -Path (Join-Path $symlinkCodex "plugins") -Target $externalSymlink -ErrorAction Stop | Out-Null
  } catch [System.UnauthorizedAccessException] {
    $symlinkCoverage = "native-reparse-fallback-no-symlink-privilege"
    # Non-elevated Windows without Developer Mode cannot create symlinks. Exercise the same
    # native reparse-point guard with a Windows app-execution alias instead of silently skipping.
    $nativeReparse = Get-ChildItem -LiteralPath "$env:LOCALAPPDATA\Microsoft\WindowsApps" -Force |
      Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 } |
      Select-Object -First 1
    if ($null -eq $nativeReparse) { throw "cannot create or locate a real native reparse point for symbolic-link coverage" }
    $symlinkCodex = Join-Path $nativeReparse.FullName "codex-home"
  }
  $attempt = Invoke-PinAttempt $symlinkClaude $symlinkCodex $source $baseCommit $approvedDigest
  if ($attempt.ok -or $attempt.message -notmatch "reparse") { $f2Errors.Add("symbolic-link/native-reparse ancestor was not rejected: $($attempt.message)") | Out-Null }
  $hardRoot = Join-Path $linkRoot "hardlink"
  $hardClaude = Join-Path $hardRoot "claude"
  $hardCodex = Join-Path $hardRoot "codex"
  $externalManifest = Join-Path $hardRoot "external-manifest.json"
  New-Item -ItemType Directory -Force -Path (Join-Path $hardClaude "plugins"), $hardCodex | Out-Null
  [IO.File]::WriteAllText($externalManifest, '{ "version": 2, "plugins": {} }')
  New-Item -ItemType HardLink -Path (Join-Path $hardClaude "plugins\installed_plugins.json") -Target $externalManifest | Out-Null
  $beforeHardlink = (Get-FileHash -Algorithm SHA256 -LiteralPath $externalManifest).Hash
  $attempt = Invoke-PinAttempt $hardClaude $hardCodex $source $baseCommit $approvedDigest
  if ($attempt.ok -or $attempt.message -notmatch "hardlink") { $f2Errors.Add("multi-hardlink manifest was not rejected: $($attempt.message)") | Out-Null }
  if ((Get-FileHash -Algorithm SHA256 -LiteralPath $externalManifest).Hash -ne $beforeHardlink) { $f2Errors.Add("hardlink peer changed") | Out-Null }

  $overlap = Join-Path $linkRoot "overlap"
  $attempt = Invoke-PinAttempt $overlap (Join-Path $overlap "codex") $source $baseCommit $approvedDigest
  if ($attempt.ok -or $attempt.message -notmatch "overlap") { $f2Errors.Add("overlapping homes were not rejected: $($attempt.message)") | Out-Null }
  $extendedAlias = "\\?\" + $overlap
  $attempt = Invoke-PinAttempt $overlap $extendedAlias $source $baseCommit $approvedDigest
  if ($attempt.ok -or $attempt.message -notmatch "alternate|overlap") { $f2Errors.Add("Win32 extended-path home alias was not rejected: $($attempt.message)") | Out-Null }
  Check-Category ($f2Errors.Count -eq 0) "F2-link-hardlink-roots" ($f2Errors -join "; ")

  $f3Errors = New-Object System.Collections.Generic.List[string]
  if ($basePackage.digest -ne $approvedDigest) { $f3Errors.Add("approved digest does not match base commit: $($basePackage.digest)") | Out-Null }
  $identityRoot = Join-Path $tmp "identity"
  $attempt = Invoke-PinAttempt (Join-Path $identityRoot "wrong-claude") (Join-Path $identityRoot "wrong-codex") $source ("0" * 40) $approvedDigest
  if ($attempt.ok -or $attempt.message -notmatch "source commit") { $f3Errors.Add("wrong expected commit accepted: $($attempt.message)") | Out-Null }

  [IO.File]::AppendAllText((Join-Path $source "README.md"), [Environment]::NewLine + "dirty")
  $attempt = Invoke-PinAttempt (Join-Path $identityRoot "dirty-claude") (Join-Path $identityRoot "dirty-codex") $source $baseCommit $approvedDigest
  if ($attempt.ok -or $attempt.message -notmatch "clean tracked") { $f3Errors.Add("dirty tracked source accepted: $($attempt.message)") | Out-Null }
  & git -C $source reset --hard --quiet $baseCommit

  $skillPath = Join-Path $source "skills\using-superpowers\SKILL.md"
  [IO.File]::AppendAllText($skillPath, [Environment]::NewLine + "substituted same-version commit")
  $substitutedCommit = Commit-All $source "substituted same-version commit"
  & git -C $source reset --hard --quiet $baseCommit
  & git -C $source replace $baseCommit $substitutedCommit
  $attempt = Invoke-PinAttempt (Join-Path $identityRoot "replace-claude") (Join-Path $identityRoot "replace-codex") $source $baseCommit $approvedDigest
  if (-not $attempt.ok) { $f3Errors.Add("replace-ref-immune exact source failed: $($attempt.message)") | Out-Null }
  & git -C $source replace -d $baseCommit | Out-Null
  & git -C $source checkout --quiet $substitutedCommit
  $attempt = Invoke-PinAttempt (Join-Path $identityRoot "substitute-claude") (Join-Path $identityRoot "substitute-codex") $source $baseCommit $approvedDigest
  if ($attempt.ok -or $attempt.message -notmatch "source commit") { $f3Errors.Add("substituted same-version HEAD accepted: $($attempt.message)") | Out-Null }
  & git -C $source checkout --quiet $baseCommit
  Check-Category ($f3Errors.Count -eq 0) "F3-source-identity" ($f3Errors -join "; ")

  $f4Errors = New-Object System.Collections.Generic.List[string]
  $contentRoot = Join-Path $tmp "content"
  $contentClaude = Join-Path $contentRoot "claude"
  $contentCodex = Join-Path $contentRoot "codex"
  $first = Invoke-PinAttempt $contentClaude $contentCodex $source $baseCommit $approvedDigest
  if (-not $first.ok) {
    $f4Errors.Add("baseline pin failed: $($first.message)") | Out-Null
  } else {
    $claudeCurrent = Join-Path $contentClaude "plugins\cache\superpowers-dev\superpowers\current"
    $codexVersioned = Join-Path $contentCodex "plugins\cache\superpowers-dev\superpowers\$expectedVersion"
    New-Item -ItemType Directory -Force -Path (Join-Path $claudeCurrent "skills\rogue") | Out-Null
    [IO.File]::WriteAllText((Join-Path $claudeCurrent "skills\rogue\SKILL.md"), "rogue-current")
    New-Item -ItemType Directory -Force -Path (Join-Path $codexVersioned "skills\rogue") | Out-Null
    [IO.File]::WriteAllText((Join-Path $codexVersioned "skills\rogue\SKILL.md"), "rogue-versioned")
    $second = Invoke-PinAttempt $contentClaude $contentCodex $source $baseCommit $approvedDigest
    if (-not $second.ok) {
      $f4Errors.Add("safe rebuild after rogue content failed: $($second.message)") | Out-Null
    } else {
      if (Test-Path -LiteralPath (Join-Path $claudeCurrent "skills\rogue\SKILL.md")) { $f4Errors.Add("rogue current skill survived") | Out-Null }
      if (Test-Path -LiteralPath (Join-Path $codexVersioned "skills\rogue\SKILL.md")) { $f4Errors.Add("rogue versioned skill survived") | Out-Null }
      if (@($second.json.claude_active_content | Where-Object { $_ -match "rogue" }).Count -gt 0) { $f4Errors.Add("receipt enumerated rogue Claude content") | Out-Null }
      if (@($second.json.codex_active_content | Where-Object { $_ -match "rogue" }).Count -gt 0) { $f4Errors.Add("receipt enumerated rogue Codex content") | Out-Null }
      if ($second.json.package_digest -ne $approvedDigest) { $f4Errors.Add("receipt package digest mismatch") | Out-Null }
      if ($second.json.source_tree -ne $baseTree) { $f4Errors.Add("receipt full source tree mismatch") | Out-Null }
      if ($second.json.source_binding_scope -ne "entire-tracked-git-tree-including-executable-surfaces") { $f4Errors.Add("receipt source binding scope mismatch") | Out-Null }
    }
  }
  Check-Category ($f4Errors.Count -eq 0) "F4-idempotent-content" ($f4Errors -join "; ")

  $f5Errors = New-Object System.Collections.Generic.List[string]
  if ($first.ok -and $null -ne $second -and $second.ok) {
    $validVerify = Invoke-Verifier $contentClaude $contentCodex $baseCommit $approvedDigest
    if ($validVerify.exitCode -ne 0) {
      $f5Errors.Add("valid exact install did not verify: $($validVerify.output)") | Out-Null
    } else {
      $installedPath = Join-Path $contentClaude "plugins\installed_plugins.json"
      $installedRaw = [IO.File]::ReadAllText($installedPath)
      $installedDocument = $installedRaw | ConvertFrom-Json
      $validEntries = @($installedDocument.plugins."superpowers@superpowers-dev")
      $extraEntry = [pscustomobject][ordered]@{
        scope = "project"
        installPath = Join-Path $tmp "outside-extra-scope"
        version = $expectedVersion
        gitCommitSha = $baseCommit
        gitTreeSha = $baseTree
        packageDigest = $approvedDigest
      }
      $installedDocument.plugins | Add-Member -MemberType NoteProperty -Name "superpowers@superpowers-dev" -Value @($validEntries + $extraEntry) -Force
      $installedDocument | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $installedPath -Encoding utf8
      $multiEntryVerify = Invoke-Verifier $contentClaude $contentCodex $baseCommit $approvedDigest
      if ($multiEntryVerify.exitCode -eq 0) { $f5Errors.Add("valid first entry plus rogue extra scoped entry verified") | Out-Null }
      [IO.File]::WriteAllText($installedPath, $installedRaw, (New-Object Text.UTF8Encoding($false)))
    }
  }
  $fakeRoot = Join-Path $tmp "fake"
  $fakeClaude = Join-Path $fakeRoot "claude"
  $fakeCodex = Join-Path $fakeRoot "codex"
  $outsideFake = Join-Path $fakeRoot "outside\superpowers-dev\superpowers\$expectedVersion"
  New-Item -ItemType Directory -Force -Path (Join-Path $fakeClaude "plugins"), (Join-Path $fakeCodex "plugins\cache\superpowers-dev\superpowers"), (Join-Path $outsideFake ".claude-plugin"), (Join-Path $outsideFake ".codex-plugin"), (Join-Path $outsideFake "skills\using-superpowers") | Out-Null
  Copy-Item -LiteralPath (Join-Path $source ".claude-plugin\plugin.json") -Destination (Join-Path $outsideFake ".claude-plugin\plugin.json")
  Copy-Item -LiteralPath (Join-Path $source ".codex-plugin\plugin.json") -Destination (Join-Path $outsideFake ".codex-plugin\plugin.json")
  Copy-Item -LiteralPath (Join-Path $source "skills\using-superpowers\SKILL.md") -Destination (Join-Path $outsideFake "skills\using-superpowers\SKILL.md")
  $fakeInstalled = [ordered]@{
    version = 2
    plugins = [ordered]@{
      "superpowers@superpowers-dev" = @([ordered]@{
        scope = "user"
        installPath = $outsideFake
        version = $expectedVersion
        gitCommitSha = $baseCommit
      })
    }
  }
  $fakeInstalled | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $fakeClaude "plugins\installed_plugins.json") -Encoding utf8
  New-Item -ItemType Junction -Path (Join-Path $fakeCodex "plugins\cache\superpowers-dev\superpowers\current") -Target $outsideFake | Out-Null
  $fakeVerify = Invoke-Verifier $fakeClaude $fakeCodex $baseCommit $approvedDigest
  if ($fakeVerify.exitCode -eq 0) { $f5Errors.Add("suffix-only outside-home fake without .git verified") | Out-Null }
  Check-Category ($f5Errors.Count -eq 0) "F5-verifier-spoof" ($f5Errors -join "; ")

  $f6Errors = New-Object System.Collections.Generic.List[string]

  # A syntactically valid mirror must not be able to self-authorize a target outside either home.
  $tamperRoot = Join-Path $tmp "tampered-journal"
  $tamperClaude = Join-Path $tamperRoot "claude"
  $tamperCodex = Join-Path $tamperRoot "codex"
  $tamperControls = @((Join-Path $tamperClaude ".superpowers-pin"), (Join-Path $tamperCodex ".superpowers-pin"))
  $tamperAssets = @((Join-Path $tamperControls[0] "a-deadbeef"), (Join-Path $tamperControls[1] "a-deadbeef"))
  New-Item -ItemType Directory -Force -Path $tamperAssets | Out-Null
  $outsideVictim = Join-Path $tamperRoot "outside-victim.bin"
  [IO.File]::WriteAllBytes($outsideVictim, [byte[]](4, 3, 2, 1, 0, 251, 252, 253))
  $outsideVictimHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outsideVictim).Hash
  $absentFingerprint = Get-StringSha256 "ABSENT"
  $tamperedRecords = @(
    [ordered]@{ name="claude-fork-base"; home=$tamperRoot; target=$outsideVictim; staged=(Join-Path $tamperAssets[0] "s"); asset_root=$tamperAssets[0]; backup=(Join-Path $tamperAssets[0] "backup-claude-fork-base"); preimage_fingerprint=$absentFingerprint; replacement_fingerprint=(Get-HomeFingerprint $outsideVictim); phase="installed" },
    [ordered]@{ name="codex-fork-base"; home=$tamperCodex; target=(Join-Path $tamperCodex "plugins\cache\superpowers-dev\superpowers"); staged=(Join-Path $tamperAssets[1] "s"); asset_root=$tamperAssets[1]; backup=(Join-Path $tamperAssets[1] "backup-codex-fork-base"); preimage_fingerprint=$absentFingerprint; replacement_fingerprint=$absentFingerprint; phase="prepared" },
    [ordered]@{ name="claude-official"; home=$tamperClaude; target=(Join-Path $tamperClaude "plugins\cache\claude-plugins-official\superpowers"); staged=""; asset_root=$tamperAssets[0]; backup=(Join-Path $tamperAssets[0] "backup-claude-official"); preimage_fingerprint=$absentFingerprint; replacement_fingerprint=$absentFingerprint; phase="prepared" },
    [ordered]@{ name="codex-official"; home=$tamperCodex; target=(Join-Path $tamperCodex "plugins\cache\claude-plugins-official\superpowers"); staged=""; asset_root=$tamperAssets[1]; backup=(Join-Path $tamperAssets[1] "backup-codex-official"); preimage_fingerprint=$absentFingerprint; replacement_fingerprint=$absentFingerprint; phase="prepared" },
    [ordered]@{ name="claude-manifest"; home=$tamperClaude; target=(Join-Path $tamperClaude "plugins\installed_plugins.json"); staged=(Join-Path $tamperAssets[0] "stage-installed_plugins.json"); asset_root=$tamperAssets[0]; backup=(Join-Path $tamperAssets[0] "backup-claude-manifest"); preimage_fingerprint=$absentFingerprint; replacement_fingerprint=$absentFingerprint; phase="prepared" }
  )
  $tamperedJournal = [ordered]@{
    schema_version="2.0"; transaction_id="20260717T000000000Z-deadbeef"; sequence=[int64]1; state="deploying";
    updated_at=[DateTime]::UtcNow.ToString("o"); claude_home=$tamperClaude; codex_home=$tamperCodex;
    source_commit=$baseCommit; source_tree=$baseTree; package_digest=$approvedDigest;
    asset_roots=$tamperAssets; records=$tamperedRecords
  }
  $tamperedRaw = $tamperedJournal | ConvertTo-Json -Depth 30
  foreach ($control in $tamperControls) {
    [IO.File]::WriteAllText((Join-Path $control "transaction.json"), $tamperedRaw, (New-Object Text.UTF8Encoding($false)))
  }
  $tamperedAttempt = Invoke-PinAttempt $tamperClaude $tamperCodex $source $baseCommit $approvedDigest
  if ($tamperedAttempt.ok -or $tamperedAttempt.message -notmatch "journal") { $f6Errors.Add("tampered managed-path journal was not rejected: $($tamperedAttempt.message)") | Out-Null }
  if (-not (Test-Path -LiteralPath $outsideVictim) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $outsideVictim).Hash -ne $outsideVictimHash) {
    $f6Errors.Add("tampered journal moved or changed an outside-home victim") | Out-Null
  }

  $finalizationKillPoints = @("AfterVerifiedBeforeFinalize", "DuringFinalize")
  foreach ($killPoint in @("AfterClaudeBeforeCodex", "AfterPointerRemoval") + $finalizationKillPoints) {
    $crashRoot = Join-Path $tmp ("crash-" + $killPoint)
    $crashClaude = Join-Path $crashRoot "claude"
    $crashCodex = Join-Path $crashRoot "codex"
    Seed-RegularCurrent $crashClaude ("claude-" + $killPoint) | Out-Null
    Seed-RegularCurrent $crashCodex ("codex-" + $killPoint) | Out-Null
    $stdout = Join-Path $crashRoot "child.out"
    $stderr = Join-Path $crashRoot "child.err"
    $arguments = Get-PinChildArguments $crashClaude $crashCodex $source $baseCommit $killPoint 0
    $child = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    Wait-ProcessBounded $child
    $crashText = ((Get-Content -Raw -LiteralPath $stdout -ErrorAction SilentlyContinue) + (Get-Content -Raw -LiteralPath $stderr -ErrorAction SilentlyContinue))
    if ($crashText -notmatch "Hard-kill injection at $killPoint") { $f6Errors.Add("$killPoint did not reach the hard-kill seam") | Out-Null }
    $journal = Join-Path $crashClaude ".superpowers-pin\transaction.json"
    if (-not (Test-Path -LiteralPath $journal -PathType Leaf)) { $f6Errors.Add("$killPoint left no durable journal") | Out-Null }
    $recovered = Invoke-PinAttempt $crashClaude $crashCodex $source $baseCommit $approvedDigest
    if (-not $recovered.ok) {
      $f6Errors.Add("$killPoint recovery failed: $($recovered.message)") | Out-Null
    } else {
      if (Test-Path -LiteralPath $journal) { $f6Errors.Add("$killPoint journal survived exact recovery") | Out-Null }
      $verified = Invoke-Verifier $crashClaude $crashCodex $baseCommit $approvedDigest
      if ($verified.exitCode -ne 0) { $f6Errors.Add("$killPoint recovered install did not verify") | Out-Null }
      foreach ($legacy in @(
        [pscustomobject]@{ Home=$crashClaude; Label=("claude-" + $killPoint) },
        [pscustomobject]@{ Home=$crashCodex; Label=("codex-" + $killPoint) }
      )) {
        $preserved = @(Get-ChildItem -LiteralPath $legacy.Home -Filter "legacy-sentinel.txt" -File -Recurse -ErrorAction SilentlyContinue | Where-Object { [IO.File]::ReadAllText($_.FullName) -eq $legacy.Label })
        if ($preserved.Count -lt 1) { $f6Errors.Add("$killPoint lost unarchived preimage sentinel for $($legacy.Label)") | Out-Null }
      }
    }
  }

  $concurrentRoot = Join-Path $tmp "concurrent"
  $concurrentClaude = Join-Path $concurrentRoot "claude"
  $concurrentCodex = Join-Path $concurrentRoot "codex"
  New-Item -ItemType Directory -Force -Path $concurrentRoot | Out-Null
  $firstOut = Join-Path $concurrentRoot "first.out"
  $firstErr = Join-Path $concurrentRoot "first.err"
  $secondOut = Join-Path $concurrentRoot "second.out"
  $secondErr = Join-Path $concurrentRoot "second.err"
  $firstArgs = Get-PinChildArguments $concurrentClaude $concurrentCodex $source $baseCommit "None" 3000
  $firstProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $firstArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $firstOut -RedirectStandardError $firstErr
  $lockPath = Join-Path $concurrentClaude ".superpowers-pin\transaction.lock"
  $deadline = [DateTime]::UtcNow.AddSeconds(10)
  while (-not (Test-Path -LiteralPath $lockPath) -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 100
  }
  if (-not (Test-Path -LiteralPath $lockPath)) { $f6Errors.Add("concurrent lock was never created") | Out-Null }
  $secondArgs = Get-PinChildArguments $concurrentClaude $concurrentCodex $source $baseCommit "None" 0
  $secondProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $secondArgs -PassThru -WindowStyle Hidden -RedirectStandardOutput $secondOut -RedirectStandardError $secondErr
  Wait-ProcessBounded $secondProcess
  Wait-ProcessBounded $firstProcess
  $secondText = ((Get-Content -Raw -LiteralPath $secondOut -ErrorAction SilentlyContinue) + (Get-Content -Raw -LiteralPath $secondErr -ErrorAction SilentlyContinue))
  $firstText = Get-Content -Raw -LiteralPath $firstOut -ErrorAction SilentlyContinue
  try { $firstReceipt = $firstText | ConvertFrom-Json } catch { $firstReceipt = $null }
  if ($null -eq $firstReceipt -or $firstReceipt.source_head -ne $baseCommit -or $firstReceipt.package_digest -ne $approvedDigest) {
    $firstError = Get-Content -Raw -LiteralPath $firstErr -ErrorAction SilentlyContinue
    $f6Errors.Add("lock owner emitted no valid success receipt: $firstError") | Out-Null
  }
  if ($secondText -notmatch "lock") { $f6Errors.Add("concurrent contender was not rejected by exclusive lock") | Out-Null }
  $concurrentVerify = Invoke-Verifier $concurrentClaude $concurrentCodex $baseCommit $approvedDigest
  if ($concurrentVerify.exitCode -ne 0) { $f6Errors.Add("concurrent winner did not leave exact install") | Out-Null }
  Check-Category ($f6Errors.Count -eq 0) "F6-crash-concurrency" ($f6Errors -join "; ")

  $receipt = [ordered]@{
    schema_version = "1.0"
    tested_source_commit = $baseCommit
    tested_source_tree = $baseTree
    source_binding_scope = "entire-tracked-git-tree-including-executable-surfaces"
    expected_version = $expectedVersion
    expected_package_digest = $approvedDigest
    complete_package_paths = @($basePackage.paths)
    test_generation = [string]$env:TEST_REASON
    receipt_harness_iteration = "focus-attempt-9-durable-bound"
    receipt_harness_defect = "Earlier runs printed a receipt inside disposable ReceiptRoot; this schema is copied outside that root before cleanup."
    finding_failures = @($fails)
    active_content = if ($second.json) {
      [ordered]@{
        claude = @($second.json.claude_active_content)
        codex = @($second.json.codex_active_content)
      }
    } else { $null }
    residual_scope = @("ACLs", "alternate-data-streams", "hardlink-topology", "timestamps")
    reparse_coverage = $symlinkCoverage
    path_alias_coverage = "Win32 extended path rejected; existing ancestors normalized by final-path handle"
    journal_binding = "exact schema, mirror, record order, managed targets, homes, stages, backups, and control assets"
    finalization_hard_kill_points = $finalizationKillPoints
  }
  $receiptPath = Join-Path $receipts "security-recovery-receipt.json"
  $receipt | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $receiptPath -Encoding utf8

  $reportedReceiptPath = $receiptPath
  if (-not $ReceiptOutput -and -not $KeepArtifacts) {
    $durableReceiptRoot = Join-Path $testTemp "superpowers-pin-receipts"
    $ReceiptOutput = Join-Path $durableReceiptRoot ("security-recovery-" + [guid]::NewGuid().ToString("N") + ".json")
  }
  if ($ReceiptOutput) {
    $receiptOutputFull = [IO.Path]::GetFullPath($ReceiptOutput)
    $tmpFull = [IO.Path]::GetFullPath([string]$tmp)
    if (-not $KeepArtifacts -and $receiptOutputFull.StartsWith($tmpFull + "\", [StringComparison]::OrdinalIgnoreCase)) {
      throw "ReceiptOutput must be outside disposable ReceiptRoot when KeepArtifacts is false"
    }
    if (Test-Path -LiteralPath $receiptOutputFull) { throw "ReceiptOutput must not already exist: $receiptOutputFull" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $receiptOutputFull) | Out-Null
    Copy-Item -LiteralPath $receiptPath -Destination $receiptOutputFull
    $reportedReceiptPath = $receiptOutputFull
  }
  if ($fails.Count -gt 0) {
    Write-Host "FAIL: $($fails.Count) secure pin finding(s) unresolved"
    exit 1
  }
  Write-Host "PASS: secure source/path/content/verifier/recovery pin"
  Write-Host "RECEIPT: $reportedReceiptPath"
} finally {
  if (-not $KeepArtifacts -and (Test-Path -LiteralPath $tmp)) {
    Remove-Item -Recurse -Force -LiteralPath $tmp
  }
}
