# rest: every headless omp call passes the shipped overlay through --config, and the L1 flags are each load-bearing

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/adapter.sh` (`OVERLAY`, `l1-argv`, `warmup-argv`, `l2-argv`, `threads-argv`)

## Context

`l1-argv` prints the invocation omp-autodream ran, so a night on the unified runner is the same worker. Three of its flags each cost a night to learn:

| Flag | Why it is there |
|---|---|
| `--config <overlay>` | Turns off the advisor, local provider probes (a sleeping Mac made them take 3.6s each) and first-turn mnemopi recall, which made headless workers exit 0 with empty stdout before any model call. |
| `--tools=Read,Write` | The worker reads the transcript and writes the findings JSON, nothing else. |
| `--no-session` | Leaves no transcript, so the next night does not triage this one (CLAUDE.md, "Self-pollution"). |

The overlay also sets `memory.backend: off`. A worker that retained or consolidated memory would write a store every later session recalls from (`docs/plans/2026-11-21-omp-l1-writes.md`).

The warmup is omp-autodream's: the worker's flags minus `--tools`, with a system prompt that asks for one word. It carries the same overlay, so the call that refreshes the token is the call a worker would have made. The L2 aggregator gets the overlay too (advisor off, no local provider probes, no first-turn recall) and only `Glob,Read`: the report and the pins come back on stdout. Its system prompt is `prompts/L2_SYSTEM.txt`, read through the loader in `bin/l2-prompt.sh`, and no file means no argv (exit 2).

## Decision

- `OVERLAY` is always `$ADIR/l1-no-advisor.yml`, the shipped file. A replacement hook would need a YAML parser in this adapter to prove it still turns the memory backend off, so there is none.
- Every argv builder (`l1-argv`, `threads-argv`, `warmup-argv`, `l2-argv`) passes `--config "$OVERLAY"`.
- L2 reads its system prompt through `l2_system_prompt`; a failure there is `exit 2` rather than starting the engine without it (`bin-a-l2-prompt-one-copy-fails-closed.md`).

## Consequences

Dropping the overlay from one builder brings back empty-stdout workers or live memory writes for just that call. Making the overlay path configurable reopens the memory-write exposure.
