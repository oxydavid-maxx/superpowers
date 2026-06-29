"""spec_registry — the INTAKE LOCK for spec_quality_audit.

Extracts a machine-readable Capability Registry from a spec .md, so the audit isn't
inert (it needs structured caps, not prose). The spec author emits a fenced block:

    ```registry
    [{"cap_id": "CAP-01", "type_tags": ["editable","persists"], ...}]
    ```

Deterministic (no NLP). a1_capability_complete then checks prose↔registry: every
CAP-id referenced in the prose must appear in the registry (catches "named in prose,
dropped from the Registry" — the cmd-center H2 class)."""
import json
import re

_BLOCK = re.compile(r"```registry\s*\n(.*?)\n```", re.DOTALL)
_CAPREF = re.compile(r"\bCAP-[A-Za-z0-9_-]+\b")


def extract_registry(md_text):
    """Return the capability list from the spec's ```registry``` block, or [] if none/invalid."""
    m = _BLOCK.search(md_text or "")
    if not m:
        return []
    try:
        data = json.loads(m.group(1))
        return data if isinstance(data, list) else []
    except Exception:
        return []


def a1_capability_complete(md_text, registry):
    """A1: every CAP-id mentioned in the prose appears in the registry. Returns the
    list of prose-mentioned cap_ids missing from the registry (empty = pass)."""
    reg_ids = {c.get("cap_id") for c in (registry or [])}
    prose_ids = set(_CAPREF.findall(md_text or ""))
    # ignore CAP-ids that appear only inside the registry block itself
    block = _BLOCK.search(md_text or "")
    if block:
        prose_only = md_text.replace(block.group(0), "")
    else:
        prose_only = md_text or ""
    prose_ids = set(_CAPREF.findall(prose_only))
    return sorted(prose_ids - reg_ids)
