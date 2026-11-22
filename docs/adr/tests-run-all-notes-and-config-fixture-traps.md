# tests-run-all: operator-notes and config fixtures reproduce the exact shape that failed

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_config_env_wins_over_config`, `test_notes_header_only_file_does_not_abort`, `test_notes_icloud_placeholder_is_counted`, `test_notes_expiry_uses_report_date`, `test_config_unbound_var_does_not_kill_run`); see CLAUDE.md "Bash traps this feature hit"

## Context

Each fixture below passes against a plausible but wrong implementation unless it has the exact shape.

## Decision

- Config: `run.sh` sources the config with `set -a` and replays the caller's `export -p` snapshot afterwards. The config uses plain `KEY=value`, so a naive `.` lets the file override a caller who deliberately exported something. The test sets different vaults in env and config and asserts the env one is read.
- Header-only `notes.md`: exactly what `autodream-note.sh` leaves after the user deletes the notes a report said were addressed. `grep -c` prints `0` and exits 1, so a `|| echo 0` fallback made the count `"0\n0"` and the arithmetic killed collect under `set -e`.
- iCloud placeholder: an evicted note is not a zero-byte `.md`. The real file is gone and only the dot-prefixed `.<name>.icloud` remains, so a `*.md` walk matches nothing. The fixture must be the placeholder file.
- Expiry: the fixture expires 2020-06-01, long after the reported `$DATE` and long before today, so a wall-clock comparison drops and archives a note that was active for the window.
- Unbound config variable: `$AUTODREAM_HOME` must stay undefined. Under `set -u` it used to abort bash before the log file or `log()` existed, so the night produced nothing and said nothing.

## Consequences

An empty-file fixture, a present `.md`, or a near-future expiry makes these tests pass with the guarded code removed.
