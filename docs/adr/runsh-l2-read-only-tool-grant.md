# runsh: L2 holds Glob and Read only, so the runner is the only writer of the report and pins

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the L2 call; `report_body`, `report_pin_lines`)

## Context
L2 cannot write the report, `pins.jsonl`, or anything else under the findings directory. The one hostile-input surface that used to need a quarantine (an L2 that rewrote `sessions-source.txt` or forged a pin) is closed at the tool grant.

## Decision
`$REPORT_PATH` and `pins.jsonl` are written by the runner from L2's stdout. See CLAUDE.md, "L2 is read-only: the report and the pins arrive on stdout".

## Consequences
Never give L2 a Write tool to simplify delivery. Any new file L2 needs is read by exact path and written by the runner.
