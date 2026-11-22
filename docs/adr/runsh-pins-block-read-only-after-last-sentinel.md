# runsh: pins are taken only from a closed block after the last sentinel

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `report_pin_lines`, `pins.jsonl.tmp`)

## Context
Only a delivered report carries pins, and only the block that follows the LAST sentinel counts, so a report that quotes the markers in its body cannot inject one. The block needs its END line: a capture cut off inside it proposes nothing, rather than half a pin. Only lines that open a JSON object are kept; `apply-pins.sh` validates each one against the authorization list that was fixed before any model ran.

## Decision
When `L2_SENTINEL = 1` and `PINS_SAFE = 1`, `report_pin_lines` output is staged to `pins.jsonl.tmp` and renamed to `pins.jsonl` only when non-empty. See CLAUDE.md, "L2 is read-only" (pins grammar).

## Consequences
Do not read pins from the report body, and do not write them on a degraded capture.
