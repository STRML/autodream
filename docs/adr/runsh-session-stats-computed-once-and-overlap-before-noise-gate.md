# runsh: Session stats are computed once from the final enumeration, and overlap runs after every sidecar and before the noise gate

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `compute_session_stats`, `compute_overlap_stats`)

## Context
Overlap is a cross-session computation, not a per-session one. Gated sessions' sidecars still exist and still participate in overlap (see `bin/overlap-stats.sh`).

## Decision
- `compute_session_stats` runs once from the final enumeration. Retry rounds reuse those sidecars and intentionally do not regenerate them during dispatch retries.
- `compute_overlap_stats` runs after every session's sidecar exists and before the noise gate that runs inside `dispatch_l1`.
- `FANOUT_ROWS` is taken from the findings dir after that.

## Consequences
- Moving overlap after dispatch drops gated sessions from the overlap measurement.
- Moving it before `compute_session_stats` computes overlap over missing sidecars.
- Regenerating sidecars per retry round changes the numbers the noise gate and oversized gate read mid-run.
