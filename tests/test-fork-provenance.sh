#!/usr/bin/env bash
# Fork-local guard: published manifests must identify oxydavid-maxx/superpowers as
# the active plugin source. Upstream attribution can remain in prose/docs, but runtime
# manifests must not point agents back to the official marketplace repository.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if command -v py >/dev/null 2>&1; then PY=(py -3)
elif command -v python3 >/dev/null 2>&1; then PY=(python3)
else PY=(python); fi

"${PY[@]}" - "$ROOT" <<'PY'
import json
import os
import sys

root = sys.argv[1]
fork_url = "https://github.com/oxydavid-maxx/superpowers"

checks = [
    (".claude-plugin/plugin.json", "homepage"),
    (".claude-plugin/plugin.json", "repository"),
    (".codex-plugin/plugin.json", "homepage"),
    (".codex-plugin/plugin.json", "repository"),
    (".codex-plugin/plugin.json", "interface.websiteURL"),
    (".cursor-plugin/plugin.json", "homepage"),
    (".cursor-plugin/plugin.json", "repository"),
    (".kimi-plugin/plugin.json", "homepage"),
    (".kimi-plugin/plugin.json", "interface.websiteURL"),
]

failures = []
for rel, field in checks:
    path = os.path.join(root, rel)
    cur = json.load(open(path, encoding="utf-8"))
    for seg in field.split("."):
        cur = cur[seg]
    print(f"  {rel} ({field}) => {cur}")
    if cur != fork_url:
        failures.append(f"{rel}:{field} expected {fork_url}, got {cur}")

if failures:
    print("FAIL: fork provenance drift")
    for failure in failures:
        print(f"  - {failure}")
    sys.exit(1)

print("PASS: runtime manifests point to oxydavid-maxx/superpowers")
PY
