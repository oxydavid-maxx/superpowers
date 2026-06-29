#!/usr/bin/env python3
"""CAP-4 discoverability audit (problem-B token containment, 2026-06-26).

Guards the slim: every domain/gate rule moved off the always-on CLAUDE.md prefix
must stay reachable — present as a rules-registry.yaml entry (injected on match) —
and the slim CLAUDE.md must still point at the registry so nothing is orphaned.
Enforcement itself is unchanged; this audits DISCOVERABILITY, not enforcement.

Exit 1 + list failures if anything went dark. Run after any edit to the registry
or CLAUDE.md slim. NOT tautological: EXPECTED_REGISTRY_KEYS is the curated set the
slim relied on, so dropping any entry later reddens this.
"""
from __future__ import annotations
import sys
from pathlib import Path
try:
    import yaml
except Exception:
    print("PyYAML missing"); sys.exit(1)

H = Path.home() / ".claude"

EXPECTED_REGISTRY_KEYS = {
    "git-protocol", "local-webpage-tunnel", "image-gen", "browser-control",
    "doc-storage", "it-permission", "plaud", "session-recovery",
    "recurring-routines", "maturity-assessment", "luminex-deploy", "goldfish",
    "plan-mode", "rationalizations", "escalation-charter", "wiki-ingest",
}

def main() -> int:
    fails = []

    # 1. registry parses + has every expected key with non-empty text
    try:
        reg = (yaml.safe_load((H / "rules-registry.yaml").read_text(encoding="utf-8")) or {})
        entries = {e.get("key"): (e.get("text") or "").strip() for e in (reg.get("rules") or [])}
    except Exception as e:
        print(f"FAIL: rules-registry.yaml unreadable: {e}"); return 1
    for k in sorted(EXPECTED_REGISTRY_KEYS):
        if k not in entries:
            fails.append(f"registry MISSING key '{k}' (discoverability went dark)")
        elif not entries[k]:
            fails.append(f"registry key '{k}' has EMPTY text")

    # 2. slim CLAUDE.md still points at the registry (discoverability not orphaned)
    try:
        cmd = (H / "CLAUDE.md").read_text(encoding="utf-8")
    except Exception as e:
        print(f"FAIL: CLAUDE.md unreadable: {e}"); return 1
    if "rules-registry.yaml" not in cmd:
        fails.append("CLAUDE.md no longer points at rules-registry.yaml (orphaned discoverability)")

    # 3. enforcement intact: gate-rules.yaml still parses and has rules
    try:
        g = yaml.safe_load((H / "gate-rules.yaml").read_text(encoding="utf-8")) or {}
        n = len(g.get("rules") or [])
        if n == 0:
            fails.append("gate-rules.yaml has zero rules (enforcement broken)")
    except Exception as e:
        fails.append(f"gate-rules.yaml unreadable: {e}")

    if fails:
        print("DISCOVERABILITY AUDIT FAILED:")
        for f in fails:
            print("  -", f)
        return 1
    print(f"OK: {len(entries)} registry rules reachable; CLAUDE.md points at registry; "
          f"{n} gate rules intact (enforcement unchanged).")
    return 0

if __name__ == "__main__":
    sys.exit(main())
