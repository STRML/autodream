# bin-a: a project key is the physical path with every byte outside `[A-Za-z0-9-]` mapped to a dash, derived once in `lib-project.sh`

Status: accepted · Date: 2026-11-21 · Code: `bin/lib-project.sh` (`encode_project`, `canonical_project`)

## Context

Claude derives a project bucket name from the session's cwd by mapping everything outside `[A-Za-z0-9-]` to a dash, on the symlink-resolved physical path. Verified against real buckets on the host:

```
/Users/<u>/.claude                      -> -Users-<u>--claude
/private/var/folders/c2/29g..z_4tv..gn  -> -private-var-folders-c2-29g..z-4tv..gn
/Users/<u>/Documents/Personal Items/..  -> -Users-<u>-Documents-Personal-Items-..
/Users/<u>/../Personal House (39 Loring)/Improvements
                                        -> ..-Personal-House--39-Loring--Improvements
```

An encoder that maps only `/` breaks on all of them, and silently: the record still carries a cwd, so nothing counts it as unreconciled and the project just splits in two.

The first encoder was `tr '/._' '---'`, which is what an eyeball survey of dash-shaped bucket names suggests, and what a survey of this repo's own paths confirms, because none of them contain a space. Measured instead: of the 96 path-derived buckets under `~/.claude/projects` on the host, the three-character form gets 89 and the complement form gets all 96. Every miss is a space or a parenthesis. The host also carries the artifact of that bug: a stale `-Users-…-Personal Items-…-RAW` bucket holding an empty `memory/` beside the live `-Personal-Items-` one that holds the sessions. That is a project split in two, already on disk.

Non-ASCII, verified 2026-10-04 by running `claude -p` in a directory named `café-日本-😀`: Claude emits one dash per UTF-16 code unit. A BMP character (2- or 3-byte UTF-8) is one dash, and an astral character (4-byte UTF-8, a surrogate pair) is two.

## Decision

- `encode_project` ends in `tr -c 'A-Za-z0-9-' '-'`, the complement form. `LC_ALL=C` is load-bearing: `tr -c` complements the set, and under a UTF-8 collation `A-Za-z` is a wider set than the 52 ASCII letters. The complement then shrinks, and characters that must be mapped silently are not.
- `tr` is byte-oriented and would give one dash per byte, so `sed` first collapses each multi-byte sequence to the dashes Claude emits. Lead byte F0-F7 starts a 4-byte sequence (two dashes), E0-EF a 3-byte one and C0-DF a 2-byte one (one dash each). The 4-byte rule goes first, so a 4-byte sequence is not consumed as a 3-byte one plus a stray byte. The byte ranges are raw bytes through `$'..'`, because BSD `sed` has no octal escapes inside a bracket.
- The key is derived once, here, because every adapter must produce the same key for the same real directory. That makes one project out of two harnesses' work, and it is why the design has no reconciliation pass: deriving the key once at triage time removes the failure rather than fixing it.
- Claude records the physical path, so a session in `/tmp/foo` is stored under `-private-tmp-foo`. A harness that reported an unresolved cwd would produce `-tmp-foo` and group as a different project, so `canonical_project` resolves with `realpath` first. It exits 1 and prints nothing rather than encode something unresolved, because a wrong key splits a group and a silent split is what the function exists to prevent.
- `canonical_project` tests `[ -e "$1" ]` before `realpath`. GNU `realpath` resolves a missing leaf and BSD `realpath` refuses it, so the explicit test makes a missing path fail on both.

## Consequences

A change to the character set or to the multi-byte handling re-keys every project. Re-measure against the real buckets, and against a non-ASCII directory, before touching it. `tests/lib-project.sh` pins the cases above.
