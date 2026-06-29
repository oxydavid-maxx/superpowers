"""Map a Cap-ID's risk attributes to its REQUIRED test-design categories.
Risk = likelihood x impact x DETECTABILITY (FMEA RPN): a silent / hard-to-observe
failure gets MORE rigor, not less — the cmd-center incident's core lesson (both
its bugs were silent: a clobbered frontmatter and a CF-cached stale asset)."""
BASELINE = {"happy", "boundary", "negative"}
HIGH_RISK = {"multi_component", "money", "auth", "data_loss", "multi_entry"}


def required_categories(risk):
    req = set(BASELINE)
    if any(risk.get(k) for k in HIGH_RISK):
        req |= {"integration", "corner"}
    if risk.get("stateful"):
        req.add("state-transition")
    if risk.get("deployed"):
        req.add("environment")
    if risk.get("silent"):
        req.add("error-guessing")   # detectability: silent failures get a targeted case
    return req
