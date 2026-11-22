# bin-a: apply-pins exits 0 whatever happened to the pins, and exits 3 only when its counters cannot be trusted

Status: accepted · Date: 2026-11-21 · Code: `bin/apply-pins.sh` (`write_result`, the `RESULT` clear, the `CONTENT` read)

## Context

A pin must never cost a report. `run.sh` logs whatever `pins-result.txt` it finds, so an earlier run's counters standing in for this run's would read as this run's. A redirect on the read loop that fails to open runs zero iterations, and the counters would then say L2 proposed no pins.

## Decision

- Exit 2 on bad arguments. Exit 3 when `pins-result.txt` cannot be cleared or written, so the caller does not read stale counters as current. Otherwise exit 0 whatever happened. The counters (`pins-result.txt`, one `key: value` per line) say what went wrong.
- The old `pins-result.txt` is removed before anything else. If it cannot be cleared, the script stores nothing and exits 3.
- `pins.jsonl` is read once into `CONTENT` and that read is checked. A failed read sets `unreadable=1`, writes the counters, leaves the pins in place, and exits 3 only if the counters could not be written.
- A missing CLI sets `cli_missing=1`, counts the non-blank lines as `total`, and leaves the pins in `pins.jsonl`.

## Consequences

A new failure mode becomes a counter and a `write_result` line, not a nonzero exit. The one exit that blocks the caller is 3, and it means the counters are not this run's. `tests/apply-pins.sh` pins these paths.
