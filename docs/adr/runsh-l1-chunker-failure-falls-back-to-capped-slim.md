# runsh: when the chunker fails, the worker falls back to the capped head/tail slim, never to the uncapped input

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, chunker fallback)

## Context
The chunker can fail (a full disk, an unwritable directory). Handing one worker the whole uncapped slim is the failure chunking exists to avoid. A transcript under `AUTODREAM_SLIM_BYTES` was never slimmed, so there may be no slim file yet.

## Decision
On a chunker failure the worker resets to one chunk, removes the chunk inputs, and builds the exact off-path input: the head/tail slim (`AUTODREAM_SLIM_FULL=0`, `AUTODREAM_SLIM_RESHAPE=0`) of the same input (`slimsrc`, or `readpath` when it was never slimmed, creating the slim file from it). If the slimmer fails too, it cuts the first `AUTODREAM_SLIM_CAP` bytes (default 262144). If that also fails it sets `l1_blocked=1`: no engine call this round, the output stays absent, the session is retried, and the last round writes the stub.

## Consequences
Do not replace the fallback with the full slim to "save" a failing session. See CLAUDE.md, "If the chunker fails".
