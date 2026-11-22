# bin-a: `pending-triage.sh` sources the user-edited config with nounset off, and the environment wins

Status: accepted · Date: 2026-11-21 · Code: `bin/pending-triage.sh` (config block)

## Context

The config is user-edited. A bare `source` under `set -u` kills the shell on one misspelled variable, before the summary prints. CLAUDE.md, "Bash traps this feature hit", records the same trap for `run.sh` and the helper scripts.

## Decision

The script saves `DREAMS_DIR` and `AUTODREAM_PENDING_DAYS` from the environment, runs `set +u`, sources the config, runs `set -u` again, then restores the saved values when they were set. A variable exported by the caller therefore beats the config.

## Consequences

Any new variable this script reads from the config needs the same save and restore, or the config will override a caller who set it on purpose.
