# tests: x-bookmarks-suite: x-bookmarks suite: shim boundary, fixture traps and the browser watchdog

Status: accepted · Date: 2026-11-22 · Code: `tests/x-bookmarks.sh` (`make_ab_shim`, `bsetup`, `run_br`, `test_watchdog_does_not_fire_after_a_command_that_finished`), `tests/x-bookmarks.sh` (`fixture_page`, `deny_writes`, `test_walk_reaches_every_suffix_variant`, `make_har`, `make_page2`, `test_the_cursor_is_matched_as_a_value_not_a_substring`), `tests/x-bookmarks.sh` (`make_curl_shim`, `setup`, `run_bm`, `test_pages_are_paced_and_the_last_one_is_not_waited_on`, `test_queryid_source_is_recorded`)

## the browser path runs against an agent-browser shim, and the watchdog is pinned by its properties

### Context

The browser fetch path (#166) needs a logged-in profile to run for real, and nothing in this repo may log in to or fetch x.com. The path is unverified on a logged-in browser (CLAUDE.md, "The browser fetch path").

The watchdog (`run_bounded`) once slept the whole limit in one call and killed that sleep on a normal exit. Its subshell then ran its next statements (flag a timeout, signal the pid) before the parent killed it, and a good command could come back as exit 124. That race cannot be reproduced deterministically here, because `pkill` cannot enumerate processes under the sandbox.

### Decision

- `make_ab_shim` logs every call to `AB_LOG` and strips the global `--session`, `--profile` and `--headed` flags. It serves `MOCK_HAR` on `network har stop <path>` and answers `get url` with `AB_URL`. `AB_FAIL=<open|har-start|har-stop|get-url|wait|scroll|close>` makes that command exit 1. `AB_HANG=<same>` makes it `exec /bin/sleep 30`, so the watchdog's kill reaches the sleep itself and not a wrapper shell.
- The suite's `sleep` fake exits at once. The watchdog therefore calls `command -p sleep`, and the hang uses an absolute `/bin/sleep`.
- `test_watchdog_does_not_fire_after_a_command_that_finished` pins the properties of the polling shape instead of the race: with a 30 second limit every command succeeds, none is reported as a timeout, and the run finishes in under 20 seconds.

### Consequences

The 20 second bound is the only check that fails if the watchdog waits out its limit. The real client, its HAR format and the daemon-close behavior are untested here. The first logged-in run is the check.

## fixture shapes that keep an assertion able to fail

### Context

Each shape below was chosen because the obvious fixture lets the guarded bug pass.

### Decision

- **Emit order.** `fixture_page` lists id 100 (older) before id 200 (newer), so file position is oldest-first. The emit is newest first, so an implementation that trusts file position fails `test_newest_first`. Do not reorder the entries to match the output.
- **`deny_writes`.** `chmod 555` blocks writes for everyone but root. The helper probes with a real write and returns 1 when the directory still takes one, and callers then skip. A root run neither fails nor passes for the wrong reason.
- **Walk fixture.** `test_walk_reaches_every_suffix_variant` serves 30 `main.*.js` page URLs and a `bundle.Bookmarks.<hash>` variant whose chunk URL is the last one the walk enumerates (`<hash>9`). With the old global cap of 24 requests that variant sat behind the 30 page URLs and was never requested (#107).
- **HAR cursors.** `make_har` writes the cursor into each Bookmarks request's `variables` parameter: none for the first pair, `CURSOR_END` for the rest, `-` for none. The reader matches the cursor as a value in `variables`, so a HAR whose URLs lack it cannot exercise paging.
- **Cursor `20`.** `test_the_cursor_is_matched_as_a_value_not_a_substring` sets the bottom cursor to `20`, which is also the page size in every URL (`count%22%3A20`). A substring match reads page one as its own next page and accepts a capture with no page two.
- **Page two.** `make_page2` replaces the entries with one bookmark and no bottom cursor, so the last page reads as the end of the timeline. Adding a cursor entry turns the "complete under the cap" cases into incomplete ones.

### Consequences

Changing any of these fixtures can leave every assertion green with the guard removed. After editing one, rerun the test against a reverted guard.

## the suite fakes curl, sleep and the queryId cache, and pins every path that could reach the host

### Context

`bin/x-bookmarks.sh` talks to a live third party. The queryId walk scrapes X's JS bundle, and a fake of it would assert only that our regex matches a string we wrote (CLAUDE.md, "X bookmarks as idea fuel"). The two bugs found while building the fetcher both lived downstream of the HTTP call: the emit came out oldest-first, and `mark-read` silently no-opped on every line (`$ids | index(.id)` rebinds `.`). Neither showed up in a smoke test, and either would have quietly wasted the feature.

The script also paces pages with a real `sleep 2`, and it sources `$AUTODREAM_DIR/config`, which on a developer machine holds whatever the owner set.

### Decision

- `curl` is a fake earlier on PATH that honours `-o` and `-w '%{http_code}'` and serves `MOCK_BODY` or the fixture page.
- Every sandbox pre-seeds `state/query-id`, so detection and the bundle walk are skipped. `test_queryid_source_is_recorded` pins what that costs: a reused id is recorded as `cache`, the state #38 made visible (the fetch works either way, so the walk could rot unseen).
- `sleep` is a fake that appends its argv to `MOCK_SLEEP_LOG` and returns. No collect waits two seconds per page, and a test can still assert what was asked.
- `run_bm` pins `AUTODREAM_DIR` and `AUTODREAM_CONFIG` into the sandbox. Without the pin the script reads the developer's real `~/.claude/autodream/config` and inherits its settings.

### Consequences

The bundle walk is covered only by the one `make_walk_shim` case and by `x_queryid_source` in run-stats. Nothing in this suite proves the live walk works. A new test that calls the script directly, not through `run_bm`, loses the config pin. The watchdog in `bin/x-bookmarks.sh` uses `command -p sleep` so the sleep fake cannot disable it (see `tests-x-bookmarks-suite.md`).
