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
   ├─ python holder (background child of this shell), handed this run's pid
   │     open  <dir minus .lock>.flock     read-only + create: flock needs no write access
   │     loop: owner alive? (kill 0, EPERM = alive) ─ no ─▶ exit, never take the lock
   │           flock LOCK_EX|LOCK_NB ─ busy ─▶ retry until <wait>, then say "held"
   │     owner alive? ─▶ say "ok" ─▶ hold until the owner is gone or SIGTERM
   │
   ├─ a directory naming a live pid with its start (a runner from before the flock) ─▶ held
   │
   └─ ok: mkdir -p <dir>; write pid and start   (any failed write = cannot lock)
          record "<dir>=<holder pid>" in this process

release_lock <dir>: only for a dir this process recorded: rm -rf <dir>, then end the holder and wait
```

- **The flock is the lock.** A directory with leftover files and no flock holder is free. Nothing
  reads a pid to decide who holds a lock taken with the flock, so EPERM, an empty `ps` and a
  pid-less directory are not cases. `reclaim_lock`, `lock_holder_state` and
  `wait_for_lock_release` are deleted, and with them the `mv` that nested a restored lock.
- **The flock file sits beside the directory.** The dashboard lists every `run-*.lock` directory
  and shows "starting" for one with no pid file, so a file kept inside would show every finished
  date as starting. A lock file that is unlinked while a contender has it open also lets two
  processes hold two inodes, so this file is never removed.
- **A holder process owns the descriptor, not the run.** `lib-flock.sh` keeps fd 9 in the calling
  shell, and every child started afterwards inherits it. A run starts L1 workers, an engine,
  `osascript` and background sync jobs, and one that outlives a killed run would keep the date
  locked with no way to tell (a hung worker's leaked grandchild already cost days in 2026-08).
  The holder is a separate process that opens the file itself, so no other process of the run
  has the descriptor.
- **The owner is a pid the holder is handed, checked before every attempt.** Asking the holder for
  its own parent at startup is wrong twice: a run killed between the fork and that call makes the
  reaper the owner, so the holder lives as long as the reaper, and a holder waiting behind another
  holder never looks at its parent until the wait is over. The run passes `$$`. The holder checks
  it with `kill -0` before each flock attempt and again before it answers, treats a pid it cannot
  signal as alive, and leaves at once when the owner is gone. A pid reused inside a quarter second
  of the owner's death is the one case this does not cover.
- **The flock file is opened read-only.** `flock(2)` needs no write access, so a run of another
  user can lock a file it can read. A file that exists and cannot be opened belongs to someone
  else and reads as held, never as "cannot lock", which would let both runs go ahead.
- **A runner from before the flock is honored.** It holds the directory with its pid and start and
  knows nothing of the flock file, so a new runner would take the flock and accept the directory.
  After the flock, a directory whose pid file names a live process that still has the recorded
  start reads as held (`lock_names_live_run`; a pid ps can see but `kill` cannot signal counts as
  alive, and a start ps cannot report counts as a match). This is the one pid judgment left, and
  it fails toward held. The pin sweep asks the same question.
- **Ownership is the process that acquired.** `release_lock` acts only on a directory this process
  recorded. A pid read from a directory proves nothing once pids are reused: a later process that
  inherits a dead run's pid but found the lock held would remove the real holder's directory and
  signal a pid that now belongs to something else. The interactive path runs `run` as a pipeline
  element, in a subshell the parent's EXIT trap cannot see, so `run` is a wrapper that sets the
  trap and releases in its own process. The directory no longer holds a `holder` file.
- **pid and start stay.** They are written after the flock is taken and removed with the directory
  at release. A write that fails is a lock that was not taken: the holder is stopped and the
  caller proceeds as for an unusable lock directory. A directory left by a killed run keeps its
  dead pid, which the dashboard already reads as stale.
- **The sweep probes instead of reading a pid.** `lock_held_by_live_run` becomes `lock_is_held`.
  Without python3 nothing can be proven, so it answers held before it looks at any file.
- **Waiting moves into the holder.** `acquire_lock` takes a wait in seconds. The run lock waits 2,
  because a sweep's probe takes the lock for a few milliseconds and must not read as a second run.
  The remote lock waits `AUTODREAM_REMOTE_LOCK_WAIT`, replacing the poll loop around the
  directory.
- **Result files.** The holder answers through a file in the locks directory. One left by an
  acquire that was killed is swept when it is older than ten minutes.
- **No python3.** A run proceeds without the per-date lock and logs a WARNING, as it does when the
  lock directory cannot be made. A remote sync reports `failed (cannot take the lock ...)`.
- **Out of scope.** The X browser lock in `x-bookmarks.sh` is a `mkdir` lock of the same shape. The
  issue names the run and remote locks, so it is left alone and noted in the PR. The pin sweep's
  window between probing a date and applying its pins also existed with the pid check.

## Failure matrix

| State or input | Before | After | The caller is told |
|---|---|---|---|
| Holder alive, pid owned by another user | `kill -0` fails, lock taken from a live run | flock held, run exits | "another run holds the lock" |
| Holder alive, `ps` fails | Recorded start differs from an empty one, read as a reused pid | flock held | same |
| Holder alive, no pid written yet | Reclaimed after three tries | flock held, whatever the age | same |
| Holder dead, directory with pid and start left | Reclaimed by rename | flock free, directory's pid dead, pid and start overwritten | none needed |
| Two contenders see the same dead holder | The slower `mv` can nest a restored lock | no reclaim step: one flock winner | the loser is told the lock is held |
| Run killed with SIGKILL | Directory left, reclaimed next run | holder sees the pid gone within a quarter second, flock free | dashboard shows stale until the next run |
| Run killed between forking the holder and its first look at the owner | n/a | the holder's parent is already pid 1, or `kill -0` fails before its first attempt: it leaves without taking the lock | none |
| Acquire in a pipeline or background subshell (interactive run, remote sync job) | n/a | the holder watches the forking subshell, not the top-level shell: the lock frees when that subshell dies | none |
| Older runner between its `mkdir` and its pid write | n/a | a directory with no usable pid under a minute old is held | "another run holds the lock" |
| Older runner creates the directory between our check and our `mkdir` | n/a | the stale directory is renamed aside and ours made with a plain `mkdir`, which fails: held | same |
| Directory with no usable pid, over a minute old | Reclaimed after three tries | crashed run's: replaced | none |
| Run killed while its holder waits behind another holder | n/a | holder checks the owner on every attempt and leaves, not at the end of the wait | none |
| A child of the run outlives it | Not an issue (pid check) | does not hold the lock: the descriptor is only in the holder | none |
| Flock file exists, owned by another user, readable | n/a | opened read-only, locked normally | none |
| Flock file exists and this user cannot open it | n/a | held: someone else's file | "another run holds the lock (pid unknown)" |
| Runner from before the flock is alive and holds the directory | Reclaimed or not by pid | directory names a live pid with its start: held | "another run holds the lock" |
| Directory names a dead or reused pid (start differs) | Reclaimed | not alive, proceed | none |
| pid or start file cannot be written | Success reported | directory removed, holder stopped, cannot lock, run goes ahead with a WARNING | log line |
| A stale directory cannot be renamed aside | n/a | cannot lock, run goes ahead with a WARNING | log line |
| Sweep probes while another run acquires | Reads a pid | probe holds the flock for milliseconds, the run lock waits 2 s | none |
| Sweep, python3 missing, no flock file | n/a | held: nothing can be proven | the date's pins wait |
| python3 missing at acquire | Not an issue | run unlocked with a WARNING; remote sync `failed (cannot take the lock ...)` | log line and run-stats |
| Lock directory cannot be made | Run unlocked with a WARNING | same | same |
| Release by a process that never took the lock, with its pid in a stale directory | pid matches, directory removed, holder pid signalled | no record in this process: nothing happens | none |
| Interactive run (pipeline subshell) | Parent trap releases by pid file | `run` releases and traps in its own process | none |
| Acquire killed after `mktemp` | n/a | result file swept after ten minutes | none |

## Tests

Red first, against the unchanged runner. A test that needs a holder takes a real flock with
`hold_flock` instead of writing a pid file:

1. `test_run_lock_a_live_holder_of_another_user_is_still_held`: pid file names pid 1.
2. `test_run_lock_a_live_holder_is_held_when_ps_cannot_report_its_start`: `ps` shimmed to fail.
3. `test_run_lock_a_holder_that_has_not_written_its_pid_is_held`: directory with no pid file.
4. `test_run_lock_a_killed_run_frees_it_while_its_child_lives`: SIGKILL the run during a hung L1
   worker, the flock frees and the worker is still alive.
5. `test_run_lock_a_flock_file_this_user_cannot_open_is_held`: mode 000.
6. `test_run_lock_a_holder_does_not_outlive_a_dead_owner`: a holder whose parent exited before it
   started, behind a busy lock, leaves and never takes the lock.
7. `test_run_lock_release_ignores_a_directory_it_never_acquired`: a directory naming this pid.
8. `test_run_lock_an_older_runner_holding_the_directory_is_honored`: live pid, no flock.
9. `test_run_lock_a_directory_that_cannot_be_replaced_is_not_a_taken_lock`: read-only locks dir.
10. `test_run_lock_the_pin_sweep_reads_an_unprobeable_lock_as_held`: no python3 on PATH.
11. `test_run_lock_a_killed_acquire_leaves_no_result_file_for_long`: an old `.hold.*` file.
12. `test_run_lock_a_holder_follows_the_subshell_that_acquired`: acquire in a subshell that exits while
    the top-level shell lives; the flock frees.
13. `test_run_lock_a_directory_an_older_runner_is_still_creating_is_held`: young pid-less directory,
    for the run and the pin sweep.
14. `test_run_lock_a_directory_with_no_pid_that_is_old_is_reclaimed`.
15. `test_run_lock_a_stale_directory_is_replaced_by_a_rename_then_mkdir`.

The existing run-lock, remote-sync and pin-sweep tests change from writing a pid file to holding a
flock.
