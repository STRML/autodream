# runsh: A held mirror lock is waited for, then the run syncs itself

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`wait_for_lock_release`, `remote_sync_locked`)

## Context
A run that scanned a mirror another run was still copying into would miss the files not yet renamed into place, and the next day's mtime lower bound would never pick them up. The nightly and an `autodream-now.sh` run for another date take different run locks and would otherwise rsync into one directory at once.

## Decision
`remote_sync_locked` takes `$AUTODREAM_DIR/locks/remote-<label>.lock` with the run lock's helpers (see `per-date-run-lock-mkdir`). If a live holder has it, `wait_for_lock_release` polls once a second up to `AUTODREAM_REMOTE_LOCK_WAIT` (default 600, a non-number becomes 600) and the run then syncs itself. A holder still alive after the wait gives `skipped_locked` and the mirror is scanned as it stands. A lock dir that cannot be made gives `failed (cannot create <dir>)`.

See CLAUDE.md, "Remote hosts" (Lock).

## Consequences
`skipped_locked` is a short-mirror label (it joins `REMOTE_SHORT_LABELS`) but not a failure for the all-failed banner.
