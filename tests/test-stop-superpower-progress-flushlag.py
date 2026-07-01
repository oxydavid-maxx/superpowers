#!/usr/bin/env python3
"""Standalone smoke test for hooks/stop-superpower-progress's flush-lag retry
(2026-07-01 regression: a live production session hit 4 consecutive false
"missing marker" verdicts even though each retried response correctly
included the marker -- confirmed root cause: the transcript file on disk can
lag behind the just-emitted assistant turn under rapid Stop-hook retries).

Run: py -3 tests/test-stop-superpower-progress-flushlag.py
"""
import json
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOOK = ROOT / "hooks" / "stop-superpower-progress"

FAILURES = []


def _run(transcript_path: str, session_id: str = "smoke-test") -> tuple[int, str]:
    payload = json.dumps({"transcript_path": transcript_path, "session_id": session_id})
    r = subprocess.run(
        [sys.executable, str(HOOK)], input=payload,
        capture_output=True, text=True, timeout=15,
    )
    return r.returncode, r.stderr


def _write(path: Path, user_text: str, assistant_text: str) -> None:
    lines = [
        json.dumps({"type": "user", "message": {"content": user_text}}),
        json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": assistant_text}]}}),
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def check(name: str, cond: bool, detail: str = "") -> None:
    status = "PASS" if cond else "FAIL"
    print(f"[{status}] {name}" + (f" -- {detail}" if detail and not cond else ""))
    if not cond:
        FAILURES.append(name)


def test_marker_present_allows():
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "t.jsonl"
        _write(p, "use superpowers:brainstorming", "Superpower: now=S0_DISCUSS(...). Hi.")
        rc, err = _run(str(p))
        check("marker present -> exit 0", rc == 0, f"rc={rc} err={err!r}")


def test_marker_missing_denies():
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "t.jsonl"
        _write(p, "use superpowers:brainstorming", "Hi, ready when you are.")
        rc, err = _run(str(p))
        check("marker genuinely missing -> exit 2", rc == 2, f"rc={rc}")
        check("exit-2 message mentions the marker", "Superpower: now=" in err, err)


def test_out_of_scope_no_superpower_skill_allows():
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "t.jsonl"
        _write(p, "hi", "Hi there, no progress line needed.")
        rc, _ = _run(str(p))
        check("no superpowers:* skill ever invoked -> exit 0 (out of scope)", rc == 0)


def test_flush_lag_recovers_via_retry():
    """Simulate the real incident: the file is STALE (missing marker) at the
    moment the hook first reads it, then gets updated with the marker shortly
    after (async flush completing) -- the hook must retry and end up exit 0,
    not permanently deny a response that DID include the marker."""
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "t.jsonl"
        _write(p, "use superpowers:brainstorming", "Hi, working on it.")  # stale: no marker

        def _flush_after_delay():
            time.sleep(0.08)  # land inside the hook's own retry window
            _write(p, "use superpowers:brainstorming",
                   "Superpower: now=S0_DISCUSS(...). Hi, working on it.")

        t = threading.Thread(target=_flush_after_delay)
        t.start()
        rc, err = _run(str(p))
        t.join()
        check("flush-lag: marker appears mid-retry -> exit 0 (not falsely denied)",
              rc == 0, f"rc={rc} err={err!r}")


if __name__ == "__main__":
    test_marker_present_allows()
    test_marker_missing_denies()
    test_out_of_scope_no_superpower_skill_allows()
    test_flush_lag_recovers_via_retry()
    if FAILURES:
        print(f"\n{len(FAILURES)} FAILED: {FAILURES}")
        sys.exit(1)
    print("\nALL CHECKS PASSED")
    sys.exit(0)
