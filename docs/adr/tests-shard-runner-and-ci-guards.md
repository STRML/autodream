# tests-shard: the shard runner and the CI shard guards each close a way for part of the suite to go unrun

Status: accepted · Date: 2026-11-22 · Code: `tests/shard.sh` (`list`, `check_matrix`, `job_if`), `tests/run-parallel.sh` (`stop_shards`, the `N` validation)

## Context

Sharding (`tests-run-all-sharding.md`) turns one suite into n parts. Each way a part can silently not run looks like a green result:

- A `run-all.sh` that ignored `RUNALL_LIST` would run the whole suite on every `list` call, so a missing feature must fail in seconds and not in a quarter of an hour.
- The matrix in `tests.yml` and `launchd.yml` can disagree with the `/n` in the run line. A shard no job runs is a part of the suite nobody runs, and CI stays green. This cannot be checked from inside `run-all.sh`.
- The weekly macOS run is the only full run under bash 3.2 and BSD tools. As one job it outgrew its timeout and was cancelled two weeks running (2026-11-09 and 2026-11-16), so it is sharded the same way.
- A manual dispatch with `suite=web` started the launchd job too, because that job's `if` did not read `inputs.suite` (#235 review).
- `tests/run-parallel.sh` once read a shard count of `08` as a bad octal: no loop ran and the run passed with zero tests. `010` read as eight.
- Background shards inherit an ignored SIGINT, and the EXIT trap would remove their temp dirs from under them while they ran.

## Decision

- `list` wraps the call in `tmo 30` and unsets `RUNALL_SHARD` and `RUNALL_LIST` first.
- `check_matrix` compares the matrix indexes, the job name count and the step name count with the count in the run line, for `tests.yml` and `launchd.yml`. `job_if` requires both launchd jobs to read `inputs.suite`.
- `run-parallel.sh` accepts at most three digits and reads them with `10#`. It starts each shard under `set -m`, so each has its own process group, and Ctrl-C or TERM sends TERM to every group. Its `TMPDIR` is short (`rp.XXXXXX`) because fixtures embed sandbox paths in lines that are cut at a fixed length.

## Consequences

A new workflow job that runs shards needs a `check_matrix` call. A new dispatch-reachable job needs an `inputs.suite` condition and a `job_if` row. Do not lengthen the `run-parallel.sh` temp prefix without checking the fixtures that cut lines.
