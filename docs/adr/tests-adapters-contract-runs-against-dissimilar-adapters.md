# tests-adapters: the adapter contract runs unchanged against every adapter, including a fixture that resembles neither harness

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-contract.sh` (`run_contract`, the `enumerate` and `is-self` groups)

## Context

A contract that only runs against the adapter it was written beside describes that adapter, and keeps passing on the day someone adds a Claude-shaped assumption to shared code.

## Decision

- `run_contract` runs the same assertions for `claude`, `omp` and `_fixture`. `_fixture` uses a session format (`{"cwd":...,"turns":2}` in a `.fixture` file) that matches neither real harness, so a leaked assumption fails immediately. A new adapter is one more `run_contract` line; if more than that is needed, the seam is not real.
- `enumerate` pins the session to a fixed day (`touch -t 202001021200`) and asks for exactly that day. A wide range such as 1970..2999 is not portable: BSD `find` fails to parse `-newermt` at that far end and errors out, and the assertions would measure the date parser rather than the contract (the runner itself uses a five-year reach for the same reason, CLAUDE.md "Which day a session belongs to").
- `is-self` must answer for a session that cannot be READ, and must not answer "not ours". The predicate greps with stderr discarded and returns 1 for a missing file, the same answer a genuine user session gives, so a vanished transcript silently became someone else's problem. Every sibling subcommand has that guard.

## Consequences

Do not special-case an adapter inside `run_contract`. Do not widen the `enumerate` date range.
