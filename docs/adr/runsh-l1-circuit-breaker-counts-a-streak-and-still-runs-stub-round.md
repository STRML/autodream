# runsh: The L1 circuit breaker counts a streak of barren rounds and still dispatches the stub round

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `L1_NOPROGRESS`, `round_start_missing`, the breaker in the round loop)

## Context
The retry budget is built for a Mac sleeping through a round, and against that it works. Against a worker that dies the same way every time it buys nothing and hides the shape: 2026-09-08 spent all five rounds and 405s to write 16 empty stubs, and the run-stats it left (`l1_rounds_used` 5 of 5, `l1_timed_out` 0) read as a healthy retry loop rather than as five identical failures. See CLAUDE.md, 'A hung worker, a cold token and a deterministic failure' (the circuit breaker bullet).

A comparison against the previous round's ending count is wrong: round 1 taking 3 missing down to 1 and round 2 recovering none leaves both ends equal at 1, which tripped the breaker after a single bad round and logged the lie that rounds 1 and 2 both recovered nothing.

## Decision
- `L1_NOPROGRESS` is a streak of consecutive rounds that recovered nothing; any recovery (fewer missing, or more chunk answers) resets it to zero. "Did THIS round recover anything" is answered from counts sampled before the dispatch (`round_start_missing`, `round_start_chunks`), not inferred from the previous round's ending count.
- Two consecutive barren rounds mean the failure is deterministic, not transient.
- The breaker still dispatches once more: the metadata-stub fallback fires only when the dispatcher sees `AUTODREAM_CURRENT_ROUND` at the budget, so breaking out here without that round would leave the slots empty, and an empty slot is not a stub. It jumps to the last round rather than skipping to the end: three dispatches instead of five, with the same artifacts on disk.
- The `round -lt L1_ROUNDS` guard matters at `AUTODREAM_L1_ROUNDS=2` (the suite runs low budgets): there the final round IS the stub round and has already run.
- `l1_breaker_fired: yes` and `l1_rounds_used` (the last round that actually dispatched) keep a short run from reading as a clean one.

## Consequences
- Do not replace the streak with an end-to-end count comparison.
- Do not break out of the loop without running the stub round.
