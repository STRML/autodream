# bin-b: a tag is due for the report of the local day it was made on, decided here from taggedAt

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`tag_pending`)

## Context

A tag is a turn the user marked in a session for the nightly run to look at. The mod that writes `tags.jsonl` has no timezone to speak of, and an evening tag is already tomorrow in UTC. Trusting a UTC day written by the mod would hold back, by a night, exactly the tags made while reviewing the day. CLAUDE.md, "The focus mod", states the rule.

## Decision

`tag_pending report-date` emits, oldest first, the tags still owed a look:

- Made before the first instant after the reported local day. That cutoff comes from BSD `date` through `pdate_epoch` and `pdate_shift`, like `session-window.sh`, so a DST day is 23 or 25 hours. If it cannot be computed, everything made so far is due.
- Not consumed by an earlier report. A tag's identity is its id and its `taggedAt` (`key` is `id<TAB>taggedAt`), because untagging and tagging a turn again reuses the id.
- Ledger rows of the report date being built do not count, so rebuilding a date that already consumed its tags keeps them.
- A `taggedAt` that does not parse counts as already due, so a tag arrives late and never gets lost. `atEpoch` is null for it.
- A torn or foreign line is skipped, not fatal: two sessions can rewrite the file within moments of each other.

## Consequences

The mod writes no day. A tag made after local midnight waits for the next report. Failure to read the file is handled separately (see `bin-b-vault-tags-read-failure-is-unreadable.md`).
