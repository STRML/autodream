# runsh: a missing l1-confine.sh runs workers unconfined and says so, rather than failing the night

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`L1_CONFINER`; `l1_confine_setup` reads it)

## Context
Issue #169: an L1 engine holds the Write tool and could write any path the user can, so workers run under `bin/l1-confine.sh`. `find_lib` looks beside the runner and then in the repo's own `bin/`, because a merge swaps `run.sh` before `install.sh` links the new helpers, so a helper added by that merge can be absent.

## Decision
`L1_CONFINER` is resolved with `find_lib`. Empty means `l1_confine_setup` records the reason "l1-confine.sh not found" and workers run as before; run-stats reports `l1_confined: no` with the reason, and the log carries `WARNING: L1 workers run unconfined (l1_confined: no): l1-confine.sh not found` unless `AUTODREAM_L1_CONFINE=0` was set on purpose. Unlike `report-format.sh`, `err-cause.sh` and `failure-class.sh`, whose absence is fatal, this helper degrades: a night's triage is worth more than the sandbox on a host that predates it. A helper that exists but cannot build an engine's prefix fails that attempt and never runs unconfined. See CLAUDE.md, "A worker writes only its staging directory (#169)" and "A host with no working sandbox says so".

## Consequences
The unconfined mode is only acceptable because it is visible in run-stats and the log; keep it visible.
