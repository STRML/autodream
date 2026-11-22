# runsh: the fan-out uses NUL transport, and a session path containing a newline is rejected rather than transported

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_one_adapter`, `REJECTED_PATHS`, the `xargs -0` fan-out)

## Context
`sessions.txt` is line-delimited and stays that way: the hash assignments in `l1_missing_count()` and `dispatch_l1()` key each artifact by the sha1 of the whole line, `oversized-gate.sh` recomputes that same hash from the file, and every archived findings dir depends on the shape. A path with a newline is written as two lines and the runner then invents a session that does not exist.

## Decision
NUL transport carries a path with a space, a tab or a glob character intact through the fan-out. It does not save a newline path, so such a path is rejected (counted in `REJECTED_PATHS`) before either representation is built, rather than transported.

## Consequences
Changing the worklist to NUL-delimited would orphan every archived findings dir's hashes. Related: CLAUDE.md, "Where state lives" (findings keyed by a sha1 of the session path).
