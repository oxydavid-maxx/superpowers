#!/usr/bin/env bash
# sync-runtime.sh — copy this plugin's bundled V-model runtime libraries into
# ${HOME}/.claude/lib so the skills that reference ~/.claude/lib/spec_* and verify_*
# actually run on a fresh install. Idempotent; creates the destination if absent;
# FAIL-OPEN (never aborts the caller) and writes ONLY to stderr — the SessionStart
# hook reserves stdout for its JSON context payload.
set -u
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="${SELF_DIR}/payload"
DEST="${HOME}/.claude/lib"
if ! mkdir -p "$DEST" 2>/dev/null; then
  echo "sync-runtime: could not create ${DEST}" >&2
  exit 0
fi
if [ -d "$SRC" ]; then
  for f in "$SRC"/*; do
    [ -e "$f" ] || continue
    [ -f "$f" ] || continue
    cp -f "$f" "$DEST/" 2>/dev/null || echo "sync-runtime: failed to copy $(basename "$f")" >&2
  done
fi
exit 0
