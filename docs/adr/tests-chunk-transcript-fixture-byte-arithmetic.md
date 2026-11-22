# tests-chunk-transcript: fixture sizes are exact byte counts, and one fixture exists to separate bytes from characters

Status: accepted · Date: 2026-11-22 · Code: `tests/chunk-transcript.sh` (`line`, `mk`, the `chunk: the limit counts bytes, not characters` case)

## Context

`bin/chunk-transcript.sh` cuts a transcript at line boundaries and measures the limit in bytes (`LC_ALL=C awk`). Every expected chunk count in the suite is arithmetic on line sizes and a limit. A fixture whose lines are 99 or 101 bytes still passes most cases, but the counts quietly stop meaning what the assertion says.

A multibyte line is the one case where a character count and a byte count give different chunk counts, so it is the only case that can tell the two implementations apart.

## Decision

- `line N` prints a line of exactly 100 bytes including its newline, padding by `84 - ${#N}` characters. The limits used in the cases (350, 250, 130) are chosen against that size.
- The multibyte case uses 60 two-byte characters, which is 120 bytes of content. At a 130-byte limit two such lines (2 x 123 bytes) do not fit together, so the correct answer is three chunks for three lines. A character count (2 x 63) would have put two lines in one chunk and returned two.

## Consequences

Changing the padding in `line`, or the character count in `mb`, changes every expected count. Recompute them rather than adjusting the assertions to the new output. Keeping the multibyte case at 60 characters and a 130-byte limit is what keeps it a mutation test for a switch from bytes to characters.
