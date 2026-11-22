# bin-b: bookmarks come from X's internal web GraphQL endpoint, and its failures are self-documenting

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`fetch_page`, `parse_page`, `detect_query_id`, `FEATURES`, `BEARER`)

## Context

The official `GET /2/users/:id/bookmarks` has never been on X's free tier and needs Basic at $200/mo (checked 2026-08-02). The request contract (endpoint shape, bearer, headers, `features` and `fieldToggles`, the queryId walk, the response path) was taken on 2026-08-02 from displace-agency/x-bookmarks-exporter (`src/api.ts`), a working implementation. CLAUDE.md "X bookmarks as idea fuel" has the rest.

## Decision

- The script calls the web app's own GraphQL endpoint with cookies the user pasted once into `x-credentials`.
- `BEARER` is the public token embedded in X's web app. It is identical for every user and is not a secret, so it sits in the source.
- `FEATURES` is verbatim from the reference. A stale object comes back as HTTP 400 whose body names the missing flags, so the list is maintained reactively: read the error, add the keys. `fetch_page` also drops the cached queryId on a 400, because a rotated id produces the same status.
- X serves the login flow instead of redirecting when the session cookie is dead, so `detect_query_id` greps the page for it and reports expired cookies with `REAUTH_HINT`.
- `parse_page` mirrors the reference's `parseTweet`: the visibility wrapper puts the real tweet under `.tweet`, and the author handle moved from user `legacy` to user `core`, so both are tried.

## Consequences

The endpoint is unofficial and can change on any X deploy. Every failure it can produce is reported as the content of `x-bookmarks.md` (see `bin-b-xbookmarks-collect-always-writes-output.md`). The `FEATURES` list needs a hand edit when X adds a flag.
