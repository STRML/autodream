# tests-adapters: an omp skill read counts as use, matched by file, and the fixtures copy real shapes

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-omp.sh` (the `skills_invoked` and `skills_authored` groups; helpers `RS`, `RB`, `RR`, `RD`)

## Context

omp has no Skill tool: the model loads a skill with `read skill://<name>` or a read of `<dir>/<name>/SKILL.md`. Of 739 transcripts modified since 2026-10-27, 2 held a `skill-prompt` record while 16 read `skill://<name>` and 18 read a SKILL.md path, so a detector that saw only `skill-prompt` read `skills_invoked_count` as 0 almost everywhere (CLAUDE.md "The OMP adapter"). Authoring detection (#179) first matched by skill name.

## Decision

- The fixtures copy real shapes: a main session writes a read as a start record (`data.toolCallId`, `data.args.path`) and as a block (`id`, `arguments.path`); an advisor writes the block alone.
- A SKILL.md the session also edits is authoring, not use. A hashline edit's start record has no `args` (279 of 629 recent edit records); its path is only in the block's `[path#HASH]` header, and it is relative while the read is absolute. The session cwd resolves the relative path.
- The match is by FILE, not skill name. Two skills with one name in different roots do not mask each other; a worktree copy edited while the main checkout's copy is read is the 2026-10-30 aim-configs session. Shapes covered: hashline edit, edit and write with an absolute or `~` path, a read with a line selector, and a `~` path, `.`, `..` and a doubled slash naming the same file as the absolute path.
- A path that cannot be resolved (no cwd in the header, no `HOME` for `~`, a URL) falls back to the name match, as before #179. Two absolute paths are still compared as files.
- A SKILL.md fetched from the web (the 2026-09-27 forks-omp session) is being installed or inspected, not invoked (#185). An earlier fixture hid it only because the session also wrote the file; one that fetches without writing used to count. File-backed reads through omp's resolvers (`file://`, `memory://`, `skill://`) and plain paths still name a skill.

## Consequences

A fixture where the edit and the read use the same string cannot tell file matching from name matching. Keep the relative-header and cross-root cases.
