# tests-l1-confine-real: the manual check runs under the nightly's own configuration

Status: accepted · Date: 2026-11-22 · Code: `tests/l1-confine-real.sh` (config block, `AUTODREAM_WORK_BUCKET`, `protect`)

## Context

The check exists to prove the profile the nightly builds. If it ran with defaults, an `AUTODREAM_L1_WRITES_EXTRA` the operator put in `$AUTODREAM_DIR/config` would be missing, and a PASS would describe a profile no run uses. `CLAUDE.md` ("run.sh sources the config now") records the two details of sourcing: `set -a` so keys are exported, and the `export -p` snapshot replayed afterwards so the caller's explicit environment still wins.

## Decision

The script resolves `AUTODREAM_DIR` and `AUTODREAM_CONFIG` as `run.sh` does, sources the config with `set -a`, replays the `export -p` snapshot, and derives the protected paths (`$AUTODREAM_DIR`, findings dir, dreams dir) and the work bucket the same way `run.sh` does. It prints which configuration it used, or that none was found.

## Consequences

A change to how `run.sh` sources the config or builds the protect list needs the same change here, or the check silently verifies a different profile. Removing the snapshot replay would let the file clobber a deliberately exported variable.
