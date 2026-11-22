# runsh: a session path holding a newline or a tab is rejected at enumeration, and nothing else is

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_one_adapter`, the `case "$sp"` check)

## Context

The line-based artifacts cannot carry two characters. `sessions.txt` is line-delimited: `find` writes a path with a newline as two lines, and the runner then triages a session that does not exist. `pin-projects.tsv` and the source map are tab-separated, so a tab in a project directory or session path shifts their columns. Both were verified on this host against the real consumers rather than assumed.

Backslash and quotes used to be refused too, because the L1 fan-out read `sessions.txt` through `xargs -I {}`, which deleted a backslash and died on a quote (#54).

## Decision

`scan_one_adapter` (called from `scan_roots`) skips a path containing `$NL` or `$TAB`, counts it in `REJECTED_PATHS` (run-stats `sessions_rejected_path`) and logs it with `printf '%q'`. `dispatch_l1` now hands each worker its path NUL-delimited and the worker writes JSON through `jq`, so backslashes and quotes are carried like any other character and are not refused.

## Consequences

Do not widen the reject set without a consumer that actually breaks on the character.
