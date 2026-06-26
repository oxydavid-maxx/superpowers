# Fork Maintenance — `oxydavid-maxx/superpowers`

This fork carries 光佑's V-model verification arm on top of upstream `obra/superpowers`. Our customizations are fork-specific — they are NEVER PR'd upstream (per their CLAUDE.md, fork-sync / fork-feature / rebrand PRs are rejected).

## Layout

```
C:\dev\superpowers-fork/                ← local clone (this repo)
  origin   = https://github.com/oxydavid-maxx/superpowers   (our fork)
  upstream = https://github.com/obra/superpowers            (read-only — sync FROM only)
```

Our V-model additions live in:
- `skills/brainstorming/SKILL.md` — native writing-arch routing + `## Surfaces` requirement + investigate-first + visual-mock-after-spec
- `skills/writing-plans/SKILL.md` — deterministic executor handoff + product-coverage boundary
- `skills/writing-arch/` (new) — left-arm architecture phase, multi-entry only
- `skills/verify-arch/` (new) — right-arm SWE.5 integration verify
- `skills/verify-spec/` (new) — right-arm SWE.6 acceptance verify
- `package.json` / `.claude-plugin/*.json` — version `6.0.3-vmodel.N`

## Routine: sync FROM upstream (keep our fork current)

Cadence: when there's an upstream feature/fix we want, or quarterly. Not every commit.

```bash
cd C:\dev\superpowers-fork
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
2. Bump version in `package.json`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (e.g. `6.0.3-vmodel.1` → `6.0.3-vmodel.2`).
3. `git commit -m "feat(vmodel): <what changed>"; git push origin main`
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
- **Do NOT edit `~/.claude/plugins/cache/superpowers-dev/...` directly.** That's the installed copy; updates overwrite it. Edit `C:\dev\superpowers-fork/`, commit, push, then `plugin marketplace update`.

## Why we forked (one-line)

Plugin skills are namespaced (`superpowers:<skill>`) — a personal skill of the same name CANNOT override the plugin's. And cache edits revert on update. Forking is the only documented path to change a plugin skill's behavior. (Claude Code docs verified 2026-06-26.)
