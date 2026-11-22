# runsh: the chunk note tells each worker it holds one chunk of one session, and its wording is matched by the test mock

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_chunk_note`); `tests/mock-claude.sh`; `tests/run-all.sh`

## Context
A chunk worker sees a slice of one transcript. A tool call and its result can fall in different chunks, and the goal and outcome may be in other chunks. The stats sidecar describes the whole session (or the report day), not one chunk, so they must be copied verbatim and not recounted.

## Decision
`l1_chunk_note i n elided` prints the paragraph appended to the worker's prompt before the stats block (SESSION_TRIAGE.md says the stats come last). When chunks were dropped from the middle it adds the omitted count.

## Consequences
The sentence "chunk I of N of ONE session" is matched by `tests/mock-claude.sh` (a `sed` that extracts the chunk index) and asserted in `tests/run-all.sh`; change the text and both together. See CLAUDE.md, "Reading a long session: chunked triage" ("The worker").
