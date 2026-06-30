# Superpower Entry Runtime Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. User override: S4_BUILD executor is Claude Code. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Superpower invocation reliable across Claude and Codex by adding a natural-language complete stage-order entry contract, stable `current` registry routing, and verification gates that reject stale hard-pins.

**Architecture:** Keep immutable `6.0.3-vmodel.N` caches for auditability, but route active discovery through `superpowers/current`. Encode the entry behavior in `using-superpowers`, validate it with contract tests, and extend pin/verify scripts so Claude registry entries also use `current` instead of versioned paths.

**Tech Stack:** Markdown skills, PowerShell install/verify scripts, existing Python runtime tests, existing vmodel contract tests.

## Global Constraints

- S4_BUILD executor is Claude Code.
- Claude Code owns implementation only; current session owns spec, verification plan, independent verification, release, push, and final signoff.
- Claude Code must not edit `docs/superpowers/specs/2026-06-30-superpower-entry-runtime-reliability-design.md`.
- Claude Code must not edit `.superpowers/verify/test-design.json` or `.superpowers/verify/test-design.md`.
- Claude Code must not push.
- Preserve the stable `current` pointer model for both Claude and Codex.
- Do not add LangGraph in this iteration.
- Do not hardcode `home-superpower`, `Codex`, or `Claude` as a default owner in the entry response contract.

## File Structure

- Modify: `skills/using-superpowers/SKILL.md` — add the entry comprehension contract and required stage/skill mapping.
- Modify: `tests/test-vmodel-contracts.ps1` — add static regression checks for entry contract, S4-only outsourcing, and current-pointer registry contracts.
- Modify: `scripts/pin-local-fork-install.ps1` — rewrite Claude `skills/registry.yaml` Superpower entries to the stable `current` pointer after pinning.
- Modify: `scripts/verify-local-fork-install.ps1` — fail when Claude active skill registry hard-pins Superpower to a versioned cache path.
- Optional modify: `FORK-MAINTENANCE.md` — if needed, document that release/install must keep Claude and Codex discovery pointed at `current`.
- Create: `.superpowers/orch/outbox/2026-06-30-superpower-entry-runtime-reliability.ack.json` — Claude Code build report.

## Task 1: Add Contract Tests First

**Files:**
- Modify: `tests/test-vmodel-contracts.ps1`

**Interfaces:**
- Consumes: current skill/script text.
- Produces: failing tests that describe the required entry and current-pointer behavior.

- [ ] **Step 1: Add entry-contract assertions**

Append this block after `$brainstorming` is loaded:

```powershell
$usingSuperpowers = Get-Content -Raw -LiteralPath (Join-Path $Root "skills\using-superpowers\SKILL.md")
Assert-Contains $usingSuperpowers "complete stage-order" "using-superpowers must require a complete stage-order recap"
Assert-Contains $usingSuperpowers "S0_DISCUSS" "using-superpowers must name S0_DISCUSS"
Assert-Contains $usingSuperpowers "S2_VERIFICATION_PLAN" "using-superpowers must name S2_VERIFICATION_PLAN"
Assert-Contains $usingSuperpowers "S4_BUILD executor" "using-superpowers must define S4_BUILD executor"
Assert-Contains $usingSuperpowers "current session" "using-superpowers must use current session as the default owner/executor wording"
Assert-Contains $usingSuperpowers "fixed boilerplate" "using-superpowers must reject boilerplate-only entry responses"
Assert-Contains $usingSuperpowers "superpowers:writing-verification-plans" "using-superpowers must map S2 to writing-verification-plans"
Assert-Contains $usingSuperpowers "superpowers:verify-spec" "using-superpowers must map S5_VERIFY_SPEC to verify-spec"
if ($usingSuperpowers -match "Owner:\s*(Codex|Claude)") {
  throw "using-superpowers must not hardcode Codex or Claude as default owner"
}
```

- [ ] **Step 2: Add install-script assertions**

Append this block after job/ack schema checks:

```powershell
$pinScript = Get-Content -Raw -LiteralPath (Join-Path $Root "scripts\pin-local-fork-install.ps1")
Assert-Contains $pinScript "Repin-ClaudeSkillRegistry" "pin-local-fork-install must repin Claude skills registry entries"
Assert-Contains $pinScript "skills\\registry.yaml" "pin-local-fork-install must update Claude skills/registry.yaml"
Assert-Contains $pinScript "superpowers-dev\\superpowers\\current" "pin-local-fork-install must route registry entries through current"

$verifyInstall = Get-Content -Raw -LiteralPath (Join-Path $Root "scripts\verify-local-fork-install.ps1")
Assert-Contains $verifyInstall "skills\\registry.yaml" "verify-local-fork-install must inspect Claude skills registry"
Assert-Contains $verifyInstall "hard-pins" "verify-local-fork-install must reject hard-pinned Superpower registry entries"
Assert-Contains $verifyInstall "superpowers-dev\\superpowers\\current" "verify-local-fork-install must require current pointer in registry entries"
```

- [ ] **Step 3: Run tests and confirm RED**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tests/test-vmodel-contracts.ps1
```

Expected: FAIL before implementation, with at least one message naming `using-superpowers`, `Repin-ClaudeSkillRegistry`, or `hard-pins`.

## Task 2: Implement Natural-Language Complete Stage-Order Entry Contract

**Files:**
- Modify: `skills/using-superpowers/SKILL.md`

**Interfaces:**
- Consumes: entry-contract tests from Task 1.
- Produces: skill text that future sessions must follow when Superpower is invoked.

- [ ] **Step 1: Add an entry contract section before `# Using Skills`**

Insert this section:

```markdown
## Superpower Entry Comprehension Gate

When the user explicitly says "use superpower", "superpower", "superpower fork", or equivalent, the first substantive response MUST be a natural-language complete stage-order recap. This is a comprehension gate, not a fixed banner.

The response MUST include:

| Stage | Required skill mapping |
|---|---|
| S0_DISCUSS | `superpowers:brainstorming` |
| S1_SPEC_DRAFT | `superpowers:brainstorming` |
| S1_EXPECTED_MOCK_V1 | `superpowers:brainstorming` |
| S1_SOTA | `superpowers:brainstorming` + source research/WebSearch |
| S1_SPEC_FINAL | `superpowers:brainstorming` |
| S1_EXPECTED_MOCK_V2 | `superpowers:brainstorming` |
| S2_VERIFICATION_PLAN | `superpowers:writing-verification-plans` |
| S3_IMPLEMENTATION_PLAN | `superpowers:writing-plans` |
| S4_BUILD | `superpowers:executing-plans`, `superpowers:test-driven-development`, or `superpowers:subagent-driven-development` as applicable |
| S5_VERIFY_ARCH | `superpowers:verify-arch`, only for multi-entry projects |
| S5_VERIFY_SPEC | `superpowers:verify-spec` |
| S5_FIX_LOOP | `superpowers:systematic-debugging` plus repeat S4/S5 |
| S6_RELEASE | `superpowers:verification-before-completion` + `superpowers:finishing-a-development-branch` |

The response MUST also state:

- Current state is `S0_DISCUSS`.
- Current action is requirements clarification only.
- Owner is `current session`.
- `S4_BUILD executor` defaults to `current session`.
- Only `S4_BUILD executor` can become external, and only after explicit confirmation before S4_BUILD.

The response MUST NOT:

- Only paste fixed boilerplate.
- Hardcode Codex or Claude as the default owner.
- Ask for an external session before S4_BUILD.
- Write a spec, plan, or code before S0_DISCUSS is complete.
```

- [ ] **Step 2: Run contract tests**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tests/test-vmodel-contracts.ps1
```

Expected: entry-contract assertions PASS; install-script assertions still FAIL until Task 3/4.

## Task 3: Repin Claude Skill Registry Through `current`

**Files:**
- Modify: `scripts/pin-local-fork-install.ps1`

**Interfaces:**
- Consumes: `$claudeActive` from `Set-CurrentPointer`.
- Produces: Claude `skills/registry.yaml` entries that point at `...\superpowers\current\skills\...`.

- [ ] **Step 1: Add registry repin function after `Repin-ClaudeManifest`**

```powershell
function Repin-ClaudeSkillRegistry([string]$homeDir, [string]$activePath) {
  $registry = Join-Path $homeDir "skills\registry.yaml"
  if (-not (Test-Path -LiteralPath $registry)) { return }

  $bak = "$registry.bak-$ts"
  Copy-Item -LiteralPath $registry -Destination $bak -Force
  $script:result.backup_paths += $bak

  $content = Get-Content -Raw -LiteralPath $registry -Encoding utf8
  $escapedHome = [regex]::Escape($homeDir)
  $pattern = "${escapedHome}\\plugins\\cache\\superpowers-dev\\superpowers\\[^\\`r`n]+?\\skills\\"
  $replacement = ($activePath -replace "\\", "\\") + "\\skills\\"
  $updated = [regex]::Replace($content, $pattern, $replacement)
  Set-Content -LiteralPath $registry -Value $updated -Encoding utf8
  Log "repinned Claude skills registry entries -> current"
}
```

- [ ] **Step 2: Call it in the Claude section**

After:

```powershell
Repin-ClaudeManifest $ClaudeHome $claudeActive
```

add:

```powershell
Repin-ClaudeSkillRegistry $ClaudeHome $claudeActive
```

- [ ] **Step 3: Run contract tests**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tests/test-vmodel-contracts.ps1
```

Expected: pin-script assertions PASS; verify-script assertions still FAIL until Task 4.

## Task 4: Reject Hard-Pinned Superpower Registry Entries

**Files:**
- Modify: `scripts/verify-local-fork-install.ps1`

**Interfaces:**
- Consumes: active Claude `skills/registry.yaml`.
- Produces: verifier failure when any active Superpower registry entry uses a versioned cache path instead of `current`.

- [ ] **Step 1: Add registry verifier before Codex current check**

```powershell
$claudeSkillRegistry = Join-Path $ClaudeHome "skills\registry.yaml"
if (Test-Path -LiteralPath $claudeSkillRegistry) {
  $hardPins = Select-String -LiteralPath $claudeSkillRegistry -Pattern "superpowers-dev\\superpowers\\(?!current\\)" -ErrorAction SilentlyContinue
  if ($hardPins) {
    Add-Error "Claude skills registry entry hard-pins Superpowers version instead of current: $($hardPins.LineNumber -join ', ')"
  }
  $missingCurrent = Select-String -LiteralPath $claudeSkillRegistry -Pattern "superpowers-dev\\superpowers\\current\\skills\\using-superpowers\\SKILL.md" -ErrorAction SilentlyContinue
  if (-not $missingCurrent) {
    Add-Error "Claude skills registry does not point using-superpowers at stable current pointer"
  }
}
```

- [ ] **Step 2: Run contract tests**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tests/test-vmodel-contracts.ps1
```

Expected: PASS.

## Task 5: Update Maintenance Documentation If Needed

**Files:**
- Optional modify: `FORK-MAINTENANCE.md`

**Interfaces:**
- Consumes: changed pin/verify semantics.
- Produces: documented release expectation for current-pointer routing.

- [ ] **Step 1: If the doc lacks registry-current wording, add this short note**

```markdown
Release/install verification must confirm both plugin install metadata and Claude skill registry entries route through `cache/superpowers-dev/superpowers/current`. Versioned `6.0.3-vmodel.N` caches remain immutable audit targets, but active discovery must not hard-pin skill entries to those versioned paths.
```

- [ ] **Step 2: Run contract tests again**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tests/test-vmodel-contracts.ps1
```

Expected: PASS.

## Task 6: Full Build Verification And Ack

**Files:**
- Create: `.superpowers/orch/outbox/2026-06-30-superpower-entry-runtime-reliability.ack.json`

**Interfaces:**
- Consumes: all changes from Tasks 1-5.
- Produces: Claude Code build report for current session verification.

- [ ] **Step 1: Run required tests**

Run:

```powershell
py -3 -m pytest lib/runtime/tests -q
powershell -ExecutionPolicy Bypass -File tests/test-vmodel-contracts.ps1
powershell -ExecutionPolicy Bypass -File scripts/verify-local-fork-install.ps1
```

Expected: all PASS.

- [ ] **Step 2: Check scope**

Run:

```powershell
git status --short
git diff --name-only
```

Expected changed files only:

```text
skills/using-superpowers/SKILL.md
tests/test-vmodel-contracts.ps1
scripts/pin-local-fork-install.ps1
scripts/verify-local-fork-install.ps1
FORK-MAINTENANCE.md
.superpowers/orch/outbox/2026-06-30-superpower-entry-runtime-reliability.ack.json
```

`FORK-MAINTENANCE.md` is optional. No spec, test-design, release, or push-only files may be touched.

- [ ] **Step 3: Commit locally**

Run:

```powershell
git add skills/using-superpowers/SKILL.md tests/test-vmodel-contracts.ps1 scripts/pin-local-fork-install.ps1 scripts/verify-local-fork-install.ps1 FORK-MAINTENANCE.md .superpowers/orch/outbox/2026-06-30-superpower-entry-runtime-reliability.ack.json
git commit -m "fix: enforce superpower entry and current registry routing"
```

Expected: one focused commit. Do not push.

- [ ] **Step 4: Write ack JSON**

Write `.superpowers/orch/outbox/2026-06-30-superpower-entry-runtime-reliability.ack.json` with:

```json
{
  "schema_version": 1,
  "job_id": "2026-06-30-superpower-entry-runtime-reliability",
  "builder_session": "Claude Code",
  "status": "done",
  "head_sha_before": "<before>",
  "head_sha_after": "<after>",
  "touched_files": [
    "skills/using-superpowers/SKILL.md",
    "tests/test-vmodel-contracts.ps1",
    "scripts/pin-local-fork-install.ps1",
    "scripts/verify-local-fork-install.ps1"
  ],
  "forbidden_paths": [],
  "tests": [
    {"command": "py -3 -m pytest lib/runtime/tests -q", "result": "pass"},
    {"command": "powershell -ExecutionPolicy Bypass -File tests/test-vmodel-contracts.ps1", "result": "pass"},
    {"command": "powershell -ExecutionPolicy Bypass -File scripts/verify-local-fork-install.ps1", "result": "pass"}
  ],
  "commit": "<commit sha>",
  "notes": "Implemented S4_BUILD only. Did not edit spec/test-design/release/push files."
}
```

If any required test fails and cannot be fixed inside S4 scope, write `status: "blocked"` with the exact blocker.

---

## Current Session Verification After Claude Code

Current session must independently run:

```powershell
py -3 -m pytest lib/runtime/tests -q
powershell -ExecutionPolicy Bypass -File tests/test-vmodel-contracts.ps1
powershell -ExecutionPolicy Bypass -File scripts/pin-local-fork-install.ps1
powershell -ExecutionPolicy Bypass -File scripts/verify-local-fork-install.ps1
```

Then inspect:

```powershell
Select-String -Path "$env:USERPROFILE\.claude\skills\registry.yaml" -Pattern "superpowers-dev\\superpowers\\6\.0\.3-vmodel"
Select-String -Path "$env:USERPROFILE\.claude\skills\registry.yaml" -Pattern "superpowers-dev\\superpowers\\current\\skills\\using-superpowers\\SKILL.md"
Get-Item "$env:USERPROFILE\.claude\plugins\cache\superpowers-dev\superpowers\current" | Format-List FullName,LinkType,Target
Get-Item "$env:USERPROFILE\.codex\plugins\cache\superpowers-dev\superpowers\current" | Format-List FullName,LinkType,Target
```

Expected:

- No hard-pinned `6.0.3-vmodel` Superpower entries in Claude skill registry.
- `using-superpowers` points through `current`.
- Claude and Codex `current` pointers resolve to the active version.

## Recommended executor: Claude Code

User explicitly selected Claude Code for S4_BUILD.
