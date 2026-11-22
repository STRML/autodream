# tests-session-window: expected bounds are literals worked out separately, and the out-of-order fixture hides its stray record in the middle

Status: accepted · Date: 2026-11-22 · Code: `tests/session-window.sh` (`START`/`END`, the `bounds` assertions, `out-of-order.jsonl`)

## Context

`bin/session-window.sh bounds` computes local-day epoch bounds with BSD `date`. A test that derives its expected bounds with the same `date` call cannot disagree with the code, so it passes whatever the helper does on a DST day. The production rules are in `bin-b-session-window-record-timestamps-place-the-day`.

`needs-slice` decides whether a transcript holds records outside the day. A file whose first and last records are inside the day looks wholly in-day to a check of just those two.

## Decision

- `START=1790812800` and `END=1790899200` (2026-10-01 00:00:00Z and 2026-10-02 00:00:00Z) are literals. Every bound in the `bounds` block is a literal worked out separately from zoneinfo: ordinary days and the 23-hour and 25-hour days in New York, London and Sydney (northern and southern hemispheres), and a half-hour offset zone (Kolkata).
- `out-of-order.jsonl` has an in-day first record, a 2026-09-29 record in the middle and an in-day last record. `needs-slice` must still say yes, so the helper has to read every record. A fixture whose stray record sat first or last would pass a first-and-last check, and another day's records would leak into this one's report.

## Consequences

Never replace a literal with a `date` call or a helper, and never move the stray record to an edge of that fixture. A new zone needs its expected bounds computed outside this repo's code.
