# bin-b: a paging walk ends only on a known end, and an unreadable response is never an empty page

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`ingest_page`, `next_cursor`, `fetch_new`, the `MAX_PAGES` check)

## Context

The walk stops at the first bookmark already in state, because the timeline is reverse-chronological and everything past that point is old. Recording a prefix of the timeline as seen therefore hides every older bookmark for good, so a walk that ends for the wrong reason silently loses data. CLAUDE.md "X bookmarks as idea fuel" ("A prefix of the timeline is committed only when it is complete") has the browser side of this.

Three defects shaped the code:

- `X_MAX_PAGES` set to something that is not a positive number made every `[ "$page" -le "$MAX_PAGES" ]` an error. Both paths read an error as "the cap is reached", giving an empty fetch or a capture accepted as complete.
- jq exiting nonzero with no output from `parse_page` used to read as an empty page, and the walk ended "complete" over a response it never read.
- `next_cursor` on a number-valued `entryId` failed in `startswith`. A failure there must not read as "no cursor", which means the end of the timeline.

## Decision

- A cap that is not a positive number is replaced by 3 with a warning on stderr. Leading zeros are decimal (`10#`).
- `ingest_page` returns 0 to carry on, 1 for an empty page (the timeline ended), 2 for a known bookmark, and 3 when the response cannot be parsed. Callers treat 3 as a failure of the whole walk, not as the end.
- `next_cursor` returns jq's exit status, and callers check it. `entryId` goes through `tostring`.
- `fetch_new` waits two seconds between pages, since X's timeline shifts between requests and a scraper-like burst is worse. It waits only when another page follows.

## Consequences

Any new fetch path must go through `ingest_page` and honor return code 3. Failure branches must empty `new.jsonl` before the state merge, since `merge_state` records whatever it holds (`bin-b-xbookmarks-browser-path.md`).
