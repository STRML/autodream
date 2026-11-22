# bin-b: `update` always exits 0, and a broken precondition says so loudly instead of failing the pipeline

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`cmd_update`, `take_lock`, `lock_message`)

## Context

This runs at the end of the nightly pipeline. A bookkeeping helper must not be the thing that costs a night its report. But a helper that skips silently every night freezes every streak and reads as a quiet week.

## Decision

- `update` exits 0 on every path. A missing `report-format.sh` or `lib-flock.sh` prints why to stderr and exits 0 for `update` (1 for other commands): without the lib every report reads as "no marker" and streaks would freeze behind a message about the report.
- A held lock is routine (another run is mid-update) and skips quietly. The permanent refusals (cannot open or lock the file, no python3, a legacy lock path that cannot be read) post a banner through `show_notification` as well.
- The state directory is created before the lock is taken, since the lock lives beside the state; on a new state path the first update otherwise read as a held lock and never created the state (Codex review of b72f0e4).
- One `trap ... RETURN` releases the lock and removes the scratch directory. A second `trap RETURN` in the same function replaces the first and leaks whichever cleanup registered earlier.
- `AUTODREAM_QUESTION_LOCK_WAIT` falls back to 15 on a non-number or more than four digits (an effectively endless wait); `10#` keeps `08` decimal.

## Consequences

`clear` is the exception and returns 1 on failure (see `bin-b-question-streaks-clear-is-strict.md`). The lock design is `bin-b-question-streaks-flock-skips-not-blocks.md`.
