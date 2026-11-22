# runsh: one `review_engine` function names both the L2 summary engine and the default L1 engine

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`review_engine`)

## Context
The run's reviewer is the engine that writes the summary (`AUTODREAM_L2_ENGINE`, else the first enabled adapter), and by default it also reviews every source in L1.

## Decision
Both read the same function, so the per-session pass and the summary cannot drift onto different engines unless the host asks (`AUTODREAM_L1_ENGINE`, `AUTODREAM_L1_ENGINE_<NAME>`). See CLAUDE.md, "The engine, then the model" and "Which engine runs L2".

## Consequences
A new place that needs "the engine" calls `review_engine` instead of re-deriving it.
