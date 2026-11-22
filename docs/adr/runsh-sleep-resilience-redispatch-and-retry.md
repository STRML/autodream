# runsh: a sleeping laptop is survived by re-dispatching missing sessions across wake cycles and retrying L2

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the sleep and network helpers: `wait_for_network`, `l1_missing_count`, the L1 and L2 retry loops)

## Context

A laptop that sleeps mid-run loses the network and whole batches of workers fail: started on a brief wake, slept through the run, about half the workers errored and L2 produced no report. See CLAUDE.md, "Sleep resilience", which carries the full record (the 104 of 215 worker failures, the launchd facts).

## Decision

The L1 worker is idempotent, since a session with a findings JSON is skipped, so the run re-dispatches only the still-missing sessions across wake and sleep cycles until they land, and retries L2 until a report exists. The knobs are tunable; the network wait and the sleeps are disabled in tests.

## Consequences

Idempotence of the worker is what makes retry cheap; a change that makes a re-run of a session non-idempotent breaks this design.
