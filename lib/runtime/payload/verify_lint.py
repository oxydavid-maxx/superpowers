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

VALID_TECHNIQUES = {"EP", "BVA", "decision-table", "state-transition",
                    "use-case", "pairwise", "error-guessing"}

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
    for c in cases:
        defects += lint_technique(c)
        defects += lint_proxy(c)
        defects += lint_ui_evidence(c)
    for cap in td.get("registry", []):
        defects += lint_round_trip(cap, cases)
        defects += lint_pairwise(cap, cases)
        defects += lint_error_guessing(cap.get("cap_id", "?"), cases)
    return defects


def lint_test_design(td):
    """Full rigor gate over a test-design: lint_all (technique/proxy/round-trip/
    pairwise/error-guessing/UI-evidence/independence) PLUS risk-scaled category
    coverage (every Cap-ID needs a case in each category its risk requires)."""
    import sys
    from pathlib import Path
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
        required[cid] = required_categories(cap.get("risk") or {})
        present[cid] = {c.get("category") for c in cases if c.get("cap_id") == cid}
    for cid, missing in category_coverage(required, present).items():
        defects.append(f"{cid}: missing required category(ies): {', '.join(missing)}")
    return defects
