# runsh: sweeps that need only files on disk run above the idempotency guard, so a catch-up trigger that no-ops for today still does them

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `write_unindexed_flag`, `sweep_stranded_pins`)

## Context
The idempotency guard returns early once today's report is finished, and launchd fires several catch-up triggers, so most triggers return at the guard. Anything placed below it only happens on the one trigger that does the work.

## Decision
- `write_unindexed_flag` writes the found-but-not-indexed Claude folders for the report (never a prompt here) before the guard, so a catch-up trigger still reports folders that appeared since setup.
- `sweep_stranded_pins` applies pins an earlier run left unapplied, whichever date they belong to, before the guard can return. It needs only files on disk, so it runs whether or not this date has work to do.

## Consequences
Do not move either below the guard. `unassembled_dates` follows the same rule (see its ADR). See CLAUDE.md, "Session roots: one dir is not the corpus".
