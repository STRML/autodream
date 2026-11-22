# bin-a: --watch decides from run.sh's own outcome line keyed by this launch's token

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (`RUN_TOKEN`, `job_finished`, `outcome_of_this_run`, `exit_on_outcome`, `LOG_START`)

## Context

Did this run deliver, and is the run over, are two separate questions. Inferring the first from the filesystem was wrong every way it was tried:

- a report file that looks complete: `run.sh` keeps a marker-bearing capture with no `AUTODREAM_REPORT_END` sentinel at the report path between L2 attempts, and a killed run leaves it there;
- the file's mtime: it is a whole second, so a report written in the launch second reads as new;
- a log line: the log also holds model text;
- a completeness predicate evaluated in the watcher: another config's questions epoch applies, and the runner accepts a legacy report before that epoch that has no marker.

A watcher that only waited for delivery watched a run whose every attempt failed for the full 90 minutes.

## Decision

Each launch gets `RUN_TOKEN` (`<epoch>.<pid>.<random>`), passed in the plist. `run.sh` appends `<token> delivered` or `<token> noop` to `logs/run-<date>.outcome`, and `--watch` reads that and nothing else, so an earlier run's line is never read as this one's.

The run is over when launchd shows no pid and `runs` is at least 1 (`runs = 0` means not started yet). An unloaded label means there is nothing to wait for. After the job finishes the outcome is read once more, because the line can land just before the job exits.

The log for a date accumulates every earlier attempt's lines, so `LOG_START` is the log size taken before `bootstrap`, and the tail starts after it.

## Consequences

CLAUDE.md, "Running on-demand without the 10-min cap", says the same. `tests/autodream-now.sh` covers the verdicts. A new way of ending a run has to write an outcome line, or `--watch` reports the run as ended without delivering.
