# tests-run-all: the warmup and breaker tests drive the exact shapes the first versions got wrong

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_warmup_empty_stdout_is_a_failure_not_ok`, `test_warmup_works_for_an_adapter_with_no_environment`, `test_breaker_needs_two_barren_rounds_not_one`, `test_a_deterministic_failure_trips_the_breaker`)

## Context

- A warmup that captured `2>&1` saw omp's `Working...` stderr chatter as a non-empty reply and recorded `l1_warmup: ok` for exactly the exit-0, empty-stdout failure it exists to expose. `MOCK_MODE=l1_incomplete` writes nothing to stdout, which is why it is the fixture.
- run.sh runs under `/bin/bash` 3.2 with `set -u`, where expanding an empty array is an unbound-variable error. An adapter whose `l1-env` prints nothing (omp's) aborted the warmup pipeline before `timeout` started, recorded `l1_warmup: failed` and blamed the provider. The test copies the claude adapter and rewrites its `l1-env` to print nothing.
- The first breaker compared each round's ending missing count with the previous round's, so round 2 alone (2 == 2) tripped it and logged that rounds 1 and 2 both recovered nothing, although round 1 recovered one session. The breaker is a streak of two barren rounds, so the earliest honest trip is round 3.
- The 2026-09-05 through 2026-09-10 shape: every round failed identically, five rounds bought sixteen empty stubs, and the stats read as a healthy retry loop.

## Decision

`MOCK_MODE=l1_partial_then_stall` recovers exactly one of three sessions in round 1 and none after; the test asserts round 3 still runs. `l1_incomplete` with five rounds asserts the breaker fires, rounds 3 and 4 do not dispatch, and the stub round still writes the stub: without it the slot stays empty and the deferral logic reads a dead worker as a dead network.

## Consequences

Do not substitute a fixture that recovers zero or all sessions in round 1: the false-trip case disappears. Do not run the empty-env test under a newer bash, where an empty array expands to nothing. See CLAUDE.md "A hung worker, a cold token and a deterministic failure".
