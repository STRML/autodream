# bin-b: the state lock is a kernel flock, and failing to take it skips the update

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`take_lock`, `drop_lock`), `bin/lib-flock.sh`

## Context

`STATE` is one file per install. The scheduled nightly and an `autodream-now.sh` run carry different launchd labels, so launchd's one-instance-per-label rule does not keep them apart. Two overlapping read-modify-write runs would lose the first one's increment.

The lock was a `mkdir` lock that contenders reclaimed by age and then by pid. A shell cannot make "judge the holder gone, then take its lock" atomic, and four review rounds on #192 each found another interleaving (`docs/plans/2026-11-21-fix_question-streaks-lock-owner-redesign.md`).

## Decision

- The lock is `flock(2)` on `$STATE.flock` through `lib-flock.sh`, the mechanism `threads.sh` uses. The kernel drops it when its holder ends, so nothing is judged, reclaimed or put back.
- Failing to take it skips the update. A missed increment costs one night of escalation latency, while a helper that hangs holds up the pipeline behind it.
- An older version's `$STATE.lock` directory is honored while younger than 300 seconds and never removed.

## Consequences

Children that can outlive the holder run with fd 9 closed (see `bin-b-question-streaks-banner.md`), or they keep the lock alive after the holder is killed. CLAUDE.md, "Open questions that never get answered", lists the distinct outcomes (held, cannot lock, no python3, double acquire).
