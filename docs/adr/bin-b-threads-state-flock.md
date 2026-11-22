# bin-b: threads.sh takes the same flock as question-streaks.sh, and honors the old mkdir lock while it is young

Status: accepted · Date: 2026-11-21 · Code: `bin/threads.sh` (`threads_acquire_lock`)

## Context

Both scripts write their own state with one rename and serialize writers on `$STATE.flock`. CLAUDE.md, "Open questions that never get answered", explains why a kernel flock replaced the reclaimable mkdir lock (#192): nothing has to judge a holder dead.

## Decision

`threads_acquire_lock` calls `flock_acquire` from `lib-flock.sh` with the older version's `$STATE.lock` directory as the legacy lock, which is honored while it is younger than 300 seconds. `question-streaks.sh` takes its lock the same way.

## Consequences

Change the lock protocol in `lib-flock.sh` for both scripts together.
