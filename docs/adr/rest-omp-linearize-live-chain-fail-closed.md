# rest: the omp linearizer keeps only the live chain and fails closed

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/linearize.sh`

## Context

An OMP session file is an append-only tree. Every entry carries `id` and `parentId`, and backing out of a branch moves a leaf pointer instead of rewriting the file, so the file keeps every branch the user abandoned. Read line by line, it credits the user with work they threw away.

omp does not persist its in-memory leaf pointer. The last appended entry is what omp falls back to when it has none, so the last entry in the file is the live leaf.

An unparseable line can change which entry is last. That puts the walk on an abandoned branch, and a confident triage of rejected work is worse than one visibly skipped session.

The tree semantics and the fail-closed rule were worked out in STRML/cc-autodream#47. The script is a rewrite with its own fixtures (`tests/adapter-omp.sh`), not that code. The adapter shipped in #81 (aee73fa). CLAUDE.md, "The OMP adapter", has the user-facing record.

## Decision

The script keeps the chain from the live leaf back to the root, root first, behind one `autodream_meta` record. The jq program does four things in order: parse every line strictly, index entries by id, walk `parentId` from the last entry bounded by the entry count so a cycle ends, then insist the chain reaches a root. A chain that stops early cannot be shown to be the live conversation.

It fails closed with no output at all, and callers must skip the session on a nonzero exit instead of reading the raw file. Nothing is written to the destination on failure.

A format gate runs first. An OMP file opens with a title slot and then a session header whose `id` is a string. A Claude transcript has no such record, so the check is structural and not a guess.

Exit codes are the caller's contract:

| Code | Meaning |
|---|---|
| 0 | wrote dst |
| 1 | usage, unreadable input, jq missing, or dst is a directory |
| 2 | not an OMP session (no session header with a string id in the first lines) |
| 3 | produced no output |
| 4 | unparseable line, entry without a string id, a duplicated id, or a broken tree (cycle, or a parentId with no entry behind it) |

## Consequences

Any new refusal must exit 4 with nothing written, and a caller must never fall back to the raw file. A duplicated id is refused because ids index the tree, and a repeated one would let the later entry silently replace the earlier one. Before changing the walk, run `tests/adapter-omp.sh` and the `test_omp_*` and `test_window_omp_*` cases in `tests/run-all.sh`.
