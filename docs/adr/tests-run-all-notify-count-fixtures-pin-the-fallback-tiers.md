# tests-run-all: the notify count fixtures include the incident shape and the "None" lead-in

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_notify_count`)

## Context

`notify.sh` counts open questions from the `autodream:open-questions=N` marker and falls back to the section's shape for reports without one (`docs/adr/bin-a-notify-count-from-marker.md`).

## Decision

- The first fixture is the real 2026-07-24 shape: one numbered question, then a list of findings dropped by the gate. The old counter scored 6 for it and the marker says 1. The test asserts the marker wins over the six list lines.
- The no-marker fixture holding only a "None that clear the triviality gate" line stays in the suite. Without it, the bare-prose tier would turn every quiet pre-marker night into a false pop-up.

## Consequences

Replacing the first fixture with a plain numbered list stops it distinguishing the marker from the shape-based count. Deleting the "None" case lets a prose-tier regression through unnoticed.
