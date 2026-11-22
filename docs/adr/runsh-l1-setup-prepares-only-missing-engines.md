# runsh: L1 setup prepares only engines that still have a session to triage

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_missing_engines`, `l1_confine_setup`)

## Context
Preparing an engine nothing will run fatals a night whose findings are already complete (a retry after L2 failed) over a database that no worker needs.

## Decision
`l1_missing_engines` lists, one per line, the engines (from `AUTODREAM_SOURCE_MAP` then `AUTODREAM_L1_ENGINES`) that still have a session with no valid findings JSON. `l1_confine_setup` prepares only those, and names the rest in `L1_SETUP_SKIPPED` so a worker that reaches a skipped engine anyway fails its attempt instead of running unconfined.

## Consequences
See `l1-write-confinement-staging`. A session whose hash cannot be derived is skipped here (it can never have findings).
