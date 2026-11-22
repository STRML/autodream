# runsh: `compute_session_stats` does not count sidecar failures: `STATS_SIDECARS_UNPARSEABLE` is initialised later, in the oversized-gate loop

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`compute_session_stats`, the oversized-gate loop that initialises `STATS_SIDECARS_UNPARSEABLE`)

## Context
`compute_session_stats` runs before the oversized-gate loop. `STATS_SIDECARS_UNPARSEABLE` is initialised to 0 in that loop, so an increment inside `compute_session_stats` would be wiped, and referencing the variable before that assignment trips `set -u` outright.

## Decision
When `session_hash` fails, `compute_session_stats` only logs a WARNING naming the session and writes no sidecar. The oversized-gate loop walks the same `sessions.txt`, which is why the #27 fix reads the session list rather than the sidecar glob. That loop's own `session_hash` failure branch counts the session in `OVERSIZED_UNMEASURABLE` (run-stats `oversized_unmeasurable`) and skips it. `STATS_SIDECARS_UNPARSEABLE` is incremented only for a session that has a hash and whose sidecar is missing or has no numeric `transcript_bytes`. The original comment said the loop counts a hashless session as an unparseable sidecar, which the code does not do.

See CLAUDE.md, "Self-audit" (Degraded measurements must say so, not read as zero).

## Consequences
Do not add the counter to `compute_session_stats`.
