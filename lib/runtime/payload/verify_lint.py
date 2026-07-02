"""verify-lint rules over a verification test-design's `cases` + `registry`.
Each rule returns a list of defect strings ([] = clean). `lint_all` aggregates.
Operationalizes the anti-proxy honesty axis + thoroughness checks of the
2026-06-28 verification-test-design-rigor spec. Pure functions; no I/O.

CEILING (read this before trusting a green lint): these rules check the SHAPE and
VOCABULARY of the test-design text — that a case exists per required category, names
a technique, avoids proxy keywords, and (for UI) cites a non-localhost artifact. They
do NOT and CANNOT prove the verification was actually PERFORMED. A careless/dishonest
author can satisfy lint_technique/lint_round_trip/lint_pairwise/lint_error_guessing/
lint_independence by writing the right words. They are label tripwires that stop the
LAZIEST failures, not a guarantee. The real force comes from (1) the verify-spec skill
DRIVING the product for real with deployed-surface evidence, and (2) information-
separation (an independent verifier given only the Registry). lint_ui_evidence is the
sturdiest rule here because it demands a real artifact + constrains its URL."""
import re
from pathlib import Path

VALID_TECHNIQUES = {"EP", "BVA", "decision-table", "state-transition",
                    "use-case", "pairwise", "error-guessing", "property-based"}

_PROXY = [r"\bhttp\s*200\b", r"\b200\s+(ok|returned)\b", r"\blooks?\b", r"\bseems?\b",
          r"structural[- ]guard", r"\bexists\b", r"\bcompiles?\b", r"\bunverified\b"]


def lint_technique(case):
    """TD-02: every case names a valid derivation technique (anti-亂寫)."""
    t = case.get("technique")
    cid = case.get("cap_id", "?")
    if not t:
        return [f"{cid}: case names no derivation technique (anti-亂寫)"]
    if t not in VALID_TECHNIQUES:
        return [f"{cid}: unknown technique '{t}'"]
    return []


def lint_proxy(case):
    """TD-03: the assertion must be a real user-visible output, not a proxy."""
    cid = case.get("cap_id", "?")
    then = (case.get("then") or "").lower()
    if not then:
        return [f"{cid}: empty assertion"]
    if any(re.search(p, then) for p in _PROXY):
        return [f"{cid}: proxy assertion ('{case.get('then')}') — assert the real user-visible output"]
    return []


def lint_round_trip(cap, cases):
    """TD-04: persistence-bearing Cap-IDs need a save->reload assertion naming both
    the changed field AND an untouched invariant (e.g. frontmatter). Principle #3."""
    if not (cap.get("risk") or {}).get("persists"):
        return []
    cid = cap.get("cap_id", "?")
    blob = " ".join((c.get("then") or "").lower() for c in cases if c.get("cap_id") == cid)
    has_reload = any(w in blob for w in ("reload", "read back", "re-read", "reopen"))
    has_invariant = any(w in blob for w in ("untouched", "unchanged", "preserved", "intact"))
    if has_reload and has_invariant:
        return []
    return [f"{cid}: persistence cap needs a round-trip assertion (reload + invariant untouched)"]


def lint_pairwise(cap, cases):
    """TD-09: a Cap-ID with >=3 independent inputs needs a pairwise/combinatorial
    case (NIST: interaction faults). The six categories alone miss them."""
    if (cap.get("risk") or {}).get("inputs", 1) < 3:
        return []
    cid = cap.get("cap_id", "?")
    if any(c.get("cap_id") == cid and c.get("technique") == "pairwise" for c in cases):
        return []
    return [f"{cid}: >=3 inputs but no pairwise/combinatorial case"]


def lint_error_guessing(cap_id, cases):
    """TD-10: every Cap-ID reserves one fault-targeting case (Beizer pesticide
    paradox + Myers: testing is destructive), not only confirmatory ones."""
    mine = [c for c in cases if c.get("cap_id") == cap_id]
    if any(c.get("category") == "error-guessing" for c in mine):
        return []
    return [f"{cap_id}: no error-guessing/fault-targeting case (all confirmatory)"]


_PROPERTY_MARKERS = ("invariant", "property", "for all", "holds", "never", "always", "round-trip")


def lint_thin_property(cap, cases):
    """CAP-25 thin-property: a state_data_contract-bearing cap's property case must
    reference an invariant/property in its assertion. A `property` category present
    but with a hollow `then` is not real invariant coverage — presence of the label
    must not launder an empty case. (Tripwire, not a proof; see the module CEILING.)"""
    if not (cap.get("risk") or {}).get("has_contract"):
        return []
    cid = cap.get("cap_id", "?")
    defects = []
    for c in cases:
        if c.get("cap_id") != cid or c.get("category") != "property":
            continue
        then = (c.get("then") or "").lower()
        if not any(m in then for m in _PROPERTY_MARKERS):
            defects.append(
                f"{cid}: thin-property case {c.get('case_id', '?')} — `then` references no "
                f"invariant/property (hollow property case; name the struck invariant)")
    return defects


def lint_ui_evidence(case):
    """TD-05/E7: a UI Cap-ID MATCHES verdict must carry render evidence of the
    DEPLOYED surface (not localhost) — else local-pass-prod-broken (CF cache)."""
    if case.get("entry_type") != "UI" or case.get("verdict") != "MATCHES":
        return []
    cid = case.get("cap_id", "?")
    if not case.get("evidence_path"):
        return [f"{cid}: UI MATCHES with no evidence_path (render screenshot required)"]
    url = (case.get("evidence_url") or "").lower()
    if "localhost" in url or "127.0.0.1" in url:
        return [f"{cid}: UI evidence is localhost — must observe the deployed user-facing URL"]
    return []


def _is_ui_cap(cap):
    tags = {str(t).lower() for t in (cap.get("risk") or {}).get("tags", [])}
    entry_type = str(cap.get("entry_type", "")).lower()
    risk_entry_type = str((cap.get("risk") or {}).get("entry_type", "")).lower()
    return (
        entry_type == "ui"
        or risk_entry_type == "ui"
        or (cap.get("risk") or {}).get("ui") is True
        or "ui" in tags
    )


def _skill_ui_human_available(td):
    if "skill_ui_human_available" in td:
        return bool(td["skill_ui_human_available"])
    return Path("C:/dev/skill-ui-human/SKILL.md").exists()


def lint_ui_human_preflight(td):
    if any(_is_ui_cap(cap) for cap in td.get("registry", [])) and not _skill_ui_human_available(td):
        return ["UI Cap-ID present but skill-ui-human unavailable (required dependency/preflight)"]
    return []


def lint_ui_human_case_detail(case):
    """UI-human categories must name the concrete human-factor evidence they check."""
    if case.get("entry_type") not in (None, "UI"):
        return []
    cid = case.get("cap_id", "?")
    category = case.get("category")
    then = (case.get("then") or "").lower()
    if category == "responsive-mobile" and not ("390" in then and "overflow" in then):
        return [f"{cid}: responsive-mobile case must include a 390px viewport overflow check"]
    if category == "touch-targets" and not ("44" in then or "touch target" in then):
        return [f"{cid}: touch-targets case must check touch target sizing"]
    if category == "keyboard-focus" and not ("focus" in then and ("tab" in then or "keyboard" in then)):
        return [f"{cid}: keyboard-focus case must check keyboard/tab focus"]
    if category == "feedback-states" and not any(w in then for w in ("loading", "success", "error", "empty")):
        return [f"{cid}: feedback-states case must check loading/success/error/empty states"]
    if category == "runtime-cleanliness" and not ("console" in then and ("page error" in then or "page errors" in then)):
        return [f"{cid}: runtime-cleanliness case must check console and page errors"]
    if category == "visual-evidence" and not any(w in then for w in ("screenshot", "trace", "visual evidence")):
        return [f"{cid}: visual-evidence case must require screenshot/trace evidence"]
    return []


def lint_runtime_verdicts(verdicts):
    defects = []
    for result in verdicts.get("results", []):
        if result.get("entry_type") != "UI" or result.get("verdict") != "MATCHES":
            continue
        cid = result.get("cap_id", "?")
        evidence = result.get("ui_human_evidence") or {}
        if not evidence.get("screenshots"):
            defects.append(f"{cid}: UI MATCHES missing screenshots")
        overflow = evidence.get("viewport_overflow") or {}
        if not overflow or any(bool(v) for v in overflow.values()):
            defects.append(f"{cid}: UI MATCHES missing passing viewport/overflow evidence")
        touch = evidence.get("touch_targets") or {}
        if touch.get("min_px", 0) < 44 or touch.get("violations"):
            defects.append(f"{cid}: UI MATCHES missing passing touch target evidence")
        focus = evidence.get("keyboard_focus") or {}
        if not (focus.get("tab_order_checked") and focus.get("visible_focus")):
            defects.append(f"{cid}: UI MATCHES missing keyboard focus evidence")
        if not evidence.get("feedback_states"):
            defects.append(f"{cid}: UI MATCHES missing feedback states evidence")
        runtime = evidence.get("runtime_cleanliness") or {}
        if "console_errors" not in runtime or "page_errors" not in runtime:
            defects.append(f"{cid}: UI MATCHES missing console/page error evidence")
        elif runtime.get("console_errors") or runtime.get("page_errors"):
            defects.append(f"{cid}: UI MATCHES has console/page errors")
    return defects


def lint_independence(td):
    """TD-07/E6 (IV&V): the test-design attests independence and verifier != builder.
    The real mechanism is information-separation (verifier given only the Registry);
    this flag is the audit record of it."""
    if not td.get("independent"):
        return ["test-design not attested independent (verifier must be a different agent given only the Registry)"]
    if td.get("verifier") and td.get("builder") and td["verifier"] == td["builder"]:
        return ["verifier == builder (no independence)"]
    return []


def lint_all(td):
    """Aggregate every per-case/per-cap rule over a full test-design. Flat list."""
    defects = []
    cases = td.get("cases", [])
    defects += lint_independence(td)
    defects += lint_ui_human_preflight(td)
    for c in cases:
        defects += lint_technique(c)
        defects += lint_proxy(c)
        defects += lint_ui_evidence(c)
        defects += lint_ui_human_case_detail(c)
    for cap in td.get("registry", []):
        defects += lint_round_trip(cap, cases)
        defects += lint_pairwise(cap, cases)
        defects += lint_error_guessing(cap.get("cap_id", "?"), cases)
        defects += lint_thin_property(cap, cases)
    return defects


def lint_test_design(td):
    """Full rigor gate over a test-design: lint_all (technique/proxy/round-trip/
    pairwise/error-guessing/UI-evidence/independence) PLUS risk-scaled category
    coverage (every Cap-ID needs a case in each category its risk requires)."""
    import sys
    try:
        from risk_scale import required_categories
        from verify_coverage import category_coverage
    except ImportError:
        sys.path.insert(0, str(Path.home() / ".claude" / "lib"))
        from risk_scale import required_categories
        from verify_coverage import category_coverage

    defects = list(lint_all(td))
    cases = td.get("cases", [])
    # Structural: a test-design with cases but no registry would silently skip ALL
    # per-capability checks (round-trip/pairwise/error-guessing/category coverage).
    if not td.get("registry"):
        defects.append("test-design has no registry — cannot verify per-capability "
                       "coverage (every capability must be declared with its risk)")
    required, present = {}, {}
    for cap in td.get("registry", []):
        cid = cap.get("cap_id", "?")
        risk = dict(cap.get("risk") or {})
        if cap.get("entry_type") and not risk.get("entry_type"):
            risk["entry_type"] = cap.get("entry_type")
        required[cid] = required_categories(risk)
        present[cid] = {c.get("category") for c in cases if c.get("cap_id") == cid}
    for cid, missing in category_coverage(required, present).items():
        defects.append(f"{cid}: missing required category(ies): {', '.join(missing)}")
    return defects
