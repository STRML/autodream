# bin-b: triage-dream.sh probes the config in a subshell before sourcing it, and the caller's environment wins

Status: accepted · Date: 2026-11-21 · Code: `bin/triage-dream.sh` (config block)

## Context

Sourcing a user-edited file under `set -u` kills the shell with its error hidden, so a bad config fails the pass with no explanation. See CLAUDE.md, "Bash traps this feature hit, all of them silent". `run.sh` follows the same rule.

## Decision

A throwaway subshell sources the config with `set -u` first and its stderr is captured. On failure the script logs `WARNING: ignoring <file>: <error>` and carries on. On success it snapshots `export -p`, sources the config with `set -a`, and replays the snapshot, so a variable the caller exported beats the config.

## Consequences

Keep the three steps together. `set -a` is what lets helper processes see a config key, and the replay is what lets a caller disable a feature by exporting an empty value.
