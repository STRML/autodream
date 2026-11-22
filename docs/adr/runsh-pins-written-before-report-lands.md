# runsh: pins.jsonl and pin-projects.tsv are written before the report is staged

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `write_pin_projects`, ordering of the pins block ahead of the `REPORT_PATH` staging; `sweep_stranded_pins`)

## Context
A report that stands complete on disk must always have its `pins.jsonl` and `pin-projects.tsv` beside it, so a kill after the report lands cannot leave a complete report whose pins were never proposed (issue 72). A kill before the report lands leaves no complete report, and the rerun moves these aside and asks L2 again. The authorization list goes to disk with the pins so a later run can still apply them if this one dies before the pin step (see `sweep_stranded_pins`).

## Decision
The pin block is extracted and `write_pin_projects` runs before the report body is written. A failure to write `pin-projects.tsv` logs that the pins wait for a later run that can.

## Consequences
Reordering these steps reintroduces the window in issue 72: report on disk, pins lost, and the next trigger skips the date.
