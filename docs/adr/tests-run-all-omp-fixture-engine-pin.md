# tests-run-all: the omp run helper pins omp sessions to the omp engine

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`run_dream_omp`, `test_omp_sessions_run_on_another_adapters_engine`)

## Context

An L1 engine resolves per source: `AUTODREAM_L1_ENGINE_<SOURCE>`, then `AUTODREAM_L1_ENGINE`, then the run's reviewer, which is the first enabled adapter. With `claude,omp` enabled, claude is first, so without a pin omp sessions would silently run on the claude CLI and the omp tests would exercise the wrong engine.

## Decision

- `run_dream_omp` exports `AUTODREAM_L1_ENGINE_OMP` as `omp` by default, using `${AUTODREAM_L1_ENGINE_OMP-omp}` so a caller who sets it, including to the empty string, wins.
- A test about the reviewer exports `AUTODREAM_L1_ENGINE_OMP=` (empty) to clear the pin.

## Consequences

Use the `-` form, not `:-`: the empty value is the supported way to clear the pin. CLAUDE.md, "Who starts the L1 worker", explains the engine-then-model resolution.
