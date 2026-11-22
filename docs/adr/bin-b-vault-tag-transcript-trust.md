# bin-b: a tagged transcript path is trusted only as an absolute, readable .jsonl, and session ids are never put in a find pattern raw

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`tag_transcript`, the transcript lookup in `collect`)

## Context

L2 holds Read and opens what the note names. `tags.jsonl` is a plain file anyone can edit. The Claude button records no transcript, and OMP and Codex keep theirs outside the Claude roots. A relative path would be read from this run's working directory and could name a different file than the one the tag was made against.

## Decision

- A transcript the harness recorded is used only when it is an absolute path to an existing, readable `.jsonl`.
- Otherwise `tag_transcript` looks for `<session>.jsonl` (depth 2) under the roots resolved the way `run.sh` resolves them: `SESSION_ROOTS`, then `PROJECTS_DIR`, then every `~/.claude*/projects`. The tag was made under whichever config dir that session ran in.
- The session id comes from the same editable file, so anything outside `[A-Za-z0-9._-]` is refused before it reaches a `find -name` pattern.
- A transcript that cannot be found prints nothing, and the note says it was not found under the session roots.

## Consequences

`bin/autodream-focus.sh` makes `--transcript` and `--file` absolute when it records them, because the nightly run reads from another directory. CLAUDE.md, "The focus mod", covers that side.
