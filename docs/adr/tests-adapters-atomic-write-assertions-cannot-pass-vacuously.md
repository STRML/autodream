# tests-adapters: the atomic-write assertions are shaped so a leaking or direct-writing adapter fails them

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-contract.sh` (`normalize`, `stats`, `slim`, directory-destination and read-only-directory groups), `tests/adapter-claude.sh` (`normalize` temp check)

## Context

Adapter subcommands that write a file go through a temp and a rename (`bin-a-adapter-claude-atomic-destination-write`, `docs/design/unify-harness-adapters-2026-08-23.md`). Several assertions for it passed against the broken implementations they were meant to catch.

## Decision

- **A glob, not a literal.** `mktemp` creates `<out>.tmp.XXXXXX`, so a check for `<out>.tmp` names a path nothing creates and passes against an adapter that leaks a temp on every call. The check is `set -- "$out".tmp*` then `-e "$1"`, the bash 3.2-safe way to ask whether a glob matched. It is `.tmp*` and not `.tmp.*`: anchoring on `.tmp.` stops seeing an adapter that leaks the bare `<out>.tmp`, the name the contract prose uses and the likeliest one a new adapter picks. The same mistake was made three times (twice in the contract, once in the claude suite).
- **A directory destination is refused.** `mv -f "$t" "$2"` with an existing directory at `$2` moves the temp inside it and returns success, so the adapter reports a write it did not perform and plants a random file in a directory the caller chose. The delegates once refused this on their own (a `>` redirect to a directory fails); the wrap removed that and has to restore it.
- **A read-only destination directory** is how the property "slim and stats do not write the destination directly" is tested, because the interrupt window cannot be opened from a unit test. The design doc requires it of every writing subcommand; the claude adapter had handed `slim` and `stats` straight to scripts that wrote the destination, so an interrupted slim left a non-empty, footer-less transcript that the caller's `-s` check accepts and sends to L1 as a whole session.
- **What both halves prove.** A pre-existing SENTINEL file in the destination rules out a direct writer (truncating in place needs no directory write, while a temp-and-rename writer cannot create its temp). The exit status rules out reporting success while writing nothing. Together they are narrower than the section name: an adapter that rejects an unwritable destination up front, without trying a temp, also passes, and that is fine because it satisfies the property (no partial write, no false success). Two review seats read a stronger guarantee into the original prose.

## Consequences

Do not weaken the glob or drop the SENTINEL. Do not describe the read-only test as proving interrupt safety. The test skips as root because a read-only directory proves nothing there.
