# runsh: an unattended run logs to a file, and SIGPIPE is ignored on the interactive path

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the tail of the script: `trap '' PIPE`, `trap release_run_lock EXIT`, the `[ -t 1 ]` branch)

## Context
`run 2>&1 | tee -a "$RUN_LOG"` turns every log line into a write to a pipe, so whatever kills `tee` kills the run on its very next log call, by SIGPIPE with no error line, before the L2 retry loop, the move-aside blocks, or the consume gate are ever reached. Three runs on 2026-08-02 died exactly there and left 2026-08-01 with no report at all: `Terminated: 15` on `tee`, `Broken pipe: 13` on run, and a log ending mid-sentence at "L2 aggregation attempt 1/3...". Every recovery path in this script assumes it gets to run, and a logger that can revoke that assumption defeats all of them at once.

## Decision
A file has no reader to lose, so an unattended run writes to `$RUN_LOG` directly (`run >> "$RUN_LOG" 2>&1`). Ignoring SIGPIPE covers the interactive path too, where `tee` is still worth having and a closed terminal should cost the run its output rather than its life. See CLAUDE.md, "The logger could kill the run, and did (2026-08-02)" (the source of the SIGTERM on `tee` is still unnamed). Pinned by `test_dead_stdout_does_not_kill_the_run`.

## Consequences
Do not restore a pipe to `tee` for the non-TTY path.
