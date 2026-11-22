# runsh: run-stats says how the bookmarks were fetched (queryId source, fetch path), always emitted

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `XQID_SOURCE`, `XFETCH_PATH`, `XFETCH_CAUSE` appended to `run-stats.txt`)

## Context
- `x_queryid_source` (#38): the queryId scraping walk against X's JS bundle is the one part of the fetcher with no test and the part most likely to break, since it turns on X's bundle layout. A cached id produces a working fetch without proving the walk still works, so `cache` and `fresh` have to be told apart or a walk that stopped working stays hidden until the cache expires. It is appended rather than written in the main block because the collector that knows the answer runs after `run-stats.txt` is closed; the key is emitted on every night that reaches the collectors, so a consumer never has to handle it being absent there (a zero-session or deferred night returns before them and writes neither key).
- `x_fetch_path` (#166): `graphql` is the default path; `browser` means `AUTODREAM_X_FETCH=browser` read them off a logged-in profile; `fallback_graphql` means the browser path failed and GraphQL served (its cause is the second line of the file); `failed` and `not_attempted` say nothing served. Emitted on the same nights as `x_queryid_source`, so on those nights absence only ever means an old runner.

## Decision
Both keys default to `not_attempted` when their record file is empty or missing; `x_fetch_browser_cause` is written only when a cause exists (tabs and CRs flattened). See CLAUDE.md, "X bookmarks as idea fuel" (`x_queryid_source`, "The browser fetch path").

## Consequences
`fallback_graphql` and `cache` are the states to watch because the night looks fine while the opted-in path or the walk is dead. PROMPT.md's self-audit names `fallback_graphql` every night it appears, and flags a stretch of `cache` with no `fresh` in it (`failed` is flagged on its own). The queryId walk stays untested on purpose (a fixture would assert a regex matches a string we wrote).
