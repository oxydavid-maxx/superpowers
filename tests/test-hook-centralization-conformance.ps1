$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$cases = @(
  @{ Path = "hooks\hooks-codex.json"; Manifest = "~/.codex/hooks/event-dispatch-manifest.json" },
  @{ Path = "hooks\hooks.json"; Manifest = "~/.claude/hooks/event-dispatch-manifest.json" }
)

foreach ($case in $cases) {
  $path = Join-Path $root $case.Path
  $config = Get-Content -Raw -LiteralPath $path -Encoding utf8 | ConvertFrom-Json
  if ($config.centralHookRegistration.mode -ne "central-only") {
    throw "$($case.Path) is not central-only"
  }
  if ($config.centralHookRegistration.manifest -ne $case.Manifest) {
    throw "$($case.Path) points at the wrong central dispatcher manifest"
  }
  if ($config.centralHookRegistration.plugin -ne "superpowers") {
    throw "$($case.Path) lost the superpowers registration identity"
  }
  if (@($config.hooks.psobject.Properties).Count -ne 0) {
    throw "$($case.Path) resurrected plugin-local host command chains"
  }
}

Write-Host "PASS: Claude and Codex Superpowers hooks delegate only to the central dispatcher"
