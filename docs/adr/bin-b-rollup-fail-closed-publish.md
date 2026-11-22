# bin-b: a failed stage fails rollup.sh and publishes nothing

Status: accepted · Date: 2026-11-21 · Code: `bin/rollup.sh` (`set -o pipefail`, `write_atomic`, the `RAW`/`BODY`/`FINDS`/`CATS` checks, `publish`)

## Context

L2 reads the tallies as ground truth. A tally built from a pipeline that lost a stage (a `sort` with no temp space, a failed `jq` or `awk`) looks like a genuine, smaller result.

## Decision

- The script runs under `pipefail`, and each of the four build stages is checked. A failure prints a message and exits 1 before any file is written.
- Each output is written through `write_atomic`: a temp file beside the target and one `mv`, so a reader never sees half a file and a failed write leaves no temp behind.

## Consequences

Exit 1 means the previous `rollup.tsv`, `categories.tsv` and `findings.tsv` are untouched, not a partial new set. Removing `pipefail` or the per-stage checks turns a broken tally into an empty one that L2 reports as a quiet night.
