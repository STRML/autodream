# runsh: A nightly sweep re-applies pins that a complete report left unstored

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`sweep_stranded_pins`, `lock_held_by_live_run`)

## Context
Pins can be stranded after a complete report: the run died between the report landing and the pin step (issue 72), or a store call failed or the CLI was missing and no one reran that date (issue 69). Nothing else revisits an old date: the nightly only processes yesterday and the idempotency guard skips a date that has a report.

## Decision
`sweep_stranded_pins` looks at findings dirs in the trailing window (`AUTODREAM_UNASSEMBLED_WINDOW`, default 7). A dir qualifies when it holds a non-empty `pins.jsonl`; the `pin-projects.tsv` the proposing run wrote (the authorization list, never rebuilt here from files a model could have touched); a complete report no older than the pins (an older report is not the one behind them); and either no `pins-result.txt` or counters (`pins_failed`, `pins_cli_missing`, `pins_unreadable`, `pins_unsupported_harness`) above zero. The pins ledger makes the rerun safe: a pin already stored is a duplicate. A pin that cannot be stored is retried each night until its date leaves the window.

Skips, each for a reason:
- A forced rebuild of the target date (`AUTODREAM_FORCE=1`) is left alone: the rebuild replaces its pins and owns them.
- A date whose run lock is held by a live pid is left alone (`lock_held_by_live_run`, which only reads and never reclaims). `autodream-now.sh` runs under a different launchd label, so another date's run may be in its pin step right now, and two `apply-pins` on one date both read the ledger before either appends and store a pin twice.
- A `pins-result.txt` older than the pins describes an earlier run of the date (a forced rebuild replaced the pins and died before applying them), so it settles nothing.
- Pins with no `pin-projects.tsv` are logged and stay in `pins.jsonl`, because no project is authorized.

## Consequences
Never rebuild the authorization list in the sweep. If the lock scheme changes (see `per-date-run-lock-mkdir`), `lock_held_by_live_run` reads the same `pid` file and must change with it.
