# runsh: chunk inputs are rebuilt each dispatch, chunk answers are cached under a name that covers the chunk and every instruction it was read under

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, chunked triage; `ccfg`)

## Context
A retry should be cheap and a failure partway through a session should not start over, but an answer merged with fresh ones after the prompt, engine, model or session changed would be a stale merge. Chunk answers are model output and must not be mistaken for sessions by anything that globs the findings directory.

## Decision
- Inputs live in `.chunks/<hash>/in/`, are deterministic for an unchanged transcript, are rebuilt on every dispatch, and are removed by the parent after the round whatever happened to the worker.
- Answers are kept under `.chunks/<hash>/` as `NN-<sha1 of the chunk, 12 chars>-<cfg>.chunkout`, with a non-`.json` suffix. `cfg` is the first 8 characters of a sha1 over SESSION_TRIAGE.md, the harness addendum, `src engine model nchunks elided` (the chunk count and omitted count the chunk note states) and the session's stats sidecar (merge-chunks.sh takes the stats fields from chunk 1). The engine is in its own right because one model id can be served by two engines through different system prompts and tools.
- A retry reuses an answer only when it passes `merge-chunks.sh --check`; otherwise only that chunk is redone.
- Chunk scratch is only worth keeping while a retry is pending: inputs never, answers until the session has a findings JSON (a stub included), when the worker removes `.chunks/<hash>`.

## Consequences
A new input to the chunk prompt must go into `ccfg`, or a retry will reuse an answer made under different instructions. See CLAUDE.md, "Reading a long session: chunked triage".
