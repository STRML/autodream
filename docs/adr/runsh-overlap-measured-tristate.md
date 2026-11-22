# runsh: The overlap pass is global and carries a measured marker so a zero is never a non-measurement

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`compute_overlap_stats`)

## Context
Issue #14 (cross-session "multi-clauding" stat) and #26. Overlap is a GLOBAL, cross-session computation: it cannot be done per-session inside `compute_session_stats` or `dispatch_l1`'s xargs subshells, which only ever see one session at a time. A genuine zero-overlap night must not be confusable with a non-measurement.

## Decision
`compute_overlap_stats` runs once `compute_session_stats` has written every sidecar (each carries the mechanical `user_turn_timestamps` array). It sets `OVERLAP_EVENTS` and `SESSIONS_WITH_OVERLAP` (default 0/0 on any failure or absence, so the run-stats writer always has a value and never aborts the pipeline) and `OVERLAP_MEASURED`: 1 when `overlap-stats.sh` ran and produced parseable output (even 0 pairs is a legitimate result), 0 when the script was missing or not executable, produced no output, or produced output `jq` could not extract both fields from. Each of those gets its own explicit "overlap not measured" log line, which says the counts were left at 0/0. The old comment called the marker a tri-state, but it only ever holds 1 or 0; the "three" are the three not-measured causes.

See CLAUDE.md, "Self-audit" (`overlap_measured: yes|no` (#26)).

## Consequences
A new failure path must set `OVERLAP_MEASURED=0` and log its own reason, never fall through to the "overlap: 0 pair(s)" line.
