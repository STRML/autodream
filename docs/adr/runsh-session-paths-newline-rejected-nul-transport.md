# runsh: the fan-out uses NUL transport, and a session path containing a newline is rejected rather than transported

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_one_adapter`, `REJECTED_PATHS`, the `xargs -0` fan-out)

## Context
`sessions.txt` is line-delimited and stays that way: the hash assignments in `l1_missing_count()` and `dispatch_l1()` key each artifact by the sha1 of the whole line, `oversized-gate.sh` recomputes that same hash from the file, and every archived findings dir depends on the shape. A path with a newline is written as two lines and the runner then invents a session that does not exist.

## Decision
Enumeration is NUL-delimited (`read -r -d ''` over the staged adapter output) and the fan-out hands each worker its path NUL-delimited (`tr '\n' '\0' < sessions.txt | xargs -0 -n 1`), so a path with a space, a glob character, a backslash or a quote reaches the worker intact. NUL transport does not save a newline path, so such a path is rejected (counted in `REJECTED_PATHS`) before either representation is built, rather than transported. A tab is rejected at the same check for a different reason (`pin-projects.tsv` and the source map are tab-separated); see `session-path-newline-tab-rejected`. The original comment says NUL transport carries a tab intact; the code beside it refuses tabs, so that sentence is not true of this check.

## Consequences
Changing `sessions.txt` away from one path per line (to carry newline paths, say) would change the sha1 each artifact is keyed by and orphan every archived findings dir. Related: CLAUDE.md, "Where state lives" (findings keyed by a sha1 of the session path).
