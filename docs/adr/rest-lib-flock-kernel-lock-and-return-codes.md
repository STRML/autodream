# rest: lib-flock takes a kernel flock on fd 9 through python3, and each failure has its own return code

Status: accepted · Date: 2026-11-21 · Code: `bin/lib-flock.sh` (`flock_acquire`, `flock_release`)

## Context

`question-streaks.sh` and `threads.sh` serialize a read-modify-write on a state file. The mkdir lock they used was reclaimed by contenders that judged its holder gone, and a shell cannot make "judge, then take away" atomic: four gate rounds on #192 each found another interleaving (`docs/plans/2026-11-21-fix_question-streaks-lock-owner-redesign.md`). The story is in CLAUDE.md, "Open questions that never get answered", and `bin-b-question-streaks-flock-skips-not-blocks`.

## Decision

One `flock(2)` for both scripts. Source `lib-flock.sh`, then `flock_acquire <lock file> <seconds> [<legacy lock directory>]` and `flock_release`. The shell opens the lock file on fd 9 and a short `python3` call takes `LOCK_EX|LOCK_NB` on that open file description, retrying until the deadline. The kernel releases the lock when the description is closed, which happens when the process ends however it ends, so there is nothing to judge, reclaim, age out or put back. `FLOCK_HELD` records the held file.

Return codes of `flock_acquire`:

- 0 taken
- 1 held by another process for the whole wait
- 2 cannot lock: the file cannot be opened, or the lock call failed for a reason other than contention
- 3 `python3` is not on PATH
- 4 this process already holds a lock (a second `exec 9>>` would close the first description and drop the first lock, so a double acquire is refused rather than allowed to unlock the outer one)
- 5 an older version's lock directory is still live (see `rest-lib-flock-legacy-dir-and-inherited-fd`)

Two guards sit in front of the lock call:

- Opening a FIFO for writing blocks until a reader appears, before any deadline exists, so a path that exists and is not a regular file is return 2. Only a regular file (or none yet) is a lock file.
- The answer from python is a word on stdout (`flock-ok`, `flock-held`, `flock-legacy`, `flock-unknown`), not an exit code. A `python3` that is broken, or a stand-in that exits with a number this file uses, must read as cannot-lock (2), never as a live holder (1 or 5); an empty or unknown word is 2.

## Consequences

`python3` is already needed by the web dashboard; without it the caller gets 3 and says so. Change the lock protocol here for both scripts together (`bin-b-threads-state-flock`). Callers decide what each code means for them (`question-streaks.sh` skips the update; see its ADR).
