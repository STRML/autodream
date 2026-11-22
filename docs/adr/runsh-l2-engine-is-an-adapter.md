# runsh: the L2 engine is an adapter and `run.sh` names no binary for it

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `review_engine`, `adapter_run "$L2_ENGINE" l2-argv`, `l1-env`)

## Context
The engine that runs L2 is chosen by `AUTODREAM_L2_ENGINE` and by default is the first enabled adapter. It prints its own argv (`adapters/<name>/adapter.sh l2-argv`). The model resolves per adapter (`AUTODREAM_L2_MODEL_<NAME>`, then `AUTODREAM_L2_MODEL`, then the manifest). None at all is legitimate and means the engine's own default. A model id belongs to one engine, which is why the per-adapter form exists.

## Decision
The runner reads NUL-delimited argv and the adapter's env lines into `L2_ARGV` and `L2_ENVS`. See CLAUDE.md, "Which engine runs L2".

## Consequences
A new engine is a new adapter, not a branch in this file. The only engine-specific code left is the claude-only fallback (`l2-builtin-claude-fallback-for-old-adapters-tree`).
