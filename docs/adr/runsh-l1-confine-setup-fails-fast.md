# runsh: L1 confinement setup builds the real prefix and state directory up front, and a refusal is a fatal, never a quiet unconfined engine

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_confine_setup`)

## Context
The sandbox probe builds a prefix with no paths. The real prefix carries an engine's write list, the operator's `AUTODREAM_L1_WRITES_EXTRA` additions and the protect list, and a character the profile cannot hold in any of them fails every call. Found late, that costs a stub for every session instead of one stopped run. Likewise a state directory that cannot be prepared (omp's throwaway `HOME`) fails every worker. A model whose only credential is OAuth cannot run on a throwaway copy: a token refresh in the copy would lose the rotated token.

## Decision
For each engine with work, setup:
1. Runs `adapter.sh l1-writes`. Exit 2 means the adapter declares no write profile (the engine is recorded `l1_confined_<engine>: no` with a reason and a WARNING). Any other nonzero exit is a write list the adapter refused: a fatal (`L1_CONFINE_FATAL`) with the reason, never an engine that quietly runs unconfined.
2. Builds the real prefix once with `l1-confine.sh engine-prefix` against a `.setup-<engine>` stage; a failure is a fatal before any worker starts.
3. Runs `adapter.sh l1-stage-env` once with the model the engine's sessions use. Exit 0 or 2 (no such verb) confines the engine. Exit 4 (a model a throwaway state cannot serve) leaves this engine unconfined with the reason and a WARNING. Any other exit is a fatal.

## Consequences
The "(omp)" in the original comment on exit 2 is out of date: both the claude and omp adapters now declare `l1-writes`, so exit 2 reaches this branch only for an adapter with no such verb. Exit 2 from `l1-stage-env` means "no state directory needed" (claude). Do not turn a nonzero `l1-writes` exit into "unconfined": the denial is the safe answer. See CLAUDE.md, "A host with no working sandbox says so".
