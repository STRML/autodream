# tests-lib-store: "did the store change" compares two full snapshots, and a store that vanishes is a failure

Status: accepted · Date: 2026-11-22 · Code: `tests/lib-store-unchanged.sh` (`store_snapshot`, `store_unchanged`, `store_verdict`), used by `tests/l1-confine.sh` and `tests/l1-confine-real.sh`

## Context

A check that lists files newer than a marker sees none of three changes: a file that is gone, a file that is new in a way the marker misses, and a file reached only through a symlinked directory below the root. "Changed" has to include all three.

A store the snapshot cannot read must not read as unchanged either. A store that disappears during the call is the loudest change there is, not a case to skip.

## Decision

- `store_snapshot <dir> <out>` writes one `size mtime_ns path` line per regular file, following symlinks at every level, sorted. It returns 0 (written), 1 (could not scan) or 2 (no such directory) and prints a reason on 1 and 2.
- `store_unchanged <before> <after>` is a diff of two snapshots: 0 when identical, 1 with the differences printed.
- `store_verdict` holds the whole decision in one place. A store absent before the call is a skip (2). One that could not be scanned before is a failure (1). One that was there before and is gone, unreadable or different after is a failure.
- "Cannot tell" from `path_state` and an unreadable directory both return 1. They are never a pass.

## Consequences

Do not replace the snapshot with `find -newer`. A new outcome for the real check goes into `store_verdict`, not into a caller.
