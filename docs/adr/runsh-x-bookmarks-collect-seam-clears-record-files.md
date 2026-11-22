# runsh: X bookmarks collect has one shape for L2, and its record files are cleared first

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the `XBOOKMARKS collect` step and the `rm -f` before it)

## Context
Unread bookmarks become idea fuel: L2 cross-references what the user saved against what they worked on. The script always exits 0 and always writes the file, including a "not configured" stub, so this seam has exactly one shape for L2. A rebuild of a date finds the earlier run's `x-bookmarks-fetch.txt` and `x-bookmarks-queryid.txt`; a collector that is missing or dies before rewriting them would otherwise have its predecessor's `browser` or `fresh` read below as tonight's.

## Decision
`run.sh` removes both record files before invoking `collect`; a failed or missing collector logs and the run continues. See CLAUDE.md, "X bookmarks as idea fuel" ("The record files are cleared before each collect", `test_x_fetch_path_reaches_run_stats`).

## Consequences
Dropping the `rm -f` makes `x_fetch_path` and `x_queryid_source` report a previous night. The `mark-read` side is gated separately (see `consume-gated-on-complete-dream-and-normal-date`).
