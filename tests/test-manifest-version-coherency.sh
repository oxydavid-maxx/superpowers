#!/usr/bin/env bash
# REL-F1 / MF-F1: version-coherency regression driven by the AUTHORITATIVE registry
# (.version-bump.json) — every declared target is checked (not a hardcoded subset), including
# .claude-plugin/marketplace.json (plugins.0.version) and gemini-extension.json. All declared
# versions must agree (single V-model release line); drift => fail. A documented intentional
# exception must be encoded here explicitly.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if command -v py >/dev/null 2>&1; then PY=(py -3)
elif command -v python3 >/dev/null 2>&1; then PY=(python3)
else PY=(python); fi
"${PY[@]}" - "$ROOT" <<'PY'
import json, os, sys
root = sys.argv[1]
reg = json.load(open(os.path.join(root, ".version-bump.json"), encoding="utf-8"))
vers = {}
for e in reg["files"]:
    cur = json.load(open(os.path.join(root, e["path"]), encoding="utf-8"))
    for seg in e["field"].split("."):
        cur = cur[int(seg)] if seg.isdigit() else cur[seg]
    vers["%s (%s)" % (e["path"], e["field"])] = cur
for k, v in vers.items():
    print("  %-52s => %s" % (k, v))
uniq = set(vers.values())
if None in uniq:
    print("FAIL: a declared target is missing its version"); sys.exit(1)
if len(uniq) != 1:
    print("FAIL: declared versions diverge:", sorted(uniq)); sys.exit(1)
print("PASS: all %d declared version targets coherent at %s" % (len(vers), uniq.pop()))
PY
