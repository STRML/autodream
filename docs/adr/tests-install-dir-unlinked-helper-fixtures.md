# tests-install-dir: an installed script must start before install.sh links its newest helper

Status: accepted · Date: 2026-11-22 · Code: `tests/install-dir.sh` (`linkdir` and `thrdir` fixtures, the notify.sh note)

## Context

A merge updates the symlinks into the checkout at once. A helper's own link appears only when `install.sh` runs again. For that window an installed script finds its sibling helpers through the link it was started by and must still start (see `bin-b-install-helper-link-fallback.md`).

`notify.sh` has no behavioural row here: its usage check runs before the resolver, and any argument that passes the usage check raises a real banner. It is covered by the structural check (it calls `resolve_install_dir`, carries no marker test) only.

## Decision

- `linkdir` links the scripts but not `lib-install-dir.sh`, and each script is started and must print its usage or normal output, not "No such file".
- `thrdir` links every helper `threads.sh` needs except `lib-flock.sh`, so the only way it can start is by finding `lib-flock.sh` in the directory its own link points at.

## Consequences

When a script gains a new sourced helper, add a fixture that links everything else and leaves out only that helper. A fixture that leaves out several helpers cannot say which fallback broke.
