# tests-run-all: chunking tests scope their environment to a subshell, and export the slim modes on purpose

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`run_chunked`, `test_a_failed_chunker_never_hands_a_worker_the_whole_slim`, `test_a_cached_chunk_answer_is_not_reused_on_another_engine`)

## Context

The chunking tests change knobs that `run.sh` reads from the environment: `AUTODREAM_L1_CHUNK_BYTES`, `AUTODREAM_SLIM_FULL`, `AUTODREAM_SLIM_RESHAPE`, and `HOME` for the omp adapter, which enumerates `~/.omp`.

- `VAR=x run_chunked` combined with an `export VAR` inside the function leaves `VAR` set after the call on bash 5, while bash 3.2 restores it. The next test then inherited a stale `CHUNK_BYTES` and never chunked. Linux CI runs bash 5 and macOS runs 3.2, so a local macOS pass hid it.
- A caller that has already set `AUTODREAM_SLIM_FULL=1` or `RESHAPE=1` must not leak into the chunker's failure fallback. A leak would turn the capped head/tail slim into the whole transcript.

## Decision

`run_chunked` sets `AUTODREAM_L1_CHUNK_BYTES` inside a `( ... )` subshell, so the knob cannot outlive the call. The engine-change test runs its second run in a subshell for the same reason: the sandbox `HOME` cannot outlive it. The failed-chunker test exports `AUTODREAM_SLIM_FULL=1` and `AUTODREAM_SLIM_RESHAPE=1` deliberately: the assertion that the worker still receives the capped slim only has power while those modes are set.

## Consequences

Do not turn the subshell into a bare `export` to save a fork, and do not drop the two exports from the failed-chunker test. With them removed, the test passes against a fallback that reads the uncapped slim. Run chunking changes under both `/bin/bash` 3.2 and a bash 5 (the Linux CI path); the difference is invisible on one interpreter.
