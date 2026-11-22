# runsh: Cut a transcript to the report day after normalizing it, and a failed cut costs a larger read, not the session

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`day_slice`, `compute_session_stats`)

## Context
Issue #113 (report-day window). A tree-shaped transcript (omp) is linearized by its adapter. Cutting the raw tree would leave entries whose parent was cut away, and the linearizer fails closed on a dangling parent, which would refuse every omp session that spans a day boundary.

## Decision
The order is normalize first, cut second, the same one the worker uses: a tree is linearized FIRST and the live chain is what gets cut. `day_slice` returns 0 when the slice was written, 1 when there is nothing to cut (the window is off, or every timestamped record is already inside the day; the destination is untouched), 2 when the helper failed. On 2 the caller reads the whole transcript: `compute_session_stats` logs a WARNING that its stats cover the whole transcript. A failed cut costs a larger read; it never costs the session.

See CLAUDE.md, "Which day a session belongs to (the report-day window, #113)" (The slice).

## Consequences
Do not reorder the steps. A new caller must handle all three return codes.
