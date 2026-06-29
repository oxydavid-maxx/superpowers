#!/usr/bin/env bash
# Fresh-HOME runtime sync test (V-model production packaging): a fresh install must be able
# to import the bundled runtime libs from ~/.claude/lib AFTER SessionStart syncs them, and
# run a markdown-level audit by construction. RED before the hooks sync; GREEN after.
#
# Windows note: the bash hook writes to ${HOME}/.claude/lib, but Windows `py -3`
# os.path.expanduser('~') keys off USERPROFILE — so we point BOTH at the same temp dir
# (HOME for bash, USERPROFILE for Python) to truly isolate from the real ~/.claude/lib.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TMPHOME="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMPHOME_WIN="$(cygpath -w "$TMPHOME")"; else TMPHOME_WIN="$TMPHOME"; fi
trap 'rm -rf "$TMPHOME"' EXIT

# 1. Run the SessionStart hook in a fresh HOME (it must sync the bundled runtime).
HOME="$TMPHOME" USERPROFILE="$TMPHOME_WIN" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "${PLUGIN_ROOT}/hooks/session-start" >/dev/null 2>&1 || true

# 2. The runtime must now be importable from the fresh HOME's ~/.claude/lib.
HOME="$TMPHOME" USERPROFILE="$TMPHOME_WIN" py -3 -c "import os,sys; sys.path.insert(0, os.path.expanduser('~/.claude/lib')); import spec_capability_discovery, spec_scaffold, spec_audit, spec_required_fields, verify_lint, verify_coverage; print('IMPORT_OK from', os.path.expanduser('~/.claude/lib'))" \
  || { echo 'FAIL: runtime not importable from fresh HOME ~/.claude/lib'; exit 1; }

# 3. End-to-end audit proof from the fresh HOME (discovery->scaffold->fill->audit).
HOME="$TMPHOME" USERPROFILE="$TMPHOME_WIN" py -3 - <<'PY' || { echo 'FAIL: markdown audit proof'; exit 1; }
import os, sys, json
sys.path.insert(0, os.path.expanduser('~/.claude/lib'))
from spec_scaffold import scaffold
from spec_audit import audit_spec_file
cap = json.loads(scaffold([{'cap_id': 'CAP-01', 'type_tags': ['editable', 'persists']}])[0])[0]
cap['user_outcome'] = 'edit a note'; cap['entry_point'] = 'note.html'
cap['entry_type'] = 'ui'; cap['reachable_path'] = '/note'
cap['acceptance'] = {'given': 'a note', 'when': 'user edits and saves',
                     'then': 'the edited text appears on the page after reload'}
cap['state_data_contract']['reload'] = 'reopen shows the edit'
cap['state_data_contract']['invariant'] = 'other fields untouched'
cap['failure_modes'] = ['an empty title shows an inline error']
md = '# spec\n\n```registry\n' + json.dumps([cap]) + '\n```\n'
assert audit_spec_file(md)['final_ready'] is True, 'final_ready not True'
print('AUDIT_OK')
PY
echo "PASS: fresh-HOME runtime sync + import + audit proof"
