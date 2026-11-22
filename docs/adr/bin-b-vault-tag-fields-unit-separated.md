# bin-b: per-tag fields are split on the unit separator, and the turn text is read on its own

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (the field extraction in the tag loop of `collect`)

## Context

`read` treats tab as IFS whitespace and collapses a run of tabs. A tag with an empty `cwd` or timestamp in the middle would shift every field after it. CLAUDE.md, "The focus mod", lists this under "`read` and tabs".

## Decision

`jq` joins the fields with `\u001f` (control characters inside a value are replaced with spaces first) and `IFS=$'\037' read` splits them. The turn text is fetched by a second `jq` call so it cannot disturb the columns. An empty `epoch` means the tag belongs to the report being built.

## Consequences

Do not switch the separator back to tab, even though the jq-side `clean` function also strips tabs from the key.
