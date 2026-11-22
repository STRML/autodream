# runsh: the runner's symlink walk is capped at 8 hops

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`RUNNER_SRC`, `runner_hops`)

## Context
A symlink can point at another symlink, and a target can be relative to the link's own directory rather than to `$PWD`. A cycle must not hang the run. A cap has to be reachable in a test: macOS refuses to execute anything behind 16+ links (ELOOP), so a cap at or above 16 could never fire on a script that got far enough to run this code, and an untestable guard is a guess. Linux allows 40, where a larger cap could genuinely fire.

## Decision
The loop follows at most 8 links, resolving a relative target against the link's directory. A real install is one hop.

## Consequences
Do not raise the cap to a "rounder" number. A walk that stops while still on a symlink means it gave up; `runner-provenance-stamp` depends on that (it stamps no sha for a still-linked path).
