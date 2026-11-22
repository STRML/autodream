# tests-mock: the shared-memory mock simulates named failure shapes, and the triage suite keeps its own capture files

Status: accepted · Date: 2026-11-22 · Code: `tests/mock-shared-memory.sh` (`MOCK_SM_MODE`, `MOCK_SM_GATE`, `MOCK_SM_LOG`), `tests/dream-triage.sh`

## Context

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

## Decision

The mode table and the gate switch are the contract between the mock and `tests/apply-pins.sh`. The triage suite reads only `triage-*` captures.

## Consequences

A new failure shape in the real CLI gets a mode here and a case in the pin tests together. Do not point the triage suite at an `l2-*` capture.
