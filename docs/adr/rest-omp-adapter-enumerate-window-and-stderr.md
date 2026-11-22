# rest: omp enumerate is an mtime window and nothing more, and keeps find's stderr

Status: accepted · Date: 2026-10-04 · Code: `adapters/omp/adapter.sh` (`enumerate`)

## Context

The adapter contract is `enumerate <root> <from> <to>`, filtered on mtime. Since #113/#119 the runner places a session in a report day by the timestamps inside the transcript (`bin/session-window.sh`), not by file mtime, and passes a `to` far in the future (the report day plus five years) so the mtime test becomes a lower bound only: a file last written before the day began cannot hold a record from it. The decision and its reasoning are in `bin-a-adapter-claude-enumerate-mtime-window-and-stderr.md` and CLAUDE.md, "Which day a session belongs to".

`find` exits 1 for an unreadable directory, and the runner has to tell a partial corpus from a failed root on that status.

## Decision

- The adapter never learns about the in-transcript window. `$2` and `$3` are an mtime window and nothing more, which keeps the adapter contract free of any knowledge of it.
- `find`'s stderr is not redirected, so the runner sees the exit status and the message and can count a partial root.

## Consequences

Adding `2>/dev/null` here would turn every unreadable directory into a silently short corpus. Putting window logic in the adapter would duplicate `session-window.sh` per harness.
