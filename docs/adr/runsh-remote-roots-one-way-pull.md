# runsh: Remote session roots are a one-way pull into local mirrors, never a mount

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`sync_remote_roots`, `remote_sync_stat` and the `REMOTE_*` globals)

## Context
Sessions also run on other hosts (#226). Without a sync that work drops out of the report with no warning.

## Decision
`AUTODREAM_REMOTE_ROOTS` names hosts as space-separated `label=ssh-target:path` entries. Each is pulled one way by `remote-sync.sh` into `$AUTODREAM_DIR/remote/<label>/projects`, and every mirror that exists, synced this run or kept from an earlier one, joins `SESSION_ROOTS` for the claude adapter. `sync_remote_roots` runs below the idempotency guard (a catch-up trigger never reaches ssh) and above enumeration. A failed host never defers the date and never stops the run: it is a line in `run-stats.txt`, and a banner when every host failed. Results go to globals (`REMOTE_SYNC_LINES` and friends), not stdout, so the function is called directly and never inside `$(...)`, which would lose them.

See CLAUDE.md, "Remote hosts: a one-way pull, not a shared filesystem (#226)".

## Consequences
Do not call `sync_remote_roots` in a command substitution. Related decisions: `remote-sync-entry-validation`, `remote-sync-parallel-jobs`, `remote-sync-waits-for-held-mirror`, `remote-mirror-size-measured`, `remote-short-dates-record-in-report`, `remote-sync-all-failed-banner`.
