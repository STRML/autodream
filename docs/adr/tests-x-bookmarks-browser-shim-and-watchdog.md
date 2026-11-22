# tests-x-bookmarks: the browser path runs against an agent-browser shim, and the watchdog is pinned by its properties

Status: accepted · Date: 2026-11-22 · Code: `tests/x-bookmarks.sh` (`make_ab_shim`, `bsetup`, `run_br`, `test_watchdog_does_not_fire_after_a_command_that_finished`)

## Context

The browser fetch path (#166) needs a logged-in profile to run for real, and nothing in this repo may log in to or fetch x.com. The path is unverified on a logged-in browser (CLAUDE.md, "The browser fetch path").

The watchdog (`run_bounded`) once slept the whole limit in one call and killed that sleep on a normal exit. Its subshell then ran its next statements (flag a timeout, signal the pid) before the parent killed it, and a good command could come back as exit 124. That race cannot be reproduced deterministically here, because `pkill` cannot enumerate processes under the sandbox.

## Decision

- `make_ab_shim` logs every call to `AB_LOG` and strips the global `--session`, `--profile` and `--headed` flags. It serves `MOCK_HAR` on `network har stop <path>` and answers `get url` with `AB_URL`. `AB_FAIL=<open|har-start|har-stop|get-url|wait|scroll|close>` makes that command exit 1. `AB_HANG=<same>` makes it `exec /bin/sleep 30`, so the watchdog's kill reaches the sleep itself and not a wrapper shell.
- The suite's `sleep` fake exits at once. The watchdog therefore calls `command -p sleep`, and the hang uses an absolute `/bin/sleep`.
- `test_watchdog_does_not_fire_after_a_command_that_finished` pins the properties of the polling shape instead of the race: with a 30 second limit every command succeeds, none is reported as a timeout, and the run finishes in under 20 seconds.

## Consequences

The 20 second bound is the only check that fails if the watchdog waits out its limit. The real client, its HAR format and the daemon-close behavior are untested here. The first logged-in run is the check.
