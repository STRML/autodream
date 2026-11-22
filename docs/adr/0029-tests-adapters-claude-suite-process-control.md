# 0029: adapter-claude suite: trap, process group and SIGTERM handling

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-claude.sh` (`ps_usable`, the FIFO interrupt test), `tests/adapter-claude.sh` (`reap_delegate`, the `set -m` launch of the FIFO test), `tests/adapter-claude.sh` (`cleanup`, `reap_delegate`, the EXIT/INT/TERM traps)

## the SIGTERM test asserts responsiveness and polls process state, and does not assert temp cleanup

### Context

The interrupt test guards two properties: the temp-and-rename wrap keeps a partial write out of the destination when a run is killed, and the adapter still dies when signalled. It does not assert that the temp is cleaned up. That would demand a signal trap, and a trap makes things worse: bash defers a trapped signal until the foreground child returns, so the adapter ignores SIGTERM for as long as the delegate runs. The version that asserted temp cleanup hung for the full timeout against exactly that fix and left orphaned delegates. The stale temp is tracked as an issue; the responsiveness assertion is what stops a reader from "fixing" the leak the obvious way (`docs/adr/0003-adapters-and-engines.md#the-stats-and-slim-wrappers-install-no-signal-trap-and-a-killed-runs-temp-file-is-swept-by-the-runner`).

### Decision

- A FIFO makes the interrupt deterministic: `[ -r ]` on it succeeds, the delegate starts, and its first read blocks with no writer, which parks the adapter after `mktemp` and before the rename.
- The test polls on a real interval for the temp to APPEAR before signalling and asserts it existed. A busy spin returned before the adapter reached `mktemp`, and killing that early made the assertion vacuous: it passed against the untrapped code exactly once.
- It polls for the adapter to go away instead of a bare `wait`, which on a process that ignores the signal hangs the suite instead of failing it.
- It reads the process STATE (`ps -o state=`), not `kill -0`. An exited child stays a zombie until the shell reaps it, and `kill -0` succeeds on a zombie, so a `kill -0` poll fails on a busy CI machine and passes locally. Empty means gone; `Z` means exited and not reaped. Both are termination.
- `ps_usable` asks `ps` about the suite's own live shell. An empty read means either "process gone" or "ps cannot run" (a sandbox answers `Operation not permitted`); folding the second into the first made the assertion pass without testing anything. An unusable `ps` FAILS the assertion rather than skipping it, since this check is what stops a trap being re-added on exactly the hosts where `ps` is restricted.

### Consequences

Do not add a temp-cleanup assertion, replace the state read with `kill -0`, or turn the unusable-`ps` failure into a skip.

## the claude adapter suite reaps its parked delegate by process group, never by name

### Context

Two rounds of #62 review went into reaping the parked delegate with `pkill -f`, which is the wrong tool twice over. It matches an unanchored regex, so an interpolated `$TMPDIR` of `/tmp/a[b]` silently matched nothing. Once `$TMPDIR` was out of the pattern, the `mktemp` suffix identified the run only probabilistically. A pattern names processes by what they look like; a process group names exactly the ones this run started.

### Decision

`set -m` around the launch gives the adapter its own process group (pgid equals pid), so the delegate and the two bash subshells beneath it inherit that pgid. `reap_delegate` sends TERM and then KILL to the negative pid, which reaches all of them in one call and keeps working after the adapter dies, because a reparented child keeps its process group. Monitor mode is on only around the launch and is restored right after, because job control changes behaviour for everything that follows.

### Consequences

Do not replace the group kill with a name match. Do not leave `set -m` on for the rest of the file: it changes how background jobs and signals behave in every later test.

## the claude adapter suite traps signals because its deferral is bounded, the adapter's is not

### Context

The suite parks a process on purpose: the FIFO test starts a `slim` whose first read waits for a writer that never comes. Cleanup used to sit on the last lines of the file, so a run that ended any other way (Ctrl-C, a harness timeout, an early exit) reached none of it and the delegate was reparented to init and blocked for good. Measured: 22 interrupted runs over about 90 minutes on 2026-08-26 left 66 `slim-transcript.sh` processes alive, still there nine days later, each holding a FIFO in a deleted temp dir.

`adapters/claude/adapter.sh` documents the opposite conclusion (no trap; see `docs/adr/0003-adapters-and-engines.md#the-stats-and-slim-wrappers-install-no-signal-trap-and-a-killed-runs-temp-file-is-swept-by-the-runner`, issue #57). Bash defers a trapped signal until the FOREGROUND child returns in both places, and a foreground `sleep` is not interruptible. Measured on bash 5.3.15 and `/bin/bash` 3.2.57, a trapped TERM sent 1s into `sleep 5` fires at t=5, while the same signal during `wait` fires at t=1.

### Decision

The suite installs EXIT, INT (exit 130) and TERM (exit 143) traps that reap the parked delegate and remove `$tmp`. The difference from the adapter is that the deferral is bounded here: every foreground child in this file is `sleep 0.05` or faster, so the worst case is a signal handled 50 ms late. The adapter's foreground child is the delegate itself, which blocks forever on the FIFO, so a trap there converts a prompt death into a hang.

### Consequences

Adding a foreground command that can block for long (a bare `sleep 5`, a read from a FIFO) to this file removes the bound and brings the orphans back. Never copy this trap into the adapter on the strength of this suite.
