# runsh: when the network never came back or the provider refused, defer the date and write no report

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the `NET_DEFERRED` branch that precedes changelog collection)

## Context
L2 over a corpus known to be short produces a report that looks complete. Findings written so far stay on disk and the worker is idempotent, so a later catch-up trigger picks up exactly the sessions still missing. The idempotency guard keys on the report existing, and `unassembled_dates()` names the date until one does, so writing no report is what makes the retry happen.

## Decision
When `NET_DEFERRED = yes` the run logs the shortfall (`COUNT - MISSING` of `COUNT`), appends the two L2 network keys, cleans the work bucket and returns 1 before L2. `NET_DEFERRED` is set earlier: when `wait_for_network` gives up before a round, or when the last round that dispatched left a `true` or `provider` row in `l1-netdown.txt` with sessions still missing. The two L2 keys are appended here because the post-L2 append is jumped over, and PROMPT.md reads all four network keys, so an absent key would read as an older runner; L2 did not run, so the values are zero waits and no deferral. The test stays narrow: only a round that could not run, or whose last round failed outright, defers, never a slow or partial one. See CLAUDE.md, "A dead network or a refusing provider defers the date".

## Consequences
Widening the condition would defer nights that are merely slow and leave days permanently unreported; narrowing it publishes short corpora. If a report is written on this path the guard stops all later retries.
