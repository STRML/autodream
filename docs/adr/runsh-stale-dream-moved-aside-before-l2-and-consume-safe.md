# runsh: an existing dream is moved aside before L2, and a failed move disarms consuming

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `STALE_REPORT`, `CONSUME_SAFE`, `PINS_SAFE`)

## Context
The only way to reach this point with `$REPORT_PATH` already non-empty is `AUTODREAM_FORCE=1`. Nothing below distinguishes "this run wrote it" from "it was already there": `report_complete` and the consume gate both read the path. The retired comment also said an old report would stop the retry loop after attempt 1; that half is stale, since the loop now breaks on `L2_DELIVERED` plus `report_complete`, not on `-s`. What remains is that a leftover report would satisfy `report_complete` and so the pins and consume gates (for instance if the post-loop partial move also failed), and the consume gate would archive the vault note and mark bookmarks read as if something had read them. That is the overnight failure mode (Mac sleeps mid-run, every L2 attempt fails) turning into silent, unrecoverable data loss for the user's notes and bookmarks.

## Decision
The old file is moved to `$REPORT_PATH.stale-<epoch>` first, so a non-empty path again means "this run produced it". It is moved, not deleted: if every L2 attempt fails, the last good report for this date stays recoverable. If the move fails, `CONSUME_SAFE=0` disarms archive and mark-read for the run (and pins), rather than warning and carrying on; that is the point of the block, not a side effect. See CLAUDE.md, "What the consume gate actually has to check (PR #37 review)".

## Consequences
"A guard whose failure path continues is not a guard." The copy is retired by `superseded-dream-copies-retired-outside-existence-test`.
