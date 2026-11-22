# tests-run-all: an enumeration shortfall costs a root, never the night, and is never reported as an empty night

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_failing_enumerator_aborts_the_run`, `test_one_failed_root_does_not_kill_the_night`, `test_all_excluded_corpus_says_so`, `test_partial_enumeration_keeps_what_it_read`, `test_all_roots_unavailable_fails`, `test_fresh_host_with_no_store_is_not_a_failure`)

## Context

`find` exits 1 for any unreadable directory in the walk, with or without matches (verified on the dev host: an unreadable sibling gives exit 1 both ways, exit 0 only without one). A secondary root legitimately matches nothing on a given date, so treating "nonzero exit, no output" as fatal let one permission-denied directory under a quiet secondary root kill a night on which the primary had a full corpus. It died invisibly: `run()` returned before `notify.sh`, and no findings JSONs existed for `unassembled_dates()`.

On a single-root host, "enumerator exited nonzero and returned nothing" is also the shape of a quiet date plus a transient find error.

`COUNT=0` has three causes that once read identically: no files, every file an autodream worker transcript, or every file an empty shell. The stub said "No session files were modified" for all three.

`scan_roots` once warned and skipped a non-directory root, so a broken `SESSION_ROOTS` produced `RAW=0` with every shortfall counter at 0. And `probe_roots` falls back to `$HOME/.claude/projects` when discovery finds nothing; counting that fallback as a configured root made a never-used machine fail.

## Decision

- A failed or partial enumeration contributes what it read, the run completes, `roots_failed` / `roots_partially_enumerated` count it, and the stub says the store was not fully read.
- Zero sessions from a non-empty corpus is explained in the stub and run-stats (`self_sessions_excluded`, `sessions_found_raw`).
- The run fails only when every configured root is unreachable, and only for roots someone asked for, not the `$HOME` fallback.
- `test_partial_enumeration_keeps_what_it_read` exists because the all-failing adapter would pass under the old fatal-on-any-nonzero code. Only an adapter that prints a path and then exits nonzero, which is find's real shape, tells the regression from the fix.

## Consequences

Keep both fixtures: removing the partial one leaves a test that cannot fail on the regression. The name `test_failing_enumerator_aborts_the_run` is historical; the test asserts the run completes.
