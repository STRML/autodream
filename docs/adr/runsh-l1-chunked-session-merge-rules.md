# runsh: a chunked session is merged only when every chunk answered properly, and one failing chunk's evidence stands for the session

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, chunked branch)

## Context
A chunk answer is untrusted model output. A chunk failure is a worker failure, and a later chunk that succeeds must not overwrite what the first failure said. After a no-route or a permanent provider refusal the other chunks would fail the same way and each would burn a call. The merged answer can only be vouched for as far as its chunks were.

## Decision
- One engine call per chunk, in sequence in the xargs slot. A chunk counts only when `merge-chunks.sh --check` passes (exactly one findings object, no `error` key); anything else is discarded so the retry round redoes that chunk alone, and a finished answer is reused. After `netdown` is `true`, `provider` or `staging` the loop breaks.
- The session-level merge runs only when no chunk failed, and `merge-chunks.sh` refuses anything else itself. A merge that fails anyway drops every cached answer (and their `.served`) so the next round cannot loop on them.
- The merged `.served` verdict is `match` when every chunk answer says match, `mismatch` when any says mismatch, `unmeasured` otherwise (a chunk whose engine reports no model, or an answer cached before the verdict existed).
- When a chunk failed, the first failing chunk's `.err` is copied to `$errlog` (`failure-class.sh` classifies it as it does any); the final-round stub is the session level and only the session level.

## Consequences
See CLAUDE.md, "A chunk answer is untrusted" and "A chunk failure is a worker failure".
