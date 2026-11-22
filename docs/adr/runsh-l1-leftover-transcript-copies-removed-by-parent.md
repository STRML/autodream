# runsh: transcript copies a killed worker left behind are removed by the parent after the round, not by a trap in the worker

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1`, after the `xargs` call)

## Context
A worker killed mid-round never reached its own cleanup. What it leaves is transcript text: the chunk inputs and, with chunking on, a slim that is now the whole conversation. A trapped TERM is deferred until the foreground engine exits (the adapter says what that cost: see `docs/adr/bin-a-adapter-claude-no-signal-trap.md`), so a trap in the worker would trade a stale file for a worker that ignores SIGTERM. `FANOUT` workers (8 by default) create their own subdirectory in `.chunks` at once; one removing it between another's two `mkdir` steps would make that chunker fail for no reason.

## Decision
After the `xargs` pass every worker has returned, so any chunk input, slim, day or norm copy still on disk is a leftover. Gated on `L1_CHUNKING=1`, the parent removes `.chunks/*/in`, `*.slim.jsonl`, `*.slim.jsonl.cap`, `*.day.jsonl` and `*.norm.jsonl`, then the empty `.chunks` directory (that one only here, never in a worker). Chunk answers stay for the retry. With chunking off nothing changes from what it always left.

## Consequences
Do not add a worker-side trap, and do not remove `.chunks` from a worker. See CLAUDE.md, "Cleanup without a trap".
