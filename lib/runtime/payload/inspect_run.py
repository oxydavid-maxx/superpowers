#!/usr/bin/env python3
"""Quick state inspection for any LangGraph SqliteSaver run dir.

Usage: py -3 ~/.claude/lib/inspect_run.py <run_dir>
       py -3 ~/.claude/lib/inspect_run.py runs/run-20260428-091058-73e9c556

Prints JSON of phase completion flags + brief presence + pending node.
Use this BEFORE deciding "resume from here" vs "step back further".

Reference: C:/dev/notes/personal-wiki/wiki/concepts/stepwise-checkpoint-resume.md
"""
import json
import sys
import warnings
from collections import Counter
from pathlib import Path

warnings.filterwarnings("ignore")


def inspect(run_dir: Path) -> dict:
    try:
        from langgraph.checkpoint.sqlite import SqliteSaver
    except ImportError:
        return {"error": "langgraph-checkpoint-sqlite not installed; pip install langgraph-checkpoint-sqlite"}

    db = run_dir / "checkpoint.db"
    if not db.exists():
        return {"error": f"no checkpoint.db at {db}"}

    run_id = run_dir.name
    with SqliteSaver.from_conn_string(str(db)) as saver:
        cfg = {"configurable": {"thread_id": run_id}}
        snap = saver.get(cfg)
        if not snap:
            return {"error": "no checkpoint snapshot — run may have crashed before first node completed"}

        v = snap.get("channel_values", {})
        phases = {k: v.get(k) for k in v if k.startswith("phase_") and k.endswith("_complete")}
        briefs = {k: v.get(k) is not None for k in v if k.endswith("_brief") or k == "study_doc" or k == "assessment_set"}
        review_verdicts = {k: v.get(k) for k in v if k.endswith("_verdict")}
        rework_counts = {k: v.get(k) for k in v if k.endswith("_rework_count")}

        return {
            "run_id": run_id,
            "checkpoint_path": str(db),
            "phases_complete": phases,
            "briefs_present": briefs,
            "review_verdicts": review_verdicts,
            "rework_counts": rework_counts,
            "current_step": snap.get("metadata", {}).get("step"),
            "pending_writes": [w[0] for w in snap.get("pending_writes", []) if w] if snap.get("pending_writes") else [],
            "_channel_values": v,
        }


def _print_v2_1_extras(state):
    """Defensive prints for v2.1 fields: output_language, footnote quotes, figure_type distribution."""
    if not state or not isinstance(state, dict):
        return
    print(f"output_language: {state.get('output_language', 'n/a')}")

    study_doc = state.get("study_doc") or {}
    # study_doc may be a Pydantic model or dict; coerce defensively
    if hasattr(study_doc, "model_dump"):
        try:
            study_doc = study_doc.model_dump()
        except Exception:
            study_doc = {}
    if not isinstance(study_doc, dict):
        study_doc = {}

    for fn in study_doc.get("footnotes", []) or []:
        if not isinstance(fn, dict):
            continue
        has_quote = bool(fn.get("key_finding_quote"))
        print(f"  fn-{fn.get('fn_id', '?')}: quote={'YES' if has_quote else 'no'} "
              f"access={fn.get('access') or 'n/a'}")

    fts = Counter(
        ((p.get("figure") or {}).get("figure_type", "?") if isinstance(p, dict) else "?")
        for cc in (study_doc.get("core_concepts", []) or [])
        if isinstance(cc, dict)
        for p in (cc.get("paragraphs", []) or [])
    )
    print(f"figure_type distribution: {dict(fts)}")


def main():
    if len(sys.argv) < 2:
        print("usage: inspect_run.py <run_dir>", file=sys.stderr)
        sys.exit(2)
    run_dir = Path(sys.argv[1])
    if not run_dir.exists() or not run_dir.is_dir():
        print(f"error: not a directory: {run_dir}", file=sys.stderr)
        sys.exit(2)
    result = inspect(run_dir)
    state = result.pop("_channel_values", None) if isinstance(result, dict) else None
    print(json.dumps(result, indent=2, default=str))
    # v2.1 additions
    try:
        _print_v2_1_extras(state)
    except Exception as e:
        print(f"[v2.1 extras] error: {e}", file=sys.stderr)


if __name__ == "__main__":
    main()
