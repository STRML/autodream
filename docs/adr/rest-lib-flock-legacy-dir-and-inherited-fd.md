# rest: lib-flock honors an old mkdir lock while it is young, and long-running children must close fd 9

Status: accepted · Date: 2026-11-21 · Code: `bin/lib-flock.sh` (`flock_acquire`, the embedded `legacy_state`)

## Context

During the upgrade an older writer may still hold the mkdir lock the flock replaced (#192). And the kernel keeps a flock alive as long as any process holds the open file description, so a child that inherits fd 9 and outlives its parent holds the lock.

## Decision

The legacy directory is the one age judgment left. After the flock is taken, inside the same deadline loop:

- no directory, or a path that is not a directory: `none`;
- a directory younger than 300 seconds: a live older writer, so the flock is released and `flock_acquire` returns 5 (`flock-legacy`);
- an older directory is ignored and never removed;
- a directory whose state cannot be read (a symlink loop, a permission error) is `unknown`, which is return 2, a permanent state to report and not a live writer.

An old writer that creates its directory after the check, or one stalled past 300 seconds, is not covered; the upgrade window bounds both.

Every child started while the lock is held inherits fd 9. The short-lived ones (awk, jq, mktemp, cp) are accepted: a hung one under a killed writer keeps the lock, and the next run skips loudly instead of racing it. Any child that can run long (a notification, a browser) runs with `9>&-`.

## Consequences

The 300-second constant and the `none` for an older directory are the remaining judgment calls; remove the legacy path once no older writer can exist. A new long-running child started under the lock needs `9>&-` (`bin-b-question-streaks-banner`).
