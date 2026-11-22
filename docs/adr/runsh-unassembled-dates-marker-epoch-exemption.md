# runsh: the run names dates whose findings were never assembled into a complete report, judging completeness by the open-questions marker with a dated exemption for legacy reports (#36)

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`unassembled_dates`, `run`)

## Context
A run killed during L2 leaves a full findings dir and no report, and nothing notices: `notify.sh` never runs, so there is not even a quiet banner. 2026-07-26 sat that way for two days and was found during an unrelated investigation; 2026-08-01 did it again. The catch-up triggers cannot cover it, because launchd will not start a second instance of a label that is already running, so a run slow enough to span its own catch-up window turns those triggers into nothing at all. Recovery is cheap whenever the findings survive (`autodream-now.sh <date>` skips straight to L2), so the gap was never the data; it was that nobody was told.

The marker became mandatory partway through this tool's life, so every report written before that is non-empty, complete and unmarked. Judged by the marker alone they all looked abandoned: on the author's host the check named six consecutive good reports every night, which trains a real warning into background noise. "Non-empty but unmarked" is genuinely ambiguous (a legacy report or a truncated capture), and the only fact that separates them is when the contract began.

## Decision
`unassembled_dates` scans the trailing `AUTODREAM_UNASSEMBLED_WINDOW` days (default 7) of findings dirs, skipping `TARGET_DATE` (this run is about to assemble it, and a stub dir from an earlier attempt would report itself as a failure), and prints `unassembled|legacy`, both comma-separated and either empty.
- A date counts when its dir holds a findings JSON (not just `*.stats.json` sidecars, which were never triaged), or a `run-stats.txt` carrying `fatal:` (a night that died before it could triage anything has no other surface: no report, no notification, nothing to rebuild from).
- Completeness is `report_finishes` (the marker, not `-s`: a report killed mid-write is not a report). A non-empty unmarked report dated before `AUTODREAM_MARKER_EPOCH` (default 2026-08-19; ISO dates compare lexicographically, so this is chronological) is listed under `legacy` and not as abandoned, under its own key so the exemption is visible.
- The `fatal:` reason is carried with the date, with commas replaced by semicolons, because PROMPT.md tells L2 to read the value as a comma-separated date list and the likeliest reason embeds one (`rejected: claude,evil` turned one dead date into three entries). `fatal_exit` writes the reason into that date's own `run-stats.txt` and L2 only reads its own date's file, so without carrying it the marker was written and read by nothing.
- `run` calls it above the idempotency guard, logs a WARNING plus the `autodream-now.sh <date>` rebuild command, and logs legacy dates as a `note:` (not a warning) so a date that should not be legacy is visible. The result reaches run-stats as `unassembled_dates`.

## Consequences
The exposure is bounded: an epoch that is wrong for a given install self-corrects within a week of upgrading; set `AUTODREAM_MARKER_EPOCH` when backfilling older dates. See CLAUDE.md, "Nobody was told (`unassembled_dates`)".
