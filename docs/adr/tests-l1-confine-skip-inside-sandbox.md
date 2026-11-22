# tests-l1-confine: the real-confinement cases skip where a sandbox cannot start

Status: accepted · Date: 2026-11-22 · Code: `tests/l1-confine.sh` (the probe-gated real-confinement cases)

## Context

`sandbox-exec` cannot start inside another sandbox (`sandbox_apply: Operation not permitted`), which is how the Claude Code sandbox and some CI runners look to the suite. `CLAUDE.md` ("A host with no working sandbox says so") records the same constraint for the suite as a whole: `AUTODREAM_L1_CONFINE=0` is exported because the mock engines write anywhere, and the confinement tests turn it back on.

## Decision

The shim cases (no tool on PATH, a tool that rejects the profile, a tool that confines nothing, profile text, refused paths) always run. The cases that need a working sandbox run only when `bin/l1-confine.sh probe` answers `yes`; otherwise they print a skip line instead of failing.

## Consequences

A red result here means the helper is wrong, never that the host cannot sandbox. The cost is that on a host nested in another sandbox the real-confinement assertions never run, so `tests/l1-confine-real.sh` (outside any sandbox) remains the only check of the real engine under the profile.
