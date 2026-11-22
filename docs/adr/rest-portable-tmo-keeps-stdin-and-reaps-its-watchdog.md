# rest: tmo's watchdog fallback hands the caller's stdin to the job and kills its own sleep

Status: accepted · Date: 2026-11-15 · Code: `bin/portable.sh` (`tmo`)

## Context

`tmo <seconds> <command...>` runs a command bounded by `timeout`, then `gtimeout`, then, with neither on PATH (macOS ships none), a watchdog the function builds. Two defects in the fallback:

- A background job gets `/dev/null` as stdin before any explicit redirect applies, so `tmo 5 cat` in a pipeline read nothing (3f53389, 2026-11-15).
- A watchdog that ran `( sleep N; kill ... ) &` and was killed on a normal exit killed only the subshell and left the `sleep` running until its timeout. The same defect was in `run_bounded` and the hard-cap watchdog in `bin/prune-worktrees.sh` (CLAUDE.md, "A watchdog takes its own `sleep` with it").

## Decision

The caller's stdin is saved on fd 3 first (`/dev/null` when fd 0 is closed) and the job gets `<&3`; fd 3 is closed in the parent right after the job starts. The watchdog subshell traps TERM, kills the sleep it started and exits, so the kill that ends it also ends the sleep, and a watchdog woken at that moment cannot signal a recycled pid. At the deadline it kills the job's children (`pkill -P`) and then the job. The function returns the job's own status.

## Consequences

`tests/portable.sh` pins both (stdin through the fallback, including a closed stdin). Removing the `trap` brings back an orphaned `sleep` per call; moving the stdin save after the `&` brings back the empty stdin.
