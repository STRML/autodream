# runsh: Session-loss counters are computed against RAW with collision drops subtracted and reported separately

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `EXCLUDED`, the zero-session stub text, `DROPPED_AFTER_FAILURES`)

## Context
- Hash-collision drops leave the worklist before the self-prune runs. Charging them to `EXCLUDED` made a forced two-session collision report `self_sessions_excluded: 2`, the report calling files "autodream-own" that were nothing of the kind.
- `RAW` stays the ENUMERATED count and is never overwritten with the post-drop worklist size: doing that made a forced two-session collision report `sessions_found_raw: 0` and "0 session file(s) were enumerated", telling the reader nothing was there when two files were, dropped for cause (see `collided-sessions-dropped-both-and-verified`).
- `HASH_COLLISIONS` counts collision events and each drops at least two paths, so adding it to a path total understates the loss. Refused paths never reach `sessions.txt.raw`, so they are not part of `RAW` either. Folding them into "N session file(s) were modified" produced sentences like "0 session file(s) were modified ... 3 with an unrepresentable path".
- The 2026-06-11 self-audit caught sessions enumerated by `find` but unaccounted for at run end: 12 `.err` files existed while stats showed `l1_missing_after_retries=0`, because both denominators counted from the POST-prune `sessions.txt`.

## Decision
- `EXCLUDED = RAW - COLLIDED_DROPPED - COUNT_AFTER_PRUNE`, floored at 0.
- `SKIPPED_EMPTY = COUNT_AFTER_PRUNE - COUNT` is taken after the self-prune, so it never overlaps `EXCLUDED`: the two telemetry counts are disjoint.
- The zero-session stub sentence reports `RAW`, `EXCLUDED`, `SKIPPED_EMPTY`, `REJECTED_PATHS` and `HASH_COLLISIONS` as separate numbers. The local `refused = REJECTED_PATHS + HASH_COLLISIONS` is only a zero test selecting which sentence prints.
- `DROPPED_AFTER_FAILURES = RAW - COLLIDED_DROPPED - L1_OK - EXCLUDED - SKIPPED_EMPTY`, floored at 0 against a counting bug in the prunes. Computing against RAW and subtracting the legitimate prunes means a session lost to a filter mis-classification or a silent worker death surfaces here. Collision drops are deliberate, not failures, and have their own key (`sessions_dropped_to_collision`).

## Consequences
- Keep the two facts as two numbers: a combined figure is wrong either way.
- Counting from the post-prune list again hides lost sessions.
- A new legitimate drop between RAW and L1 needs its own subtraction here, or it reads as a failure.
