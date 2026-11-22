# bin-b: the focus mod asks the writer where tags.jsonl is, and uses its own environment only as a fallback

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-focus/hooks/focus-lib.ts` (`tagsFileFromEnv`), `mods/autodream-focus/hooks/register.tsx` (`tagsFilePath`)

## Context

`bin/autodream-focus.sh` reads `$AUTODREAM_DIR/config`; the mod cannot source a shell file. A tags file named only in that config would be written by the script and invisible to the mod: no button would light, and pressing one again would take back a tag that was never shown. CLAUDE.md "The focus mod" notes `autodream-focus.sh path` exists for this reason.

## Decision

`tagsFilePath` runs `<script> path` (5 s timeout, with the `AUTODREAM_DIR` and `AUTODREAM_TAGS_FILE` the mod can see) and uses its stdout. When the script is not installed, exits non-zero, prints nothing, or throws, it falls back to `tagsFileFromEnv`, which resolves the way `bin/vault-notes.sh` does: an exported `AUTODREAM_TAGS_FILE` wins, else `AUTODREAM_DIR` (empty counts as unset) plus `tags.jsonl`.

## Consequences

The tests cover both branches (writer answers, writer cannot answer). The writer's `path` verb is part of this mod's contract.
