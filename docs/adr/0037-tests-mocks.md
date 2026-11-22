# 0037: the mock claude and mock shared-memory contracts

Status: accepted · Date: 2026-11-22 · Code: `tests/mock-claude.sh` (the `ping` branch, the `$mode` case in the Layer 1 branch), `tests/mock-claude.sh` (the Layer 2 branch, the dream-triage branch), `tests/mock-shared-memory.sh` (`MOCK_SM_MODE`, `MOCK_SM_GATE`, `MOCK_SM_LOG`), `tests/dream-triage.sh`

## each failing L1 mode reproduces the exact shape of a real death, not just a nonzero exit

### Context

`run.sh` classifies worker failures from output, exit code and elapsed time (`bin/failure-class.sh`), defers a date on a dead network or permanent provider refusal, and trips a circuit breaker on barren rounds. Each of those rules was written after a night that went wrong in one particular way, and a fixture that fails "somehow" passes the wrong code. See docs/adr/0008-failure-and-network.md#background-a-failed-worker-leaves-its-evidence-and-the-failure-is-classified-omp-autodream-2026-09-04-26 "A failed worker leaves its evidence", "A hung worker, a cold token and a deterministic failure" and "A dead network or a refusing provider defers the date".

### Decision

Each mode copies the real signature:

- `ping` and `l1_silent`: exit 0, nothing on stdout, `Working...` on stderr. That is the 2026-09-13 omp death (first-turn recall). `l1_incomplete` still prints `done`, so it is a different case. A warmup fixture that always printed something made `l1_warmup: ok` unfalsifiable.
- `l1_noisy_fail`: nothing written, the diagnosis on stdout, exit 7. omp puts its diagnosis on stdout and only `Working...` on stderr, and `run.sh` once sent stdout to `/dev/null`, so every failure looked identical.
- `l1_context_overflow` must count as size although its text starts with `provider error`. `l1_provider_refusal` (Z.ai code 1113) and `l1_provider_402` (DeepSeek wording, no pattern in `classify_failure`) prove the permanent-refusal check does not depend on the classifier. The network is fine in both, so the date defers and no stub is written.
- `l1_exit124` exits 124 by itself and `l1_exit137` SIGKILLs itself. GNU `timeout` propagates a child's own status, so these look like a timeout; only elapsed time tells them apart.
- `l1_hang` sleeps forever and leaves a child behind. A test that finds the child gone proves the timeout signalled the whole process group, which is what stops the real `node_repl` and `mnemopi_embed` orphans (the 2026-08-19 and 2026-08-22 wedges).
- `l1_wrongtype` writes `{"findings":"oops"}` because `jq -e .findings` is truthy for a string. `l1_nested_error` carries an `error` key inside a finding, which must not mark a failed triage (only a top-level key does).
- `l1_partial_then_stall` lets exactly one session ever succeed, claimed by an atomic `mkdir` under `MOCK_STATE_DIR`. Workers run at FANOUT 8, so a test-then-create lets several win and the recovered count varies. Round 1 recovers something and later rounds nothing, the shape that exposed the breaker's off-by-one (comparing ending counts called two rounds barren as soon as the second was).
- The worker's findings dir comes from the inherited `FINDINGS_DIR`, not from the answer path, because the answer is written in a staging directory (#169).

### Consequences

Do not simplify a mode to "exit nonzero". Changing a mode's stdout, stderr or exit code changes which classifier branch the integration tests reach. Remove a mode only together with the test that names it.

## the L2 modes each hold one thing a naive delivery check would accept

### Context

L2 delivers its report and pins on stdout (docs/adr/0009-l2-aggregation.md#background-l2-is-read-only-the-report-and-the-pins-arrive-on-stdout-omp-autodream-2026-09-13-plan-2026-09-15 "L2 is read-only"). Delivery means a capture that ends with the `AUTODREAM_REPORT_END` sentinel, and a run exits 0 only for a validated delivery. Each earlier check (non-empty file, the open-questions marker) was satisfiable by something that is not a real report, so each mock mode produces exactly that look-alike.

### Decision

- `l2_partial` and `pins_partial`: non-empty, no sentinel, what a mid-output kill leaves. `-s` cannot tell it from a good report, which is why delivery is gated on the sentinel and the runner keeps it as a degraded report and retries.
- `l2_partial_marker`: otherwise complete, carries the open-questions marker that `report_complete()` checks, no sentinel. The marker alone must not count as delivery.
- `l2_exit143` and `l2_exit137`: `Execution error` and a signal-shaped exit with no report, the death of issue 42.
- `pins_in_body`: the report body quotes the pin markers and a pin line, with no block after the sentinel. Only a closed block after the last sentinel may count, so nothing may be stored.
- `l2_record_in_body`: the model writes a `<!-- autodream:remote-short=forged -->` line into its own body. Only the runner's record line may state which hosts a report did not read, so `run.sh` must drop this one.
- The good path emits the marker (PROMPT.md mandates it and `run.sh` treats its absence as a truncated report), then the sentinel the runner strips, then the optional pin block.
- The dream-triage call writes `triage-*.txt` to `MOCK_CAPTURE_DIR`, never `l2-*`, so a test asserting on L2's args or stdin cannot be overwritten by that call.

### Consequences

A new delivery rule needs a mode here that satisfies the old rule and fails the new one. Do not make the good path the only L2 shape any test sees: every assertion above is vacuous against it.

## the shared-memory mock simulates named failure shapes, and the triage suite keeps its own capture files

### Context

`apply-pins.sh` has to survive every shape in which the `shared-memory` CLI can answer badly. The mock stands in for the CLI and never touches Mnemopi, so each real failure shape needs a mode:

| Mode | What the mock does |
|---|---|
| `ok` (default) | prints a stored result |
| `fail` | prints an error result, exits 1 |
| `garbage` | exits 0 with output that is not JSON |
| `nocontext` | `context` fails, `call` is never reached |
| `emptyid` | `call` reports stored with an empty `memory_id` |
| `journal` | write committed but the journal append failed: status `mutation_committed_journal_incomplete`, a `memory_id`, exit 1 |
| `ctxexit` | `context` prints a valid `retainBank` but exits 1 |
| `storedexit1` | `call` prints a stored result with a `memory_id` but exits 1 |

`MOCK_SM_LOG` appends one JSON line per call (`tool`, `payload`, `cwd`). `context --cwd DIR` answers `bank-<basename DIR>` and is not logged. `startup --host` with no value fails closed with the harness-gate message of a real `shared-memory`; `MOCK_SM_GATE=0` stands in for an older build that ignores the flag.

The triage suite shares `tests/mock-claude.sh` with the L2 assertions. Its capture files are the mock's `triage-*` files, never its `l2-*` files, so this suite cannot disturb an assertion about L2's own arguments and prompt.

### Decision

The mode table and the gate switch are the contract between the mock and `tests/apply-pins.sh`. The triage suite reads only `triage-*` captures.

### Consequences

A new failure shape in the real CLI gets a mode here and a case in the pin tests together. Do not point the triage suite at an `l2-*` capture.
