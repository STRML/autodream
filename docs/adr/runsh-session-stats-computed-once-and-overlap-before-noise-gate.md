# runsh: Session stats are computed once from the final enumeration, and overlap runs after every sidecar and before the noise gate

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `compute_session_stats`, `compute_overlap_stats`)

## Context
Overlap is a cross-session computation, not a per-session one. Gated sessions' sidecars still exist and still participate in overlap (see `bin-a-overlap-stats-corpus-and-pair-semantics.md`: the script cannot see the gate decision, and the stat deliberately includes every gated top-level session).

## Decision
- `compute_session_stats` runs once from the final enumeration. Retry rounds reuse those sidecars and intentionally do not regenerate them during dispatch retries.
- `compute_overlap_stats` runs after every session's sidecar exists and before the noise gate that runs inside `dispatch_l1`.
- `FANOUT_ROWS` is taken from the findings dir after that.

## Consequences
- Overlap must run after `compute_session_stats` has written every sidecar; run before it, it measures over missing sidecars.
- Placement before the noise gate is deliberate, so a later move must keep gated sessions in the measurement.
- Retry rounds reuse the sidecars; they are not regenerated during dispatch retries.
