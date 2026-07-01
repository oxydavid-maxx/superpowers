"""userpromptsubmit-superpower-entry (2026-07-01 fix): on a superpower-entry prompt,
the hook must refresh progress.json from ON-DISK ground truth and print the DERIVED
line to stderr -- so the agent reads the line rather than composing it from memory.
Runs the real hook script as a subprocess against a temp repo (with a git root)."""
import json
import subprocess
import sys
from pathlib import Path

HOOK = Path.home() / ".claude" / "plugins" / "marketplaces" / "superpowers-dev" / "hooks" / "userpromptsubmit-superpower-entry"


def _run(cwd, prompt):
    payload = json.dumps({"prompt": prompt})
    p = subprocess.run([sys.executable, str(HOOK)], input=payload, capture_output=True,
                       text=True, cwd=str(cwd))
    return p.returncode, p.stdout, p.stderr


def _init_repo(tmp_path):
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    (tmp_path / ".superpowers").mkdir()          # opt-in marker
    return tmp_path


def test_superpower_prompt_prints_derived_line_not_generic_reminder(tmp_path):
    _init_repo(tmp_path)
    rc, out, err = _run(tmp_path, "用 superpower 幫我改一下")
    assert rc == 0
    assert "Superpower: now=S0_DISCUSS(" in err
    assert (tmp_path / ".superpowers" / "fsm" / "progress.json").is_file()


def test_non_superpower_prompt_does_nothing(tmp_path):
    _init_repo(tmp_path)
    rc, out, err = _run(tmp_path, "hello there")
    assert rc == 0
    assert err == ""
    assert not (tmp_path / ".superpowers" / "fsm" / "progress.json").exists()


def test_not_opted_in_repo_skips_derivation(tmp_path):
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)  # no .superpowers dir
    rc, out, err = _run(tmp_path, "用 superpower 幫我改一下")
    assert rc == 0
    assert not (tmp_path / ".superpowers").exists()
