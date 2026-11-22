# rest: l1-stage-env refuses when omp keeps state somewhere the seeding does not model, and never reads an unanswerable test as absent

Status: accepted · Date: 2026-11-21 · Code: `adapters/omp/adapter.sh` (`l1-stage-env`), `bin/lib-path-state.sh` (`path_state`)

## Context

Running a confined worker on the wrong files is worse than failing it. A named profile, an XDG redirect, or a path override moves omp's state to a place the throwaway-HOME seeding (`rest-omp-adapter-l1-stage-env-throwaway-home.md`) does not look. A failed `-e` test is also not proof that nothing is there: a path under a directory this user cannot search tests as absent too.

## Decision

The verb exits 1 with an `omp l1-stage-env:` message in each of these cases:

- `OMP_PROFILE` or `PI_PROFILE` is set. A named profile moves the state.
- `$XDG_DATA_HOME`, `$XDG_STATE_HOME` or `$XDG_CACHE_HOME` is set and `<it>/omp` exists. omp redirects a directory category to `$XDG_<CATEGORY>_HOME/omp` on Linux and on macOS, but only when that directory exists, so the refusal is on the same condition and not on the variable alone.
- One of `OMP_WORKTREE_DIR`, `OMP_GITHUB_CACHE_DB`, `OMP_COMMIT_CACHE_DB`, `OMP_JUDGMENT_CACHE_DB`, `OMP_AUTH_BROKER_SNAPSHOT_CACHE`, `PI_NATIVES_DIR` is set. These point outside any tree the seeding covers (omp's `dirs.ts`).
- `PI_CONFIG_DIR` is not a plain directory name under `HOME`.
- The stage path holds a newline.

`path_state` has three answers: present, absent, and "cannot tell" (an unreachable path, a symlink into a directory this user cannot search). Only "absent" is believed to mean nothing there. "Cannot tell" refuses for the XDG trees, the agent dir, every seeded file and database (a database that cannot be snapshotted is not an absent one), and the `.env` files. An agent dir that exists and cannot be read also refuses; one that is absent seeds nothing.

## Consequences

A new omp env override that relocates state needs a line in the override list, or workers silently run on the wrong files. The newer the omp, the likelier a missed override: re-read omp's `dirs.ts` when upgrading across a major version. A refusal here is a setup failure for the engine (CLAUDE.md, "A host with no working sandbox says so"): no stub, a fatal before any worker starts.
