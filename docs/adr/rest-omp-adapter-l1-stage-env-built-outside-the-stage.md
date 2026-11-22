# rest: l1-stage-env builds the seeded state in a directory beside the stages and renames it into the stage at the end

Status: accepted · Date: 2026-11-21 · Code: `adapters/omp/adapter.sh` (`l1-stage-env`)

## Context

The verb runs outside the sandbox, as the user, and every path inside a stage is chosen by the last worker that ran there: a read-only directory, a symlink at a seeded name, a database that is a link. A copy or snapshot written straight into the stage would follow any of those, so a worker could aim the runner's write at a file of its choosing.

## Decision

- Remove the previous `<stage>/omp-home` first, and refuse if it cannot be removed.
- Build everything under `mktemp -d "$(dirname "$1")/seed.XXXXXX"`, a directory of its own beside the stages. An EXIT trap removes it on any failure.
- Nothing below writes into the stage. A final `mv` renames the finished tree to `<stage>/omp-home`, then the trap is cleared.

## Consequences

The stage is touched exactly once, by the final rename. Moving a seeding step to write into `$1` directly re-opens the symlink-in-stage hole. The runner also writes the verb's stderr to a file beside the stages for the same reason (`runsh-l1-write-confinement-staging.md`).
