# runsh: memory pins run right after the streak update, only behind a complete report from this run

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: the `PINS` block; `write_pin_projects`, `restore_pins_ledger`, `apply-pins.sh`); plan `docs/plans/2026-09-15-mnemopi-pins.md`

## Context
- Ordering: pins are the first step after the report that calls out (the streak update only writes a local file), ahead of `notify.sh` and the consume steps. `notify.sh` runs `AUTODREAM_OPEN` synchronously, so a blocking editor command holds the run there; if the run dies in that wait, the next run skips the date and pins placed after it are never stored.
- Gating: pins need a complete report from THIS run behind them: `report_complete`, `CONSUME_SAFE` (cleared when the old report could not be moved aside), and `PINS_SAFE` (cleared when an earlier `pins.jsonl` could not be moved aside). They skip the consume date gate on purpose: an old-date rebuild still teaches something real, and `apply-pins.sh`'s ledger stops a rerun from storing the same pin twice.
- `pin-projects.tsv` is the authorization list. It holds only projects this run triaged, each with the working directory its session's adapter resolved, so a pin naming any other project is refused and memory is never scoped by a path the model wrote.

## Decision
The chain of `elif`s skips, with a logged reason, when the gates fail, when `pin-projects.tsv` cannot be written, or when the ledger cannot be restored (duplicates cannot be ruled out); otherwise it runs `apply-pins.sh` and logs the counters. See CLAUDE.md, "Where state lives" (`pin-projects.tsv`, `pins-applied.tsv`).

## Consequences
Do not apply pins from a stale or unvalidated `pins.jsonl`. Do not gate them on the normal-nightly-date rule used for consuming.
