# bin-a: the on-demand label borrows our base label and always carries an install hash

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (`BASE_LABEL`, `INSTALL_REAL`, `LABEL`)

## Context

The transient label should sit in the same namespace as this install's scheduled job. `scheduler-label.sh` owns that decision for `install.sh` too, and it will not hand back a label belonging to another autodream install. The `bootout` before each run evicts whatever holds the on-demand label, and another install's on-demand plist lives in its own `AUTODREAM_DIR`, where no scan can see it. Two installs share a base label whenever one holds the default or neither has a scheduled job, so no check on the base label can rule the collision out.

## Decision

`BASE_LABEL` comes from `scheduler-label.sh`. A conflict on the default name is not fatal here, because the script only borrows the namespace. The on-demand label is `<base>.ondemand.<8 hex of a sha1 of the resolved install dir>`, always. `pwd -P` keeps the hash the same for a trailing slash or a symlinked path, so `bootout` still finds this install's prior run.

## Consequences

The label's hash must be computed from `pwd -P`, or `bootout` misses the prior run. CLAUDE.md, "The label is owned by a runner, not by a name", has the incident that shaped `scheduler-label.sh`.
