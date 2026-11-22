# runsh: chunked triage is one switch, on only when asked for and when both helpers are found

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`CHUNKER`, `MERGER`, `L1_CHUNKING`)

## Context
A transcript too big for one worker is split at line boundaries (`chunk-transcript.sh`), one worker reads each chunk, and `merge-chunks.sh` merges the answers back into the one findings JSON per session that L2 reads. See CLAUDE.md, "Reading a long session: chunked triage".

## Decision
`L1_CHUNKING=1` only when `AUTODREAM_L1_CHUNK_BYTES` is above 0 AND both helpers are found with `find_lib` (a merge swaps run.sh before install.sh links the new helpers). With either missing, the oversized transcript is read the old way (head/tail slim) and the run says so. Everything new sits behind this one switch: `L1_CHUNKING=0` reaches the slimmer with no reshape and no full mode, no chunker, no merge and no chunk note, so the off path is what it was.

## Consequences
New chunking behaviour must be gated on `L1_CHUNKING`, not on the byte knob alone, or the off path stops being byte-identical to the old behaviour.
