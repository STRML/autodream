# runsh: A dead network or a refusing provider defers the date; it never publishes a short corpus

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: the `wait_for_network` check at the top of each L1 round, and the deferral block after the round loop)

## Context
A report written from a run that could not reach the model looks complete, ships open questions, and its own self-audit cannot tell the corpus is missing. See CLAUDE.md, 'A dead network or a refusing provider defers the date; it never publishes a short corpus (omp-autodream 2026-09-04, #37)'. The overnight failure is a Mac that slept through its trigger, so round 1 is the round most likely to run at a host with no route.

## Decision
- `wait_for_network` is checked BEFORE dispatching every round, round 1 included. When it fails, `NET_DEFERRED=yes`, `NET_DEFERRED_CAUSE=network`, and the loop breaks. The run then stops before L2 and writes no report, so the date stays unassembled and a later catch-up trigger retries it.
- The outage question is decided AFTER the retry budget, not during it: one transient DNS timeout mid-round is ridden out on the next round and must not defer the date. Both conditions are required: sessions are still missing, AND the last round that dispatched (`LAST_ROUND_RUN`) has a `true` or `provider` row in `l1-netdown.txt`. A run that recovered is never deferred, however bad round 1 was. `NET_DEFERRED_CAUSE` becomes `provider` when a `provider` row exists.

## Consequences
- Moving the decision into the round loop turns every flap into a deferred night.
- Dropping the "still missing" condition defers recovered runs.
- Related: `l1-setup-failure-is-fatal-not-deferral` (a runner that cannot set up its workers is not an outage).
