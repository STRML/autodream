# bin-b: the store and sibling helpers resolve through the script's own link, with the link target as fallback

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`sibling`, `resolve_install_dir`), `bin/session-window.sh`

## Context

`install.sh` links each script into the install's own `AUTODREAM_DIR`. A merge updates the links at once, but a newly added helper only gets its link when `install.sh` runs again.

A bare invocation (`status`, `clear`, or the early empty-night path in `run.sh`) has no `AUTODREAM_DIR`, and the legacy `~/.claude/autodream` would read the wrong store on an install elsewhere (Codex review of 232c94c).

## Decision

- `sibling` looks beside the invoked path, then beside the target of its symlink. Same rule as `bin-b-review-sibling-lookup-through-symlink.md`; `session-window.sh` applies it to `portable.sh`.
- The store is found by `resolve_install_dir` (`lib-install-dir.sh`): the install the script was linked into when that directory carries a `config` or `l1-no-advisor.yml`, with the legacy directory as the last resort. `run.sh` passes `AUTODREAM_DIR` at its call sites.

## Consequences

`tests/install-dir.sh` runs `question-streaks.sh` from a link directory with no helper links. `tests/report-format.sh` requires the `. "$_rf"` source lines to keep that shape.
