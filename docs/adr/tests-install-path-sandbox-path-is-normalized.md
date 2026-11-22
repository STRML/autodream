# tests-install-path: the sandbox path is normalized through cd and pwd before the plist PATH is compared

Status: accepted · Date: 2026-11-22 · Code: `tests/install-path.sh` (`new_sandbox`)

## Context

macOS `TMPDIR` ends in a slash, so `mktemp -d "${TMPDIR:-/tmp}/ccad-ip.XXXXXX"` returns a path holding `//`. `install.sh` writes the directories it finds through `cd` and `pwd`, which collapse the double slash, so a comparison against the raw `mktemp` path misses on every directory the test expects to find in the plist PATH.

## Decision

`new_sandbox` reassigns `SANDBOX=$(cd "$SANDBOX" && pwd)` right after `mktemp`, so every expected path is built in the same form the installer writes.

## Consequences

Build any path the plist must contain from `$SANDBOX`, not from `$TMPDIR`. Removing the normalization makes the PATH assertions fail on macOS and pass on Linux, where `TMPDIR` has no trailing slash.
