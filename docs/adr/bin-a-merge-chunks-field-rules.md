# bin-a: the chunk merge is mechanical, with a fixed rule for each field when answers disagree

Status: accepted · Date: 2026-11-21 · Code: `bin/merge-chunks.sh` (the jq program)

## Context

The per-chunk answers for one session become the one findings JSON that L2 and every other consumer already reads. No model call does this, so the merge has to say what each field means when the answers disagree. The stats fields in particular are copied by every worker from the same precomputed sidecar. `tests/merge-chunks.sh` is the contract.

## Decision

| Field | Rule |
|---|---|
| `session_path` | The original transcript, never a chunk file. |
| `underlying_goal` | The first non-empty one: the session says what it wants where it begins. |
| `outcome` | The last chunk that states one: the end state is where the outcome is judged. |
| stats fields | Taken once from the first chunk. Every worker copies the same sidecar verbatim, so summing them would be nonsense. |
| `findings` | Union, each tagged with its chunk. Exact duplicates on (`category`, `what`) are dropped, most severe first, capped at 10 (the schema cap). A finding with neither a category nor a `what` has no identity to merge on, so it is kept. |
| other lists | Order-preserving union. `instructions_given` is capped at 3 (the schema cap). |
| `deferred_ideas` | Chunk-order union by normalized (`idea`, `quote`), valid entries only, capped at 3. |
| `meta` | `chunks` (how many answered) and `chunks_elided` (how many the chunker dropped). |

Every read goes through the `arr`, `objs`, `strs` and `num` helpers, so a wrongly typed field is ignored. It does not abort the merge and with it the findings of every other chunk.

## Consequences

A new field in the findings schema needs a row here and a rule in the jq program. If it is left out, it comes from the first chunk only (the program starts from `$all[0]`).
