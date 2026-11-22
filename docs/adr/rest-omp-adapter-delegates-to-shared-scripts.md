# rest: the omp adapter linearizes and reads stats itself and delegates the rest to shared scripts, resolving its own directory physically

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (header, `ADIR`, `BIN`, `normalize`, `stats`, `slim`, `is-self`, `enumerate`)

## Context

An omp session is an append-only tree, not a flat transcript (CLAUDE.md, "The OMP adapter"). Unlike the claude adapter, whose `normalize` is a copy, this one has real work to do: `normalize` linearizes the tree to the live conversation (`linearize.sh`) and `stats` reads omp's own record shapes (`stats.sh`). The shared scripts (`slim-transcript.sh`, `prune-self-sessions.sh`, the enumeration `find`) already understand omp records, so rewriting them per harness would give two copies to keep in step (see `bin-a-adapter-claude-delegate-not-reimplement.md`).

The store is `$HOME/.omp/agent/sessions/<project-encoded>/<stamp>_<uuid>.jsonl`. Child sessions sit in a directory named after the parent file (`<stamp>_<uuid>/__advisor.jsonl`, `<stamp>_<uuid>/<Name>.jsonl`) and ARE sessions to triage, so the enumeration walk takes every `*.jsonl` below the root and does not stop at a bucket's top level.

`install.sh` symlinks the adapter, so `${BASH_SOURCE[0]}` is a link into the install dir. `ADIR` and `BIN` are resolved with `cd -P` for the same reason as the claude adapter: so `ADIR` is the real `adapters/omp` and `BIN` the real `bin/`, whichever way the adapter was reached.

## Decision

- `normalize` runs `linearize.sh` and `stats` runs `stats.sh` through the atomic writer. `slim` and `is-self` call the shared scripts, and `enumerate` is a plain `find` over `*.jsonl`.
- `ADIR` and `BIN` come from `cd -P`, never from the unresolved path.
- Child sessions are enumerated like any other file. Nothing in the adapter excludes them.

## Consequences

A fix to a shared script reaches both harnesses at once, and a change to omp's record shapes is made in `linearize.sh` and `stats.sh` only. An unresolved `ADIR` under a symlinked install would look for `../../bin` relative to the link and miss it.
