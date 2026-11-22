# runsh: on the final L1 round a failed session gets a metadata-only stub, except when the network was down or the provider refused outright

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, failure branch; `l1_missing_count`)

## Context
Without a stub the session disappears into a silent `.err` file (2026-06-11 self-audit: 12 `.err` files with `l1_findings_with_error=0`). But a stub carries a `.findings` key, so it satisfies `l1_missing_count`: writing one marks the session done. MISSING drops to zero, the run never defers, L2 publishes on a short corpus, and the next run skips the session because its slot is filled.

## Decision
Earlier rounds leave `$output` absent so the next round retries. Only when `AUTODREAM_CURRENT_ROUND` has reached `AUTODREAM_L1_ROUNDS` (default 5, passed through the environment) does the worker write a stub (`error: worker exited without findings JSON after N rounds`, `meta` with bytes, lines, slimmed and any chunk counts, a runner `.served` marker). When `netdown` is `true`, `provider` or `staging` no stub is written and the log says the session is left for a later run: leaving the slot empty is what makes the retry work, and the run defers instead, so the silent-failure concern is answered by the deferral and not the stub.

## Consequences
Never write the stub on an outage branch. See CLAUDE.md, "A dead network or a refusing provider defers the date" and "A hung worker, a cold token and a deterministic failure" (the breaker still dispatches once more at the budget because the stub only fires there).
