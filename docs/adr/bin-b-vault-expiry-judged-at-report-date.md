# bin-b: note expiry is judged against the report date, and expired notes are still archived

Status: accepted · Date: 2026-11-21 · Code: `bin/vault-notes.sh` (`report_date_of`, `note_expiry`, `collect`)

## Context

Rebuilding an old date, or a launchd catch-up running a missed night days later, would drop and archive every note whose expiry fell between that date and today. Those notes were active for the window being reported.

## Decision

- `report_date_of` takes the date from the findings dir name. A name that is not `YYYY-MM-DD` (tests, an ad-hoc dir) falls back to today. `archive_tags` uses the same function.
- A vault note with frontmatter `expires: YYYY-MM-DD` is dropped at collect time when that date is before the report date, so `PROMPT.md` keeps exactly one expiry format to reason about (the `- [date] (expires DATE)` lines in `notes.md`).
- An expired note is still written to the manifest, so it leaves the inbox. It has done its job.

## Consequences

Using `date +%F` for the comparison would drop live notes on every rebuild. The `notes.md` surface is not filtered here at all; its expiry stays in the prompt.
