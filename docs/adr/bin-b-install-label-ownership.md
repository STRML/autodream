# bin-b: the schedule label comes from scheduler-label.sh, never from a name match

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`install_schedule`), `bin/scheduler-label.sh`

## Context

Matching a plist on the string `run.sh` alone took over another install's job and left it dead for 18 days (omp-autodream#14, https://github.com/STRML/cc-autodream/issues/60). CLAUDE.md, "The label is owned by a runner, not by a name", is the full record.

## Decision

`install_schedule` asks `bin/scheduler-label.sh` for the label. It reuses this install's own prior label (so a re-install is idempotent), never adopts a plist that runs someone else's `run.sh`, and exits 3 rather than overwrite a foreign job holding the default name. The installer returns that code unchanged.

## Consequences

See `bin-b-install-schedule-exit-codes` for what the caller does with exit 3.
