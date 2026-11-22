# bin-b: reshape drops Claude Code bookkeeping by a denylist of record types and attachment subtypes, never an allowlist

Status: accepted · Date: 2026-11-21 · Code: `bin/slim-transcript.sh` (`reshape_defs`: `noise`, `noise_attachment`, `reshape`)

## Context

Measured 2026-10-02 on a 3,479-line session: 36% of the lines were conversation, 24% hook and reminder attachments and 21% `mode`, `permission-mode`, `last-prompt` and `bridge-session` records. The head/tail pass is positional, so on the raw stream it spent its whole budget on those and the worker saw about 2% of the conversation. On 24 hours of this host's Claude transcripts, `hook_success` and `total_tokens_reminder` alone were 12,000 and 8,000 of about 33,000 attachments.

Claude Code writes `message` before `timestamp`, so the 400-character line cut dropped the timestamp from a third of the lines. The envelope (`parentUuid`, `uuid`, `cwd`, `sessionId`, `version`, `gitBranch`, `userType`, `toolUseResult`, message id, model, usage) used about 185 characters before the content began.

## Decision

- With `AUTODREAM_SLIM_RESHAPE=1`, a denylist drops bookkeeping record types and hook and reminder attachment subtypes, plus `system/stop_hook_summary` and `system/turn_duration`.
- It is a denylist, never an allowlist of user and assistant. OMP transcripts come through this script too, and an allowlist would delete every one of their records, leaving an empty transcript and a findings list that reads like a quiet night. It is a denylist of attachment subtypes as well: keeping an unknown subtype costs bytes, dropping one silently costs signal.
- Kept on purpose: `attachment/queued_command` (the user typing mid-turn, the only place that text lives), `attachment/skill_listing` (SESSION_TRIAGE.md names it for the StructuredOutput rule and `missed_skill`), every `system` record but the two above (`compact_boundary` is the compaction marker), `pr-link` and summary records.
- Each kept Claude record is rebuilt with `type` then `timestamp` first and only the fields triage reads. A key is added only when the source has it, because inventing a null is the bug the guards in the main program exist to stop. The thinking `signature` is a base64 blob that filled whole lines.
- OMP and unknown-schema records come out of the reshape unchanged.

## Consequences

Before dropping a record type, grep the prompts for it: the first draft's denylist caught `queued_command`. CLAUDE.md, "Reading a long session: chunked triage", has the replay figures.
