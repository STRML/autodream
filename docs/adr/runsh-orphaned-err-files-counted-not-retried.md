# runsh: An orphaned .err is counted and named, never retried

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_worklist_leftovers`, `worklist_hashes`)

## Context
Issue #113. An orphaned `.err` is a failed triage nobody has finished: no findings JSON beside it, and its session is not in the worklist (the file is gone, or this run no longer places it in the day). While its session is in the worklist the retry loop owns it and `l1_missing_count` counts it. One with no owner is retried by nothing and seen by no other counter, so `l1_err_files` could not tell "two workers crashed tonight" from "two crashed last week and nobody retried".

## Decision
`scan_worklist_leftovers` sets `L1_ERR_ORPHANED` and `ORPHAN_ERR_NAMES` for each `*.json.err` with no findings JSON whose hash is outside `worklist_hashes`, and logs a WARNING. It reads `SESSIONS_LIST`, which is empty on a night that found nothing, so the same scan serves the early stub exit. It counts and names; it does not retry, because the `.err` is the only record of which session it was, and a worker with the Write tool could have put any path in it. A findings JSON outside the worklist is handled by `findings-outside-worklist-set-aside`.

See CLAUDE.md, "Which day a session belongs to" (Both halves of #113).

## Consequences
`l1_err_files` still counts every `.err` in the directory; `l1_err_files_orphaned` is the subset with no owner.
