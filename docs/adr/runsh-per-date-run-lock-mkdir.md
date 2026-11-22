# runsh: One run per date at a time, through a reclaimable mkdir lock that fails open

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`acquire_lock`, `lock_holder_state`, `reclaim_lock`, `release_lock`, `acquire_run_lock`, `release_run_lock`, `proc_start`)

## Context
launchd serialises a label against itself and nothing more, and `autodream-now.sh` runs under a different label than the scheduled nightly (issue #55). An on-demand run and a trigger for the same date are two processes sharing one findings dir, one sidecar set and one report path, and the second one's move-aside would even carry off the first one's report mid-build.

## Decision
`mkdir` is the lock: atomic on every filesystem here, and needs no flock. The lock dir holds the owner's pid and process start time (`proc_start`, from `ps -o lstart=`). A run killed mid-flight (this pipeline's documented failure mode) leaves the directory behind, so a holder that is gone, or whose pid now belongs to a different process, is reclaimed. The lock sits outside the findings dir (`$AUTODREAM_DIR/locks/run-<date>.lock`), so clearing a date's findings for a clean rebuild cannot release it under a live run.

- With no recorded start (`ps` unavailable) the live pid is all there is to go on, so `lock_holder_state` accepts it.
- `reclaim_lock` renames the stale lock aside (atomic, so one reclaimer wins) rather than `rmdir`: a second reclaimer that judged the same stale holder must not delete the winner's NEW lock. If the moved dir's pid is not the one judged stale, the reclaimer put back a lock a faster reclaimer had already replaced.
- A lock directory that cannot be made at all (`acquire_lock` returns 3) does not stop the night: `acquire_run_lock` logs a WARNING and runs unlocked, which is the old behaviour.
- `release_run_lock` is also the EXIT trap, which a run that never took the lock reaches too and which must not touch the holder's lock, so `release_lock` removes it only when the recorded pid is this process.

See CLAUDE.md, "Sleep resilience" (per-date run lock).

## Consequences
Known residual defects are tracked in https://github.com/STRML/autodream/issues/242 (see CLAUDE.md); `question-streaks.sh` and `threads.sh` use flock instead. The remote sync lock reuses these helpers (see `remote-sync-waits-for-held-mirror`), so a change to the pid/start format affects both.
