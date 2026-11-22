# tests-mock-claude: each failing L1 mode reproduces the exact shape of a real death, not just a nonzero exit

Status: accepted · Date: 2026-11-22 · Code: `tests/mock-claude.sh` (the `ping` branch, the `$mode` case in the Layer 1 branch)

## Context

`run.sh` classifies worker failures from output, exit code and elapsed time (`bin/failure-class.sh`), defers a date on a dead network or permanent provider refusal, and trips a circuit breaker on barren rounds. Each of those rules was written after a night that went wrong in one particular way, and a fixture that fails "somehow" passes the wrong code. See CLAUDE.md "A failed worker leaves its evidence", "A hung worker, a cold token and a deterministic failure" and "A dead network or a refusing provider defers the date".

## Decision

Each mode copies the real signature:

- `ping` and `l1_silent`: exit 0, nothing on stdout, `Working...` on stderr. That is the 2026-09-13 omp death (first-turn recall). `l1_incomplete` still prints `done`, so it is a different case. A warmup fixture that always printed something made `l1_warmup: ok` unfalsifiable.
- `l1_noisy_fail`: nothing written, the diagnosis on stdout, exit 7. omp puts its diagnosis on stdout and only `Working...` on stderr, and `run.sh` once sent stdout to `/dev/null`, so every failure looked identical.
- `l1_context_overflow` must count as size although its text starts with `provider error`. `l1_provider_refusal` (Z.ai code 1113) and `l1_provider_402` (DeepSeek wording, no pattern in `classify_failure`) prove the permanent-refusal check does not depend on the classifier. The network is fine in both, so the date defers and no stub is written.
- `l1_exit124` exits 124 by itself and `l1_exit137` SIGKILLs itself. GNU `timeout` propagates a child's own status, so these look like a timeout; only elapsed time tells them apart.
- `l1_hang` sleeps forever and leaves a child behind. A test that finds the child gone proves the timeout signalled the whole process group, which is what stops the real `node_repl` and `mnemopi_embed` orphans (the 2026-08-19 and 2026-08-22 wedges).
- `l1_wrongtype` writes `{"findings":"oops"}` because `jq -e .findings` is truthy for a string. `l1_nested_error` carries an `error` key inside a finding, which must not mark a failed triage (only a top-level key does).
- `l1_partial_then_stall` lets exactly one session ever succeed, claimed by an atomic `mkdir` under `MOCK_STATE_DIR`. Workers run at FANOUT 8, so a test-then-create lets several win and the recovered count varies. Round 1 recovers something and later rounds nothing, the shape that exposed the breaker's off-by-one (comparing ending counts called two rounds barren as soon as the second was).
- The worker's findings dir comes from the inherited `FINDINGS_DIR`, not from the answer path, because the answer is written in a staging directory (#169).

## Consequences

Do not simplify a mode to "exit nonzero". Changing a mode's stdout, stderr or exit code changes which classifier branch the integration tests reach. Remove a mode only together with the test that names it.
