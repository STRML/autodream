# rest: remote-sync refuses a bad label, host or path before any ssh, and uses builtins until then

Status: accepted · Date: 2026-11-21 · Code: `bin/remote-sync.sh` (argument checks, `usage_invalid`)

## Context

The label names a directory under `remote/` and a lock, so a label with a slash, a dot-only name or an odd character could write outside the mirror root. A host that starts with `-` would reach ssh as an option. The path reaches the remote shell, and openrsync does not quote it, so a character outside what a projects path needs could be interpreted there. The runner validates its own config the same way (`runsh-remote-sync-entry-validation`); the helper repeats the checks because it is also run alone.

## Decision

Before any ssh or rsync the helper refuses, with `invalid (<why>)` and exit 2: a wrong argument count, a label outside `[A-Za-z0-9._-]+` or equal to `.` or `..`, a target with no `:`, a host that is empty, starts with `-` or holds a character outside `[A-Za-z0-9._@-]`, a path that is empty, starts with `-` or holds a character outside `[A-Za-z0-9._/~+-]`, and an empty mirror. Everything up to the `command -v` checks uses builtins only, so a PATH without rsync or ssh is reported (`failed (rsync not found)`, `failed (ssh not found)`) and not crashed on.

## Consequences

Widening the path character set widens what openrsync hands the remote shell. A missing `err-cause.sh` beside the script (looked up through the symlink `install.sh` makes) is `failed (err-cause.sh not found beside remote-sync.sh)`, not a crash (`bin-b-install-helper-link-fallback`).
