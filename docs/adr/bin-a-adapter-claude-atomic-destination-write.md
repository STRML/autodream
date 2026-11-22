# bin-a: adapter subcommands write through a unique temp in the destination directory, refuse a directory destination, and verify a regular file afterwards

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`normalize`, `stats|slim`), `adapters/_fixture/adapter.sh` (`normalize`, `stats`, `slim`)

## Context

The adapter contract (`docs/design/unify-harness-adapters-2026-08-23.md`, "Every subcommand has a named skip path and atomic output") says a failed subcommand leaves no output. A half-written file that a later step reads as a whole session is worse than no session. For `stats` and `slim` the delegates write the destination directly (`slim-transcript.sh` in two steps, a `>` for the body and a `>>` for the footer), so an interruption leaves a non-empty file with no footer, which the caller's `-s` check accepts as a whole session. The atomicity lives in the adapter and not in those scripts because both have callers outside this seam.

## Decision

- Write to `mktemp "$2.tmp.XXXXXX"` in the destination directory, `mv -f` it onto `$2` on success, and remove it on failure. A fixed `"$2.tmp"` is a shared name: two invocations writing the same output would clobber or remove each other's temp file and leave the result from the wrong one, or none.
- Refuse a directory at the destination before any work. `mv -f "$t" "$2"` would move the temp inside it and return success, so the adapter would report a write it never performed and leave a randomly named file in the caller's directory. The delegates used to reject this themselves, because a `>` redirection to a directory fails; wrapping them removed that.
- After the `mv`, verify `$2` is a regular file and remove the stray otherwise, because the guard is a check-then-act: something can create a directory at `$2` between the two, and `mv` then moves the temp inside it and returns 0. macOS has no `mv -T`. Verified by deleting the guard: the post-condition alone still satisfies the directory-destination contract test, so it is a real backstop. The guard stays because it fails before any work and stops a file appearing inside the caller's directory even briefly.
- The fixture adapter carries the same shape so the contract test exercises it against a second implementation.

## Consequences

This narrows the race and does not close it. A sequence that creates a directory at `$2` after the guard, lets `mv` move the temp inside, then replaces `$2` with a regular file before the check, still reports success with the output elsewhere. Closing that needs an atomic rename-if-not-a-directory, which is `renameat2` on Linux and does not exist on macOS, where this runs. Winning any of these needs write access to the findings dir, at which point the dir is already the attacker's; the checks exist because silent wrong success is the failure this repo keeps getting caught by, not because there is a threat model. A fourth layer would not close it either. Keep both checks: the guard fails early, the post-condition backstops the race.
