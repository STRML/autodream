# rest: `tag` takes a kernel flock through a python3 wrapper that re-runs the script

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-focus.sh` (`LOCKER_PY`, `hold_lock_and_rerun`, `cmd_last`'s hand-off to `tag`)

## Context

Three harnesses (Claude mod, OMP, Codex) can tag at once, and the Claude mod now takes the lock too by running this script rather than writing the file. The lock used to be a directory holding its owner's pid, with a `.reclaim` claim for waiters. Every version of that had a window: an age rule let a suspended writer's lock be taken, an empty pid file read as stale, two waiters could both remove a stale claim. A shell cannot make "judge the holder gone, then take its lock" atomic, which is the same lesson as `question-streaks.sh` (CLAUDE.md, "Open questions that never get answered", and "The focus mod").

## Decision

- `tag` re-runs itself (`AUTODREAM_FOCUS_LOCKED=1`) under a small python3 program that opens `$TAGS_FILE.lock`, takes `flock(2)` `LOCK_EX|LOCK_NB`, marks the descriptor inheritable and `execv`s the script, so the lock is held for the script's whole life.
- The kernel owns the lock: it is dropped when that process exits or dies however it ends. There is no stale lock to detect, so no age rule, no owner pid and no reclaim claim, and a writer suspended for any length of time still holds it.
- A waiter polls without blocking every 50 ms and gives up after five seconds, saying `another tag is being written and did not finish; nothing was changed`.
- Without python3 the script exits 3 and says so rather than writing unlocked.
- A directory left at the lock path by the earlier build is cleared (its `pid` file removed, then `rmdir`), because it cannot be opened as a file. A directory holding anything else is somebody else's and is refused, not deleted.
- `last` only reads session files. It does not hold the lock: it runs `tag` as its own invocation of the script, which takes it.

## Consequences

`python3` is already needed by the web dashboard, so the dependency costs nothing new. Do not reintroduce a file or directory lock that a script judges. The tests (`test_focus_cli_*` in `tests/run-all.sh`) hold a flock from python to check both that a holder keeps it however long and that a waiter changes nothing.
