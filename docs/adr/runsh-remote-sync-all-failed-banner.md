# runsh: A banner fires only when every remote host failed

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (end of `sync_remote_roots`)

## Context
Every host failing is a broken path (lost key, renamed host, no route), and the per-host lines sit in `run-stats.txt` until the report, so it needs a louder signal. One host failing, or a host another run is syncing, is not a path failure.

## Decision
When `REMOTE_SYNC_BAD` equals `REMOTE_SYNC_TOTAL` (and the total is above zero), `notify.sh --warning` posts one banner in its own `remote-sync` group naming the first failure. `REMOTE_SYNC_BAD` counts only `failed` and `invalid` hosts, so `skipped_locked` and `partial` do not count. The banner is a warning, in its own group, so it cannot replace the changelog warning. A failure of the notify call is logged and ignored.

See CLAUDE.md, "Remote hosts" (Reporting).

## Consequences
A failure never defers the date and never aborts the run.
