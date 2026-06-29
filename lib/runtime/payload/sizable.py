"""Classify a change as sizable (must go through the full pipeline + verify)
vs trivial (exempt). Mirrors CLAUDE.md: >1 file OR a new component/file =
sizable. New-component is approximated by 'a new file was added'."""


def is_sizable(changed_files, *, added_files):
    if len(changed_files) > 1:
        return True
    if added_files:
        return True
    return False
