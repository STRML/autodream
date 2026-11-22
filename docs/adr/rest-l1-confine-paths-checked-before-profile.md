# rest: every path is checked, and resolved, before it can reach a sandbox profile or a bind

Status: accepted · Date: 2026-11-21 · Code: `bin/l1-confine.sh` (`safe_path`, `resolve_path`, `profile_path`, `check_writable`, `check_protect`, `check_stage`, `check_all`)

## Context

The profile is text handed to `sandbox-exec -p`, and the bwrap argv names paths directly. A path that holds a quote or a newline can close the string and add a rule; a glob character becomes a pattern; a symlink as a writable path grants its target; a relative path means something different in the engine's cwd. The checks were added by the #241 review follow-ups (#244, `docs/plans/2026-11-21-l1-confine-hardening.md`).

## Decision

Before any path is used, whatever the tool:

- A writable path must be absolute, made only of the characters a profile can hold (`A-Za-z0-9._/@+~=,:` space and `-`: no glob, no quote), and must not itself be a symlink. A trailing `*` marks a prefix and is stripped before the check.
- A protected path (from `L1_CONFINE_PROTECT`, colon-separated) must be absolute and profile-safe. `$AUTODREAM_DIR` sits under `~/.claude` on a default install, so it must be denied after the state paths that cover it.
- The stage must not be a symlink and must exist; when `L1_STAGE_ROOT` is set it must resolve under that root.
- The checked path is resolved again, as the kernel sees it, before it enters the profile (`profile_path`). `resolve_path` resolves the part that exists, so a symlinked parent (`/tmp`, `/var`, `~` on some hosts) compares as the kernel sees it, and keeps the tail of a path that does not exist yet. A regular file cannot be `cd`'d into, so its parent is resolved and its name kept. The second check exists because a symlink can lead to a name the profile text cannot hold, which the check on the supplied path never saw.
- Globbing is off for the whole script (`set -f`). The one place a prefix rule needs it, the bwrap loop that expands `${p%*}*`, turns it on for that loop and off again.

A refusal is a message on stderr and exit 1; `engine-prefix` and `prefix` print no argv in that case.

## Consequences

A new field that reaches a profile or a bind gets the same checks first, or it is an injection point. Checking only the supplied path, not the resolved one, was the gap the second check closes. `tests/l1-confine.sh` pins the refusals (quote, newline, symlink, relative path, glob in a protected path, stage outside the staging root).
