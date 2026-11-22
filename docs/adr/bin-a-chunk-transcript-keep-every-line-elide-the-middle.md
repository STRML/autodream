# bin-a: the chunker keeps every line, cuts only at line boundaries, and when over the cap drops the middle

Status: accepted · Date: 2026-11-21 · Code: `bin/chunk-transcript.sh` (the whole script)

## Context

A day of a long session slims to far more than one worker can read. Eliding its middle is how Layer 1 came to see about 2% of a conversation. CLAUDE.md, "Reading a long session: chunked triage", has the measurements and the worker side of the design. `tests/chunk-transcript.sh` is the contract.

Call shape: `chunk-transcript.sh SRC OUTDIR CHUNK_BYTES MAX_CHUNKS`. Stdout is `COUNT ELIDED` and `OUTDIR` holds `chunk-01.jsonl` through `COUNT` files. Exit 0 is ok, 1 is an empty source, 2 is bad usage, an unreadable source or a failure writing the chunks.

## Decision

- Every line is kept. Chunks are cut only at line boundaries. A line longer than `CHUNK_BYTES` becomes a chunk of its own instead of being split, so no line is torn. A tool call and its result are separate lines, in order. When a cut falls between them, one ends a chunk and the other opens the next, and the caller says so in the chunk note.
- Over `MAX_CHUNKS` the middle is dropped, deliberately and loudly. `ELIDED` is how many chunks went. The first ceil(MAX/2) and the last floor(MAX/2) are kept, because the start holds the goal and the end holds the outcome. A cap of 1 keeps the first chunk only, so it is still a bounded read and never the whole transcript.
- Sizes are bytes, not characters: `LC_ALL=C` makes awk `length()` count bytes. A source whose last line has no newline gets one, so every chunk ends on a line.
- Numbers are read as decimal (`10#`), because bash arithmetic reads `08` as an invalid octal number.
- Chunks are transcript text, so `umask 077` keeps them private to the user whatever umask the caller has.
- Chunks and scratch files left by an earlier run are removed first, because the caller globs the directory. On a failure (exit 2) no chunk or scratch file is left, so the caller cannot mistake a partial split for a whole one.

## Consequences

The caller must report `ELIDED` to the worker and record it: a nonzero value is a degraded read (`l1_chunks_elided` in run-stats). Cutting inside a line, or keeping a partial directory after a failure, would hand a worker a transcript that looks complete and is not.
