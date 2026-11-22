# runsh: Hosts sync in parallel background jobs, and results are read in config order

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`sync_remote_roots` passes 1 and 2, `remote_sync_job`, `remote_sync_finish`)

## Context
A host that is asleep costs `ConnectTimeout` and a stalled copy costs rsync's `--timeout`, so with several hosts down the waits added up (#229).

## Decision
Pass 1 validates every entry and starts one `remote_sync_job` per valid label in the background, so the waits overlap. Each label has its own lock and mirror, so the jobs share nothing, and `$$` is still this run's pid inside a job, so the lock it takes is this run's. A job cannot set the parent's variables, so it leaves `<prefix>.status`, `.secs` and `.mirror` in a per-run job dir. That dir is `$AUTODREAM_DIR/remote-jobs/<run pid>`, under the install and not in `$TMPDIR`: a run killed while it waits skips every cleanup, so the next run removes the dirs of dead pids there and never a live one's (a name is only ever this run's pid or an earlier run's). If the dir cannot be made no job starts and every valid entry reads `failed (cannot make a job dir for the sync jobs)`. `remote_sync_finish` is given an empty prefix in that case and reads nothing, so a failed job-dir allocation never turns into a read of `/0.status`. Pass 2 reads the results in `AUTODREAM_REMOTE_ROOTS` order, so run-stats and `SESSION_ROOTS` do not depend on which host answered first, and a refused entry keeps its place.

See CLAUDE.md, "Remote hosts" (Hosts sync in parallel (#229)).

## Consequences
Never add a variable assignment to the job body expecting the parent to see it. `bin/remote-sync.sh` itself is unchanged by this.
