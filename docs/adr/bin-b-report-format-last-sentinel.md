# bin-b: L2's report is everything before the LAST `AUTODREAM_REPORT_END`, and pins come only from a closed block after it

Status: accepted · Date: 2026-11-21 · Code: `bin/report-format.sh` (`report_body`, `report_after_sentinel`, `report_pin_lines`, `report_has_sentinel`)

## Context

L2 holds no Write tool, so the runner is the only writer and reads the report and the pin block off L2's stdout (CLAUDE.md, "L2 is read-only: the report and the pins arrive on stdout"). A report can quote the sentinel or the pin markers in prose.

## Decision

- The sentinel is exactly `AUTODREAM_REPORT_END` on a line of its own. Indented, CRLF or quoted text is not one.
- The report is what precedes the LAST sentinel, so a quoted sentinel inside the report does not truncate it.
- Pins are the JSON-object lines of a CLOSED `AUTODREAM_PINS_BEGIN`/`AUTODREAM_PINS_END` block that follows the last sentinel. A block quoted in the body cannot inject a pin, and a capture cut off before `PINS_END` proposes nothing rather than half a pin.
- Every function takes the report or capture as `$1` and returns the status of its last command, so `report_body f > f.tmp && mv f.tmp f` stops when the read fails.

## Consequences

`apply-pins.sh` still validates every pin against the authorization list fixed before any model ran. This parser only narrows what reaches it. Changing the grammar means changing `prompts/L2_SYSTEM.txt` with it.
