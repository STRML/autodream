# runsh: l1_attempt is one engine call with a fixed argument contract, and it judges a chunk by the chunk rule

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_attempt`)

## Context
A session is read by one engine call, or by one call per chunk. Both paths need the same failure evidence, network verdict and ledger, and a chunk answer has a different validity rule from a whole-session answer.

## Decision
`l1_attempt TRANSCRIPT ANSWER ERRFILE OUTFILE [CHUNK_NOTE]`: `$1` is the transcript to read, `$2` the findings path the worker is told to write, `$3` and `$4` hold the engine stderr and stdout. It returns 0 only when `$2` ends up holding a findings object. On failure it leaves its evidence in `$3` and the network verdict in `netdown` (and in the ledger), and the caller decides what the failure costs. A set `$5` is the chunk note, and the answer is then judged by `merge-chunks.sh --check` (exactly one object, no `error` key) instead of a findings array alone. `l1_subject` names the session or a chunk of it in the diagnostic line.

## Consequences
That diagnostic line is skipped by `failure-class.sh` on its prefix, so naming a chunk there costs the classifier nothing; any new line added to the `.err` would be read as worker output. See CLAUDE.md, "A chunk failure is a worker failure".
