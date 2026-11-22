# 0021: Dropped threads index

Status: accepted · Governs: `bin/threads.sh`, `bin/portable.sh`

This record holds 3 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [threads.sh gives cmux a launcher file, not an inline command](#threadssh-gives-cmux-a-launcher-file-not-an-inline-command)
- [threads.sh hands the status filter its state as a file, never on a pipe](#threadssh-hands-the-status-filter-its-state-as-a-file-never-on-a-pipe)
- [threads.sh takes the same flock as question-streaks.sh, and honors the old mkdir lock while it is young](#threadssh-takes-the-same-flock-as-question-streakssh-and-honors-the-old-mkdir-lock-while-it-is-young)

## threads.sh gives cmux a launcher file, not an inline command

Status: accepted · Date: 2026-11-21 · Code: `bin/threads.sh` (`threads_launcher`)

### Context

cmux types `--command` into the user's login shell, which can be fish, and fish cannot parse bash's `$'...'` quoting. docs/adr/0025-web-dashboard.md#background-local-web-dashboard, "Local web dashboard" and the Tests section on `threads.sh explore`, record the launch contract.

### Decision

`threads_launcher` writes the bash command to a file in a fresh 0700 `mktemp -d` directory and prints its path. cmux is handed only `/bin/bash '<file>'`, which every shell reads the same way. The path is absolute (the pane may start in another directory) and free of single quotes and backslashes (a directory name containing either is rejected), so the single quotes are safe. The launcher removes its own file and directory when it starts, and nothing else is ever deleted.

### Consequences

`test_threads_explore_*` pins the quoting. Do not inline the command to save the file.

## threads.sh hands the status filter its state as a file, never on a pipe

Status: accepted · Date: 2026-11-21 · Code: `bin/threads.sh` (`threads_render_unlocked`), `bin/portable.sh` (`tmo`)

### Context

With no `timeout` binary, `tmo` backgrounds the command, and a background job's stdin is `/dev/null`. Piped state vanishes and jq exits 0 with no output. The same constraint is recorded for the Python renderer in `docs/adr/0025-web-dashboard.md#threads-render-hands-jq-its-state-as-a-file-never-on-stdin`.

### Decision

`threads_render_unlocked` writes the state to a `mktemp` file, passes its path to `threads_status_jq`, and removes it afterward.

### Consequences

Do not switch to a pipe or here-string to save the temp file. An empty result is an error here, not an empty thread list.

## threads.sh takes the same flock as question-streaks.sh, and honors the old mkdir lock while it is young

Status: accepted · Date: 2026-11-21 · Code: `bin/threads.sh` (`threads_acquire_lock`)

### Context

Both scripts write their own state with one rename and serialize writers on `$STATE.flock`. docs/adr/0020-question-streaks.md#background-open-questions-that-never-get-answered, "Open questions that never get answered", explains why a kernel flock replaced the reclaimable mkdir lock (#192): nothing has to judge a holder dead.

### Decision

`threads_acquire_lock` calls `flock_acquire` from `lib-flock.sh` with the older version's `$STATE.lock` directory as the legacy lock, which is honored while it is younger than 300 seconds. `question-streaks.sh` takes its lock the same way.

### Consequences

Change the lock protocol in `lib-flock.sh` for both scripts together.
