# bin-a: autodream-now.sh takes its install dir from the symlink's directory, not the repo's

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-now.sh` (`resolve_install_dir` call), `bin/lib-install-dir.sh`

## Context

`scheduler-label.sh` decides ownership by comparing a plist's runner dir against the install dir. A hardcoded default never matched a custom-path install (`./install.sh /custom`), so the `.ondemand` label silently left that install's namespace.

## Decision

The script resolves the install dir with `resolve_install_dir "${BASH_SOURCE[0]}"`, the same idiom as its siblings. `BASH_SOURCE` is left unresolved on purpose: the symlink's own directory is the install dir, while `BIN_DIR` (resolved through the symlink chain) points at the repo.

## Consequences

Do not pass `SELF` or `BIN_DIR` to the resolver: they name the repo, which carries no install marker. See `bin-a-lib-install-dir-one-resolver.md` for the resolution order.
