# Run lock and remote sync lock: flock decides, files only report (#242)

## Problem

`acquire_lock`, `lock_holder_state` and `reclaim_lock` in `bin/run.sh` guard the per-date run lock
and the per-label remote sync lock with a `mkdir` and a judgment about the holder's pid. The gate
found three defects in the judgment while fixing #192 (https://github.com/STRML/autodream/pull/238):

| Site | Defect |
|---|---|
| `lock_holder_state`, the `kill -0` line | A failed `kill -0` reads as dead, but EPERM means a live process of another user |
| `lock_holder_state`, the start compare | An empty `proc_start` (ps failed) differs from the recorded start, so a live holder reads as a reused pid |
| `reclaim_lock`, the restore | `mv` of the displaced directory onto a path that was taken meanwhile nests it inside the new lock and reports success. A pid-less directory is also reclaimed after three tries whatever its age |

A shell cannot make "judge the holder gone, then take its lock" atomic. #192 ended the same class
in `question-streaks.sh` by letting the kernel hold the lock.

## Design

```
acquire_lock <dir> [wait]
   │
   ├─ python holder (background child of this shell)
   │     open  <dir minus .lock>.flock        a file beside the directory, never removed
   │     flock LOCK_EX|LOCK_NB, retry until <wait>
   │     write ok | held | error  ─────────▶  result file the shell polls
   │     ok: hold until getppid() changes or SIGTERM
   │
   └─ ok: mkdir -p <dir>; write pid and start      (the web dashboard reads these)

release_lock <dir>: rm -rf <dir>, then SIGTERM the holder and wait for it
```

- **The flock is the lock.** A directory with leftover files and no flock holder is free. Nothing
  reads a pid to decide anything, so EPERM, an empty `ps` and a pid-less directory are not cases.
  `reclaim_lock`, `lock_holder_state` and `wait_for_lock_release` are deleted, and with them the
  `mv` that nested a restored lock.
- **The flock file sits beside the directory.** The dashboard lists every `run-*.lock` directory
  and shows "starting" for one with no pid file, so a file kept inside would show every finished
  date as starting. A lock file that is unlinked while a contender has it open also lets two
  processes hold two inodes, so this file is never removed. The directory also holds `holder`,
  the holder's pid: the interactive path runs `run` in a pipeline subshell while the EXIT trap
  is in the parent shell, so release finds the holder through the directory and not through a
  shell variable.
- **A holder process owns the descriptor, not the run.** `lib-flock.sh` keeps fd 9 in the calling
  shell, and every child started afterwards inherits it. A run starts L1 workers, an engine,
  `osascript` and background sync jobs, and one that outlives a killed run would keep the date
  locked with no way to tell (a hung worker's leaked grandchild already cost days in 2026-08).
  The holder is a separate process that opens the file itself, so no other process of the run
  has the descriptor. It exits within a quarter second of its parent's death (the parent pid
  changes when a process is reparented), and `release_lock` ends it and waits, so the lock is free
  when release returns.
- **pid and start stay.** They are written after the flock is taken and removed with the directory
  at release. A directory left by a killed run keeps its dead pid, which the dashboard already
  reads as stale.
- **The sweep probes instead of reading a pid.** `lock_held_by_live_run` becomes a `LOCK_NB` probe
  of the same file. A probe that cannot run (no python3) reads as held, so the sweep skips a date
  it cannot prove idle.
- **Waiting moves into the holder.** `acquire_lock` takes a wait in seconds. The run lock waits 2,
  because a sweep's probe takes the lock for a few milliseconds and must not read as a second run.
  The remote lock waits `AUTODREAM_REMOTE_LOCK_WAIT`, replacing the poll loop around the
  directory.
- **No python3.** A run proceeds without the per-date lock and logs a WARNING, as it does when the
  lock directory cannot be made. A remote sync reports `failed (cannot lock ...)`.
- **Out of scope.** The X browser lock in `x-bookmarks.sh` is a `mkdir` lock of the same shape. The
  issue names the run and remote locks, so it is left alone and noted in the PR.

## Failure matrix

| State or input | Before | After | The caller is told |
|---|---|---|---|
| Holder alive, pid owned by another user | `kill -0` fails, lock taken from a live run | flock held, run exits | "another run holds the lock" |
| Holder alive, `ps` fails | Recorded start differs from an empty one, read as a reused pid | flock held | same |
| Holder alive, no pid written yet | Reclaimed after three tries | flock held, whatever the age | same |
| Holder dead, directory with pid and start left | Reclaimed by rename | flock free, pid and start overwritten | none needed |
| Two contenders see the same dead holder | The slower `mv` can nest a restored lock | no reclaim step: one flock winner | the loser is told the lock is held |
| Run killed with SIGKILL | Directory left, reclaimed next run | holder exits within a quarter second, flock free | dashboard shows stale until the next run |
| A child of the run outlives it | Not an issue (pid check) | does not hold the lock: the descriptor is only in the holder | none |
| Sweep probes while another run acquires | Reads a pid | probe holds the flock for milliseconds, the run lock waits 2 s | none |
| python3 missing | Not an issue | run unlocked with a WARNING; remote sync `failed (cannot lock ...)` | log line and run-stats |
| Lock directory cannot be made | Run unlocked with a WARNING | same | same |
| Flock file cannot be opened | n/a | holder answers `error`, treated as cannot lock | same as above |
| Release by a process that never took the lock (EXIT trap) | Owner check on the pid file | owner check on the pid file, unchanged: the directory names another pid, so nothing happens | none |

## Tests

Red first, against the unchanged runner. Each holds a real flock with `hold_flock` instead of
writing a pid file:

1. `test_run_lock_a_live_holder_of_another_user_is_still_held`: pid file names pid 1.
2. `test_run_lock_a_live_holder_is_held_when_ps_cannot_report_its_start`: `ps` shimmed to fail.
3. `test_run_lock_a_holder_that_has_not_written_its_pid_is_held`: directory with no pid file.
4. `test_run_lock_a_killed_run_frees_it_while_its_child_lives`: SIGKILL the run during a hung L1
   worker, the flock frees and the worker is still alive.

The existing run-lock and remote-sync lock tests change from writing a pid file to holding a flock.
