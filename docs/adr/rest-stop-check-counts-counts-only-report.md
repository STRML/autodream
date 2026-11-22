# rest: stop-check-counts prints counts only, reports every line it skipped, and fails when either pipeline stage fails

Status: accepted · Date: 2026-11-22 · Code: `bin/stop-check-counts.sh`, `tests/stop-check-counts.sh`; CLAUDE.md "Report scripts" (shipped report scripts)

## Context

The stop-check mod appends one JSON line per judged turn to `~/.claude/stop-check/verdicts.jsonl`: `{"kind":"ok|ask|bad|error","at":"<UTC ISO, with milliseconds>","message":"...","note":"..."}`. This script is a report script for the nightly run: allowlisted in `report-scripts.conf`, its stdout becomes `report-<name>.md` and L2 can quote its rows (README, "Report scripts"). It makes no model call and writes nothing.

## Decision

- **Counts only.** `message` and `note` hold quoted session text and are never printed, so a report row cannot leak or inject transcript text.
- **Nothing is dropped silently.** A line that does not parse, or lacks a usable `kind` and `at`, is counted as `unparseable lines skipped`. A line dated after the clock is reported as `dated after now (not counted)`. A `kind` outside `[a-z]+` is counted as `other`: the log is written by another tool, and a kind holding a tab or newline would forge rows in this tab-separated report.
- **Two views.** `recent` is the window (default 36 hours, `--since-hours N`) grouped by kind, most frequent first. `weekly` is the last eight UTC weeks (Monday start, oldest first) with one column per kind seen in them. A week with no verdicts is a row of zeros, never a gap, so a quiet week reads as quiet and not as a missing row. A Sunday 23:59:59 line belongs to the week before it.
- **The clock is injectable.** `STOP_CHECK_NOW` (epoch seconds) replaces the clock so `tests/stop-check-counts.sh` pins literal expected numbers. `STOP_CHECK_VERDICTS` names the log (default `$HOME/.claude/stop-check/verdicts.jsonl`).
- **jq emits tagged TSV rows and awk lays them out**, so the column widths do not depend on jq's version.
- **Both stages must succeed.** The script reads `PIPESTATUS` and exits with the first failing stage. jq alone failing, or awk failing to write the layout, is a script failure, and the collector reads exit 0 as `ok`.

## Consequences

A new field in the verdict log must not be printed without checking that it is not session text. A change to the row layout changes what L2 quotes, so update the literals in `tests/stop-check-counts.sh` with it. Exit codes: 2 for a usage error, 1 for a missing `jq` or log.
