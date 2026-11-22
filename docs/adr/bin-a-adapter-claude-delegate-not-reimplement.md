# bin-a: the claude adapter delegates to the existing bin/ scripts and never reimplements their predicates

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`BIN`, `is-self`, `stats|slim`)

## Context

The adapter exists so that `run.sh` stops knowing which harness it is talking to. Nothing about Claude ingest was meant to change when it was introduced. `bin/prune-self-sessions.sh` is the single source of truth for "is this one of autodream's own transcripts", and `session-stats.sh` and `slim-transcript.sh` have callers outside this seam.

## Decision

- Every subcommand that has an existing implementation calls that script (`is-self` execs `prune-self-sessions.sh --is-self`; `stats` and `slim` call `session-stats.sh` and `slim-transcript.sh`). A marker added to the self-session predicate must not have to be remembered in the adapter too.
- `BIN` is resolved with `cd -P`. Logical resolution could succeed against a coincidental `$TARGET/bin` in the installed layout and land in the wrong directory; `-P` follows the `adapters` symlink physically first, so it resolves to the real `bin/`.

## Consequences

A behavior change belongs in the delegate. The atomic-write wrapper around `stats` and `slim` is the one thing the adapter adds, because the contract is the adapter's (see `bin-a-adapter-claude-atomic-destination-write.md`).
