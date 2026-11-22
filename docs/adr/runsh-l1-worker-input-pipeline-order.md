# runsh: L1 worker input is built in a fixed order: normalize, cut to the report day, slim, then chunk

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body)

## Context
Oversized transcripts (multi-MB, base64 images, giant tool outputs) blow the worker's token budget so it errors instead of triaging. An omp session is an append-only tree. A transcript can span more than the report day, and a worker handed a slice has no other way to know the first turn it reads is not the start of the session.

## Decision
1. An adapter listed in `AUTODREAM_NORMALIZE_SOURCES` (omp) is linearized first to the live conversation, and the worker reads `<hash>.norm.jsonl`. A session the adapter cannot prove is the live conversation gets a deterministic error record rather than a worker reading abandoned branches.
2. When the window is on, `session-window.sh day-file` cuts that to the report day. Status 0 wrote a slice, 1 means nothing to cut, 2 means the helper failed; the last two read the whole transcript, because a failed cut must cost a larger read and never the session. The stats sidecar the noise gate read was cut the same way. A worker handed a slice is told so in a `## Report day` paragraph.
3. Over `AUTODREAM_SLIM_BYTES` (default 262144) the transcript is slimmed and the worker reads the slim. While chunked triage is on the slimmer keeps every conversation line and drops Claude Code bookkeeping first (`AUTODREAM_SLIM_RESHAPE` and `AUTODREAM_SLIM_FULL` follow `L1_CHUNKING`). Off, both are 0 and it writes what it always wrote.
4. After a successful run the findings `session_path` is rewritten back to the original.

## Consequences
Normalize first, cut second: cutting the raw tree leaves entries whose parent was cut away, which `linearize.sh` refuses. See CLAUDE.md, "Which day a session belongs to" and "Reading a long session: chunked triage".
