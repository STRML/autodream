# 0025: The local web dashboard

Status: accepted · Governs: `bin/threads.sh`, `tests/autodream-web-browser.py`, `tests/autodream-web.sh`, `bin/autodream-web.py`, `bin/autodream_web_data.py`, `bin/threads-render.py`, `bin/portable.sh`

This record holds 8 sections: one per decision, and a Background section for each narrative that used to live in CLAUDE.md.

- [Background: Local web dashboard](#background-local-web-dashboard)
- [the Pages demo shifts every date forward to the visitor's local today and reloads when the day changes](#the-pages-demo-shifts-every-date-forward-to-the-visitors-local-today-and-reloads-when-the-day-changes)
- [the screenshot fixture's older threads are unfinished work past the seven-day dropped cutoff](#the-screenshot-fixtures-older-threads-are-unfinished-work-past-the-seven-day-dropped-cutoff)
- [browser tests retry unfinished Chrome runs inside one shared time budget](#browser-tests-retry-unfinished-chrome-runs-inside-one-shared-time-budget)
- [/login answers 200 with a refresh page, never a redirect](#login-answers-200-with-a-refresh-page-never-a-redirect)
- [the server skips HTTPServer's reverse DNS lookup on bind](#the-server-skips-httpservers-reverse-dns-lookup-on-bind)
- [a night with run-stats but no worklist is damaged, not complete](#a-night-with-run-stats-but-no-worklist-is-damaged-not-complete)
- [threads-render hands jq its state as a file, never on stdin](#threads-render-hands-jq-its-state-as-a-file-never-on-stdin)

## Background: Local web dashboard

This section was moved here from the former CLAUDE.md. Its original title: "Local web dashboard".

`autodream-web open` signs in to the local five-view dashboard: Lately, Dreams,
Threads, Progress and Stats. The server binds only `127.0.0.1`; requests require
the canonical Host and session cookie, and POSTs also require Origin and
`X-Autodream: 1`. The token file is 0600. Query strings are redacted from logs.
The CSP is an HTTP header; transcript and model text reaches the DOM as text.

Threads has four tabs, Dropped, Open, Ideas and Done, each carrying its count. A card
has Resume and a "Move to" button group, labelled for screen readers, listing the
targets other than the view the card is in (a Dropped card offers all three). The
only thread POSTs are `/api/threads/<id>/resume` and `move-open`, `move-idea` and
`move-done`, which run `threads.sh move ID open|idea|done`; close and reopen are not
routes. The static `threads.html` copies the same `threads.sh move ID target` command
instead of posting.

Progress reads `locks/run-<date>.lock/pid` and `start`, using kill-0 and normalized
`ps -o lstart=` with a 2-second timeout. Missing recorded start retains the live-pid
fallback. Elapsed time comes from process start; unknown times are null. Locks
are read-only. The last log line is text, with no phase inference. Visible
Progress polls every 5 seconds and retries after “server not reachable”.

Stats uses the existing per-night cache and file mtime/size fingerprints, including
run-stats, categories, findings, sidecars and thread state. `read_allowed_run_stats`
fixes the HTTP allowlist in `bin/autodream_web_data.py`; unknown and account keys
are excluded before response construction. Numeric values must parse, unavailable
measurements stay null, and overlap events are null unless overlap was measured.
Activity and outcomes cover top-level sessions; missing sidecars leave gaps.
Category totals use `severity=all`, keeping separate severity rows in the API.
Charts use inline SVG, accessible labels and tables of values.
“Finished that day” counts current done threads whose `last_seen` is that day.
It changes on reopen and does not reconstruct historical status transitions.

The server class skips `HTTPServer.server_bind`'s `socket.getfqdn` (a reverse DNS lookup of
127.0.0.1). On the macOS runner it stalled for many seconds before the server printed its
origin, so 25 of the suite's 31 tests failed in `start_server` (#223; a faulthandler dump
named the line). Test fixture servers use `tests/loopback_http.py` for the same reason. `open`
writes a per-call handoff `web-login-<16 hex>.html` (0600, exclusive create) and puts `h=<id>`
in the login URL; a successful login deletes only its own file, and the next `open` sweeps
handoff files older than ten minutes (#199). The browser suite runs Chrome through `dump_dom`,
which retries with a larger virtual-time budget and a fresh profile while the page has not
written `data-result`, because a missing result means unfinished and `FAIL:` means failed
(#202). All Chrome time in one process shares a 270 second budget (`ADWEB_BROWSER_BUDGET`):
each attempt is clamped to what is left, a retry that restarts the live backend needs 40
seconds left, and `tests/autodream-web.sh` gives the suite 330 seconds, so an exhausted budget
fails one test with `TimeoutExpired` and the suite still prints its counts. Stats treats a night whose `run-stats.txt` exists but whose `sessions.txt` does not as
damaged: it is degraded and its sidecar-only top-level hashes count as pending (#204).
`launchd.yml`'s manual dispatch takes `suite=web` to run only this suite on macOS.

Run `TMPDIR=/tmp/adw41 /bin/bash tests/autodream-web.sh` for the data, HTTP security
and local browser suites. HTTP tests use ephemeral ports. The browser suite needs
Chrome; browser checks skip in CI and when Chrome is unavailable. The data and
HTTP suites still run in CI.

## the Pages demo shifts every date forward to the visitor's local today and reloads when the day changes

Status: accepted · Date: 2026-11-16 · Code: `docs/demo/demo-fetch.js` (`currentShift`, `move`, `window.fetch`), `docs/demo/build.py`

### Context

The demo has no server. API reads come from the JSON files `build.py` wrote next to the page, and thread actions answer with a notice instead of changing anything. Every date in the data is relative to the day it was built (`window.DEMO_BUILT`). Served as is, "the last 7 days", thread ages and the age filter would drift as the demo aged.

### Decision

- Answers are moved forward by the number of days between `DEMO_BUILT` and the visitor's local today, so those views read the same on any day in any timezone. Relative ages do not change, so neither do the statuses computed from them. Dates in a request route are moved back by the same amount before the file is looked up.
- The shift is fixed for the life of the page, because links already drawn carry shifted dates.
- The first request after the local date changes reloads the page instead of answering, which redraws every link. Before it does, it moves the dates in the URL fragment by the same days so the fragment still names the same report.
- Anything but a GET answers `{ok: false, error: "demo"}`, and only a fixed list of routes is served from files.

### Consequences

`tests/autodream-web-data.py` drives this file under node (`test_web_demo_moves_dates_to_the_visitors_today`, `test_web_demo_reloads_when_the_date_changes`), and `tests/ci-scope.sh` treats it as web scope. A new API route the dashboard fetches needs a JSON file in `build.py` and an entry in the route list here, or the demo answers `not_found`.

## the screenshot fixture's older threads are unfinished work past the seven-day dropped cutoff

Status: accepted · Date: 2026-11-16 · Code: `docs/screenshots/fixture.py` (`OLDER_THREADS`), `bin/threads.sh` (`DROPPED_DAYS`)

### Context

An open work thread reads as Dropped when its newest session is older than `AUTODREAM_THREADS_DROPPED_DAYS`, which defaults to 7 in `bin/threads.sh`. The fixture builds threads whose sessions predate the findings it writes, so the screenshot of the Threads view has a Dropped tab with something in it.

### Decision

`OLDER_THREADS` work rows with stored status `open` and an unfinished outcome (`not_achieved`, `partially_achieved` or `unclear_from_transcript`) use an age above seven days (`last_seen` is that many days back), so the read-time rule (`bin/threads-status.jq`) derives Dropped for them. Idea rows stay open at any age, so the fixture's old ideas fill the Ideas tab instead. The fixture never stores `dropped`.

### Consequences

If the default cutoff in `bin/threads.sh` changes, change the ages here or the Dropped tab in the screenshots goes empty.

## browser tests retry unfinished Chrome runs inside one shared time budget

Status: accepted · Date: 2026-11-21 · Code: `tests/autodream-web-browser.py` (`CHROME_ATTEMPTS`, `SUITE_BUDGET`, `RESTART_RESERVE`, `dump_dom`), `tests/autodream-web.sh`

### Context

`dump_dom` runs headless Chrome with `--virtual-time-budget`. A busy machine can exhaust that budget before the fetches a check waits for return, and the headless process can miss its deadline outright. Either way the page never writes `data-result`, which means unfinished, not failed (#202). A real `FAIL:` result is a failure and must not be retried.

Per-attempt deadlines cannot simply add up: a suite of 23 tests could spend 23 x 130 seconds.

### Decision

- `CHROME_ATTEMPTS` is a list of (virtual-time budget in ms, subprocess deadline in seconds) pairs. An attempt that wrote no `data-result` is retried with more room and a fresh profile. A `FAIL` result is returned at once.
- `SUITE_BUDGET` (`ADWEB_BROWSER_BUDGET`, default 270 seconds) covers all Chrome time in the process. Each attempt is clamped to what is left. `tests/autodream-web.sh` gives the process a deadline above this one, so the suite is not killed mid-run. When the budget is gone before any attempt starts, `dump_dom` raises `TimeoutExpired`. When it runs out after an unfinished attempt, `dump_dom` returns that last output and the calling test's assertion fails. Either way the suite still prints its counts.
- A retry must start from the state the first attempt started from. `before_retry` puts back anything the page's own run changed, such as a killed backend. A `before_retry` that restarts the live backend waits up to 30 seconds for its origin line and 5 to stop the old one, so a retry needs `RESTART_RESERVE` (40 seconds) left before it may start.
- The login handoff test gives Chrome a copy of the handoff page, because the server deletes the original on first login and a retry would otherwise read a file that is gone.

### Consequences

docs/adr/0025-web-dashboard.md#background-local-web-dashboard, section "Local web dashboard", states the shared budget and the 330-second shell deadline. Changing either number means changing both files. A new browser test that deletes or mutates state on its first page load needs a `before_retry`.

## /login answers 200 with a refresh page, never a redirect

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-web.py` (`SAME_ORIGIN_HOP`, `AutodreamHandler.do_GET`)

### Context

`autodream-web open` hands the browser a `file://` page that navigates to `/login?t=...`. That is a cross-site navigation. A `303` to `/` stays inside the same navigation, so the browser treats the follow-up request as cross-site and withholds the `SameSite=Strict` session cookie `/login` just set. The user lands on a 401.

### Decision

`/login` sets the cookie and answers `200` with a page holding `<meta http-equiv="refresh" content="0;url=/">`. The refresh starts a new navigation. That one is same-origin, so the cookie goes with it.

### Consequences

Do not replace the page with a `Location` redirect, and do not loosen the cookie to `Lax` to make a redirect work: `Strict` is part of the local-dashboard threat model in docs/adr/0025-web-dashboard.md#background-local-web-dashboard ("Local web dashboard"). The browser suite (`tests/autodream-web-browser.py`) opens the real handoff file and fails if the content never renders.

## the server skips HTTPServer's reverse DNS lookup on bind

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream-web.py` (`LoopbackServer.server_bind`)

### Context

`HTTPServer.server_bind` calls `socket.getfqdn(host)`, a reverse DNS lookup. On a loopback address it blocked for many seconds on the macOS CI runner before the server printed its origin, so 25 of the web suite's 31 tests failed in `start_server` (#223). docs/adr/0025-web-dashboard.md#background-local-web-dashboard, section "Local web dashboard", records the incident.

### Decision

`LoopbackServer` overrides `server_bind` to call `socketserver.TCPServer.server_bind` and then set `server_name` and `server_port` from `server_address`. Nothing in the server reads `server_name`.

### Consequences

If anything starts reading `server_name`, set it explicitly instead of restoring the lookup. Test fixture servers use `tests/loopback_http.py` for the same reason.

## a night with run-stats but no worklist is damaged, not complete

Status: accepted · Date: 2026-11-21 · Code: `bin/autodream_web_data.py` (`run_enumerated`, `night_sessions`)

### Context

Stats counts a night's sessions from `sessions.txt`. When that file is missing, treating the night as empty makes a damaged run read as complete, and a session that was triaged but never finished looks like it does not exist (#204).

`fatal_exit` in `run.sh` writes `run-stats.txt` with a `fatal:` line before any enumeration, so a fatal run legitimately has no worklist.

### Decision

- `run_enumerated` says whether a run got as far as enumeration. A readable `run-stats.txt` with no `fatal:` line means yes. One that exists but cannot be read also means yes, since an unreadable file proves nothing about a fatal exit. No file means no.
- When the run enumerated and `sessions.txt` is absent, the night is degraded (`sessions.txt` joins the unreadable set) and every `*.stats.json` sidecar counts as a pending session.
- Without a worklist no rebuild left stale sidecars behind, so a sidecar with no findings JSON is a session still pending. Leaving it out would read the night as complete.

### Consequences

The docs/adr/0025-web-dashboard.md#background-local-web-dashboard "Local web dashboard" section states the damaged-night rule in one sentence. Keep `tests/autodream-web-data.py` cases for fatal, unreadable and missing run-stats in step with this logic when `run.sh` changes what a fatal run writes.

## threads-render hands jq its state as a file, never on stdin

Status: accepted · Date: 2026-11-21 · Code: `bin/threads-render.py` (the status calculation call), `bin/portable.sh` (`tmo`)

### Context

The status filter runs `tmo 10 jq ...` through `portable.sh`. With no `timeout` binary on the host, `tmo` runs the command as a background job, and a background job's stdin is `/dev/null`. `tmo` now saves the caller's stdin on fd 3 and hands that to the job, but the renderer's own subprocess runs with `stdin=subprocess.DEVNULL`, so state piped on stdin would still reach jq empty.

### Decision

`threads-render.py` writes the state to a `NamedTemporaryFile` and passes its path as jq's input argument. Reading a named file does not depend on how `tmo` wires stdin.

### Consequences

Do not switch back to `input=` or a pipe to save the temp file. An empty jq result fails loudly (the renderer raises an invalid-JSON error), so a regression here shows up as an error, not an empty thread list.
