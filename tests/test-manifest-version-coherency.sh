#!/usr/bin/env bash
# MF-F1: every plugin-harness manifest + package.json MUST share ONE version for the V-model
# release line. There is no documented reason for any harness to diverge; if one is added later,
# encode the exception here explicitly. Drift => this test fails.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
py -3 - "$ROOT" <<'PY'
import json, sys, os
root = sys.argv[1]
files = ["package.json", ".claude-plugin/plugin.json", ".codex-plugin/plugin.json",
         ".cursor-plugin/plugin.json", ".kimi-plugin/plugin.json"]
vers = {}
for f in files:
    with open(os.path.join(root, f), encoding="utf-8") as fh:
        vers[f] = json.load(fh).get("version")
for f, v in vers.items():
    print(f"  {f} => {v}")
uniq = set(vers.values())
if None in uniq:
    print("FAIL: a manifest is missing a version"); sys.exit(1)
if len(uniq) != 1:
    print("FAIL: manifest versions diverge:", sorted(uniq)); sys.exit(1)
print("PASS: all 5 manifests coherent at", uniq.pop())
PY
