# tests-with-pty: the pty wrapper sends one best-effort end-of-file and reports exec failure plainly

Status: accepted · Date: 2026-11-22 · Code: `tests/with-pty.py` (`main`)

## Context

`with-pty.py` runs a command with a pseudo-terminal as its stdin, stdout and stderr, whatever the caller's own are. BSD `script -q /dev/null cmd` does the same job but calls `tcgetattr` on its own stdin and dies with "Operation not supported on socket" when handed a socket or a closed descriptor.

- In the child after `pty.fork`, stderr is the pty. An exec failure printed as a traceback would arrive in the test's output as terminal noise.
- A program that reads its terminal would otherwise wait forever for input.
- The newline and `^D` are written in canonical mode, once the child has had time to exec. A program that flushes its terminal input after that point (readline does) discards them, and one that reads its terminal would then wait.

## Decision

- An `OSError` from `execvp` prints `with-pty: cannot run <cmd>: <reason>` and exits 127, the shell's status for a command that cannot be run.
- After a 0.2 second sleep the parent writes `"\n\x04"` to the master. The newline completes a line and `^D` at the start of a line is end-of-file. A write error means the child already exited and is ignored.
- Output is copied to the parent's stdout until EIO and the exit status is the child's.

## Consequences

The EOF is best effort and covers the commands the suite runs. A command that flushes terminal input needs another way to be driven.
