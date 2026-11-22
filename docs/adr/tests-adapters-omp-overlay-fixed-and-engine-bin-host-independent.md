# tests-adapters: the omp L1 overlay cannot be replaced by the environment, and the engine-bin tests do not depend on the host

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-omp.sh` (the overlay `--config` group, the `engine-bin` group)

## Context

The L1 overlay (`adapters/omp/l1-no-advisor.yml`) turns omp's memory recall and the advisor off, because a worker that retained or consolidated memory would write a store every later session recalls from (CLAUDE.md "A host with no working sandbox says so", `docs/plans/2026-11-21-omp-l1-writes.md`).

## Decision

- `NO_ADVISOR_CFG` is ignored. Proving that a replacement overlay keeps memory off would need a YAML parser in the adapter, so there is none and every verb (`l1-argv`, `threads-argv`, `warmup-argv`, `l2-argv`) carries the shipped file. The test sets a hostile overlay (`memory: backend: mnemopi`) and checks all four verbs still pass the shipped path.
- The `engine-bin` fallback to the bare name `omp` is asserted only on a host that has none of the absolute candidates (`/opt/homebrew/bin/omp`, `/usr/local/bin/omp`). Those are real paths on a developer machine, so asserting it unconditionally made the suite depend on where omp happens to be installed.

## Consequences

Adding an overlay override means adding a validation step first, and updating the hostile-overlay test. Do not make the bare-name assertion unconditional.
