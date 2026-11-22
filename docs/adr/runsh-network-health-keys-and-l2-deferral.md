# runsh: network health is recorded in two scopes (L1 and L2) and L2 retries stop when there is no route

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `network_*` keys in the `run-stats.txt` block, the deferral branch before changelog collection, the L2 retry loop and the post-loop probe)

## Context
- `run-stats.txt` is closed before L2 runs, so the L2 side is appended after the aggregator loop as `network_down_seconds_l2` / `network_deferred_l2`.
- `network_down_seconds` is time the runner spent blocked BETWEEN rounds; the per-worker ledger (`l1-netdown.txt`) is one curl at the instant a worker failed. A flapping network makes the first large and the second false for every worker, which is not a contradiction; `network_flapped: yes` is emitted when the former is positive and no worker saw a `true`.
- PROMPT.md reads all four network keys. The deferral exit jumps over the post-L2 append, and an absent key cannot be told from an older runner, so the deferral branch writes `network_down_seconds_l2: 0` and `network_deferred_l2: no` itself (L2 did not run: zero waits, no deferral).
- Between L2 attempts, spending the remaining attempts against a host with no route produces nothing but a later exit, so `wait_for_network` failing sets `NET_DEFERRED=yes` and breaks out.
- The last attempt is classified too: the probe in the retry loop only runs between attempts, so a route that dropped before the final attempt was never seen and the run would record `network_deferred_l2: no`. The probe runs only when L2 failed; a delivered report needs no explanation.

## Decision
The keys, the deferral-branch defaults and the post-loop probe exist as described. The L2 delta is `NET_DOWN_SECONDS - NET_DOWN_SECONDS_PRE_L2`. See CLAUDE.md, "A dead network or a refusing provider defers the date; it never publishes a short corpus (#37)".

## Consequences
Removing the explicit zero/no append on the deferral path makes the keys vanish exactly when a reader most needs them. The L2 probe is gated on `AUTODREAM_NETCHECK` (tests set it to 0).
