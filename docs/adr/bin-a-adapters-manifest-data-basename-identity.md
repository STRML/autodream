# bin-a: an adapter's manifest is data read with jq, its identity is its directory basename, and containment is resolved, not assumed

Status: accepted · Date: 2026-11-21 · Code: `bin/adapters.sh` (`_adapter_ok`, `adapter_manifest_get`, `adapter_run`)

## Context

Dispatch builds a command path from an adapter name (`$root/$name/adapter.sh`). Three ways to get that wrong are easy to write:

- A manifest in a format whose parser is bash would execute arbitrary code as the user when sourced, and becomes an injection surface the moment a third-party adapter is a reasonable idea.
- If a manifest field could name its own directory, it would reintroduce the path construction that JSON parsing was adopted to remove. Two disagreeing identities (field and basename) are the state where a later reader picks the wrong one.
- A basename check is not containment: `adapters/evil` may be a symlink pointing anywhere on the filesystem.

## Decision

- The manifest is JSON, read with `jq`, never sourced. `$HOME` is the only interpolation, done by substitution (`${v//\$HOME/$HOME}`) rather than evaluation, so a manifest holding backticks yields literal backticks.
- Identity is the directory basename, never a manifest field. The manifest's `name` must agree with the basename; a mismatch is a load-time refusal, not a silently preferred value.
- `_adapter_ok` resolves both the adapter directory and the adapters root with `realpath` and refuses the adapter unless the real directory is still under the real root. Every check ahead of it passes for a symlinked directory.
- `jq -e` fails on unparseable JSON, so a malformed manifest is refused whole rather than partially trusted.
- The dispatchers (`adapter_manifest_get`, `adapter_run`) re-check the name with `_adapter_name_safe`, because the identity argument is only true if the functions that build the path enforce it. Every caller today passes a name that came through `adapters_list`, so this guards the third-party adapter that arrives later, not a live hole.

## Consequences

A manifest field can never become a path, and a plugin format whose parser is bash is not on offer. Do not switch the manifest to a sourced file, and do not let `name` choose a directory. See `docs/adr/bin-a-adapters-name-charset-enumerated.md` for the character rule the check uses and CLAUDE.md, "Several harnesses in one run", for how an accepted adapter becomes an enabled one.
