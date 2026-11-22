# runsh: The per-run L1 ledgers are truncated past the idempotency guard

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, the `: > l1-timeouts.txt` block)

## Context
- A catch-up trigger that no-ops on a finished date must not wipe that date's record of what timed out. This point is past the idempotency guard, which is why the ledger is truncated here and not where `FINDINGS_DIR` is created.
- The chunk ledgers are append-only per run like the two above them. `l1-chunks.txt` holds one "hash chunks elided" line each time a session is planned (a retry plans it again, so readers keep the last line per hash). `l1-chunk-calls.txt` holds one "hash round chunk" line per engine call actually made, a reused answer making none, which is what a night cost in model calls.

## Decision
`l1-timeouts.txt` and `l1-netdown.txt` are truncated here, and `l1-chunks.txt` and `l1-chunk-calls.txt` too when `L1_CHUNKING` is 1.

## Consequences
- Moving the truncation above the guard lets a no-op catch-up trigger erase timeout evidence.
- Readers of `l1-chunks.txt` must take the last line per hash.
