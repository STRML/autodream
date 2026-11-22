# tests-run-all: collision assertions check that no session reaches the shared artifact, and count paths, not lines

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_forced_hash_collision_drops_both`, `test_three_way_collision_counts_paths_not_lines`, `test_mixed_collision_run_attributes_correctly`, `test_unwritable_collision_index_fails_closed`, `test_broken_shasum_never_collapses_sessions`)

## Context

The collision design requires that neither session reaches the artifact they would have shared. Counters alone can pass while the drop is only bookkeeping, and a log line saying "skipping both" can pass while skipping neither.

## Decision

- The drop test asserts that the artifact and its stats sidecar are never written, and that both paths are gone from `sessions.txt.raw` and `sessions-source.txt`. Those file checks catch a branch that logs "skipping both" while skipping neither. The counters alone would not.
- Three colliding paths count as three drops. The earlier path is re-appended for every later collision, so the drop file reads A,B,A,C for three paths, and counting lines reported four.
- A mixed run (two collide, one survives) is its own test. The all-collide fixtures take the zero-session path, which emits a reduced key set, so only a run that triages a session reaches the normal run-stats writer. The mixed run proves that writer carries `sessions_dropped_to_collision` and `sidecar_stale_rows`, and that deliberate drops stay out of `self_sessions_excluded` and `sessions_dropped_after_failures`.
- The unwritable-index test (`chmod 500` on the findings dir) asserts the invariant: exit 1, `FATAL` in the log, no report. It does not name which guard fires, because an unwritable findings dir is caught one layer earlier, when enumeration cannot be staged. The bookkeeping guard covers the narrower case of a writable dir with unwritable files. If the index could not be written, every path would look unseen, no collision would be detected, and both sessions would reach dispatch onto one artifact.
- The broken-`shasum` test (the tool exists and exits 3) asserts no `.json` under an empty hash and at most one findings record per session. Preflight only checks that `shasum` exists, and an empty hash sends every session in the night to `.json`: the same silent overwrite, reached from the other direction.

## Consequences

If the unwritable-index test names one guard, it fails whenever the earlier enumeration guard changes. Dropping the file assertions from the drop test leaves a counter-only test.
