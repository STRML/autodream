# runsh: A session with no artifact hash is counted as an unparseable sidecar in the oversized-gate loop, not in compute_session_stats

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`compute_session_stats`, the oversized-gate loop that initialises `STATS_SIDECARS_UNPARSEABLE`)

## Context
`compute_session_stats` runs before the oversized-gate loop. `STATS_SIDECARS_UNPARSEABLE` is initialised to 0 in that loop, so an increment inside `compute_session_stats` would be wiped, and referencing the variable before that assignment trips `set -u` outright.

## Decision
When `session_hash` fails, `compute_session_stats` only logs a WARNING naming the session and writes no sidecar. The oversized-gate loop walks the same `sessions.txt` and counts that session there, which is why the #27 fix reads the session list rather than the sidecar glob.

See CLAUDE.md, "Self-audit" (Degraded measurements must say so, not read as zero).

## Consequences
Do not add the counter to `compute_session_stats`.
