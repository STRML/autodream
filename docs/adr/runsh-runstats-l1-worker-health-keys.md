# runsh: run-stats records what L1 workers actually did (rounds, confinement, chunk cost)

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `run-stats.txt` block in `run()`: `l1_rounds_used`, `l1_confine_stat_lines`, the `l1_chunk*` keys)

## Context
- `l1_rounds_used` is read from `LAST_ROUND_RUN`, not `$round`: the loop variable is assigned before a round dispatches, so a loop that stopped before dispatching would still read as having used that round. (The round-budget and circuit-breaker behavior is in CLAUDE.md, "A hung worker, a cold token and a deterministic failure".)
- Confinement (#169): whether workers could write only to their staging directory, and with what. A `no` is a degraded night, not a failed one; the reason says why. `l1_confine_stat_lines` writes the keys.
- Chunked triage cost: `l1_chunk_bytes` is the setting in force (0 = off, including when the helpers were not found); the rest are 0 on a night nothing was over the limit. `l1_chunks` is the chunk workers the oversized sessions needed, `l1_chunk_calls` the engine calls actually made (retries add, a reused answer makes none), and `l1_chunks_elided` how many chunks the cap dropped from the middle of a session. A nonzero `l1_chunks_elided` is a degraded read, named here so it cannot pass as a complete one.

## Decision
`l1_rounds_used` uses `LAST_ROUND_RUN`; the chunk keys print `0` for `l1_chunk_bytes` unless `L1_CHUNKING = 1`, and the others default to 0. See CLAUDE.md, "Reading a long session: chunked triage" ("What it costs") and "A worker writes only its staging directory (#169)".

## Consequences
Do not swap `LAST_ROUND_RUN` for `$round`. Do not fold `l1_chunks_elided` into a quieter place: it is the only signal that a session was read with its middle cut.
