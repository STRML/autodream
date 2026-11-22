# rest: a tag carries `harness` and an absolute `transcript` path

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-focus.sh` (`cmd_tag`), `bin/vault-notes.sh`

## Context

The line `autodream-focus.sh tag` writes is the Claude mod's line plus `harness` and, when known, `transcript` (the session file), so the nightly run can open a session that is not a Claude one. `bin/vault-notes.sh` turns pending tags into notes for L2, which will Read the file a note names. The tags file is a plain file anyone can edit, so the collector trusts a recorded transcript only if it is an absolute path to an existing `.jsonl` (CLAUDE.md, "The focus mod").

The nightly run reads from another working directory, so a relative `--transcript` recorded as given would point nowhere at 03:15.

## Decision

`cmd_tag` resolves a relative `--transcript` to an absolute path at write time (`cd` to its directory, `pwd -P`, plus the basename), and refuses the tag if it cannot. An empty transcript is omitted from the line; the `transcript` key is added only when set. The same applies to `--file` through `last`, which hands its file to `tag` as `--transcript`.

## Consequences

Do not record a path the collector would have to resolve against its own cwd. A new field on the line is ignored by the mod (which reads only what it knows) and must be taught to `vault-notes.sh` separately.
