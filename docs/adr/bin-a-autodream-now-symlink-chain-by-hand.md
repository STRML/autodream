# bin-a: autodream-now.sh walks its own symlink chain by hand

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (`resolve`)

## Context

macOS has no `readlink -f`. `install.sh` symlinks this helper into `$AUTODREAM_DIR`, so the script has to resolve through the link to find the real `bin/` and the `run.sh` beside it.

## Decision

`resolve` follows `readlink` one hop at a time until the path is no longer a symlink, joining a relative target to the link's directory.

## Consequences

Replacing it with `readlink -f` works on Linux and breaks on macOS, where this script runs.
