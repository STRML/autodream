# tests-notes-path: the writer and the reader are run from an installed layout and compared by the file they touch

Status: accepted · Date: 2026-11-22 · Code: `tests/notes-path.sh` (the `AUTODREAM_DIR` rows, `INSTALL2` symlink fixture, the seam rows)

## Context

`autodream-note.sh` (writer) hardcoded `$HOME/.claude/autodream`, while `vault-notes.sh` (reader) resolves `AUTODREAM_DIR`. Under this port's install the writer appended to a file the nightly never opened. Nothing errored: no missing note and no warning, only an operator note that never reached the report.

Two test shapes would have passed with that bug present:

- Both scripts contain the string `$AUTODREAM_DIR/notes.md`, so a source grep matches even when the two resolve `AUTODREAM_DIR` to different directories.
- With the real `HOME`, the "legacy path is not written" row would check a directory nothing in the test could ever write to.

## Decision

- The rows are behavioural. Both scripts run from their installed location with no environment and the test compares the actual file each wrote to or read from.
- `install.sh` symlinks `bin/*.sh` into the target, so the writer's own directory is the install directory. The fixture reproduces that with `ln -s` rather than trusting the repo layout.
- `HOME` points at a sandbox, so the legacy-path row can fail.
- The note must be visible in the reader's own file, not merely adjacent to it.

## Consequences

Do not replace a row with a grep for the path expression. Add a new resolution path (a new variable or location) as a row that runs both halves and compares the file.
