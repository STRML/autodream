# bin-b: a tags file that cannot be read is reported as UNREADABLE, never as "no tags"

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`tag_pending` call and the tag branch of `collect`)

## Context

No tags file is the normal case and says nothing. A `tags.jsonl` that exists and will not read (permissions, a `jq` error), or a host with no `jq`, looks the same as no tags unless the failure is seen. The same rule as the iCloud placeholder and `overlap_measured` applies: a degraded measurement must say so. CLAUDE.md, "The focus mod", records it.

## Decision

- `collect` runs `tag_pending` into a temp file and tests its status. A process substitution would hide the exit status.
- On failure, or when `jq` is absent, it emits a `focus-tags - UNREADABLE` block, counts it under `unreadable:`, and manifests nothing, so the tags are tried again.
- `vault-tags-manifest.txt` is truncated on every run, tags file or not, so a stale one from an earlier run can never be archived.

## Consequences

macOS 15 ships `jq` in `/usr/bin`, so the no-`jq` test builds a PATH without it. `status` does not need `jq` (see `bin-b-vault-status-counts-lines.md`).
