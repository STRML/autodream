# bin-a: notify.sh has a `--failure` and a `--warning` form for runs that cannot write, or only partly write, a report

Status: accepted · Date: 2026-11-21 · Code: `bin/notify.sh` (the `FAILURE_MODE` branch)

## Context

A run that dies never writes a report. Until the failure form existed, a failed night was completely silent: no report, no banner, and nothing in `run-stats.txt` for a later run to read. For a persistent cause (a lost exec bit, a dependency off the launchd PATH) no later run ever succeeds to read it.

A run can also carry on and still write its report while having lost a part of its input that the operator should hear about now, not in tomorrow's report. The example is every upstream changelog source failing.

## Decision

- `notify.sh --failure <date> <reason>` reuses the notifier resolved above it and stops before everything that reads a report. It posts the banner and writes `<date>-FAILED.txt` to the inbox.
- `notify.sh --warning <date> <reason> [<key>]` takes the same path, labelled WARNING, and writes no `<date>-FAILED.txt`, because the run did not fail.
- A key gives the warning its own notification group (`autodream-warn-<key>-<date>`), so two warnings for one date do not replace each other. Without a key every warning shares one group.
- Both forms always exit 0: a notification that cannot be posted must not become a second failure on top of the first.

## Consequences

CLAUDE.md ("A failure quotes git, and a total failure posts a banner" and the remote-sync reporting) names the callers. A new caller that wants its banner to coexist with another for the same date needs its own key. The dry-run contract applies to both forms (`bin-a-notify-dry-run-stops-before-side-effects.md`).
