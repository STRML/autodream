# bin-b: root-probe refuses a root path containing ':' and shell-quotes the rest

Status: accepted · Date: 2026-11-21 · Code: `bin/root-probe.sh` (`consolidated_roots`, `--write-config`)

## Context

`SESSION_ROOTS` is colon-separated, and the scan side (`scan_roots` in `run.sh`) splits on `:` after the config has been sourced. `$AUTODREAM_DIR/config` is sourced by bash, so a root with spaces or shell metacharacters changes meaning unless quoted.

## Decision

- `consolidated_roots` skips any root containing `:` and says so on stderr, because the scan would split it into two paths.
- `--write-config` writes `SESSION_ROOTS=` through `printf '%q'`, so the sourced value is the exact joined list. The colon limit survives that quoting: `%q` protects the shell read, not the later split on `:`.

## Consequences

A profile directory with a colon in its path is never indexed, and the only trace is the stderr line. Supporting it needs a different separator on the scan side, which every `SESSION_ROOTS` consumer would have to change together.
