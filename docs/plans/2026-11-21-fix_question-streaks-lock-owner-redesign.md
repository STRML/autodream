# Redesign: question-streaks takes an flock, not a reclaimable mkdir lock (#192)

Replace the mkdir lock in `question-streaks.sh` with an `flock(2)`, the mechanism `threads.sh` already uses. This is the redesign plan for branch `fix/question-streaks-lock-owner` (PR https://github.com/STRML/autodream/pull/238). The review gate used four rounds and the design still blocks (exit 6).

## What the four rounds found, by the mistake behind it

Every finding has one root: a contender may take the lock away from its holder when it judges the holder gone, and a shell cannot make "judge, then take away" atomic. Each fix closed one interleaving, and the next round found the next.

| Round | Finding | Window |
|---|---|---|
| 1 | a failed `ps` or `stat` read as dead or old | the judgment itself is unavailable |
| 1 | a regular file at the lock path is deleted | the reclaimer moves whatever is at the path |
| 1, 2, 3 | restoring a displaced lock nests it, overwrites a pid, or writes a start time through a taken path | judge, move aside, find out it was live, put back |
| 4 | two reclaimers remove each other's gate | the gate has the same problem one level up |
| 4 | a reused pid is never reclaimed | a regression from the previous fix: it tested existence, not the start time |
| 4 | a zero-second wait still sleeps | the deadline is checked after a blocking acquisition |

Each fix moved the judgment, and none removed it. The class ends when nothing is judged: the kernel holds the lock and drops it when the holder dies.

## The design change

`question-streaks.sh` takes an `flock(2)` on `$STATE.flock`. The shell opens the file on fd 9 and a short `python3` call takes `LOCK_EX|LOCK_NB` on that open file description (the pattern in `threads_acquire_lock`). The lock lives as long as the description does, so it goes with the process however the process ends.

```
before   mkdir lock -> contender judges the holder dead (pid, start, age) -> moves it aside -> restore, gate, ...
after    open $STATE.flock on fd 9 -> flock(LOCK_EX|LOCK_NB), retry until the deadline -> held until fd 9 closes or the process ends
```

What this removes:

| Finding class | Why it cannot happen |
|---|---|
| an unavailable `ps` or `stat` read as proof | nothing is read: no pid, no start time, no age |
| a file at the lock path is deleted | nothing is ever removed or moved; a path that cannot be opened fails the acquire, loudly |
| restore, gate, nested directories | there is no reclaim, so nothing is put back and there is no second reclaimer |
| a reused pid is never reclaimed | no pid is recorded |
| a zero-second wait sleeps | the wait is one deadline loop in python, checked every 200 ms |
| A stalls past 120 s, B takes over, A's release removes B's lock | B never takes over, and A releases by closing its own descriptor, which cannot touch B |

Scope, and what this redesign leaves out:

- `bin/run.sh` keeps its mkdir lock exactly as on main (the run lock and the remote sync lock). The web dashboard reads its `pid` and `start` files (`bin/autodream_web_data.py`, Progress), and the run-lock and remote-sync tests simulate a holder by writing a pid file. Moving it is a separate change with its own tests, tracked in a new issue. `bin/lib-lock.sh`, `tests/lib-lock.sh` and the `run.sh` edits leave this PR, and the lock helpers stay where the `remote` worker's block expects them.
- `threads.sh` moves onto the new `bin/lib-flock.sh` in this PR: `threads_acquire_lock` and `threads_release_lock` become wrappers over it, with the wait as a parameter and the messages `tests/threads-state.sh` pins unchanged. Two copies of the flock code would be the drift the issue asked to end. (The plan review found that the legacy-directory check differs only in its wait count, not in kind.)
- The issue comment asked for one lock library for all three scripts. This PR delivers it for two of the three. `run.sh` waits for the reason above, and the three round-1 defects that stay in its lock (a failed `kill -0` read as dead, a failed `ps` read as stale, a restore that nests) are filed as their own issue, linked from the PR body.

## Failure matrix

| State | What acquire does | How it can fail | What the caller is told |
|---|---|---|---|
| nobody holds the lock | takes it at once | python3 is missing, or the lock call fails for a reason other than contention (a filesystem without flock, a broken python) | three distinct outcomes: held (exit 1 of the helper), cannot lock (2), no python3 (3). `update` skips with the named reason and exit 0, and for cannot lock and no python3 also posts a banner, because those are permanent and a frozen board would otherwise look like a quiet week. `clear` exits 1 with the same reason |
| a live holder, even one stalled for hours | retries every 200 ms until `AUTODREAM_QUESTION_LOCK_WAIT` (default 15 s), then gives up | none: the holder keeps it | `update`: "another run holds $LOCK; skipping this update", exit 0. `clear`: "FAILED to clear: another run holds $LOCK", exit 1 (both messages unchanged) |
| the holder was killed (`kill -9`, power loss) | the kernel has dropped the lock, so acquire succeeds at once with no age wait | none | none |
| `update` and `clear` race | one takes the lock, the other waits and then skips or fails loudly | none | as the two rows above |
| the lock path cannot be opened (a directory, a read-only parent) | fails without waiting | the open fails | `update`: "cannot open lock at $LOCK", exit 0. `clear`: exit 1 |
| an older version's `$STATE.lock` directory exists | the one remaining age judgment, made inside the same deadline loop as the flock: a directory younger than 300 s counts as a live older writer, a directory whose age cannot be read counts as live, and an older one is ignored and never removed | an old writer that takes its directory after the check runs beside the new one, and an old holder stalled past 300 s is ignored; both are bounded by the upgrade window and named here | as "a live holder" |
| the same process takes the lock twice | `flock_acquire` refuses when this process already holds a lock (a second `exec 9>>` would close the first description and drop the first lock) | a bug in a caller | an error naming the double acquire, no waiting |
| fd 9 is inherited by a child that outlives the holder | the lock would outlive the holder | the one child that can run long under the lock is `osascript` (the banner) | the banner runs with fd 9 closed (`9>&-`), and a test kills the script while it is stalled in an `osascript` shim and checks the next update succeeds |
| the holder is killed between taking the lock and writing state | the state file is replaced by one rename, so it is whole or unchanged | none | none |

`write_state` no longer re-checks ownership. The lock cannot be lost while the process lives, so the `lock_owned` guard and its "lost the lock" message go with the mkdir lock.

## Tests (each row above, red first)

All in `tests/run-all.sh` as `test_question_streaks_*`, driving the real script:

Every test that invokes the script uses `/bin/bash`, the interpreter launchd uses (bash 3.2).

1. A holder process takes the same flock and sleeps. `update` exits 0 with "another run holds" and the state is unchanged. `clear` exits 1 with the unchanged message. The lock file is aged with `touch`, so a reclaim-by-age implementation fails this.
2. The script is the holder: the `mktemp` PATH shim already in the suite stalls `update` inside its critical section. A non-blocking flock probe from outside fails, `clear all` exits 1, and the state is unchanged. This is the test that fails if the acquire sits in a `$(...)` or the helper opens its own descriptor.
3. `kill -9` a holder. The next `update` succeeds at once, in under 3 s. The holder is a single process, not a shell with a `sleep` child, which would keep the lock after the kill.
4. `kill -9` the script while an `osascript` shim stalls the banner (escalation at 1, dry run off). The next `update` succeeds.
5. A directory at `$STATE.flock` fails the acquire without waiting: `update` exits 0 with "cannot open lock" and the directory is untouched, `clear` exits 1.
6. A legacy `$STATE.lock` directory younger than 300 s blocks. An older one is ignored and left in place. With `AUTODREAM_QUESTION_LOCK_WAIT=0` a young one returns in under 2 s.
7. `AUTODREAM_QUESTION_LOCK_WAIT=0` against a live flock holder returns in under 2 s with the skip message and an unchanged state.
8. No python3 on PATH: `update` skips with the "python3 is required" reason and a banner, `clear` exits 1. A python3 shim that exits non-zero for a reason other than contention reads as "cannot lock", not as "held".
9. A second `flock_acquire` in the same process fails at once and does not drop the first lock.
10. The existing `test_question_streaks*` tests stay, with their hold fixtures now holding the flock, and `tests/threads-state.sh` stays green with its pinned messages after `threads.sh` moves onto the lib.

`lib-flock.sh` has no caller besides `question-streaks.sh`, so its unit coverage is the same behavior driven through that script. A separate suite would test the same thing twice.

## Rebuild steps

1. Restore `bin/run.sh` to `origin/main`, drop the lib-lock link from `install.sh`, delete `bin/lib-lock.sh` and `tests/lib-lock.sh`, remove `lib-lock` from the suite registry and its install assertion in `tests/run-all.sh`, and replace the mkdir-lock tests and the `lock_owned` message in `question-streaks.sh`.
2. Add `bin/lib-flock.sh` (`flock_acquire <file> <seconds>`, `flock_release`, the legacy check inside the deadline loop, distinct return codes) and link it in `install.sh`. `question-streaks.sh` finds it the way it finds `report-format.sh`: a missing lib is loud, and `update` still exits 0. `threads.sh` calls it through its two existing functions.
3. Run the banner with fd 9 closed.
4. Port the tests above.
5. Update CLAUDE.md, the README map and the codemap: flock for `question-streaks.sh`, the run lock unchanged and why.
6. File the run.sh follow-up issue and link it. Re-run the gate with `--plan` (round 5, a full review against this plan).
