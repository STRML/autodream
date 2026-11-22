# bin-b: the per-session and per-category counts are computed by rollup.sh, not by L2

Status: accepted · Date: 2026-11-21 · Code: `bin/rollup.sh` (the whole script; `session_hashes`)

## Context

L2 reads with Glob and Read, and both stop at 200 entries. A findings dir holds three files per session plus about 28 side files. On 2026-10-31 the dir held 2683 entries for 885 sessions, and the report counted from a 90-file sample and never saw `fanouts.tsv`.

## Decision

- `rollup.sh` writes `rollup.tsv`, `categories.tsv` and `findings.tsv`, and L2 counts from those. L2 opens a single `<hash>.json` only to quote evidence.
- The script reads only inputs it names exactly: `<hash>.json`, its `.stats.json` sidecar, `sessions-source.txt` and `fanouts.tsv`.
- `session_hashes` takes only files directly in the dir whose name is 12 lowercase hex digits plus `.json`, in `LC_ALL=C` order. Sidecars, `.served` and `.err` files, side files and anything under `outside-worklist/` never match.

## Consequences

A new side file L2 needs gets a named line in `PROMPT.md`, never a glob. CLAUDE.md, "Where state lives" (the `rollup.tsv` bullet), records the same incident and the 224-session fixture that `tests/rollup.sh` pins it against.
