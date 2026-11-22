# bin-a: a pin counts as stored only on exit 0 with status stored, or on mutation_committed_journal_incomplete

Status: accepted · Date: 2026-11-21 · Code: `bin/apply-pins.sh` (`apply_line`)

## Context

`shared-memory call mnemopi_remember` exits 1 with status `mutation_committed_journal_incomplete` when the write committed but its journal append failed. That memory exists and has an id. Calling it a failure would store it again on the next run, so the exit status alone cannot decide the outcome.

The script reads `pins.jsonl` on a separate fd, but a CLI that reads stdin must never be able to swallow the pins after the current one.

## Decision

- Both `shared-memory` calls (`context` and `call mnemopi_remember`) run with `</dev/null`.
- The output is parsed with `jq`, with the exit code passed in. A memory is stored when `status == "stored"` and the exit code is 0, or when the status is `mutation_committed_journal_incomplete`, the one status that may pair a nonzero exit with a stored memory. Anything else is `failed` and stays retryable.
- For the journal-incomplete status the script logs `stored <id>, but shared-memory reported mutation_committed_journal_incomplete` to stderr and still ledgers the pin.

## Consequences

A new shared-memory status that commits a write with a nonzero exit has to be added to the `jq` select, or its pins are stored again on every rerun. `bin-a-apply-pins-ledger-never-guesses` covers what happens after the status is read.
