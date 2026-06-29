import sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".claude" / "lib"))
from acceptance_lint import lint_example


def test_concrete_example_passes():
    ex = "given a task on the homepage, when clicked, then a 3-pane workspace appears"
    assert lint_example(ex) == []


def test_missing_then_fails():
    ex = "given a task, when clicked"
    assert any("then" in d for d in lint_example(ex))


def test_vague_example_fails():
    assert any("vague" in d for d in lint_example("works correctly"))


def test_registry_table_flags_vague_row():
    from acceptance_lint import lint_registry_table
    spec = """
| Cap-ID | capability | acceptance_example |
|---|---|---|
| CAP-01 | editor | given a task, when clicked, then editor opens |
| CAP-02 | ai | works correctly |
"""
    res = lint_registry_table(spec)
    ids = [c for c, _ in res]
    assert "CAP-02" in ids and "CAP-01" not in ids


def test_registry_table_clean_when_all_gwt():
    from acceptance_lint import lint_registry_table
    spec = "| CAP-01 | x | given a, when b, then c |"
    assert lint_registry_table(spec) == []
