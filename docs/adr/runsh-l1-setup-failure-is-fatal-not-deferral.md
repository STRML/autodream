# runsh: A runner that cannot set up its L1 workers is a fatal, not an outage deferral

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: the `staging` row check after the round loop)

## Context
A setup failure (stage directory, engine state, sandbox) heals nothing by waiting. A deferral would leave no report, no banner and (with no findings JSON) no `unassembled_dates` entry, every night. See CLAUDE.md, 'A host with no working sandbox says so' (the setup-failure sentences).

## Decision
When sessions are still missing and the last round that dispatched has a `staging` row in `l1-netdown.txt`, `run` removes the stage root, wipes the work bucket, then `log_fatal` and `fatal_exit` and returns 1. The fatal posts the banner and leaves the marker the next run reads. No stub is written, so the date has no report and a later run retries it.

## Consequences
- This check runs before the network/provider deferral check; reordering them turns a setup failure back into a silent deferral.
