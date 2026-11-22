# runsh: a missing l1-confine.sh runs workers unconfined and says so, rather than failing the night

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`L1_CONFINER`; `l1_confine_setup` reads it)

## Context
Issue #169: an L1 engine holds the Write tool and could write any path the user can, so workers run under `bin/l1-confine.sh`. An install whose checkout predates the helper has no copy of it.

## Decision
`L1_CONFINER` is resolved with `find_lib`. Empty means `l1_confine_setup` records the reason "l1-confine.sh not found" and workers run as before; run-stats reports `l1_confined: no` with the reason. See CLAUDE.md, "A worker writes only its staging directory (#169)" and "A host with no working sandbox says so".

## Consequences
The unconfined mode is only acceptable because it is visible in run-stats and the log; keep it visible.
