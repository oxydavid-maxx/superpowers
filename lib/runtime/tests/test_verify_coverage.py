import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from verify_coverage import evaluate_coverage, reconcile_baseline


def _reg(*ids):
    return {"capabilities": [{"cap_id": i} for i in ids]}


def _verdicts(now, **kv):
    return {"results": [
        {"cap_id": c, "verdict": v, "evidence_ts": now - age}
        for c, (v, age) in kv.items()
    ]}


def test_all_matches_fresh_is_complete():
    now = 1000.0
    out = evaluate_coverage(_reg("CAP-01", "CAP-02"),
                            _verdicts(now, **{"CAP-01": ("MATCHES", 10), "CAP-02": ("MATCHES", 10)}),
                            now=now, max_age_s=3600)
    assert out["complete"] is True
    assert out["uncovered"] == []


def test_missing_cap_is_incomplete():
    now = 1000.0
    out = evaluate_coverage(_reg("CAP-01", "CAP-02"),
                            _verdicts(now, **{"CAP-01": ("MATCHES", 10)}),
                            now=now, max_age_s=3600)
    assert out["complete"] is False
    assert out["uncovered"] == ["CAP-02"]


def test_misplaced_blocks():
    now = 1000.0
    out = evaluate_coverage(_reg("CAP-01"),
                            _verdicts(now, **{"CAP-01": ("MISPLACED", 10)}),
                            now=now, max_age_s=3600)
    assert out["complete"] is False
    assert "CAP-01" in out["non_matches"]


def test_stale_evidence_blocks():
    now = 1000.0
    out = evaluate_coverage(_reg("CAP-01"),
                            _verdicts(now, **{"CAP-01": ("MATCHES", 99999)}),
                            now=now, max_age_s=3600)
    assert out["complete"] is False
    assert "CAP-01" in out["stale"]


def test_dropped_capability_is_flagged():
    out = reconcile_baseline(_reg("CAP-01"), _reg("CAP-01", "CAP-02"), signed_off=set())
    assert out["dropped"] == ["CAP-02"]
    assert out["ok"] is False


def test_dropped_but_signed_off_passes():
    out = reconcile_baseline(_reg("CAP-01"), _reg("CAP-01", "CAP-02"), signed_off={"CAP-02"})
    assert out["dropped"] == ["CAP-02"]
    assert out["ok"] is True
