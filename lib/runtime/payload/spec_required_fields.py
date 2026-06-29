"""Single source of truth for spec capability requirements (DRY across the audit and the
generative scaffold). THREE things live here and are consumed by BOTH spec_audit (DETECT)
and spec_scaffold (GENERATE) — parity tests assert no consumer keeps a second truth:

  1. RULES                — tag-driven state_data_contract requirements (A4).
  2. high_risk_tags()     — the high-risk tag set, DERIVED from RULES where
                            risk_tier == 'high' (spec_audit.derive_risk_tier consumes it;
                            there is no inline _HIGH_RISK_TAGS literal). [GAP-01]
  3. BASELINE_FIELDS      — the baseline capability presence fields + prompts (the
                            A2/A3/A5/A6/A7 family). The audit's presence checks pull their
                            field paths from here; the scaffold builds slots+prompts from
                            here. No hardcoded _BASELINE_SLOTS. [GAP-02]

Each RULE fires when a capability's type_tags match `when_any` (≥1) and/or `when_all` (all),
then requires `requires` (all of) and/or `requires_any` (≥1 of) fields in the cap's
state_data_contract. `prompt` is the author-facing question the scaffold emits.
"""
import copy

RULES = [
    {"id": "state-roundtrip", "when_any": ["editable", "persists", "stateful"],
     "requires": ["reload", "invariant"], "risk_tier": "standard",
     "prompt": "How does the user confirm the change survived (reload)? What must stay unchanged (invariant)?"},
    {"id": "reversible", "when_any": ["destructive", "data_loss"],
     "requires_any": ["undo", "rollback"], "risk_tier": "high",
     "prompt": "How is this destructive action reversed — undo or rollback?"},
    {"id": "migration", "when_any": ["migration", "schema_change"],
     "requires": ["idempotency", "rollback"], "risk_tier": "high",
     "prompt": "Is re-running a no-op (idempotency)? How do you roll back?"},
    {"id": "concurrency", "when_any": ["concurrent"],
     "requires": ["invariant"], "risk_tier": "high",
     "prompt": "What invariant must hold under concurrent/parallel access?"},
    {"id": "trust", "when_any": ["authz", "money"],
     "requires": ["invariant"], "risk_tier": "high",
     "prompt": "What access/financial invariant must always hold (e.g. owner-only, no double-spend)?"},
]


def applicable_rules(tags):
    """Rules whose when_all (all present) and when_any (≥1 present) match the cap's tags."""
    t = set(tags or [])
    out = []
    for r in RULES:
        if set(r.get("when_all", [])) - t:
            continue
        wa = r.get("when_any")
        if wa and not (set(wa) & t):
            continue
        out.append(r)
    return out


def required_contract_fields(tags):
    """The set of state_data_contract fields any applicable rule names (requires +
    requires_any). The scaffold seeds a slot for each; the audit predicate below enforces
    the requires-all / requires_any-one semantics."""
    fields = set()
    for r in applicable_rules(tags):
        fields |= set(r.get("requires", []))
        fields |= set(r.get("requires_any", []))
    return fields


def contract_satisfied(tags, sdc):
    """Audit predicate (A4): every applicable rule's `requires` all present AND each rule's
    `requires_any` has ≥1 present."""
    sdc = sdc or {}
    for r in applicable_rules(tags):
        if any(not sdc.get(f) for f in r.get("requires", [])):
            return False
        ra = r.get("requires_any")
        if ra and not any(sdc.get(f) for f in ra):
            return False
    return True


def high_risk_tags():
    """GAP-01: the high-risk tag set DERIVED from RULES (every tag named by any rule with
    risk_tier == 'high'). spec_audit.derive_risk_tier consumes THIS — no second truth."""
    out = set()
    for r in RULES:
        if r.get("risk_tier") == "high":
            out |= set(r.get("when_any", [])) | set(r.get("when_all", []))
    return out


# GAP-02: baseline presence fields every capability needs, as the SINGLE source consumed by
# the audit (presence checks pull their paths by audit_item) AND the scaffold (slots+prompts).
#   path:       dotted for nested fields
#   default:    seeds the scaffold slot
#   kind:       'required' = audit enforces non-empty presence; 'resolved' = audit enforces
#               resolution/emptiness (gap_questions); 'scaffold_only' = slot only, not audited
#   audit_item: which audit item enforces it (or '-' for scaffold_only)
BASELINE_FIELDS = [
    {"path": "user_outcome", "default": "", "kind": "scaffold_only", "audit_item": "-",
     "prompt": "What user-visible OUTCOME does this capability deliver?"},
    {"path": "entry_point", "default": "", "kind": "required", "audit_item": "A3",
     "prompt": "Where does the user reach it (page / command / endpoint)?"},
    {"path": "entry_type", "default": "", "kind": "required", "audit_item": "A3",
     "prompt": "Surface kind: ui / cli / api / library?"},
    {"path": "reachable_path", "default": "", "kind": "required", "audit_item": "A3",
     "prompt": "The concrete route the user takes to it?"},
    {"path": "acceptance.given", "default": "", "kind": "required", "audit_item": "A2",
     "prompt": "Given: the starting state."},
    {"path": "acceptance.when", "default": "", "kind": "required", "audit_item": "A2",
     "prompt": "When: the user action."},
    {"path": "acceptance.then", "default": "", "kind": "required", "audit_item": "A2",
     "prompt": "Then: the OBSERVABLE user-visible result (not a proxy like HTTP 200)."},
    {"path": "failure_modes", "default": [], "kind": "required", "audit_item": "A5",
     "prompt": "At least one failure mode + what the user sees (≥3 words)."},
    {"path": "type_tags", "default": [], "kind": "required", "audit_item": "A6",
     "prompt": "Capability type tags drawn from the taxonomy."},
    {"path": "gap_questions", "default": [], "kind": "resolved", "audit_item": "A7",
     "prompt": "Resolve every open gap-question before FINAL (none may remain)."},
]


def baseline_required_paths():
    """Dotted paths the audit must find present (kind == 'required'). Consumed aggregate-wise
    by baseline_presence_ok and per-item by baseline_paths_for."""
    return [f["path"] for f in BASELINE_FIELDS if f["kind"] == "required"]


def baseline_paths_for(audit_item):
    """The required paths a given audit item (A2/A3/A5/A6) owns — so each audit function
    pulls its field list from here instead of hardcoding names."""
    return [f["path"] for f in BASELINE_FIELDS
            if f["kind"] == "required" and f["audit_item"] == audit_item]


def baseline_slot_skeleton():
    """The empty-but-present baseline slots for the scaffold, built from BASELINE_FIELDS
    (NOT a hardcoded literal). Fresh mutable defaults per call."""
    sk = {}
    for f in BASELINE_FIELDS:
        keys = f["path"].split(".")
        d = sk
        for k in keys[:-1]:
            d = d.setdefault(k, {})
        d[keys[-1]] = copy.deepcopy(f["default"])
    return sk
