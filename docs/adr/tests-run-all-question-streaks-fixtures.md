# tests-run-all: the question-streaks tests use fixtures shaped to hit the specific failure, not the obvious one

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`streak_rows`, `test_question_streaks_state_lives_with_the_install`, `test_question_streaks`, `test_question_streaks_reruns_and_mismatch`, `test_question_streaks_lock_is_a_kernel_flock`)

## Context

CLAUDE.md "Open questions that never get answered" has the feature and its review history. Several fixtures only have power because of a detail that looks arbitrary.

- The empty-night run sets `AUTODREAM_DIR` explicitly. `run.sh` takes its install dir from `AUTODREAM_DIR` (default `~/.claude/autodream`), not from its own location. A value that comes from that default is not exported on the early path, which is why both call sites pass it to the helper.
- `AUTODREAM_QUESTION_LOCK_WAIT=1`: the default is 15 one-second tries, and two cases each held a lock on purpose for all of them. That was 32 seconds of the suite, in a suite where one test takes 46.
- The unreadable-state case uses `chmod 200` (write-only), so a wrongly written update would land and the `cmp` would catch it.
- A streak key is hex, so it can be all digits. `awk` compares two numeric-looking strings as numbers: `clear 89709551468` matched the row `089709551468` (Codex review of omp-autodream 5f7ddaa). `awk -v` also decodes backslash escapes: `\060...` became `0...` and matched a real key (omp-autodream b67c2f1).
- `streak_rows` counts with `wc -l`, not `grep -c . || echo 0`: `grep -c` prints `0` and exits 1 on no match, so the fallback also fires and the value is `0\n0`. That trap is in CLAUDE.md and still caught this test on its first run.
- The bad-`python3` loop tries exit codes 1, 7, 11 and 15, which include numbers the lock code once used for a holder.

## Decision

Each fixture keeps the shape above: an explicit `AUTODREAM_DIR`, a one-second lock wait, a write-only state file, a digits-only key with a leading zero, an escaped key, `wc -l` for row counts, and the extra `python3` exit codes.

## Consequences

Replacing the leading-zero key with an ordinary hex key, or the escaped key with a plain one, leaves the assertions passing against an `awk` comparison that is wrong. Raising the lock wait back toward the default adds about 30 seconds to the suite.
