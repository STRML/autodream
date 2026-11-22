# bin-b: the browser fetch path is opt-in, falls back to GraphQL, and commits only a complete timeline

Status: accepted · Date: 2026-11-21 · Code: `bin/x-bookmarks.sh` (`run_fetch`, `fetch_new_browser`, `browser_capture`, `browser_read_pages`, `browser_pick_row`, `run_bounded`, `browser_lock`, `browser_lock_reap`, `browser_close`)

## Context

The queryId grep is the only part of the GraphQL path that ever broke (ten nights in 2026-09), so `AUTODREAM_X_FETCH=browser` (#166) removes it: a logged-in `agent-browser` profile opens x.com/i/bookmarks, a HAR records the page's own Bookmarks calls, and each response goes through the same `ingest_page` and `merge_state` as GraphQL. CLAUDE.md "The browser fetch path" is the full account. It is unverified against a logged-in browser.

## Decision

- The default stays GraphQL, and GraphQL is the fallback. Any browser failure falls back when credentials exist, and the cause is recorded (`bin-b-xbookmarks-provenance-recorded.md`).
- `run_fetch` reads the credentials only after the browser failed, so a night the browser served never sources them or writes the curl configs that hold the cookies. The session lives in the profile and reaches `agent-browser` as environment variables, so no secret is in argv and every call has the same argv shape.
- Browser mode is "not configured" only when there is neither a profile nor a credentials file.
- On any failure `fetch_new_browser` empties `new.jsonl`, because the caller's failure branch merges whatever it holds. `run_fetch` does the same for a failed GraphQL walk.
- `browser_read_pages` follows the cursor chain, not HAR order, so a retried request is not another page. `browser_pick_row` compares the cursor as a value read from the request's own `variables` parameter. A substring test of the URL matched a cursor of `20` against the page size in every URL and took page one for its own next page. The path is accepted only when it reached a known id, an empty page, a page with no bottom cursor, or the cap.
- The HAR starts before the page opens, or the first Bookmarks call is missed. The `wait` calls and scrolls are best effort, since X may never go idle, and a missed wait costs at worst a response the export does not hold, which is reported as such.
- `run_bounded` replaces `timeout(1)`, which macOS lacks. The watchdog polls once a second and leaves as soon as the command is gone. An earlier version slept the whole limit and killed that sleep on a normal exit, and the watchdog then flagged a timeout before the parent killed it, so a good command came back as 124. It sleeps through `command -p` so a test that shims `sleep` cannot make it fire at once.
- `browser_close` clears `BROWSER_OPEN` after the close, because `ab` sets it on every call and clearing first left it set, so the EXIT trap closed a second time. That trap needs no signal traps, since EXIT also runs on TERM, INT and HUP (measured under bash 3.2, `test_a_terminated_collector_closes_the_browser`).
- One run owns the profile at a time (`browser_lock`), because the run lock is per date and a Chrome profile belongs to one browser. A stale lock is renamed away by `browser_lock_reap`, never removed with `rm -rf` by path: a slow reaper could delete the lock a faster one had just taken. The rename is atomic, and the reaper puts the directory back if it holds a lock other than the one it judged stale. Only the process named in the pid file removes the lock.
- `browser_login` is headed, since X's login needs a password, a second factor and a person. It uses its own `<session>-login` session name so a nightly run that starts during login cannot close that window.

## Consequences

Known limit: the timeout signal goes to the `agent-browser` client, not its daemon, so a wedged daemon keeps the profile until someone runs `agent-browser --session autodream-x close`. The next night then falls back to GraphQL and names the cause. Changing the cursor or HAR logic needs `tests/x-bookmarks.sh` run, since only shims exercise it.
