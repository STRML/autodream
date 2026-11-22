# bin-a: a pin is stored only into the bank its project's own directory names, and a project matches by exact value

Status: accepted · Date: 2026-11-21 · Code: `bin/apply-pins.sh` (`project_cwd`, `apply_line`)

## Context

`pin-projects.tsv` (`project<TAB>cwd`, written by `run.sh` for every project the run triaged) is the authorization list: a pin naming any other project is refused. A model writes the project name in each pin.

`mnemopi_remember` takes its bank from the payload, then `MNEMOPI_MCP_BANK`, then `"default"`, and never from `--cwd`. A call that passes only `--cwd` lands every pin in the global store.

A forced rebuild can resolve a project to a different directory (`/tmp/a_b` and `/tmp/a-b` encode alike), and a pin stored in one bank is not stored in the other.

## Decision

- `project_cwd` passes the project to awk through `ENVIRON`, not `awk -v`. `-v` expands backslash escapes, so a model-written project could match a row it does not name.
- `apply_line` asks `shared-memory context --cwd <cwd>` for the project's `retainBank` and names it in the `mnemopi_remember` payload. No bank means no store: the pin counts as `failed` and stays retryable.
- The `context` output is captured into a variable first, so the call's own exit status counts. Piped straight into `jq`, only `jq`'s status would.
- The bank is part of the pin's identity: the ledger hash is the sha1 of `<bank>\n<canonical pin>`.

## Consequences

Changing the awk call back to `-v`, or dropping the bank from the payload or the hash, reopens a silent wrong-store or wrong-match path with no error. `tests/apply-pins.sh` and `tests/mock-shared-memory.sh` pin the bank rules (`MOCK_SM_MODE=ctxexit`: `context` prints a valid `retainBank` but exits 1). Plan and failure matrix: `docs/plans/2026-09-15-mnemopi-pins.md`.
