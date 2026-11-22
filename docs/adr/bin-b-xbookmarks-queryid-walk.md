# bin-b: the queryId walk reads the live bundle, enumerates the hash suffix, and keeps candidate order

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`detect_query_id`, `get_query_id`, `extract_qid`)

## Context

The queryId in the Bookmarks URL rotates whenever X deploys, so it is scraped from the live JS bundle and cached for a day (`X_QUERYID_TTL`). The walk is bookmarks page, then the webpack runtime's id-to-name and id-to-hash maps, then the Bookmarks chunk, then the literal beside `operationName:"Bookmarks"`. It broke from 2026-09-05 to 09-14 and every run reported "could not find the Bookmarks queryId in any X JS bundle". The cause was a hash regex pinned to `{7,8}` hex digits: X moved to 16-character hashes (`34778:"c316cbd4536390c0"`), `hash` came back empty, and no candidate URL was ever built.

## Decision

- The hash width is a range (`{7,64}`) and must not be pinned. The quotes on both ends keep the match on the hash map entry instead of the name entry, and `tail -1` takes the later occurrence because the id appears in both maps.
- The chunk's filename carries one more hex digit than the map stores (`main.<16>a.js` beside `main:"<16>"`, and `<name>.c316cbd4536390c0a.js` against `c316cbd4536390c0`). That digit cannot be derived, so `detect_query_id` enumerates it: `a` first because every observed chunk used it, then the bare hash in case X stops truncating, then the other 15 digits. A miss is a cheap 404, and the loop stops at the first bundle that yields a queryId.
- The page's own client-web URLs are capped at `PAGE_URL_CAP` (8) separately, so a page that lists many cannot push the reconstructed suffix variants out of the walk (#107). With the 17 suffix candidates the total is bounded by construction.
- The candidate list is deduplicated with `awk '!seen[$0]++'`, never `sort -u`. The suffix order is deliberate, and sorting put the digit variants ahead of `a`, so the one that resolves came last and the cap cut it off first.

## Consequences

Two layers of guessing (hash width, suffix digit) sit on X's bundle layout, which no fixture can honestly test (see CLAUDE.md "X bookmarks as idea fuel" on why #38 closed without one). `x_queryid_source` in run-stats is the signal (`bin-b-xbookmarks-provenance-recorded.md`). When the walk breaks again, read the actual bundle names before changing a regex.
