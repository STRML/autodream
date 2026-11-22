# tests: ci-scope-and-shard-guards: ci-scope and shard guard suites

Status: accepted · Date: 2026-11-22 · Code: `tests/ci-scope.sh` (the rename fixture repo, `reader_paths`), `tests/shard.sh` (`list`, `check_matrix`, `job_if`), `tests/run-parallel.sh` (`stop_shards`, the `N` validation)

## the selector leans toward `full`, sees both sides of a rename, and is checked against what the full suite reads

### Context

`.github/ci-scope.sh` decides whether a PR's `tests.yml` run needs the whole suite or only the web dashboard's. The failure that matters is a PR classified `web` whose change the full suite would have caught. Cheap CI is never worth that, so every assertion leans toward `full`.

- `git diff --name-only` reports a rename by its new path only. Moving `bin/run.sh` into `web/` read as a web-only change. The selector now runs the diff itself with `--no-renames`.
- The rule "a web file is one the full suite never reads" needs an oracle. `web/threads.*` failed it, which is why the selector excludes those files.
- Readers deliberately left out of the oracle: `install.sh` (only links the web files); the macOS-only suites `run-all.sh` adds on Darwin, among them `install-web-agent` (`tests.yml`'s Linux shards never run them and `launchd.yml` runs them on its own paths); and `bin/autodream-web`, the launcher only the web suite and those macOS suites start.
- `reader_paths` is a function and not a loop inside `$(...)`: bash 3.2, the interpreter `run-all.sh` and launchd use on macOS, cannot parse a case pattern's `)` inside a command substitution.

### Decision

The test builds a throwaway repo with a rename and asserts `base..moved` is `full` while `moved..css` is `web`. A missing ref also yields `full`. The oracle lists every tracked file the selector calls web and fails if any code the Linux shards run names one, minus the three exclusions above.

### Consequences

A new assertion that could narrow the scope needs a matching case that proves it still returns `full` on the dangerous input. Keep the `reader_paths` exclusions in step with `run-all.sh`'s Darwin-only list.

## the shard runner and the CI shard guards each close a way for part of the suite to go unrun

### Context

Sharding (`tests-run-all-harness-and-engine-isolation.md`) turns one suite into n parts. Each way a part can silently not run looks like a green result:

- A `run-all.sh` that ignored `RUNALL_LIST` would run the whole suite on every `list` call, so a missing feature must fail in seconds and not in a quarter of an hour.
- The matrix in `tests.yml` and `launchd.yml` can disagree with the `/n` in the run line. A shard no job runs is a part of the suite nobody runs, and CI stays green. This cannot be checked from inside `run-all.sh`.
- The weekly macOS run is the only full run under bash 3.2 and BSD tools. As one job it outgrew its timeout and was cancelled two weeks running (2026-11-09 and 2026-11-16), so it is sharded the same way.
- A manual dispatch with `suite=web` started the launchd job too, because that job's `if` did not read `inputs.suite` (#235 review).
- `tests/run-parallel.sh` once read a shard count of `08` as a bad octal: no loop ran and the run passed with zero tests. `010` read as eight.
- Background shards inherit an ignored SIGINT, and the EXIT trap would remove their temp dirs from under them while they ran.

### Decision

- `list` wraps the call in `tmo 30` and unsets `RUNALL_SHARD` and `RUNALL_LIST` first.
- `check_matrix` compares the matrix indexes, the job name count and the step name count with the count in the run line, for `tests.yml` and `launchd.yml`. `job_if` requires both launchd jobs to read `inputs.suite`.
- `run-parallel.sh` accepts at most three digits and reads them with `10#`. It starts each shard under `set -m`, so each has its own process group, and Ctrl-C or TERM sends TERM to every group. Its `TMPDIR` is short (`rp.XXXXXX`) because fixtures embed sandbox paths in lines that are cut at a fixed length.

### Consequences

A new workflow job that runs shards needs a `check_matrix` call. A new dispatch-reachable job needs an `inputs.suite` condition and a `job_if` row. Do not lengthen the `run-parallel.sh` temp prefix without checking the fixtures that cut lines.
