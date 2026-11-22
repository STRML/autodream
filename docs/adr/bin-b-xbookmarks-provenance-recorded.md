# bin-b: which queryId source and which fetch path served the night are recorded on every path

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`get_query_id`, `qid_source`, `write_fetch_record`, `collect`)

## Context

A night that reused a cached queryId looks identical to one that proved the scraping walk still works, and the walk is the part most likely to break because it depends on X's bundle layout (#38). In the same way, a browser-mode night that fell back to GraphQL looks fine while the opted-in path is dead. CLAUDE.md "X bookmarks as idea fuel" covers both (`x_queryid_source`, `x_fetch_path`).

## Decision

- `get_query_id` writes `cache`, `fresh` or `failed` to `$TMP/queryid-source`. The default `not_attempted` stands when no credentials were available and the walk never ran. It is a file again, because `get_query_id` runs inside a command substitution.
- `FETCH_PATH` (`graphql`, `browser`, `fallback_graphql`, `failed`, `not_attempted`) and `BROWSER_CAUSE` go to `x-bookmarks-fetch.txt` through `write_fetch_record`. Line one is the path, line two the browser's cause, single-lined and cut to 300 characters.
- `collect` stamps both files on every path, early returns and the jq-missing stub included. run.sh copies them into run-stats.

## Consequences

"The walk did not run tonight" is the state this exists to make visible, so a new early return in `collect` must not skip the stamps. run.sh clears both files before each collect so a rebuild cannot report its predecessor's value.
