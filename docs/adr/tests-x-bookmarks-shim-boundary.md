# tests-x-bookmarks: the suite fakes curl, sleep and the queryId cache, and pins every path that could reach the host

Status: accepted · Date: 2026-11-22 · Code: `tests/x-bookmarks.sh` (`make_curl_shim`, `setup`, `run_bm`, `test_pages_are_paced_and_the_last_one_is_not_waited_on`, `test_queryid_source_is_recorded`)

## Context

`bin/x-bookmarks.sh` talks to a live third party. The queryId walk scrapes X's JS bundle, and a fake of it would assert only that our regex matches a string we wrote (CLAUDE.md, "X bookmarks as idea fuel"). The two bugs found while building the fetcher both lived downstream of the HTTP call: the emit came out oldest-first, and `mark-read` silently no-opped on every line (`$ids | index(.id)` rebinds `.`). Neither showed up in a smoke test, and either would have quietly wasted the feature.

The script also paces pages with a real `sleep 2`, and it sources `$AUTODREAM_DIR/config`, which on a developer machine holds whatever the owner set.

## Decision

- `curl` is a fake earlier on PATH that honours `-o` and `-w '%{http_code}'` and serves `MOCK_BODY` or the fixture page.
- Every sandbox pre-seeds `state/query-id`, so detection and the bundle walk are skipped. `test_queryid_source_is_recorded` pins what that costs: a reused id is recorded as `cache`, the state #38 made visible (the fetch works either way, so the walk could rot unseen).
- `sleep` is a fake that appends its argv to `MOCK_SLEEP_LOG` and returns. No collect waits two seconds per page, and a test can still assert what was asked.
- `run_bm` pins `AUTODREAM_DIR` and `AUTODREAM_CONFIG` into the sandbox. Without the pin the script reads the developer's real `~/.claude/autodream/config` and inherits its settings.

## Consequences

The bundle walk is covered only by the one `make_walk_shim` case and by `x_queryid_source` in run-stats. Nothing in this suite proves the live walk works. A new test that calls the script directly, not through `run_bm`, loses the config pin. The watchdog in `bin/x-bookmarks.sh` uses `command -p sleep` so the sleep fake cannot disable it (see `tests-x-bookmarks-browser-shim-and-watchdog.md`).
