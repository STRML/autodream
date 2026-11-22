# runsh: Nested transcripts find their parent by walking up, and the session total is split into top-level and nested

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`session_parent`, `fanout_rows`, `compute_fanout_stats`)

## Context
Issue #79: a parent that spawned thirty workers read as thirty-one sessions in the report. A child lives in a directory named after its parent's file: claude nests workers at `<bucket>/<id>/subagents/` and `<bucket>/<id>/subagents/workflows/wf_*/`, omp at `<bucket>/<stamp>_<id>/`.

## Decision
`session_parent` walks up from the transcript (at most 6 levels) until `<dir>.jsonl` is a file, which finds the parent at any depth. `fanout_rows` writes one `worker-hash<TAB>parent-hash` row per nested transcript in `sessions.txt` (a sidecar with `isSidechain` or `nested` set). When the parent file is gone, the parent hash is taken from the path that file would have (the string `session_parent` would return), so a fanout still groups. The rows are held in the runner's memory, like `session_rows`, because L1 and L2 can rewrite the worklist. `compute_fanout_stats` runs after L1 (so a gated stub drops out, the same set the Activity snapshot's N counts), sets `FANOUT_TOP`, `FANOUT_NESTED`, `FANOUT_PARENTS` and `FANOUT_LARGEST`, and writes `fanouts.tsv` for L2 from `FANOUT_ROWS`, which ran before any model did.

See CLAUDE.md, "Where state lives" (`fanouts.tsv`).

## Consequences
The depth cap of 6 bounds the walk; a new nesting deeper than that needs the cap raised.
