# bin-a: the pins ledger never guesses, so every doubtful case stores nothing or becomes its own outcome

Status: accepted · Date: 2026-11-21 · Code: `bin/apply-pins.sh` (`apply_line`)

## Context

`pins-applied.tsv` holds `<sha1 of the resolved bank and the canonical pin><TAB><memory_id>` per stored pin. A pin already listed is skipped, so a rerun never stores the same memory twice. A failed call writes no row, so a rerun of the same date retries it. `run.sh`'s `sweep_stranded_pins` reruns the script for any date in the trailing week whose counters show failed pins.

Several ways of reading the ledger look like "not stored yet" when they are not.

## Decision

- An empty hash is refused. `cut` succeeds even when `shasum` dies, and an empty hash, once ledgered, would make every later pin in the file look like a duplicate. The hash must match `^[0-9a-f]{40}$`.
- A ledger that exists and cannot be read is `failed`, because reading it as empty would store the pin again. When duplicates cannot be ruled out, nothing is stored.
- An empty `memory_id` is `failed`. It is not a stored memory anyone can find, and ledgered it would block every retry.
- A ledger row that cannot be written after the memory is stored is its own outcome, `unledgered`, never `applied`. The id goes to the run log so the duplicate a rerun will create can be found and removed.

## Consequences

The counters separate `failed` (nothing stored, retryable) from `unledgered` (stored, will duplicate on rerun). Merging them hides a duplicate-memory risk. `tests/apply-pins.sh` pins each row of the failure matrix in `docs/plans/2026-09-15-mnemopi-pins.md`.
