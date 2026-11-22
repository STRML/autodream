# web: /login answers 200 with a refresh page, never a redirect

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-web.py` (`SAME_ORIGIN_HOP`, `AutodreamHandler.do_GET`)

## Context

`autodream-web open` hands the browser a `file://` page that navigates to `/login?t=...`. That is a cross-site navigation. A `303` to `/` stays inside the same navigation, so the browser treats the follow-up request as cross-site and withholds the `SameSite=Strict` session cookie `/login` just set. The user lands on a 401.

## Decision

`/login` sets the cookie and answers `200` with a page holding `<meta http-equiv="refresh" content="0;url=/">`. The refresh starts a new navigation. That one is same-origin, so the cookie goes with it.

## Consequences

Do not replace the page with a `Location` redirect, and do not loosen the cookie to `Lax` to make a redirect work: `Strict` is part of the local-dashboard threat model in CLAUDE.md ("Local web dashboard"). The browser suite (`tests/autodream-web-browser.py`) opens the real handoff file and fails if the content never renders.
