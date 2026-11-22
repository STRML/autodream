# bin-b: a session belongs to the day its records say, by top-level `.timestamp`, compared as epoch seconds

Status: accepted · Date: 2026-11-21 · Code: `bin/session-window.sh` (`in-window`, `bounds`)

## Context

Enumeration selected a session by file mtime inside the report day, so a session written again after its day closed (a resumed one, or OMP rewriting its title line) vanished from every later rebuild of that day, and a transcript spanning several days was read whole for each of them (#113).

## Decision

- The window is `[START, END)`: local midnight to the next local midnight from BSD `date` (`bounds`), so a DST day is 23 or 25 hours.
- A record's clock is its top-level `.timestamp` string (`2026-10-01T16:12:38.483Z`), which both harnesses write. An OMP `.message.timestamp` is an epoch-millisecond number on a record that already has the string, and is deliberately not read. A record whose timestamp is missing, not a string or not ISO-8601 UTC has no clock: it neither selects a file nor lands in a slice.
- Timestamps compare as epoch seconds with the fraction dropped, not as strings: `00.5Z` sorts before `00Z` lexicographically, which misplaces the boundary second.
- `in-window` is yes when any record is inside, no when records have clocks and none is inside, and when no record has a clock the file's mtime decides (before the day ended: yes, so it is biased to triage). Without that, the find that no longer has an upper bound would enumerate a clockless file on every later date and triage it twice under the wrong day.
- An unreadable file or a failing jq is exit 2, never 1. The caller keeps the session on an error, so a broken helper costs extra work and never reads as a quiet night.

## Consequences

CLAUDE.md, "Which day a session belongs to (the report-day window, #113)", carries the runner side. `tests/session-window.sh` pins DST bounds with literal expected values.
