# Redesign: the run lock's handling of a directory it did not make

Branch `fix/run-lock-liveness`, PR https://github.com/STRML/autodream/pull/250, issue https://github.com/STRML/autodream/issues/242. Rounds 1 to 4 of the codex gate blocked. This replaces the part of the design that kept blocking. The rest (flock held by a holder process, the owner is the forking shell, release from the recorded owner) passed review and is unchanged.

## What blocked, by round

| Round | Finding | Group |
|---|---|---|
| 1 | A lock held by another user read as an acquisition error | A |
| 1 | Failed pid or start write reported as a taken lock | A |
| 1 | The pin sweep read an unprobeable missing flock file as idle | A |
| 1 | Existing runs and upgraded runs use different locks | B |
| 2 | An older runner between its `mkdir` and its pid write is taken over | B |
| 2 | The holder watched the top-level shell, not the shell that acquired | C |
| 3 | An older runner creates its directory after the check and before the move | B |
| 4 | The move-aside makes the older runner's pid write fail, then the restored empty directory is reclaimed a minute later | B |

Groups A and C were fixed by class and did not come back. Group B came back in rounds 1 to 4 and is the subject of this plan.

## The mistake behind group B

Each fix tried to make a new flock runner and an older mkdir runner exclude each other at the instant the older one is acquiring. Every version added a step (a young-directory check, a rename aside, a judgment on the renamed copy, a put-back) and every step opened a window of its own, because the new runner was moving a directory that an older runner might still be writing into. The round 4 finding is the clearest: the fix for round 3 is what made the older runner's writes fail.

The requirement was never that. Upgrading replaces the code for every process that starts afterwards, because `install.sh` links one working tree. An older runner can therefore only be one that was already running when the code changed. Its acquire finished within milliseconds of its start, minutes or hours ago: its directory is complete, with a pid that is alive. A new process cannot meet an older runner that is mid-acquire, because no process starts on the old code once the new code is linked.

## Design change

The new runner never moves, renames or removes a lock directory it did not create.

1. Directory absent: a plain `mkdir` (atomic). If it fails because the directory now exists, the lock reads as held.
2. Directory present and names a live process with the recorded start (an older runner that is still running): held.
3. Directory present and stale (a recorded pid that is dead, or no usable pid and the directory is over a minute old): keep the directory, overwrite `pid` and `start` inside it. If either write fails, report "cannot lock" and leave the directory as it was.
4. Directory present, no usable pid, under a minute old: held, as now. It costs nothing, and it covers a directory another new runner is writing.

Removed: the rename aside, the judgment on the renamed copy, the atomic put-back, and the `.stale.*` leftovers.

What this does not cover, stated so it is not read as covered: an older-code process that starts after the new code is linked, for example another checkout of the repo sharing one `$AUTODREAM_DIR`. Two such processes would reclaim one stale directory at the same moment, and the new runner's in-place write cannot be made exclusive against an older runner's rename, since the older runner takes no flock. Closing that needs the older code retired, not a step in the new code.

## Changes after review

A read-only review of this plan found three things, folded in:

- The claim above that an older runner's acquire takes milliseconds is true only for the common path. The older code's reclaim loop sleeps and retries, so a run that was in that loop when the code was linked can be inside it for seconds. That is one more uncovered case, listed below, and it happens once, at the upgrade.
- A failed in-place write must not release the flock. The caller treats "cannot lock" as "run without the directory", so releasing the flock as well would leave the run with no lock at all. The holder now stays, the flock stays held, and only the report to older runners and the dashboard is missing.
- `start` is written before `pid`, so a live new owner never reads as dead between the two writes.

## Failure matrix

| State | Result |
|---|---|
| No directory, no flock holder | `mkdir`, write pid and start, run |
| No directory, an older runner creates one first | `mkdir` fails, held |
| Directory, live older runner with a matching start | held, nothing touched |
| Directory, live older runner, `ps` cannot report its start | held (a start `ps` cannot report counts as a match) |
| Directory, dead recorded pid | pid and start overwritten in place, run |
| Directory, no pid, over a minute old | pid and start written in place, run |
| Directory, no pid, under a minute old | held |
| Directory, stale, start or pid write fails | cannot lock, the directory left as found, the flock still held, the run goes ahead with a WARNING |
| Lock path is a regular file or a symlink | the writes under it fail: cannot lock, flock still held, WARNING |
| A live older remote-sync holder | held at once, no wait (an older holder is waited for by older code only): the host reads `skipped_locked` once, at the upgrade |
| Another new runner holds the flock | held before the directory is looked at |
| Older runner already running at the upgrade | its complete directory reads as held until it ends |
| Older-code process starts after the upgrade, or is inside its reclaim loop at the link | not covered (see above) |

## Round 5 findings, by class

Round 5 was the first full review of the redesign. It held the design and found six places where the code did not do what the matrix above says:

| Finding | Class | Fix |
|---|---|---|
| Release deleted a lock path the run had not made (a file, or a stale directory with contents) | Deleting unowned state | Release removes only its own `pid` and `start` and then `rmdir`s; a lock that returned cannot-lock is released without touching the path |
| A symlink at the lock path was written through | Following an unvalidated path | A symlink or a regular file is cannot-lock before any write |
| A failed `pid` write left `start` already replaced | Partial update | Every file is checked writable before the first write |
| `kill` EPERM plus a failing `ps` read a live older holder as dead | An indeterminate probe read as death | Liveness is `os.kill(pid, 0)` in python: only "no such process" is dead |
| The pin sweep read an untraversable locks directory as idle | Fail-open probe | The sweep opens the flock file and reads anything but "no such file" as held |
| A pid of 0 read as a live process group | Invalid pid accepted | A pid that is 0, empty, non-numeric or has a leading zero is no pid |

## Tests

Red first against the current branch head, then green:

1. `test_run_lock_a_stale_directory_is_taken_over_in_place`: a dead pid in the directory, `mv` shadowed to print `MOVED`; after acquire the same directory (same inode) names this process and nothing was moved or set aside.
2. `test_run_lock_a_stale_directory_that_cannot_be_written_is_left_as_found`: a read-only `start` file in a stale directory; acquire returns 3 and the old pid is still there.
3. `test_run_lock_a_young_pidless_directory_is_never_moved`: `mv` and `rm` shadowed; acquire over a young pid-less directory returns held and the directory is still there.

Removed: `test_run_lock_an_older_runner_that_creates_the_directory_after_the_check_keeps_it`, which pinned the put-back that no longer exists.
