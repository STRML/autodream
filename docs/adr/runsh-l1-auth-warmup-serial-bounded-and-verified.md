# runsh: A serial, bounded, verified auth warmup runs per engine before the parallel L1 dispatch

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `L1_WARMUP` block)

## Context
`FANOUT` workers starting cold at once all find the same expired token and all try to refresh it. See CLAUDE.md, 'A hung worker, a cold token and a deterministic failure' (the auth warmup bullet).

## Decision
- One serial `ping` per adapter before the dispatch, so the refresh happens once. It never fails the run; the verdict lands in run-stats as `l1_warmup`.
- It is bounded by its own deadline (`AUTODREAM_L1_WARMUP_TIMEOUT`) because it runs ahead of every recovery path (the retry loop, the circuit breaker, `wait_for_network`). An unbounded warmup that hangs on exactly the cold-start condition it targets wedges the run before all of them, with launchd suppressing later triggers while the job stays alive. With no timeout binary it is skipped (`skipped_no_timeout`), not run unbounded.
- It warms the engine the workers will call, which an `AUTODREAM_L1_ENGINE_<NAME>` override moves.
- The call expands the env array as `${_wenv[@]+"${_wenv[@]}"}`, not `"${_wenv[@]}"`: `run.sh` runs under `/bin/bash` 3.2 with `set -u`, where expanding an EMPTY array is an unbound-variable error. omp's `l1-env` prints nothing, so the pipeline aborted before `timeout` started and the warmup recorded `failed`, blaming a healthy provider.
- The reply must be the single word `ok` (case, surrounding whitespace and punctuation tolerated) with exit 0. Anything else on stdout with exit 0 is a diagnostic, not a reply, and must not read as a healthy provider.
- On failure the log line names both streams (`stdout=[...] stderr=[...]`; an empty stdout IS the finding), because the point of the warmup is that this line exists before 8 workers repeat the failure in parallel and bury it.

## Consequences
- Do not make the warmup fatal, unbounded, or judge it on exit code alone.
- Keep `${arr[@]+...}` for any array that can be empty under bash 3.2.
