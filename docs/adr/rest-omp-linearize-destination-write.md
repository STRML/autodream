# rest: the linearizer refuses a directory destination and checks it again after the move

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/linearize.sh`

## Context

A directory at the destination makes `mv` move the temp file inside it and report success, with nothing written where the caller looks. The same happens if a directory appears at `$dst` between a guard and the `mv`: it takes the temp inside and still returns 0. The claude adapter hit the same shape, see `bin-a-adapter-claude-atomic-destination-write`.

## Decision

The script refuses a directory destination up front (exit 1) and writes through a temp file beside the destination. After `mv` it checks that `$dst` is a regular file. If it is not, it removes the temp that landed inside and exits 3.

## Consequences

A check-then-act guard alone is not enough, which is why the post-condition stays. The temp is created beside `$dst`, never in `$TMPDIR`, so the move is a rename and not a cross-filesystem copy.
