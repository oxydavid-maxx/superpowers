# Fork Maintenance — `oxydavid-maxx/superpowers`

This fork carries 光佑's V-model verification arm on top of upstream `obra/superpowers`. Our customizations are fork-specific — they are NEVER PR'd upstream (per their CLAUDE.md, fork-sync / fork-feature / rebrand PRs are rejected).

## Layout

```
C:\dev\skills\superpowers/              ← local clone (this repo)
  origin   = https://github.com/oxydavid-maxx/superpowers   (our fork)
  upstream = https://github.com/obra/superpowers            (read-only — sync FROM only)
```

Our V-model additions live in:
- `skills/brainstorming/SKILL.md` — `## Surfaces` requirement + investigate-first + visual-mock-after-spec
- `skills/writing-plans/SKILL.md` — deterministic executor handoff + product-coverage boundary
- `skills/writing-arch/` — **superseded/historical**: architecture placement is now encoded by `Capability Registry.entry_point` + `## Surfaces`; this directory is no longer active or callable
- `skills/verify-arch/` (new) — right-arm SWE.5 integration verify
- `skills/verify-spec/` (new) — right-arm SWE.6 acceptance verify
- `package.json` / `.claude-plugin/*.json` — version `6.0.3-native.N`

## Routine: sync FROM upstream (keep our fork current)

Cadence: when there's an upstream feature/fix we want, or quarterly. Not every commit.

```bash
cd C:\dev\skills\superpowers
git fetch upstream
git rebase upstream/main
# Resolve any conflicts (likely in brainstorming/writing-plans where we edited).
# Our changes are localized to specific sections — keep ours where we changed,
# accept theirs where they touched untouched parts.
git push --force-with-lease origin main
```

Then refresh the installed plugin in any active Claude Code:
```bash
claude plugin marketplace update superpowers-dev
# In a running session: /reload-plugins
```

`--force-with-lease` (not bare `--force`): refuses if someone else pushed since our last fetch — protects against accidental overwrite.

## Routine: ship a new V-model change to the fork

1. Edit `skills/.../SKILL.md` (or other fork files).
2. Bump version in `package.json`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (e.g. `6.0.3-native.1` → `6.0.3-native.2`).
3. `git commit -m "feat(native): <what changed>"; git push origin main`
4. `claude plugin marketplace update superpowers-dev` to pull the new version into the cache.
5. In the running session: `/reload-plugins` (or just open a new session).

## Routine: rollback to the official upstream plugin

One command — official plugin is kept installed-but-disabled for instant rollback:
```bash
claude plugin enable superpowers@claude-plugins-official
claude plugin disable superpowers@superpowers-dev
# /reload-plugins in any running session
```

## NEVER do

- **Do NOT open a PR upstream** with fork-specific changes. Their CLAUDE.md closes them; 94% PR rejection rate.
- **Do NOT bare `--force` push** to fork main — use `--force-with-lease`.
- **Do NOT edit `~/.claude/plugins/cache/superpowers-dev/...` directly.** That's the installed copy; updates overwrite it. Edit `C:\dev\skills\superpowers/`, commit, push, then `plugin marketplace update`.

## Why we forked (one-line)

Plugin skills are namespaced (`superpowers:<skill>`) — a personal skill of the same name CANNOT override the plugin's. And cache edits revert on update. Forking is the only documented path to change a plugin skill's behavior. (Claude Code docs verified 2026-06-26.)

## Routine: cut a release + pin the local install (no human memory)

When shipped content changes after a release, run this ONE sequence (do not rely on
remembering to police official-marketplace drift or stale caches):

```bash
# 1. bump every declared manifest (jq-free; all 7 targets)
bash scripts/bump-version.sh 6.0.3-native.<N+1>
# 2. coherency + provenance gates
bash scripts/bump-version.sh --check && bash tests/test-manifest-version-coherency.sh && bash tests/test-fork-provenance.sh
# 3. commit + push this source repo
git add -A && git commit -m "release(6.0.3-native.<N+1>): ..." && git push
```
```powershell
# 4. pin the LOCAL Claude + Codex install to the reviewed release identity
#    (<FULL-COMMIT> is the explicitly reviewed full source-commit approval token)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/pin-local-fork-install.ps1 -ExpectedVersion 6.0.3-native.<N+1> -ExpectedSourceCommit <FULL-COMMIT> -ExpectedPackageDigest <APPROVED-PACKAGE-DIGEST>
# (standalone verify, if needed)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-local-fork-install.ps1 -ExpectedVersion 6.0.3-native.<N+1> -ExpectedSourceCommit <FULL-COMMIT> -ExpectedPackageDigest <APPROVED-PACKAGE-DIGEST>
```

For the currently approved `6.0.3-native.18` package, `<APPROVED-PACKAGE-DIGEST>` is
`2f686cf09aff6d76b0416df01fb7e0cd71b949a2b7542b46984c1f908a9d29e3`. Every new release
changes the manifest blobs, so its package digest and the script approval constant must be
independently recomputed and reviewed; never reuse the prior digest.

`ExpectedSourceCommit` is the external approval token for the entire tracked Git tree, including
hooks and other executable surfaces. The routine pushes first, but the script proves exact
commit/tree equality and approved-origin identity; it does not infer remote reachability.

`pin-local-fork-install.ps1` (idempotent, temp-home-friendly) accepts only an approved-origin,
tracked-clean source whose HEAD equals that approval token and package digest. For BOTH the Claude
and Codex homes it creates two distinct regular, contained, byte-exact Git checkouts:
`cache/superpowers-dev/superpowers/<version>` and
`cache/superpowers-dev/superpowers/current`. Neither checkout may be a reparse point. `current` carries
`.in_use` and `.superpowers-active.json` resolved metadata (`version`, `gitCommitSha`, `gitTreeSha`, source,
activation time). The script **quarantines** (moves, never deletes) stale fork caches + any
official-marketplace Superpowers caches into `plugins/.quarantine-superpowers-<ts>/`, backs up +
repins Claude `installed_plugins.json` (removes `superpowers@claude-plugins-official`, points
`superpowers@superpowers-dev` at the stable `current` pointer with the new version +
gitCommitSha + gitTreeSha), and leaves `known_marketplaces.json` + other plugins untouched. Then it runs the
verifier.

**Drift self-detection:** the verifier requires Claude's `installPath` to point at the stable
regular `current` checkout, rejects reparse/hardlink escape surfaces, and proves both regular
`current` and versioned checkouts match the exact approved commit and full tracked tree (including
executable surfaces), approved package digest, tracked bytes,
manifest version, and required skill semantics. A future official re-add, stale cache, rogue file,
content drift, or rollback without matching metadata is caught by re-running pin
(idempotent) or verify — no manual cache surgery, no remembering.

**Regression for the scripts themselves:**
`powershell -NoProfile -ExecutionPolicy Bypass -File tests/test-local-fork-install.ps1`
seeds a dirty temp install and proves official-removed + distinct exact regular checkouts +
caches-quarantined + version/commit/digest binding + idempotence. Run it whenever the pin/verify scripts
change.

Release/install verification must confirm both plugin install metadata and Claude skill registry entries route through `cache/superpowers-dev/superpowers/current`. Versioned `6.0.3-native.N` caches remain immutable audit targets, but active discovery must not hard-pin skill entries to those versioned paths.
