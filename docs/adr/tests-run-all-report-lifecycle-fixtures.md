# tests-run-all: report-lifecycle fixtures force each failure with a concrete mechanism

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_unmovable_stale_report_disarms_consuming`, `test_partial_report_does_not_consume`, `test_run_outcome_is_written_only_for_a_delivered_or_untouched_report`, `test_unassembled_*`, `test_pre_marker_report_is_not_abandoned`, `test_missing_report_still_abandoned_before_epoch`, `test_dead_stdout_does_not_kill_the_run`, `run_dream_broken_pipe`)

## Context

The report, the consume gate and `unassembled_dates` fail silently. Each test makes its failure happen by a specific mechanism, and would pass without the guard if that mechanism were swapped for a looser one.

## Decision

- Move-aside failure: `chmod 555` on the dreams dir, so the old report stays at the report path. Without the disarm, the retry loop and the consume gate both see the old file.
- `MOCK_MODE=l2_partial` writes a non-empty report with no open-questions marker, which is what a mid-write kill leaves. `-s` alone cannot tell it from a good report.
- Stub staging failure: the stub is written to `<report>.tmp` and renamed over the report, so a read-only old report is replaced. A directory at the staging path is what makes the write fail.
- Epoch: `AUTODREAM_MARKER_EPOCH` is pinned to the fixture's date so the marker is required. The default would exempt every 2020 date. A missing report must stay abandoned under an epoch that exempts an unmarked one: the epoch must not swallow it.
- The marker-less fixture has the real shape of the six reports in `~/.claude/dreams` that the check called abandoned every night.
- Dead stdout: `run_dream_broken_pipe` pipes the run into a reader that closes at once. Three runs died this way on 2026-08-02. Tee was killed, the next log line SIGPIPEd the run, and the retry loop, the move-aside and the consume gate were never reached. No error line said so, because saying so was the thing that died. See CLAUDE.md "The logger could kill the run".

## Consequences

Running the suite as root defeats the `chmod`-based cases.
