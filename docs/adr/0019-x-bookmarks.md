# 0019: X bookmarks as idea fuel

Status: accepted · Governs: `bin/cookie-cadence.sh`, `bin/x-bookmarks.sh`, `bin/run.sh`

This record holds 14 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: X bookmarks as idea fuel](#background-x-bookmarks-as-idea-fuel)
- [Background: The browser fetch path (`AUTODREAM_X_FETCH=browser`, #166)](#background-the-browser-fetch-path-autodream_x_fetchbrowser-166)
- [`--days` is validated, never defaulted](#--days-is-validated-never-defaulted)
- [only a cookie rejection ends a credential's life, and the running stretch is a lower bound](#only-a-cookie-rejection-ends-a-credentials-life-and-the-running-stretch-is-a-lower-bound)
- [the browser fetch path is opt-in, falls back to GraphQL, and commits only a complete timeline](#the-browser-fetch-path-is-opt-in-falls-back-to-graphql-and-commits-only-a-complete-timeline)
- [every collect path exits 0 and writes its output file, and failure reasons cross subshells through a file](#every-collect-path-exits-0-and-writes-its-output-file-and-failure-reasons-cross-subshells-through-a-file)
- [bookmarks come from X's internal web GraphQL endpoint, and its failures are self-documenting](#bookmarks-come-from-xs-internal-web-graphql-endpoint-and-its-failures-are-self-documenting)
- [a paging walk ends only on a known end, and an unreadable response is never an empty page](#a-paging-walk-ends-only-on-a-known-end-and-an-unreadable-response-is-never-an-empty-page)
- [which queryId source and which fetch path served the night are recorded on every path](#which-queryid-source-and-which-fetch-path-served-the-night-are-recorded-on-every-path)
- [the queryId walk reads the live bundle, enumerates the hash suffix, and keeps candidate order](#the-queryid-walk-reads-the-live-bundle-enumerates-the-hash-suffix-and-keeps-candidate-order)
- [unread bookmarks are emitted from state, sorted by id, and marked read only after a real report](#unread-bookmarks-are-emitted-from-state-sorted-by-id-and-marked-read-only-after-a-real-report)
- [cookies stay out of argv, user-edited files are sourced with nounset off, and config is read here too](#cookies-stay-out-of-argv-user-edited-files-are-sourced-with-nounset-off-and-config-is-read-here-too)
- [X bookmarks collect has one shape for L2, and its record files are cleared first](#x-bookmarks-collect-has-one-shape-for-l2-and-its-record-files-are-cleared-first)
- [run-stats says how the bookmarks were fetched (queryId source, fetch path), always emitted](#run-stats-says-how-the-bookmarks-were-fetched-queryid-source-fetch-path-always-emitted)

## Background: X bookmarks as idea fuel

This section was moved here from the former CLAUDE.md. Its original title: "X bookmarks as idea fuel".

`bin/x-bookmarks.sh` fetches recent bookmarks into `findings/<date>/x-bookmarks.md`; `PROMPT.md`'s "Ideas from bookmarks" section crosses them against the day's findings. The section's whole value is the intersection, so the prompt is explicit that a bookmark with no connection to this run gets left out and "none connected" is a correct answer — otherwise the model manufactures links and the section becomes a reading list the user already read.

The official API is not an option: `GET /2/users/:id/bookmarks` has never been on the free tier and needs Basic at $200/mo (checked 2026-08-02). So it reads X's internal web GraphQL endpoint with cookies pasted once into `$AUTODREAM_DIR/x-credentials`. The queryId in that endpoint's path rotates on X deploys, which is why the script scrapes it from the live JS bundle and caches it rather than hardcoding one.

Two invariants keep this from ever costing a night's report: the script always exits 0, and it always writes its output file — including a "not configured" stub and a `# x-bookmarks: fetch failed — <reason>` header. `mark-read` runs only after a non-empty report, same reasoning as the note archive above: a bookmark stamped read by a run that produced nothing is a bookmark the user never gets an idea from.

The queryId walk against X's JS bundle stays untested, and #38 closed on that rather than on a fixture. A fixture would assert that our regex matches a string we wrote, and would keep passing on the only day it mattered — the day X changes its chunk naming. A live canary was rejected too: it buys a few hours of notice over the nightly report, at the cost of an unattended job hitting a third party on a schedule. What shipped instead is `x_queryid_source` in `run-stats.txt` (`fresh` / `cache` / `failed` / `not_attempted`), because the one state nothing could see was `cache` — the fetch works, so the walk looks fine, while it may have rotted at any point since the last `fresh`. `x-bookmarks.sh` stamps it on every path via a file rather than a variable, for the reason the whole script does: `get_query_id` runs inside a command substitution.

`bin/cookie-cadence.sh` (#39) answers how long a pasted cookie pair lasts, which is what decides whether automating the capture is worth its moving parts. Same shape as `oversized-gate.sh`: it recomputes from the `x-bookmarks.md` headers already on disk, makes no model calls, reads no credentials, and is safe to re-run. Two things in it are load-bearing rather than decorative. It counts only the 401/403 rejection and the login-page redirect as expiries — a dead network or a missing jq says nothing about the cookies, and folding those in would make a yearly chore read as a weekly one with no visible sign of the error. And a stretch of working nights with no expiry at the end of it is right-censored, so it is reported as a lower bound and never as a lifetime.

## Background: The browser fetch path (`AUTODREAM_X_FETCH=browser`, #166)

This section was moved here from the former CLAUDE.md. Its original title: "The browser fetch path (`AUTODREAM_X_FETCH=browser`, #166)".

The queryId grep is the only part of the GraphQL path that ever broke, so the opt-in browser path removes it: an `agent-browser` profile that a person logged in once opens `x.com/i/bookmarks`, a HAR records the page's own calls, and every `.../graphql/<id>/Bookmarks` response in it goes through `ingest_page`, the same parse, known-id stop and `merge_state` as the GraphQL path (`fetch_new` and `fetch_new_browser` share `ingest_init` and `ingest_page`, so the read-state rules cannot drift between them). It is **unverified on a logged-in browser**: the tests shim `agent-browser`, and nothing in this repo may log in to or fetch x.com. Decisions:

- **The default does not move.** Unset or unknown `AUTODREAM_X_FETCH` is `graphql` (an unknown value warns on stderr). With it unset, `agent-browser` is never called, and `tests/x-bookmarks.sh` pins that with a logging shim.
- **Every browser failure falls back to GraphQL when credentials exist.** `run_fetch` owns the order: browser, then `fetch_new`. Causes it can name: binary not found, no profile directory (the browser is never launched against a profile that does not exist, which would create an empty, logged-out one), a failed `har start`/`open`/`har stop`, a command past `X_BROWSER_TIMEOUT`, the page ending on a login URL, a Bookmarks response with 401/403/429/other status, no Bookmarks request in the HAR, an unreadable HAR. With no credentials, or a broken credentials file, there is no fallback and the failure header names the browser cause. When both fail, one reason carries both. Earlier unread bookmarks are still served, as for any failed fetch.
- **`x-bookmarks-fetch.txt` is the record.** Line one is the path (`graphql`, `browser`, `fallback_graphql`, `failed` or `not_attempted`), line two the browser's cause when it failed. `collect` writes it on every path, the jq-missing stub included, and `run.sh` copies them into run-stats as `x_fetch_path` and `x_fetch_browser_cause`. `fallback_graphql` is the state to watch: the fetch works, so the night looks fine while the opted-in path is dead, the same shape as `x_queryid_source: cache`. PROMPT.md's self-audit names it.
- **Browser mode is "not configured" only when there is no profile and no credentials.** A profile with no `x-credentials` is a complete setup; `status` then says the GraphQL fallback is unavailable.
- **No secret reaches argv or this script.** The session lives in the profile. The session and profile reach `agent-browser` as `AGENT_BROWSER_SESSION` and `AGENT_BROWSER_PROFILE`, so every call has the same argv shape. The one exception is `browser-login`, which passes `--profile` and `--headed` as flags because it is a person's one-off command. The credentials file is read only when the browser path has failed and the GraphQL fallback is about to run (`run_fetch`), so a night the browser served never sources it or writes the curl configs that hold the cookies (`test_credentials_are_read_only_when_the_fallback_runs`).
- **A bounded call, without `timeout(1)`.** `run_bounded` backgrounds the command and a watchdog subshell polls it once a second, leaving as soon as the command is gone and, at the limit, sending TERM and then KILL two seconds later, flagging the timeout in a file (a variable would die with the subshell). It polls instead of sleeping the whole limit because the first shape killed that sleep on a normal exit, and the subshell then ran its next statements (flag, signal) before the parent killed it, so a command that finished in time could come back as exit 124. The flag is now set only while the command is alive. The watchdog sleeps through `command -p sleep` because the test suite shims `sleep` to a no-op, and a shimmed watchdog fires at once. A test blocks the shim with `exec /bin/sleep` so the kill reaches the sleep itself. Known limit: the signal goes to the `agent-browser` client, not its process group (bash 3.2 has no `setsid`, and the client starts a daemon that is meant to outlive it). After a timeout `fetch_new_browser` asks the daemon to `close`, and a daemon too wedged to answer that keeps holding the profile until `agent-browser --session autodream-x close` or `agent-browser doctor --fix`; the next night then falls back to GraphQL and names the cause. `browser-login` is bounded the same way, but killing its client does not close the window it opened.
- **The HAR must start before the page opens**, or the first Bookmarks call is missed (`test_browser_mode_orders_the_har_before_the_page`). `wait` calls and scrolls are best effort; the export is not. The session is always closed, by `fetch_new_browser` and again by the EXIT trap if a signal cut it short. A TERM, INT or HUP runs that trap (measured under `/bin/bash` 3.2, pinned by `test_a_terminated_collector_closes_the_browser`), so there are no signal traps. A close that fails or times out is kept, not discarded: the night still counts as `browser` (the capture is good), and line two of `x-bookmarks-fetch.txt` says `the browser did not close cleanly`.
- **A prefix of the timeline is committed only when it is complete.** The walk stops at a known bookmark, so recording pages that did not reach one hides every older bookmark for good (the next night stops at the first known id). `browser_read_pages` therefore reads the HAR the way the GraphQL walk reads the API: the request with no cursor, then the request that carried the previous page's bottom cursor (the cursor is read out of each request's own `variables` parameter when the rows are built and compared as a value, `@uri`-encoded or raw; a substring test of the URL matched a cursor of `20` against the page size in every URL and took page one for its own next page, and a `features` parameter that mentions a cursor must not make the first page look like a later one), up to `X_MAX_PAGES`. It accepts the result when it reached a known id, an empty page, a page with no bottom cursor, or the cap, and otherwise fails the whole browser path ("the HAR holds no response to the Bookmarks request after cursor ..."), so a scroll or wait that did not load a page falls back to GraphQL instead of losing the page. Pages come from the cursor chain, not from HAR order, so a retried or refreshed request is not counted as another page, and a bad response among several answers to one request is skipped for a good one. A non-200 status, a body that is not JSON, JSON without `data.bookmark_timeline_v2.timeline.instructions`, and a timeline `parse_page` or `next_cursor` cannot parse (`ingest_page` returns 3; `next_cursor`'s exit status is checked, and a non-string `entryId` no longer breaks it) each fail the path, never read as an empty page or as the end of the timeline. `X_MAX_PAGES` must be a positive number or it is replaced by 3 with a warning, because a bad value made every cap test an error that both paths read as "cap reached". A well-formed empty timeline is a success. On any failure `new.jsonl` is emptied, because the caller's failure branch merges it into state; the same truncation now covers a GraphQL walk whose later page fails (the default path used to record the earlier pages as seen, which hid the later ones). Unverified: that agent-browser's HAR carries the same request URL, with the cursor in `variables`, that the page sent.
- **One run at a time owns the profile.** `browser_lock` (`$AUTODREAM_DIR/locks/x-browser.lock`, a `mkdir` with the owner's pid) is held from `browser_ready` to the end of `fetch_new_browser`, because the run lock is per date and two dates can collect at once, and a Chrome profile belongs to one browser: the second run would stop the first one's HAR or close its session. A live holder is waited for (`X_BROWSER_LOCK_WAIT`, default 120 seconds) and then the run falls back; a dead holder's lock, or one with no pid older than 300 seconds, is reclaimed by renaming it away (`browser_lock_reap`; `rm -rf` by path let a slow reaper delete the lock a faster one had just taken), and only the process whose pid is in the lock removes it. `browser-login` uses its own session name (`<session>-login`), so a nightly run that starts while you log in cannot close that window; Chrome refuses a second browser on the same profile, so that run falls back with the cause.
- **The record files are cleared before each collect.** `run.sh` removes `x-bookmarks-fetch.txt` and `x-bookmarks-queryid.txt` first, because a rebuild finds the earlier run's copies and a collector that is missing or dies early would have its predecessor's `browser` or `fresh` reported as tonight's (`test_x_fetch_path_reaches_run_stats`).
- **One page, plus scrolls.** The page makes one Bookmarks call; `X_MAX_PAGES - 1` scrolls trigger the rest. The GraphQL path stops at the first known bookmark before it requests the next page, and the browser path can only stop reading, not stop fetching, so it costs up to two more scrolls on a night with nothing new.
- **Cannot log in unattended.** `browser-login` opens the profile headed and prints the `close` command, because a headless run cannot share a profile with an open window. The README has the setup. `agent-browser` is a node script, so the launchd PATH needs `node` too: with `AUTODREAM_X_FETCH=browser` in the config, `install.sh` (`x_browser_bin_dirs`) puts the directory of `agent-browser` (or of an absolute `X_BROWSER_BIN` in the config) and of `node` into the plist PATH, and a re-install is needed after turning the mode on, as for an adapter (`tests/install-path.sh`).

## `--days` is validated, never defaulted

Status: accepted · Date: 2026-11-21 · Code: `bin/cookie-cadence.sh` (argument loop)

### Context

A bare `--days` with no value used to leave the argument loop's `shift 2` refusing to shift. `bin/oversized-gate.sh` was fixed for the same reason, and the loop here follows it.

### Decision

`--days` exits 2 with a message when its value is missing, is not digits, or is zero. It never falls back to a default for a missing value.

### Consequences

Defaulting a missing value would turn a typo into a full-history run. A new numeric option in this script gets the same checks.

## only a cookie rejection ends a credential's life, and the running stretch is a lower bound

Status: accepted · Date: 2026-11-21 · Code: `bin/cookie-cadence.sh` (`classify`, the lifetime loop)

### Context

Issue #39 asks how long a pasted X `auth_token`/`ct0` pair lasts, because that number decides whether automating the capture is worth its moving parts. The bookmark fetcher authenticates with cookies the user pastes by hand. Every night already leaves the evidence: `findings/<date>/x-bookmarks.md` carries a `# x-bookmarks: fetch failed — ...` header when the fetch broke, and names expired cookies specifically.

The fetcher reports an expired credential in two ways: the 401/403 rejection and the login page it is served instead of JSON. Both say the same thing.

### Decision

- `classify` sorts each night into `ok`, `auth`, `other`, `none` or `absent`. Only `auth` ends a credential's life. A network failure or a missing jq (`other`), a night with no credentials configured (`none`) and a night with no `x-bookmarks.md` (`absent`) neither start nor end a life. They are nights that measured nothing.
- A life runs from the first working night after a paste to the first night the cookies were rejected.
- The current stretch of working nights is right-censored: the cookies are still alive, so its length is a lower bound on a lifetime, not a lifetime. The report says "a lower bound, not a lifetime".
- The mtime of `x-credentials` is read as the last paste. Its contents are never read.

### Consequences

Counting a network failure as an expiry would make the cadence come out far shorter than it is. Reporting the running stretch as a lifetime would understate it, which is the exact error that makes a yearly chore look monthly. If the fetcher changes the wording of its two expiry headers (`cookies are expired`, `expired or invalid`), `classify` reads them as `other` and expiries drop out of the measurement without any error. docs/adr/0019-x-bookmarks.md#background-x-bookmarks-as-idea-fuel, "X bookmarks as idea fuel", describes `bin/cookie-cadence.sh` and states the same two rules, and `tests/cookie-cadence.sh` pins the classification against every header shape the fetcher writes.

## the browser fetch path is opt-in, falls back to GraphQL, and commits only a complete timeline

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`run_fetch`, `fetch_new_browser`, `browser_capture`, `browser_read_pages`, `browser_pick_row`, `run_bounded`, `browser_lock`, `browser_lock_reap`, `browser_close`)

### Context

The queryId grep is the only part of the GraphQL path that ever broke (ten nights in 2026-09), so `AUTODREAM_X_FETCH=browser` (#166) removes it: a logged-in `agent-browser` profile opens x.com/i/bookmarks, a HAR records the page's own Bookmarks calls, and each response goes through the same `ingest_page` and `merge_state` as GraphQL. docs/adr/0019-x-bookmarks.md#background-the-browser-fetch-path-autodream_x_fetchbrowser-166 "The browser fetch path" is the full account. It is unverified against a logged-in browser.

### Decision

- The default stays GraphQL, and GraphQL is the fallback. Any browser failure falls back when credentials exist, and the cause is recorded (`docs/adr/0019-x-bookmarks.md#which-queryid-source-and-which-fetch-path-served-the-night-are-recorded-on-every-path`).
- `run_fetch` reads the credentials only after the browser failed, so a night the browser served never sources them or writes the curl configs that hold the cookies. The session lives in the profile and reaches `agent-browser` as environment variables, so no secret is in argv and every call has the same argv shape.
- Browser mode is "not configured" only when there is neither a profile nor a credentials file.
- On any failure `fetch_new_browser` empties `new.jsonl`, because the caller's failure branch merges whatever it holds. `run_fetch` does the same for a failed GraphQL walk.
- `browser_read_pages` follows the cursor chain, not HAR order, so a retried request is not another page. `browser_pick_row` compares the cursor as a value read from the request's own `variables` parameter. A substring test of the URL matched a cursor of `20` against the page size in every URL and took page one for its own next page. The path is accepted only when it reached a known id, an empty page, a page with no bottom cursor, or the cap.
- The HAR starts before the page opens, or the first Bookmarks call is missed. The `wait` calls and scrolls are best effort, since X may never go idle, and a missed wait costs at worst a response the export does not hold, which is reported as such.
- `run_bounded` replaces `timeout(1)`, which macOS lacks. The watchdog polls once a second and leaves as soon as the command is gone. An earlier version slept the whole limit and killed that sleep on a normal exit, and the watchdog then flagged a timeout before the parent killed it, so a good command came back as 124. It sleeps through `command -p` so a test that shims `sleep` cannot make it fire at once.
- `browser_close` clears `BROWSER_OPEN` after the close, because `ab` sets it on every call and clearing first left it set, so the EXIT trap closed a second time. That trap needs no signal traps, since EXIT also runs on TERM, INT and HUP (measured under bash 3.2, `test_a_terminated_collector_closes_the_browser`).
- One run owns the profile at a time (`browser_lock`), because the run lock is per date and a Chrome profile belongs to one browser. A stale lock is renamed away by `browser_lock_reap`, never removed with `rm -rf` by path: a slow reaper could delete the lock a faster one had just taken. The rename is atomic, and the reaper puts the directory back if it holds a lock other than the one it judged stale. Only the process named in the pid file removes the lock.
- `browser_login` is headed, since X's login needs a password, a second factor and a person. It uses its own `<session>-login` session name so a nightly run that starts during login cannot close that window.

### Consequences

Known limit: the timeout signal goes to the `agent-browser` client, not its daemon, so a wedged daemon keeps the profile until someone runs `agent-browser --session autodream-x close`. The next night then falls back to GraphQL and names the cause. Changing the cursor or HAR logic needs `tests/x-bookmarks.sh` run, since only shims exercise it.

## every collect path exits 0 and writes its output file, and failure reasons cross subshells through a file

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`collect`, `fail`, `state_write_failed`, the `HAVE_JQ` dispatch)

### Context

`x-bookmarks.sh` runs inside the nightly pipeline. X changing a bundle path at 3am must not cost a night's report, and PROMPT.md reads an absent `x-bookmarks.md` as "feature not enabled, do not mention it". So a failure has to be the content of the file, never an exit code or a missing file. docs/adr/0019-x-bookmarks.md#background-x-bookmarks-as-idea-fuel "X bookmarks as idea fuel" states the invariant.

Three incidents shaped the code:

- A missing `jq` used to `exit 0` before the dispatch. run.sh's `|| log` never fired, and a user with working credentials saw the section vanish from every report with nothing separating "off" from "broken". The jq check now only sets `HAVE_JQ`, and `collect` writes a `fetch failed` stub.
- `fail()` first assigned `FAIL_REASON` from inside nested command substitutions (`qid=$(get_query_id)` runs `qid=$(detect_query_id)`). Each forks a subshell whose variable writes are discarded, so the cookie-expiry remediation arrived as an empty string and the report said a fetch failed for no stated reason.
- `merge_state` failing meant this run's bookmarks never reached state, and `emit_unread` read the old state: with none, the report was told there is nothing unread (#108).

### Decision

- `fail` writes the reason to `$TMP/fail-reason`, and `fail_reason` reads it. A file crosses the subshell boundary; a variable does not.
- Every `collect` outcome (not configured, credentials broken, fetch failed, jq missing) writes `x-bookmarks.md` and the manifest and exits 0.
- A failed `merge_state` is reported through `state_write_failed`, under the `fetch failed` header L2 already treats as a failure, instead of letting an old state read as "nothing unread".

### Consequences

Nothing about a bookmark may ever change the exit status of `collect`, and a new failure path must write the file. A new value that has to leave `get_query_id` or `detect_query_id` must go through a file too (`docs/adr/0019-x-bookmarks.md#which-queryid-source-and-which-fetch-path-served-the-night-are-recorded-on-every-path`).

## bookmarks come from X's internal web GraphQL endpoint, and its failures are self-documenting

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`fetch_page`, `parse_page`, `detect_query_id`, `FEATURES`, `BEARER`)

### Context

The official `GET /2/users/:id/bookmarks` has never been on X's free tier and needs Basic at $200/mo (checked 2026-08-02). The request contract (endpoint shape, bearer, headers, `features` and `fieldToggles`, the queryId walk, the response path) was taken on 2026-08-02 from displace-agency/x-bookmarks-exporter (`src/api.ts`), a working implementation. docs/adr/0019-x-bookmarks.md#background-x-bookmarks-as-idea-fuel "X bookmarks as idea fuel" has the rest.

### Decision

- The script calls the web app's own GraphQL endpoint with cookies the user pasted once into `x-credentials`.
- `BEARER` is the public token embedded in X's web app. It is identical for every user and is not a secret, so it sits in the source.
- `FEATURES` is verbatim from the reference. A stale object comes back as HTTP 400 whose body names the missing flags, so the list is maintained reactively: read the error, add the keys. `fetch_page` also drops the cached queryId on a 400, because a rotated id produces the same status.
- X serves the login flow instead of redirecting when the session cookie is dead, so `detect_query_id` greps the page for it and reports expired cookies with `REAUTH_HINT`.
- `parse_page` mirrors the reference's `parseTweet`: the visibility wrapper puts the real tweet under `.tweet`, and the author handle moved from user `legacy` to user `core`, so both are tried.

### Consequences

The endpoint is unofficial and can change on any X deploy. Every failure it can produce is reported as the content of `x-bookmarks.md` (see `docs/adr/0019-x-bookmarks.md#every-collect-path-exits-0-and-writes-its-output-file-and-failure-reasons-cross-subshells-through-a-file`). The `FEATURES` list needs a hand edit when X adds a flag.

## a paging walk ends only on a known end, and an unreadable response is never an empty page

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`ingest_page`, `next_cursor`, `fetch_new`, the `MAX_PAGES` check)

### Context

The walk stops at the first bookmark already in state, because the timeline is reverse-chronological and everything past that point is old. Recording a prefix of the timeline as seen therefore hides every older bookmark for good, so a walk that ends for the wrong reason silently loses data. docs/adr/0019-x-bookmarks.md#background-x-bookmarks-as-idea-fuel "X bookmarks as idea fuel" ("A prefix of the timeline is committed only when it is complete") has the browser side of this.

Three defects shaped the code:

- `X_MAX_PAGES` set to something that is not a positive number made every `[ "$page" -le "$MAX_PAGES" ]` an error. Both paths read an error as "the cap is reached", giving an empty fetch or a capture accepted as complete.
- jq exiting nonzero with no output from `parse_page` used to read as an empty page, and the walk ended "complete" over a response it never read.
- `next_cursor` on a number-valued `entryId` failed in `startswith`. A failure there must not read as "no cursor", which means the end of the timeline.

### Decision

- A cap that is not a positive number is replaced by 3 with a warning on stderr. Leading zeros are decimal (`10#`).
- `ingest_page` returns 0 to carry on, 1 for an empty page (the timeline ended), 2 for a known bookmark, and 3 when the response cannot be parsed. Callers treat 3 as a failure of the whole walk, not as the end.
- `next_cursor` returns jq's exit status, and callers check it. `entryId` goes through `tostring`.
- `fetch_new` waits two seconds between pages, since X's timeline shifts between requests and a scraper-like burst is worse. It waits only when another page follows.

### Consequences

Any new fetch path must go through `ingest_page` and honor return code 3. Failure branches must empty `new.jsonl` before the state merge, since `merge_state` records whatever it holds (`docs/adr/0019-x-bookmarks.md#the-browser-fetch-path-is-opt-in-falls-back-to-graphql-and-commits-only-a-complete-timeline`).

## which queryId source and which fetch path served the night are recorded on every path

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`get_query_id`, `qid_source`, `write_fetch_record`, `collect`)

### Context

A night that reused a cached queryId looks identical to one that proved the scraping walk still works, and the walk is the part most likely to break because it depends on X's bundle layout (#38). In the same way, a browser-mode night that fell back to GraphQL looks fine while the opted-in path is dead. docs/adr/0019-x-bookmarks.md#background-x-bookmarks-as-idea-fuel "X bookmarks as idea fuel" covers both (`x_queryid_source`, `x_fetch_path`).

### Decision

- `get_query_id` writes `cache`, `fresh` or `failed` to `$TMP/queryid-source`. The default `not_attempted` stands when no credentials were available and the walk never ran. It is a file again, because `get_query_id` runs inside a command substitution.
- `FETCH_PATH` (`graphql`, `browser`, `fallback_graphql`, `failed`, `not_attempted`) and `BROWSER_CAUSE` go to `x-bookmarks-fetch.txt` through `write_fetch_record`. Line one is the path, line two the browser's cause, single-lined and cut to 300 characters.
- `collect` stamps both files on every path, early returns and the jq-missing stub included. run.sh copies them into run-stats.

### Consequences

"The walk did not run tonight" is the state this exists to make visible, so a new early return in `collect` must not skip the stamps. run.sh clears both files before each collect so a rebuild cannot report its predecessor's value.

## the queryId walk reads the live bundle, enumerates the hash suffix, and keeps candidate order

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`detect_query_id`, `get_query_id`, `extract_qid`)

### Context

The queryId in the Bookmarks URL rotates whenever X deploys, so it is scraped from the live JS bundle and cached for a day (`X_QUERYID_TTL`). The walk is bookmarks page, then the webpack runtime's id-to-name and id-to-hash maps, then the Bookmarks chunk, then the literal beside `operationName:"Bookmarks"`. It broke from 2026-09-05 to 09-14 and every run reported "could not find the Bookmarks queryId in any X JS bundle". The cause was a hash regex pinned to `{7,8}` hex digits: X moved to 16-character hashes (`34778:"c316cbd4536390c0"`), `hash` came back empty, and no candidate URL was ever built.

### Decision

- The hash width is a range (`{7,64}`) and must not be pinned. The quotes on both ends keep the match on the hash map entry instead of the name entry, and `tail -1` takes the later occurrence because the id appears in both maps.
- The chunk's filename carries one more hex digit than the map stores (`main.<16>a.js` beside `main:"<16>"`, and `<name>.c316cbd4536390c0a.js` against `c316cbd4536390c0`). That digit cannot be derived, so `detect_query_id` enumerates it: `a` first because every observed chunk used it, then the bare hash in case X stops truncating, then the other 15 digits. A miss is a cheap 404, and the loop stops at the first bundle that yields a queryId.
- The page's own client-web URLs are capped at `PAGE_URL_CAP` (8) separately, so a page that lists many cannot push the reconstructed suffix variants out of the walk (#107). With the 17 suffix candidates the total is bounded by construction.
- The candidate list is deduplicated with `awk '!seen[$0]++'`, never `sort -u`. The suffix order is deliberate, and sorting put the digit variants ahead of `a`, so the one that resolves came last and the cap cut it off first.

### Consequences

Two layers of guessing (hash width, suffix digit) sit on X's bundle layout, which no fixture can honestly test (see docs/adr/0019-x-bookmarks.md#background-x-bookmarks-as-idea-fuel "X bookmarks as idea fuel" on why #38 closed without one). `x_queryid_source` in run-stats is the signal (`docs/adr/0019-x-bookmarks.md#which-queryid-source-and-which-fetch-path-served-the-night-are-recorded-on-every-path`). When the walk breaks again, read the actual bundle names before changing a regex.

## unread bookmarks are emitted from state, sorted by id, and marked read only after a real report

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`emit_unread`, `merge_state`, `mark_read`, `collect_bookmarks`)

### Context

docs/adr/0019-x-bookmarks.md#background-x-bookmarks-as-idea-fuel "X bookmarks as idea fuel" and "What the consume gate actually has to check" give the contract. Five defects shaped the code:

- After a failed run the bookmarks are already recorded as seen (so incremental paging stops at them) but nobody was shown them. Emitting only this fetch's finds would drop them forever.
- The fetch appends each page newest-first, so file order is chronological only within one run. Taking the head or tail of it served the oldest 40 bookmarks.
- Cursor pagination can return one post on two pages (the timeline shifts between requests). Deduping against `$SEEN` alone, which is state from before the run, wrote both copies: one bookmark shown twice, using two `MAX_UNREAD` slots.
- `$TMP` is under `TMPDIR`, a different filesystem on macOS, so `mv` from there is a copy-then-unlink, not an atomic rename. A truncated `seen.jsonl` re-surfaces every lost bookmark as unread.
- In `$ids | index(.id)` the `.` has already been rebound to the array, so `.id` indexes an array with a string and jq errors on every line. The result is a silent no-op that leaves everything unread forever.

### Decision

- `collect_bookmarks` merges the fetch into `seen.jsonl`, then `emit_unread` emits every entry with a null `read_on`, not only this fetch's. A failed fetch still lets earlier unread bookmarks through; "failed" is the header only when there is also nothing to show.
- `emit_unread` sorts by `[(.id | length), .id]` descending. Snowflake ids exceed 2^53, so `tonumber` would round them. Length-then-string orders numeric strings correctly even if X shortens ids again.
- `merge_state` keeps an `accepted-ids` file for ids taken during this run, and stages its temp file in `STATE_DIR` so `mv` is a real rename, gated on the copy having succeeded. `mark_read` stages in `STATE_DIR` for the same reason.
- `mark_read` binds `.id as $i` before the pipe into `$ids`.
- run.sh calls `mark-read` only after a non-empty report exists.

### Consequences

Never sort by file position, stage state outside `STATE_DIR`, or rebind `.` before reading `.id` in that filter. `tests/x-bookmarks.sh` pins the emit order and the mark-read no-op.

## cookies stay out of argv, user-edited files are sourced with nounset off, and config is read here too

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`write_curl_configs`, `cfg_escape`, `warn_perms`, `load_creds`, the config source at the top)

### Context

docs/adr/0019-x-bookmarks.md#background-x-bookmarks-as-idea-fuel "X bookmarks as idea fuel" and "Bash traps this feature hit" give the background. The cookies are a full account session: anyone who can read them can post as the user. `-H "cookie: auth_token=..."` puts that into the process list for the life of each request, and the nightly run makes several while unattended.

### Decision

- `write_curl_configs` writes the headers to two 0600 `curl --config` files inside the per-run `$TMP`, which the EXIT trap removes. There are two because the bookmarks-page fetch sends cookies only, while the GraphQL call sends cookies, the CSRF token and the bearer. It is the one place credentials touch the disk.
- The JS chunk fetch is deliberately unauthenticated. It hits abs.twimg.com, a public CDN, and a session cookie sent there would widen where the credential goes for nothing.
- `cfg_escape` escapes `\` and `"` because curl's config parser treats a double-quoted value as escapable. X cookie values are hex or base64url in practice, but the failure would be a curl parse error on a line the user pasted by hand.
- `warn_perms` warns about a mode other than 600 or 400 and never refuses. A nightly job that silently does nothing is worse than one that works and complains.
- Both the config and the credentials file are sourced with `set +u`. Under nounset a stray unbound reference in a hand-edited file kills the whole script, `||` cannot catch it, and `collect` then never writes its output stub. L2 would read the feature as off rather than broken. The config source also replays the `export -p` snapshot so the caller's environment wins, and stays quiet because run.sh already warns about the typo.
- The config is sourced here too, not only in run.sh, because `status` is run by hand and must see the settings the nightly run sees.
- The `portable.sh` lookup falls back to the symlink target's directory: installed copies are symlinks, and a merge updates them before `install.sh` links a new helper.

### Consequences

Never pass a credential as a curl argument or an environment value to a child. A new authenticated call site gets its header set in `write_curl_configs`, not inline.

## X bookmarks collect has one shape for L2, and its record files are cleared first

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the `XBOOKMARKS collect` step and the `rm -f` before it)

### Context
Unread bookmarks become idea fuel: L2 cross-references what the user saved against what they worked on. The script always exits 0 and always writes the file, including a "not configured" stub, so this seam has exactly one shape for L2. A rebuild of a date finds the earlier run's `x-bookmarks-fetch.txt` and `x-bookmarks-queryid.txt`; a collector that is missing or dies before rewriting them would otherwise have its predecessor's `browser` or `fresh` read below as tonight's.

### Decision
`run.sh` removes both record files before invoking `collect`; a failed or missing collector logs and the run continues. See docs/adr/0019-x-bookmarks.md#background-x-bookmarks-as-idea-fuel, "X bookmarks as idea fuel" ("The record files are cleared before each collect", `test_x_fetch_path_reaches_run_stats`).

### Consequences
Dropping the `rm -f` makes `x_fetch_path` and `x_queryid_source` report a previous night. The `mark-read` side is gated separately (see `consume-gated-on-complete-dream-and-normal-date`).

## run-stats says how the bookmarks were fetched (queryId source, fetch path), always emitted

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `XQID_SOURCE`, `XFETCH_PATH`, `XFETCH_CAUSE` appended to `run-stats.txt`)

### Context
- `x_queryid_source` (#38): the queryId scraping walk against X's JS bundle is the one part of the fetcher with no test and the part most likely to break, since it turns on X's bundle layout. A cached id produces a working fetch without proving the walk still works, so `cache` and `fresh` have to be told apart or a walk that stopped working stays hidden until the cache expires. It is appended rather than written in the main block because the collector that knows the answer runs after `run-stats.txt` is closed; the key is emitted on every night that reaches the collectors, so a consumer never has to handle it being absent there (a zero-session night, or one an L1 network deferral ends, returns before them and writes neither key).
- `x_fetch_path` (#166): `graphql` is the default path; `browser` means `AUTODREAM_X_FETCH=browser` read them off a logged-in profile; `fallback_graphql` means the browser path failed and GraphQL served (its cause is the second line of the file); `failed` and `not_attempted` say nothing served. Emitted on the same nights as `x_queryid_source`, so on those nights absence only ever means an old runner.

### Decision
Both keys default to `not_attempted` when their record file is empty or missing; `x_fetch_browser_cause` is written only when a cause exists (tabs and CRs flattened). See docs/adr/0019-x-bookmarks.md#background-x-bookmarks-as-idea-fuel, "X bookmarks as idea fuel" (`x_queryid_source`, "The browser fetch path").

### Consequences
`fallback_graphql` and `cache` are the states to watch because the night looks fine while the opted-in path or the walk is dead. PROMPT.md's self-audit names `fallback_graphql` every night it appears, and flags a stretch of `cache` with no `fresh` in it (`failed` is flagged on its own). The queryId walk stays untested on purpose (a fixture would assert a regex matches a string we wrote).
