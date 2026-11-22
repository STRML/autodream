# bin-b: an installed script finds a newer helper through its own symlink target

Status: accepted · Date: 2026-11-21 · Code: `bin/session-stats.sh`, `bin/triage-candidates.sh`, `bin/threads.sh` (the `portable.sh` and `lib-flock.sh` sourcing)

## Context

`install.sh` symlinks each script into `~/.claude/autodream/`. Updating the checkout updates every installed script at once, but a helper added by the update (`lib-flock.sh`, `portable.sh`) has no link until `install.sh` runs again. The nightly must not stop in between. CLAUDE.md, "Which code actually ran", describes the same exposure.

## Decision

Each script first looks for the helper beside itself. If it is missing, it resolves its own symlink and looks beside the target (the checkout).

## Consequences

A new helper needs a link in `install.sh` for the normal case. This fallback only covers the window between a merge and the next install.
