# tests-run-all: the network deferral tests pin when a failure must defer without a stub and when it must not defer at all

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_wait_for_network_cap_bounds_the_probe`, `test_route_lost_after_the_precheck_still_defers`, `test_provider_refusal_defers_without_a_stub`, `test_provider_402_and_missing_curl_still_defer`, `test_missing_curl_is_not_read_as_an_outage`, `test_no_curl_does_not_defer_a_healthy_run`, `test_unexecutable_curl_is_not_read_as_an_outage`, `test_a_transient_outage_is_ridden_out_not_deferred`)

## Context

A deferral is only correct if the slot stays empty. A findings stub carries `.findings`, and `jq -e` counts an empty array as present, so writing one marks the session done: the missing count hits zero, the run stops deferring, L2 publishes an empty report, and every later run skips the session because its slot is filled. That applies to a route lost after the pre-dispatch check (the round-5 shape from 2026-09-04, hence `AUTODREAM_NETCHECK=0` in the fixture: the pre-check only proves the route was up when the round started) and to a provider refusal on a reachable network (the provider carve-out).

The opposite failures also happened. A curl that cannot run (127 missing, 126 not executable) answers nothing, so reading it as an outage would defer every date forever on a host without curl; `net_up` ran curl unconditionally and looped to the full cap until it grew the `command -v` guard the worker-failure path already had. The first version of the outage fix broke out of the retry loop on any network-flavoured failure, so one transient DNS timeout deferred the date for three hours instead of succeeding in round 2. Some shells skip a non-executable PATH entry and run the next curl, so the 126 shim is an executable script that returns 126 directly.

## Decision

Fixtures use a tiny `AUTODREAM_NETCHECK_CAP` (a missing guard then defers fast) and `TEST_CURL_SHIMMED=1` shims on PATH. The cap test clamps probes to the cap: with six dead hosts against a 2 s cap, a loop that keeps probing after the cap runs about 2 s plus 5 x 1 s, one that stops runs about 2 s, and the 4 s ceiling sits between them by more than the 1 s granularity of `date +%s`.

## Consequences

Do not move the ceiling to the single-host bound or tighten it to 2 s. Do not replace the 126 shim with a `chmod -x` file. See CLAUDE.md "A dead network or a refusing provider defers the date".
