# tests-adapters: the SIGTERM test asserts responsiveness and polls process state, and does not assert temp cleanup

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-claude.sh` (`ps_usable`, the FIFO interrupt test)

## Context

The interrupt test guards two properties: the temp-and-rename wrap keeps a partial write out of the destination when a run is killed, and the adapter still dies when signalled. It does not assert that the temp is cleaned up. That would demand a signal trap, and a trap makes things worse: bash defers a trapped signal until the foreground child returns, so the adapter ignores SIGTERM for as long as the delegate runs. The version that asserted temp cleanup hung for the full timeout against exactly that fix and left orphaned delegates. The stale temp is tracked as an issue; the responsiveness assertion is what stops a reader from "fixing" the leak the obvious way (`bin-a-adapter-claude-no-signal-trap`).

## Decision

- A FIFO makes the interrupt deterministic: `[ -r ]` on it succeeds, the delegate starts, and its first read blocks with no writer, which parks the adapter after `mktemp` and before the rename.
- The test polls on a real interval for the temp to APPEAR before signalling and asserts it existed. A busy spin returned before the adapter reached `mktemp`, and killing that early made the assertion vacuous: it passed against the untrapped code exactly once.
- It polls for the adapter to go away instead of a bare `wait`, which on a process that ignores the signal hangs the suite instead of failing it.
- It reads the process STATE (`ps -o state=`), not `kill -0`. An exited child stays a zombie until the shell reaps it, and `kill -0` succeeds on a zombie, so a `kill -0` poll fails on a busy CI machine and passes locally. Empty means gone; `Z` means exited and not reaped. Both are termination.
- `ps_usable` asks `ps` about the suite's own live shell. An empty read means either "process gone" or "ps cannot run" (a sandbox answers `Operation not permitted`); folding the second into the first made the assertion pass without testing anything. An unusable `ps` FAILS the assertion rather than skipping it, since this check is what stops a trap being re-added on exactly the hosts where `ps` is restricted.

## Consequences

Do not add a temp-cleanup assertion, replace the state read with `kill -0`, or turn the unusable-`ps` failure into a skip.
