"""GENERATE half of the spec-authoring guide (Task 2): turn identified capabilities + tags
into (a) a VALID registry.json skeleton with required fields present-but-empty, and (b) a
SEPARATE markdown prompt sheet. Consumes the SAME spec_required_fields source as the audit
(DRY) — baseline slots from baseline_slot_skeleton(), tag-driven contract slots from
required_contract_fields(), prompts from BASELINE_FIELDS + applicable_rules. Content-quality
items (A2 observable / A8 surface / A9 tag↔prose) cannot be scaffolded as slots — only
PROMPTED (D2). No hardcoded baseline-slot literal (the guard test enforces this)."""
import json
import os
import sys
sys.path.insert(0, os.path.expanduser("~/.claude/lib"))
from spec_required_fields import (applicable_rules, required_contract_fields,
                                   BASELINE_FIELDS, baseline_slot_skeleton)

# Content-quality judgements that cannot be a slot — emitted as prompts only (D2).
_CONTENT_PROMPTS = [
    "acceptance.then must be an OBSERVABLE user-visible outcome, not a proxy (no 'HTTP 200' / 'works' / 'looks ok').",
    "acceptance must match the cap's SURFACE: a ui cap -> a visible/rendered outcome; a cli cap -> stdout/exit-code.",
    "if the outcome involves money/authz/delete/migrate/concurrency, the matching high-risk type_tag MUST be present (tag<->prose).",
]


def scaffold(capabilities):
    """Return (registry_json_str, prompt_sheet_md). capabilities: [{cap_id, type_tags}].
    Baseline slots come from baseline_slot_skeleton() (GAP-02: NO hardcoded literal — the
    same source the audit's presence checks use)."""
    reg, sheet = [], ["# Spec authoring prompt sheet", ""]
    for cap in capabilities:
        cid, tags = cap.get("cap_id", "CAP-??"), cap.get("type_tags", [])
        entry = baseline_slot_skeleton()                 # baseline slots from the shared source
        entry["cap_id"] = cid                            # set AFTER baseline so real values win
        entry["type_tags"] = list(tags)                  # (baseline seeds type_tags=[]; restore)
        sdc = {f: "" for f in sorted(required_contract_fields(tags))}
        entry["state_data_contract"] = sdc or None
        reg.append(entry)

        sheet.append(f"## {cid}  (tags: {', '.join(tags) or 'none'})")
        for f in BASELINE_FIELDS:                        # baseline presence prompts (shared source)
            sheet.append(f"- (baseline {f['audit_item']}) {f['prompt']}  -> fill: {f['path']}")
        for r in applicable_rules(tags):                 # tag-driven contract prompts
            fields = list(r.get("requires", [])) + list(r.get("requires_any", []))
            sheet.append(f"- [{r['id']}] {r['prompt']}  -> fill: {', '.join(fields)}")
        for p in _CONTENT_PROMPTS:                        # content-quality prompts (not slots)
            sheet.append(f"- (content) {p}")
        sheet.append("")
    return json.dumps(reg, ensure_ascii=False, indent=2), "\n".join(sheet)
