# rest: a tags file that will not read is a refusal, an add is one append, and only a take-back replaces the file

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-focus.sh` (`cmd_tag`, `fingerprint`)

## Context

Taking a tag back rewrites the whole file, so reading "could not read" as "empty" would replace every tag with the one being added. Only a file that does not exist is empty (CLAUDE.md, "The focus mod": "A read that fails must never lead to a write").

The first version built every write as a copy and a rename, with the copy made by a `{ cat; printf; } > tmp || die` group. Bash ignores errexit inside a group on the left of `||`, and the group's status is its last command's, so a `cat` that failed part-way was hidden by the `printf` after it and the rename replaced every tag with a partial copy. That was the P0 the gate raised on the first version of the OMP and Codex writer. Adding a tag now needs no copy at all.

The Claude mod used to rewrite the file itself, without the script's lock. A copy of that old mod can still be in use.

## Decision

- A tags file that exists and is not a readable regular file, or does not parse, makes the script die with `nothing was changed`. Only an absent file counts as empty.
- Lines the script does not understand are kept as they stood: untagging drops only the lines whose parsed `.id` matches, found by 1-based line number (any number of them, in case of a hand edit), and an add never touches existing lines.
- An add is one `O_APPEND` write of the line, preceded by a newline when the last byte of the file is not one (a torn last line), in the same write, so the new tag is not glued onto the torn one. It cannot drop another writer's line even if that writer takes no lock, and there is no copy to come out partial.
- A take-back is a temp file in the same directory and one `mv`. The cksum fingerprint is taken before the copy and checked again just before the rename, and a change makes the script refuse. The lock holds off every cooperating writer; the fingerprint is for a writer that takes no lock.
- Tagging the same turn again is the toggle: it takes the tag back, as the mod's button does.

## Consequences

The one race nothing here can close is an old unlocked writer against a take-back: the fingerprint narrows it, it does not remove it. Never build a copy as a brace group on the left of `||`. Any new write path must start from "a failed read refuses".
