# runsh: The network gate opens when any provider answers, its cap is wall-clock, and giving up defers the date

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_probe_urls`, `l2_probe_url`, `wait_for_network`)

## Context
- A dead route to one provider must not hold back sessions that run on another. A worker that does need the dead one fails, is classified as an outage by its own probe, and defers the date through the existing path.
- The cap used to count only the sleeps, so each probe (up to `AUTODREAM_NETUP_LIMIT`) ran past the bound it was handed, and a hung one was only noticed after it returned.
- A non-numeric cap makes every `[ "$elapsed" -ge "$cap" ]` test error out, and an erroring test reads as false, so the give-up branch became unreachable and the bound that was supposed to limit the wait removed it instead.
- Giving up used to `return 0` ("proceeding anyway"). That dispatched a full round of workers at a host with no route, which fails every one of them in about 9s and burns a retry round to learn nothing.
- A fixed 15s sleep step meant any cap below 15 still waited a full 15 seconds, so the wait overran its bound and reported a `network_down_seconds` larger than the configured maximum.

## Decision
`l1_probe_urls` yields one URL per distinct provider, from `AUTODREAM_L1_PROBE_URLS`, the per-source map resolved against each source's L1 engine (`AUTODREAM_L1_ENGINE_<NAME>`): an omp source on the claude engine needs anthropic. It is empty when no adapter has a resolvable provider, which `wait_for_network` reads as "nothing to ask". `wait_for_network` returns up when any URL answers. The cap (`AUTODREAM_NETCHECK_CAP`, default 1800) is wall-clock and counts the probes themselves: each probe gets at most what is left of the cap, the first one always runs (so a cap of 0 still asks once), and once the cap is spent the pass stops rather than flooring every later URL at 1s (which ran the pass N-1 probes past the cap). A non-numeric cap logs and becomes 1800. Past the cap it returns 1 and the caller defers the date. The sleep step is `min(15, cap - elapsed)`.

See CLAUDE.md, "A dead network or a refusing provider defers the date; it never publishes a short corpus".

## Consequences
Do not change give-up back to `return 0`. `tests/run-all.sh` extracts `wait_for_network()` with `sed -n '/^wait_for_network() {/,/^}/p'`, so it must stay top-level and end in a column-0 `}`. See also `network-probe-biases-to-up` and `network-down-seconds-in-run-stats`.
