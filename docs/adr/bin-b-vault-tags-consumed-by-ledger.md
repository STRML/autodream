# bin-b: tags are consumed by appending to a ledger, never by editing tags.jsonl

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`archive_tags`)

## Context

A tag is written by a session that can be open at any hour and consumed by a run that cannot see the session. The writers of `tags.jsonl` (the mod, `bin/autodream-focus.sh`) rewrite it, possibly from an open session at 03:15. A second writer editing the same file would race them. CLAUDE.md, "The focus mod", describes the two-file design.

## Decision

- `archive_tags` appends `<id><TAB><report date><TAB><taggedAt>` to `tags-consumed.txt`. This script is the only writer of that ledger. "Pending" is the tags file minus the ledger.
- It records only the keys that `collect` put in `vault-tags-manifest.txt`, so a tag made while the run was in flight is read by the next one.
- A rerun of the same date does not record a tag twice: a ledger row matches on id and `taggedAt`.
- A failed append leaves the tag pending and says so.
- Tags are consumed by `archive` under the same gates as an inbox note, and never by `collect`.

## Consequences

Deleting `tags-consumed.txt` makes every tag due again for the next report. The ledger only grows.
