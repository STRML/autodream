# bin-b: the review agent pins the first usable claude, config before PATH

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`install_schedule`, `CLAUDE_BIN_ABS`, `eff_claude`)

## Context

`review.sh` preflights the exact binary path and aborts when `CLAUDE_BIN` is not executable. Its default, `$HOME/.local/bin/claude`, is wrong when claude lives elsewhere, so the installer must pass the real one. A config value is the user's explicit choice (a wrapper or custom claude) and `review.sh` restores env over config at run time, so the plist must not override it. A directory passes `-x` but `exec <dir>` fails at once and leaves a dead workspace (auditor 7.2 and 7.3).

## Decision

Candidates are tried in order: config `CLAUDE_BIN`, then the `claude` found on the cleaned PATH (`CLAUDE_BIN_ABS`). The first that is a regular file and executable wins. A config value that points at nothing therefore does not disable the agent while a working claude is on PATH. No usable candidate means the agent is skipped with a message.

## Consequences

The same `-f` and `-x` test applies to any new binary pinned in the plist.
