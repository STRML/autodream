# tests-report-scripts: fixtures that must be able to fail, and a skip that never counts as a pass

Status: accepted · Date: 2026-11-22 · Code: `tests/report-scripts.sh`, `tests/stop-check-counts.sh`, `tests/portable.sh` (watchdog sleep), `tests/run-all.sh` (`test_report_scripts_*`, the unit-suite totals loop)

## Context

`bin/report-scripts.sh` runs allowlisted commands before L2 so a failure becomes content in the findings dir, never silence and never an aborted run. Each trap below made a first version of a test pass for the wrong reason.

## Decision

- **A check that cannot run prints `skip - <reason>`.** It adds nothing to the passed count, and the totals line carries `skipped: N`. `run-all.sh` repeats that number beside the suite's count, so a CI log shows ran against skipped. A suite that prints no `skipped:` total is unchanged.
- **The watchdog test asks `kill -0`, not a process table.** A `sleep` shim records its pid and then becomes the real `sleep`; `kill -0` on that pid shows the watchdog's sleep ended with the command. `pgrep` and `ps` are denied in some sandboxes. `tests/portable.sh` and `tests/report-scripts.sh` use the same shim.
- **The failed-write case limits the file size.** SIGXFSZ is ignored and the limit is 1 KB, so the report's header line (the command is 1.2 KB) cannot be written while the short index row for a failed write can. The old collector wrapped every write in one brace group, whose status is its last command, and recorded an `ok` row for a report that was not there.
- **The unremovable stale index is an `rm` and an `mv` that refuse it.** The cleanup uses `rm -rf`, so a planted directory with a report name is not unremovable, and a read-only findings dir would stop the run long before the seam under test.
- **Fixture ordering and rewrites are deliberate in `run-all.sh`.** `report-z.md` sorts after the collected files, so the rows before it hash and match and `shasum` then fails on it. A stand-in collector rewrites the conf and the good script during `snapshot`, which `run.sh` calls after it fingerprinted the file: what an L1 worker with Write could do before the collector starts. A forced rerun keeps the findings dir, so the earlier run's files must not survive a failed collect.
- **`tests/stop-check-counts.sh` expected numbers are literals worked out by hand.** Every fixture line is synthetic and the clock is injected (`STOP_CHECK_NOW`, 2026-11-19T12:00:00Z, a Thursday whose UTC week starts Monday 2026-11-16). The real log's `message` and `note` fields hold quoted session text, so the script must print counts only.

## Consequences

A new case in these suites needs a way to fail with the guarded code removed. Do not replace a literal with a second run of the code under test.
