# tests: run-all-failure-visibility-tests: run-all: tests that keep failures visible

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_failing_enumerator_aborts_the_run`, `test_one_failed_root_does_not_kill_the_night`, `test_all_excluded_corpus_says_so`, `test_partial_enumeration_keeps_what_it_read`, `test_all_roots_unavailable_fails`, `test_fresh_host_with_no_store_is_not_a_failure`), `tests/run-all.sh` (`test_fatal_does_not_clobber_a_complete_date`, `test_no_usable_adapter_leaves_a_trace`), `tests/run-all.sh` (`test_forced_hash_collision_drops_both`, `test_three_way_collision_counts_paths_not_lines`, `test_mixed_collision_run_attributes_correctly`, `test_unwritable_collision_index_fails_closed`, `test_broken_shasum_never_collapses_sessions`), `tests/run-all.sh` (`collision_sandbox`, `run_dream_collision`, `test_collision_worklist_failure_aborts`, `test_collision_membership_probe_failure_aborts`, `test_persistent_sidecar_failure_counts_rows_not_attempts`)

## an enumeration shortfall costs a root, never the night, and is never reported as an empty night

### Context

`test_failing_enumerator_aborts_the_run` exists because its absence once let 306 assertions pass over a broken fix: the runner staged enumeration to a file and checked its exit status, but the `enumerate_for` wrapper ended in a literal `return 0`, so the check always read success, and no test drove an adapter whose enumerate fails.

`find` exits 1 for any unreadable directory in the walk, with or without matches (verified on the dev host: an unreadable sibling gives exit 1 both ways, exit 0 only without one). A secondary root legitimately matches nothing on a given date, so treating "nonzero exit, no output" as fatal let one permission-denied directory under a quiet secondary root kill a night on which the primary had a full corpus. It died invisibly: `run()` returned before `notify.sh`, and no findings JSONs existed for `unassembled_dates()`.

On a single-root host, "enumerator exited nonzero and returned nothing" is also the shape of a quiet date plus a transient find error.

`COUNT=0` has three causes that once read identically: no files, every file an autodream worker transcript, or every file an empty shell. The stub said "No session files were modified" for all three.

`scan_roots` once warned and skipped a non-directory root, so a broken `SESSION_ROOTS` produced `RAW=0` with every shortfall counter at 0. And `probe_roots` falls back to `$HOME/.claude/projects` when discovery finds nothing; counting that fallback as a configured root made a never-used machine fail.

### Decision

- A failed or partial enumeration contributes what it read, the run completes, `roots_failed` / `roots_partially_enumerated` count it, and the stub says the store was not fully read.
- Zero sessions from a non-empty corpus is explained in the stub and run-stats (`self_sessions_excluded`, `sessions_found_raw`).
- The run fails only when every configured root is unreachable, and only for roots someone asked for, not the `$HOME` fallback.
- `test_partial_enumeration_keeps_what_it_read` exists because the all-failing adapter would pass under the old fatal-on-any-nonzero code. Only an adapter that prints a path and then exits nonzero, which is find's real shape, tells the regression from the fix.

### Consequences

Keep both fixtures: removing the partial one leaves a test that cannot fail on the regression. The name `test_failing_enumerator_aborts_the_run` is historical; the test asserts the run completes.

## a fatal still posts a banner and leaves a marker, including under --force and a persistent cause

### Context

`fatal_exit` truncates `run-stats.txt` and posts a FAILED banner. `AUTODREAM_FORCE` bypasses the idempotency guard by design (`autodream-now.sh <date> --force`), so a fatal there would overwrite a complete date's telemetry with a five-line stub. An earlier version of the test asserted the banner must not fire and passed, which is how the guard came to suppress it: the run-stats write is what must not clobber a complete date, and the banner was taken down with it by sitting inside the same `return`. That branch runs detached under launchd, where a silent death leaves the operator polling `dreams/<date>.md`, finding the old report and reading the failed rebuild as a success.

Losing the exec bit on `adapters/claude/adapter.sh` (tarball copy, restrictive umask, `core.fileMode=false`) makes `_adapter_ok` accept nothing and `run()` return about 600 lines before `notify.sh`, with no findings JSON and no run-stats. The cause repeats every night, so no later run ever succeeds to read a marker and report it.

### Decision

- Under `--force` a fatal leaves run-stats untouched but still calls `notify.sh --failure`, saying the standing report is the old one.
- A total adapter outage writes a `fatal:` marker, calls the banner (the surface that works tonight), and the next night's run names the dead date.
- The tests install a `notify.sh` stub that records its arguments, because `fatal_exit` gates on `-x` and without one the notification step is skipped and unobservable.
- The banner is matched with `'[-][-]failure'`. `assert_grep` passes the pattern straight to grep, so a literal `--failure` reads as end-of-options and an inserted `--` becomes the pattern, which is what the first version did.

### Consequences

Do not move the banner back inside the run-stats guard. CLAUDE.md, "Nobody was told (`unassembled_dates`)", has the related unassembled-date surface.

## collision assertions check that no session reaches the shared artifact, and count paths, not lines

### Context

The collision design requires that neither session reaches the artifact they would have shared. Counters alone can pass while the drop is only bookkeeping, and a log line saying "skipping both" can pass while skipping neither.

### Decision

- The drop test asserts that the artifact and its stats sidecar are never written, and that both paths are gone from `sessions.txt.raw` and `sessions-source.txt`. Those file checks catch a branch that logs "skipping both" while skipping neither. The counters alone would not.
- Three colliding paths count as three drops. The earlier path is re-appended for every later collision, so the drop file reads A,B,A,C for three paths, and counting lines reported four.
- A mixed run (two collide, one survives) is its own test. The all-collide fixtures take the zero-session path, which emits a reduced key set, so only a run that triages a session reaches the normal run-stats writer. The mixed run proves that writer carries `sessions_dropped_to_collision` and `sidecar_stale_rows`, and that deliberate drops stay out of `self_sessions_excluded` and `sessions_dropped_after_failures`.
- The unwritable-index test (`chmod 500` on the findings dir) asserts the invariant: exit 1, `FATAL` in the log, no report. It does not name which guard fires, because an unwritable findings dir is caught one layer earlier, when enumeration cannot be staged. The bookkeeping guard covers the narrower case of a writable dir with unwritable files. If the index could not be written, every path would look unseen, no collision would be detected, and both sessions would reach dispatch onto one artifact.
- The broken-`shasum` test (the tool exists and exits 3) asserts no `.json` under an empty hash and at most one findings record per session. Preflight only checks that `shasum` exists, and an empty hash sends every session in the night to `.json`: the same silent overwrite, reached from the other direction.

### Consequences

If the unwritable-index test names one guard, it fails whenever the earlier enumeration guard changes. Dropping the file assertions from the drop test leaves a counter-only test.

## collision tests stub `shasum` first on PATH and break one `grep` call at a time

### Context

A natural 48-bit hash collision cannot be produced in a test, so the hash is stubbed. Without a forced collision, every assertion in this family passes whether or not the collision handling works. That is what happened while the branch was patched across four review rounds. `run.sh` also appends its own fixed list to the caller's `PATH`, so a stub that is not first on `PATH` is never seen. The first version put the stub in a temp dir behind the system `shasum` and silently measured nothing.

### Decision

- `collision_sandbox` puts a constant-hash `shasum` in `$HOME/.local/bin`, and `run_dream_collision` puts that directory first on `PATH`.
- Each failure test installs a `grep` wrapper in the same directory. It exits 2 on one argv shape and execs `/usr/bin/grep` otherwise. The three call sites are separate: `-vxF` is the worklist rewrite, `-qxF` is the membership probe, and `-v` followed by a `^...` pattern is the sidecar rewrite. Failing one while the others work shows which guard fails closed.
- The membership-probe test exists because an earlier fixture failed only the `-vxF` rewrite. Reverting the probe to `|| continue` then left the suite green: a fail-open on the way into a check that fails closed on the way out.
- The sidecar-rewrite test counts rows, not attempts. One provenance row stays stale, and counting attempts reported 3 for it: one at detection plus the same hash seen once per dropped path.

### Consequences

A new `grep` flag used in the collision path needs its own shim case. A stub left behind the system tool on `PATH` makes these tests pass without testing anything.
