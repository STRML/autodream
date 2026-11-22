# runsh: The no-sessions stub is staged, status-checked and published in one rename; a failed publish fails the run

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the stub heredoc and the publish step on the `COUNT -eq 0` path)

## Context
- A stub written straight to the report path, stopped after the questions block but before the record line (or anywhere else), would leave a half stub that `report_complete` would accept without its record. See CLAUDE.md, 'What a report did not fully read' ("The record is a line inside the report").
- A stub that could not be opened for writing leaves the previous report in place, and that old file is complete, so `report_complete` alone would call it this run's delivery.
- A run that could not publish its report has not done what it was asked. The exit code is what the launchd job and a forced rebuild's caller see.

## Decision
- The stub is written to `$REPORT_PATH.tmp`; the heredoc's status is kept in `STUB_WRITTEN` for both the publish step and the outcome.
- Dropped-thread input is spliced in before `AUTODREAM_QUESTIONS_BEGIN` through `$REPORT_PATH.threads`, then renamed over the tmp.
- The report is published with `mv -f` only when `STUB_WRITTEN` is 0. On failure the temp files are removed, `log_fatal` and `fatal_exit` run, and the run returns 1; a report already at the path stays the old one.
- `write_run_outcome delivered` is written only when `STUB_WRITTEN` is 0 and `report_complete` holds; otherwise a WARNING says the stub was not written and it is not reported as delivered.

## Consequences
- Do not test `report_complete` alone to decide delivery on this path.
- Do not write the stub in place.
