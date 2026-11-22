# tests-adapters: the claude adapter suite traps signals because its deferral is bounded, the adapter's is not

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-claude.sh` (`cleanup`, `reap_delegate`, the EXIT/INT/TERM traps)

## Context

The suite parks a process on purpose: the FIFO test starts a `slim` whose first read waits for a writer that never comes. Cleanup used to sit on the last lines of the file, so a run that ended any other way (Ctrl-C, a harness timeout, an early exit) reached none of it and the delegate was reparented to init and blocked for good. Measured: 22 interrupted runs over about 90 minutes on 2026-08-26 left 66 `slim-transcript.sh` processes alive, still there nine days later, each holding a FIFO in a deleted temp dir.

`adapters/claude/adapter.sh` documents the opposite conclusion (no trap; see `bin-a-adapter-claude-no-signal-trap`, issue #57). Bash defers a trapped signal until the FOREGROUND child returns in both places, and a foreground `sleep` is not interruptible. Measured on bash 5.3.15 and `/bin/bash` 3.2.57, a trapped TERM sent 1s into `sleep 5` fires at t=5, while the same signal during `wait` fires at t=1.

## Decision

The suite installs EXIT, INT (exit 130) and TERM (exit 143) traps that reap the parked delegate and remove `$tmp`. The difference from the adapter is that the deferral is bounded here: every foreground child in this file is `sleep 0.05` or faster, so the worst case is a signal handled 50 ms late. The adapter's foreground child is the delegate itself, which blocks forever on the FIFO, so a trap there converts a prompt death into a hang.

## Consequences

Adding a foreground command that can block for long (a bare `sleep 5`, a read from a FIFO) to this file removes the bound and brings the orphans back. Never copy this trap into the adapter on the strength of this suite.
