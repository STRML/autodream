# rest: the omp binary resolves OMP_BIN, then PATH, then the known install places, and the adapter prints which one

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (`omp_bin`, `engine-bin`)

## Context

On 2026-08-25 a 17.3.7-versus-18.0.4 split between PATH and the hard-coded default cost half of every L1 round to provider 400s, and nothing in the log said which omp ran. A launchd job has a minimal PATH, so a bun or homebrew install is not found by `command -v` alone.

## Decision

`omp_bin` answers in order: an explicit `OMP_BIN` (for pinning a build), then `command -v omp`, then the places omp installs to (`~/.local/bin`, `~/.bun/bin`, `/opt/homebrew/bin`, `/usr/local/bin`), then the bare name `omp`. The `engine-bin` verb prints the answer, an absolute path or the bare name when none was found, so the runner can log and verify exactly which binary every argv starts with. `l1-argv`, `threads-argv`, `warmup-argv` and `l2-argv` all start from the same function, so a worker, its warmup and the aggregator cannot run different builds.

## Consequences

Installing a second omp earlier on PATH changes which one runs, unless `OMP_BIN` pins it. CLAUDE.md, "What goes in the plist PATH", covers how `install.sh` makes the directory reachable from launchd.
