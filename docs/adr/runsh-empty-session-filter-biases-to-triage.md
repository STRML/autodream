# runsh: the empty-session filter drops only provably empty sessions and keeps anything it cannot parse

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`filter_empty_sessions`, `session_is_substantive`)

## Context

Most of a quiet night's corpus is auto-opened or aborted sessions with no user input: observed ~150 of 163 files on 2026-05-30 were single-line `ai-title` shells. Each costs an L1 worker for zero signal. But dropping a real session silently is worse than one wasted call.

## Decision

A session is SUBSTANTIVE if it holds at least one `user` turn that is not `isMeta:true`. `session_is_substantive` returns 1 (skip) only when `jq -s` parses the file and finds none; an unreadable or unparseable file is kept (returns 0). The predicate reads both transcript shapes, because the worklist holds every enabled harness: a Claude user record that is not meta, or an OMP `message` record with role user holding a text item. OMP UI-only `custom_message` records never count. `filter_empty_sessions` reads a worklist on stdin and prints the substantive subset; `AUTODREAM_SKIP_EMPTY=0` turns the filter off.

## Consequences

The bias is to triage: the cost of a miss is one wasted model call. A new transcript shape needs its own clause in the `jq` expression or its sessions will all be dropped as empty. The filter is independent of the self-prune, so their telemetry counts do not overlap (`SKIPPED_EMPTY` is derived from the count after the prune).
