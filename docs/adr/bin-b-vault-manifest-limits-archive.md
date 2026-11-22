# bin-b: archive moves only the inbox files that collect recorded in its manifest

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`collect`, `archive_notes`)

## Context

Inbox files move to `processed/` after a successful report, so the inbox stays a to-do list and not a growing pile. A run takes about 10 minutes. A note written in that window and archived unread would be lost without a trace, and it is the note the user cared enough to write mid-run.

## Decision

- `collect` writes `vault-notes-manifest.txt`, one path per file it read (an expired note is listed too, since it has done its job).
- `archive_notes` moves exactly the manifest's files into `processed/<date>/`. A file that is not in the manifest stays in the inbox for the next run.
- A placeholder that iCloud has not downloaded is never manifested (see `bin-b-vault-icloud-materialize.md`).

## Consequences

CLAUDE.md, "What the consume gate actually has to check", covers when `archive` may run at all: only after a complete report written by this run, for the normal nightly date. Skipping the manifest and archiving the whole inbox is the shortcut this decision rules out.
