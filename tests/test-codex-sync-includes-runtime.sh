#!/usr/bin/env bash
# RT-F1 guard: the Codex plugin sync must INCLUDE lib/runtime (bundled V-model runtime) while
# still excluding the rest of /lib/. rsync is first-match-wins, so the /lib/runtime include MUST
# precede the /lib/** exclude. This proves the rules + order in scripts/sync-to-codex-plugin.sh
# (always), and the semantics via an rsync dry-run when rsync is available.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SYNC="${ROOT}/scripts/sync-to-codex-plugin.sh"
fail() { echo "FAIL: $1"; exit 1; }

grep -qF -- '--include="/lib/runtime/***"' "$SYNC" || fail "no /lib/runtime/*** include in sync script"
grep -qF -- '"/lib/**"' "$SYNC" || fail "EXCLUDES does not narrow /lib/ to /lib/**"
grep -Eq '^[[:space:]]*"/lib/"[[:space:]]*$' "$SYNC" && fail "a bare /lib/ exclude remains (would exclude lib/runtime)"

inc_line=$(grep -nF -- '--include="/lib/runtime/***"' "$SYNC" | head -1 | cut -d: -f1)
exc_loop_line=$(grep -nF 'for pat in "${EXCLUDES[@]}"' "$SYNC" | head -1 | cut -d: -f1)
[ -n "$inc_line" ] && [ -n "$exc_loop_line" ] || fail "could not locate include/exclude lines"
[ "$inc_line" -lt "$exc_loop_line" ] || fail "runtime include ($inc_line) must precede EXCLUDES loop ($exc_loop_line)"
echo "GUARD OK: /lib/runtime/*** include present and precedes the /lib/** exclude (line $inc_line < $exc_loop_line)"

if command -v rsync >/dev/null 2>&1; then
  TMP="$(mktemp -d)"; SRC="$TMP/src"; DST="$TMP/dst"
  mkdir -p "$SRC/lib/runtime/payload" "$SRC/lib/runtime/tests/__pycache__" "$SRC/skills"
  echo x > "$SRC/lib/runtime/payload/spec_audit.py"
  echo x > "$SRC/lib/runtime/tests/__pycache__/foo.pyc"
  echo x > "$SRC/lib/unrelated.py"
  echo x > "$SRC/skills/s.md"
  out=$(rsync -a --dry-run --itemize-changes \
    --include="/lib/" \
    --exclude="/lib/runtime/**/__pycache__/" --exclude="/lib/runtime/**/*.pyc" \
    --include="/lib/runtime/***" --exclude="/lib/**" "$SRC/" "$DST/" 2>/dev/null)
  echo "$out" | grep -q "lib/runtime/payload/spec_audit.py" || { rm -rf "$TMP"; fail "dry-run dropped lib/runtime payload"; }
  echo "$out" | grep -q "lib/unrelated.py" && { rm -rf "$TMP"; fail "dry-run wrongly shipped unrelated lib"; }
  echo "$out" | grep -q "foo.pyc" && { rm -rf "$TMP"; fail "dry-run wrongly shipped a .pyc"; }
  echo "$out" | grep -q "skills/s.md" || { rm -rf "$TMP"; fail "dry-run dropped skills"; }
  rm -rf "$TMP"; echo "DRY-RUN OK: runtime in, other-lib out, pyc out, skills in"
else
  echo "SKIP rsync dry-run (rsync not on PATH here); grep+order guard is authoritative. Production sync host requires rsync (script asserts it at runtime)."
fi
echo "PASS: codex sync includes lib/runtime (RT-F1)"
