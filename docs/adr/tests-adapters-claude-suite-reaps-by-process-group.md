# tests-adapters: the claude adapter suite reaps its parked delegate by process group, never by name

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-claude.sh` (`reap_delegate`, the `set -m` launch of the FIFO test)

## Context

Two rounds of #62 review went into reaping the parked delegate with `pkill -f`, which is the wrong tool twice over. It matches an unanchored regex, so an interpolated `$TMPDIR` of `/tmp/a[b]` silently matched nothing. Once `$TMPDIR` was out of the pattern, the `mktemp` suffix identified the run only probabilistically. A pattern names processes by what they look like; a process group names exactly the ones this run started.

## Decision

`set -m` around the launch gives the adapter its own process group (pgid equals pid), so the delegate and the two bash subshells beneath it inherit that pgid. `reap_delegate` sends TERM and then KILL to the negative pid, which reaches all of them in one call and keeps working after the adapter dies, because a reparented child keeps its process group. Monitor mode is on only around the launch and is restored right after, because job control changes behaviour for everything that follows.

## Consequences

Do not replace the group kill with a name match. Do not leave `set -m` on for the rest of the file: it changes how background jobs and signals behave in every later test.
