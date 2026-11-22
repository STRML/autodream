# 0012: Shared shell helpers: flock, path state and portable date and stat

Status: accepted · Governs: `bin/lib-flock.sh`, `bin/lib-path-state.sh`, `bin/portable.sh`

This record holds 5 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [lib-flock takes a kernel flock on fd 9 through python3, and each failure has its own return code](#lib-flock-takes-a-kernel-flock-on-fd-9-through-python3-and-each-failure-has-its-own-return-code)
- [lib-flock honors an old mkdir lock while it is young, and long-running children must close fd 9](#lib-flock-honors-an-old-mkdir-lock-while-it-is-young-and-long-running-children-must-close-fd-9)
- [path_state has three answers, and "absent" is believed only under a searchable ancestor](#path_state-has-three-answers-and-absent-is-believed-only-under-a-searchable-ancestor)
- [date and stat calls go through portable.sh, whose date parsing is strict on purpose](#date-and-stat-calls-go-through-portablesh-whose-date-parsing-is-strict-on-purpose)
- [tmo's watchdog fallback hands the caller's stdin to the job and kills its own sleep](#tmos-watchdog-fallback-hands-the-callers-stdin-to-the-job-and-kills-its-own-sleep)

## lib-flock takes a kernel flock on fd 9 through python3, and each failure has its own return code

Status: accepted · Date: 2026-11-21 · Code: `bin/lib-flock.sh` (`flock_acquire`, `flock_release`)

### Context

`question-streaks.sh` and `threads.sh` serialize a read-modify-write on a state file. The mkdir lock they used was reclaimed by contenders that judged its holder gone, and a shell cannot make "judge, then take away" atomic: four gate rounds on #192 each found another interleaving (`docs/plans/2026-11-21-fix_question-streaks-lock-owner-redesign.md`). The story is in docs/adr/0020-question-streaks.md#background-open-questions-that-never-get-answered, "Open questions that never get answered", and `bin-b-question-streaks-flock-skips-not-blocks`.

### Decision

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

### Consequences

`python3` is already needed by the web dashboard; without it the caller gets 3 and says so. Change the lock protocol here for both scripts together (`bin-b-threads-state-flock`). Callers decide what each code means for them (`question-streaks.sh` skips the update; see its ADR).

## lib-flock honors an old mkdir lock while it is young, and long-running children must close fd 9

Status: accepted · Date: 2026-11-21 · Code: `bin/lib-flock.sh` (`flock_acquire`, the embedded `legacy_state`)

### Context

During the upgrade an older writer may still hold the mkdir lock the flock replaced (#192). And the kernel keeps a flock alive as long as any process holds the open file description, so a child that inherits fd 9 and outlives its parent holds the lock.

### Decision

The legacy directory is the one age judgment left. After the flock is taken, inside the same deadline loop:

- no directory, or a path that is not a directory: `none`;
- a directory younger than 300 seconds: a live older writer, so the flock is released and `flock_acquire` returns 5 (`flock-legacy`);
- an older directory is ignored and never removed;
- a directory whose state cannot be read (a symlink loop, a permission error) is `unknown`, which is return 2, a permanent state to report and not a live writer.

An old writer that creates its directory after the check, or one stalled past 300 seconds, is not covered; the upgrade window bounds both.

Every child started while the lock is held inherits fd 9. The short-lived ones (awk, jq, mktemp, cp) are accepted: a hung one under a killed writer keeps the lock, and the next run skips loudly instead of racing it. Any child that can run long (a notification, a browser) runs with `9>&-`.

### Consequences

The 300-second constant and the `none` for an older directory are the remaining judgment calls; remove the legacy path once no older writer can exist. A new long-running child started under the lock needs `9>&-` (`bin-b-question-streaks-banner`).

## path_state has three answers, and "absent" is believed only under a searchable ancestor

Status: accepted · Date: 2026-11-22 · Code: `bin/lib-path-state.sh` (`path_state`)

### Context

`[ -e p ]` answers false for a path that exists but cannot be reached: a symlink whose target sits in a directory this user cannot search, or a path under an unsearchable parent. Code that reads false as "not there" then skips state it should have refused to run without. The omp L1 adapter and its store-unchanged test used `-e`/`-f` and a discarded `find` error as negatives and so treated "could not look" as "nothing there" (`docs/plans/2026-11-21-feat_omp-l1-writes-redesign.md`, section C).

### Decision

`path_state <path>` prints nothing and returns 0 (present), 1 (absent) or 2 (cannot tell). Present is `-e`. A symlink at the path that `-e` cannot follow is 2. Otherwise it walks up to the nearest ancestor that exists (or is a symlink), stopping at `/` or `.`, and returns 1 only when that ancestor is a searchable directory (`-d` and `-x`); anything else is 2.

### Consequences

Every existence check that gates a security decision has three outcomes, and "could not look" fails. The adapter (`adapters/omp/adapter.sh`) and `tests/lib-store-unchanged.sh` use it at each such site; `tests/l1-confine.sh` pins the five cases (file, missing under a searchable directory, dangling symlink, symlink into a locked directory, path under a locked directory). Do not collapse 2 into 1 at a caller.

## date and stat calls go through portable.sh, whose date parsing is strict on purpose

Status: accepted · Date: 2026-10-07 · Code: `bin/portable.sh` (`pdate_*`, `pstat_*`, `repo_slug`)

### Context

The scripts and tests called `date -v`, `date -j -f` and `stat -f` directly, which is why the whole suite needed a macOS runner. `portable.sh` is sourced, never executed, by the scripts and by the suite, so the pure-logic suites run on Linux (#153; docs/adr/0028-test-suite-organization.md#background-the-test-suite). GNU `date -d` also accepts "tomorrow" and "last friday", while BSD `date -j -f %Y-%m-%d` does not, so a caller handed garbage would fail on one platform and not the other.

### Decision

Every caller goes through these functions. Each tool is detected on its own (`_P_GNU_DATE`, `_P_GNU_STAT`), because a Mac with coreutils' gnubin on PATH has a GNU date and a BSD stat. Dates are checked for shape first (`_p_is_date`, `_p_is_stamp`, `_p_is_int`) so garbage fails the same way on both.

- `pdate_yesterday` prints yesterday, local time, `YYYY-MM-DD`.
- `pdate_shift <YYYY-MM-DD> <signed whole number> <d|y>` prints the shifted date; exit 1 on a bad date, number or unit.
- `pdate_epoch "<YYYY-MM-DD HH:MM:SS>"` (local) prints epoch seconds, exit 1 when it does not parse; a bare `YYYY-MM-DD` is midnight.
- `pdate_fmt_epoch <epoch> <+FORMAT>` prints the epoch formatted in local time (`TZ=UTC pdate_fmt_epoch` for UTC).
- `pstat_mtime <file>` prints the mtime in epoch seconds; `pstat_mode <file>` the permission bits in octal with no leading zeros (600, 755).
- `repo_slug <repo dir>` prints `owner/repo` from a github.com origin URL, and nothing otherwise.
- `tmo` is in `rest-portable-tmo-keeps-stdin-and-reaps-its-watchdog`.

### Consequences

A new script or test that needs one of those calls the helper, never the raw tool. `tests/portable.sh` pins the behavior with literal expected values on both platforms, and `launchd.yml` runs it on macOS when this file changes. Relaxing the shape checks would let GNU-only inputs pass on Linux CI and fail on the Mac.

## tmo's watchdog fallback hands the caller's stdin to the job and kills its own sleep

Status: accepted · Date: 2026-11-15 · Code: `bin/portable.sh` (`tmo`)

### Context

`tmo <seconds> <command...>` runs a command bounded by `timeout`, then `gtimeout`, then, with neither on PATH (macOS ships none), a watchdog the function builds. Two defects in the fallback:

- A background job gets `/dev/null` as stdin before any explicit redirect applies, so `tmo 5 cat` in a pipeline read nothing (3f53389, 2026-11-15).
- A watchdog that ran `( sleep N; kill ... ) &` and was killed on a normal exit killed only the subshell and left the `sleep` running until its timeout. The same defect was in `run_bounded` and the hard-cap watchdog in `bin/prune-worktrees.sh` (docs/adr/0016-report-scripts.md#background-report-scripts-one-collector-so-a-note-can-ask-for-a-command, "A watchdog takes its own `sleep` with it").

### Decision

The caller's stdin is saved on fd 3 first (`/dev/null` when fd 0 is closed) and the job gets `<&3`; fd 3 is closed in the parent right after the job starts. The watchdog subshell traps TERM, kills the sleep it started and exits, so the kill that ends it also ends the sleep, and a watchdog woken at that moment cannot signal a recycled pid. At the deadline it kills the job's children (`pkill -P`) and then the job. The function returns the job's own status.

### Consequences

`tests/portable.sh` pins both (stdin through the fallback, including a closed stdin). Removing the `trap` brings back an orphaned `sleep` per call; moving the stdin save after the `&` brings back the empty stdin.
