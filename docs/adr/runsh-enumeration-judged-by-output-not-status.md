# runsh: root enumeration is judged by what it returned, per root, and never by its exit status alone

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`scan_roots`, `enumerate_for`)

## Context

BSD `find` exits 1 when a single subdirectory is unreadable or vanishes mid-walk, and still prints every other match. Verified on this host: 3 files, one locked directory, exit 1, two paths printed. It exits 1 for any unreadable subdirectory anywhere in the walk, with or without matches; without one, exit 0. Treating a nonzero status as fatal threw away a usable corpus and produced no report on a night that previously produced a full one, which is worse than the silent zero the check exists to catch.

Multi-root scanning is the tool's premise: a secondary root (`~/.claude-nous/projects`, `~/.claude-sigint/projects`) legitimately matches nothing on a given date. One permission-denied directory under a quiet secondary root used to kill a night on which the primary root had a full corpus, and kill it invisibly, because `run()` returned 1 before `notify.sh` ran and no findings JSONs existed for `unassembled_dates()` to notice.

`enumerate_for` once ended in a literal `return 0`, which silently defeated the caller's status check: enumeration was staged to a file and the exit code examined, and the wrapper handed it a success every time. The suite passed 306 assertions over that, because none ran an adapter whose enumerate fails. `tests/run-all.sh` has one now.

## Decision

Each root's NUL-delimited output is staged to `$FINDINGS_DIR/.enum.XXXXXX` and the status is read after. Nonzero status with output is a partial walk: `PARTIAL_ROOTS` counts it, the log says the corpus is possibly incomplete, and the run goes on. Nonzero status with no output counts `ROOTS_FAILED`, logs that the root contributes no sessions and moves to the next root; a failed root is never fatal on its own. The comment in the code said an all-roots-failed case after the loop still refuses to report; that comment is stale. What the code does is the run-level fatal `all N configured session root(s) are unavailable`, which fires only when every configured root was not a directory (`ROOTS_SCANNED` stays 0). When every root was reached and failed to enumerate, the run completes, and the zero-session stub says the store was not fully read (`roots_failed` and `roots_unavailable` in run-stats) instead of claiming no session files were modified. `enumerate_for` returns the adapter's own status (`return $?`), never a constant. The staging file is removed on every exit, including the fatal one when a session list write fails: under `AUTODREAM_FORCE=1` the findings dir is reused across reruns, so repeated failures would pile `.enum.*` files into the directory the aggregator globs.

## Consequences

A shrinking corpus must stay visible in the log and in the `PARTIAL_ROOTS` / `ROOTS_FAILED` counters; do not fold either into "quiet night". Do not make a lone nonzero status fatal again (`test_one_failed_root_does_not_kill_the_night`, `test_partial_enumeration_keeps_what_it_read` and `test_failing_enumerator_aborts_the_run`, whose name predates the change and which now asserts the run completes, pin this), and do not replace `return $?` in `enumerate_for` with a success. Remote-sync's `remote_short_labels` also reads these counters (a failed root cannot be told from a mirror), see CLAUDE.md, "Remote hosts".
