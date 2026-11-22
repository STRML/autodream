# web: browser tests retry unfinished Chrome runs inside one shared time budget

Status: accepted · Date: 2026-11-21 · Code: `tests/autodream-web-browser.py` (`CHROME_ATTEMPTS`, `SUITE_BUDGET`, `RESTART_RESERVE`, `dump_dom`), `tests/autodream-web.sh`

## Context

`dump_dom` runs headless Chrome with `--virtual-time-budget`. A busy machine can exhaust that budget before the fetches a check waits for return, and the headless process can miss its deadline outright. Either way the page never writes `data-result`, which means unfinished, not failed (#202). A real `FAIL:` result is a failure and must not be retried.

Per-attempt deadlines cannot simply add up: a suite of 23 tests could spend 23 x 130 seconds.

## Decision

- `CHROME_ATTEMPTS` is a list of (virtual-time budget in ms, subprocess deadline in seconds) pairs. An attempt that wrote no `data-result` is retried with more room and a fresh profile. A `FAIL` result is returned at once.
- `SUITE_BUDGET` (`ADWEB_BROWSER_BUDGET`, default 270 seconds) covers all Chrome time in the process. Each attempt is clamped to what is left. `tests/autodream-web.sh` gives the process a deadline above this one, so an exhausted budget fails one test with `TimeoutExpired` and the suite still prints its counts.
- A retry must start from the state the first attempt started from. `before_retry` puts back anything the page's own run changed, such as a killed backend. A `before_retry` that restarts the live backend waits up to 30 seconds for its origin line and 5 to stop the old one, so a retry needs `RESTART_RESERVE` (40 seconds) left before it may start.
- The login handoff test gives Chrome a copy of the handoff page, because the server deletes the original on first login and a retry would otherwise read a file that is gone.

## Consequences

CLAUDE.md, section "Local web dashboard", states the shared budget and the 330-second shell deadline. Changing either number means changing both files. A new browser test that deletes or mutates state on its first page load needs a `before_retry`.
