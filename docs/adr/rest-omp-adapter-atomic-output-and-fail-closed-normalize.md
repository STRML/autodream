# rest: omp stats and slim write through a unique temp and refuse a directory destination, and normalize leaves no output when linearize fails

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (`atomic`, `stats`, `slim`, `normalize`)

## Context

A half-written output that a later step reads as a whole session is worse than no output. `stats.sh` and `slim-transcript.sh` write their destination directly, so atomicity lives in the adapter, which is the one place that owns the destination. The full reasoning, including why `mv` into a directory reports success while writing nothing where the caller looks, and the check-then-act race that remains, is in `bin-a-adapter-claude-atomic-destination-write.md`. This adapter carries the same shape.

`linearize.sh` is a different case. It is its own atomic writer, refuses a directory destination itself, and exits nonzero with no output for anything it cannot prove is the live conversation (a malformed line, a dangling `parentId`, a cycle). The callers skip such a session instead of reading the raw file, which would credit the user with branches they abandoned.

## Decision

`atomic DEST CMD...` runs the command with a unique `mktemp "$dest.tmp.XXXXXX"` as its last argument, then `mv -f` onto the destination. It refuses a directory destination up front, removes the temp on any failure, and after the `mv` checks the destination is a regular file (removing the stray inside a directory otherwise). `stats` and `slim` use it. `normalize` calls `linearize.sh` directly and maps its failure to exit 1 with no output.

## Consequences

Wrapping `linearize.sh` in `atomic` would add nothing and would hide its own refusal. Pointing `normalize` at the raw file on failure would silently count abandoned branches as work.
