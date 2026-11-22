# bin-a: only a cookie rejection ends a credential's life, and the running stretch is a lower bound

Status: accepted · Date: 2026-11-21 · Code: `bin/cookie-cadence.sh` (`classify`, the lifetime loop)

## Context

Issue #39 asks how long a pasted X `auth_token`/`ct0` pair lasts, because that number decides whether automating the capture is worth its moving parts. The bookmark fetcher authenticates with cookies the user pastes by hand. Every night already leaves the evidence: `findings/<date>/x-bookmarks.md` carries a `# x-bookmarks: fetch failed — ...` header when the fetch broke, and names expired cookies specifically.

The fetcher reports an expired credential in two ways: the 401/403 rejection and the login page it is served instead of JSON. Both say the same thing.

## Decision

- `classify` sorts each night into `ok`, `auth`, `other`, `none` or `absent`. Only `auth` ends a credential's life. A network failure or a missing jq (`other`), a night with no credentials configured (`none`) and a night with no `x-bookmarks.md` (`absent`) neither start nor end a life. They are nights that measured nothing.
- A life runs from the first working night after a paste to the first night the cookies were rejected.
- The current stretch of working nights is right-censored: the cookies are still alive, so its length is a lower bound on a lifetime, not a lifetime. The report says "a lower bound, not a lifetime".
- The mtime of `x-credentials` is read as the last paste. Its contents are never read.

## Consequences

Counting a network failure as an expiry would make the cadence come out far shorter than it is. Reporting the running stretch as a lifetime would understate it, which is the exact error that makes a yearly chore look monthly. If the fetcher changes the wording of its two expiry headers (`cookies are expired`, `expired or invalid`), `classify` reads them as `other` and expiries drop out of the measurement without any error. CLAUDE.md, "X bookmarks as idea fuel", describes `bin/cookie-cadence.sh` and states the same two rules, and `tests/cookie-cadence.sh` pins the classification against every header shape the fetcher writes.
