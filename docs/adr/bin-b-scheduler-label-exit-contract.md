# bin-b: scheduler-label reports a foreign holder of the default label as exit 3 and never guesses a plist

Status: accepted · Date: 2026-11-21 · Code: `bin/scheduler-label.sh` (conflict branch, `--plist` mode)

## Context

Two callers read this script and need different things. `install.sh` writes the plist and must not overwrite another install's job. `autodream-now.sh` only borrows the label as a namespace and always adds a per-install hash. Both use the same ownership rule (see `bin-b-scheduler-label-runner-ownership.md`).

## Decision

- Label mode prints the base label on every path, a conflict included. The `-review` and `.ondemand` siblings suffix it.
- Exit 3 means a plist running a different install holds the default label. stdout still carries the label. A caller that would write the plist aborts on it. autodream-now ignores the status.
- `--plist` prints the path of the scheduled plist this install owns, and exits 1 when there is none. autodream-now reads the job's environment from that file, so "none" must never fall back to a plist that only shares the label.

## Consequences

Dropping the label from stdout on a conflict breaks autodream-now. Returning a label-matching plist from `--plist` would put another install's environment into an on-demand run. CLAUDE.md, "The label is owned by a runner, not by a name", covers the install.sh side (skip scheduling, keep the symlinks).
