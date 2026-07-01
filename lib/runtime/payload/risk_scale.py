"""Map a Cap-ID's risk attributes to its REQUIRED test-design categories.
Risk = likelihood x impact x DETECTABILITY (FMEA RPN): a silent / hard-to-observe
failure gets MORE rigor, not less — the cmd-center incident's core lesson (both
its bugs were silent: a clobbered frontmatter and a CF-cached stale asset).

NON-WHITELIST RIGOR (2026-07-01 audit): classical ISTQB black-box techniques
(EP/BVA/decision-table/pairwise/error-guessing) only prove "the paths we thought
of work" — they never exercise unknown failure space. A verdict built entirely
from these is the SAME failure mode as a thin spec judged only against its own
acceptance whitelist. HIGH_RISK caps therefore also require `exploratory` (an
unscripted charter — go find what the scripted cases didn't anticipate) and
`forbidden-state` (an explicit oracle for a state that must NEVER occur, not
just a happy-path assertion). Caps that declare an actual input/boundary surface
add the matching layer instead of forcing it everywhere (a pure-library FSM
formatter has no attack surface to fuzz — forcing `security-abuse` on it would
just produce a faked, gamed case)."""
BASELINE = {"happy", "boundary", "negative"}
HIGH_RISK = {"multi_component", "money", "auth", "data_loss", "multi_entry"}
NON_WHITELIST_HIGH_RISK = {"exploratory", "forbidden-state"}
UI_HUMAN_CATEGORIES = {
    "browser-clickthrough",
    "responsive-mobile",
    "touch-targets",
    "keyboard-focus",
    "feedback-states",
    "runtime-cleanliness",
    "visual-evidence",
    "heuristic-eval",
    "assistive-tech",
}


def is_ui_risk(risk):
    tags = {str(t).lower() for t in risk.get("tags", [])}
    entry_type = str(risk.get("entry_type", "")).lower()
    return (
        entry_type == "ui"
        or risk.get("ui") is True
        or "ui" in tags
    )


def required_categories(risk):
    req = set(BASELINE)
    if any(risk.get(k) for k in HIGH_RISK):
        req |= {"integration", "corner"} | NON_WHITELIST_HIGH_RISK
    if risk.get("stateful"):
        req.add("state-transition")
    if risk.get("deployed"):
        req.add("environment")
    if risk.get("silent"):
        req.add("error-guessing")   # detectability: silent failures get a targeted case
    if risk.get("user_input"):
        req |= {"fuzz", "security-abuse"}
    if risk.get("external_boundary"):
        req.add("fault-injection")
    if is_ui_risk(risk):
        req |= UI_HUMAN_CATEGORIES
    return req
