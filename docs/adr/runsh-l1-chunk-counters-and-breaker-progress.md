# runsh: Chunk counters read the planning and call ledgers, and finished chunk answers count as progress

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_chunk_totals`, `l1_chunk_answers`)

## Context
Chunked triage cost needs to be visible in run-stats, and the L1 circuit breaker would otherwise read a round that finishes most chunks but no whole session as barren and trip after two rounds.

## Decision
`l1_chunk_totals` prints `sessions chunks elided calls`. Sessions and chunks count what the chunker planned, taking the last plan per session from `l1-chunks.txt` (a retry plans again); elided is the chunks dropped from the middle; calls is the number of lines in `l1-chunk-calls.txt`, the engine calls actually made. A night with chunking off, or with nothing over the limit, reads `0 0 0 0`. `l1_chunk_answers` counts finished `*.chunkout` files under `.chunks/`; it is 0 when chunking is off (the directory does not exist), so the breaker is what it was.

See CLAUDE.md, "Reading a long session: chunked triage" (A chunk failure is a worker failure; What it costs).

## Consequences
Summing plans instead of keeping the last per session would double count every retried session.
