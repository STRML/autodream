# runsh: an earlier pins.jsonl is moved aside before every L2 attempt

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `STALE_PINS`, `PINS_SAFE`)

## Context
A `pins.jsonl` already present came from an earlier run or an earlier attempt, and no complete report from THIS attempt stands behind it. Left in place, a dead attempt's pins would be stored alongside the next attempt's report. The name comes from `mktemp`, not a timestamp: two forced rebuilds inside one second would otherwise pick the same name, and the second move would overwrite the first run's unapplied pins.

## Decision
Moved to `pins.jsonl.stale-XXXXXX`, not deleted, so a pin that never reached Mnemopi stays readable. A failed move clears `PINS_SAFE` for the run, for the same reason `CONSUME_SAFE` works that way (see `stale-dream-moved-aside-before-l2-and-consume-safe`), and removes the empty `mktemp` placeholder it left behind, which would otherwise be litter once per attempt.

## Consequences
Do not replace the `mktemp` with a timestamp. Nothing in the runner reads a `pins.jsonl.stale-*` file again; it is a record only. A `pins.jsonl` that stands beside a finished report and never finished storing is a different case, handled by `sweep_stranded_pins`.
