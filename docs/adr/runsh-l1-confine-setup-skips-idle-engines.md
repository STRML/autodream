# runsh: L1 confinement setup prepares only the engines that still have work

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_confine_setup`, `l1_missing_engines`, `L1_SETUP_SKIPPED`, `l1_attempt`)

## Context
`l1_confine_setup` builds a real sandbox prefix and, for omp, a seeded state directory per engine. An engine whose sessions already have findings from an earlier run has no worker to start, so preparing it costs time and can raise a fatal for nothing.

## Decision
`needed=$(l1_missing_engines)` restricts `all_engines` to engines with sessions still missing a findings JSON. Every other engine is listed in `L1_SETUP_SKIPPED`. `l1_attempt` checks that list and fails the attempt (`l1_infra_fail`, ledgered `staging`) when a worker reaches a skipped engine anyway, so such an engine is never run unconfined by default. This applies only when the sandbox probe said yes (`L1_CONFINED=yes`); with confinement off or unavailable `L1_SETUP_SKIPPED` stays empty. When no engine has work at all, every engine is listed as skipped and `l1_confined` reads `n/a`.

## Consequences
Anything that makes a worker use an engine `l1_missing_engines` did not report (a changed source map, a late re-dispatch) fails closed instead of running unconfined. Keep `l1_missing_engines` and the dispatcher's engine choice in step. See CLAUDE.md, "A worker writes only its staging directory (#169)" and "A host with no working sandbox says so".
