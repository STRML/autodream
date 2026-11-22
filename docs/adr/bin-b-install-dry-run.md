# bin-b: a dry run runs every read, replaces every write, and generates plists in a scratch directory

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`dry`, `DRY_SCRATCH`, `show_plist`, `lctl`)

## Context

A rehearsal that skips the checks proves nothing. CLAUDE.md, "Rehearsing an install", has the contract and the test (`tests/install-dry-run.sh`).

## Decision

With `--dry-run` the same code path runs. Every write becomes a `[dry-run]` line. Anything that only reads (the label ownership check, the cmux and claude lookups, the validations in `link`) still runs, so the dry run reports the refusals a real install would hit. The plists are generated and `plutil`-linted in one scratch directory under `TMPDIR`, removed on every exit path, so the dry run shows exactly what would be written without touching the real LaunchAgents directory. The ownership check still reads the real one.

## Consequences

A new write in the installer must go through `dry`, `lctl` or the scratch directory, or the "tree is identical afterward" test fails.
