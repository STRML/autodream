# rest: the Pages demo shifts every date forward to the visitor's local today and reloads when the day changes

Status: accepted · Date: 2026-11-16 · Code: `docs/demo/demo-fetch.js` (`currentShift`, `move`, `window.fetch`), `docs/demo/build.py`

## Context

The demo has no server. API reads come from the JSON files `build.py` wrote next to the page, and thread actions answer with a notice instead of changing anything. Every date in the data is relative to the day it was built (`window.DEMO_BUILT`). Served as is, "the last 7 days", thread ages and the age filter would drift as the demo aged.

## Decision

- Answers are moved forward by the number of days between `DEMO_BUILT` and the visitor's local today, so those views read the same on any day in any timezone. Relative ages do not change, so neither do the statuses computed from them. Dates in a request route are moved back by the same amount before the file is looked up.
- The shift is fixed for the life of the page, because links already drawn carry shifted dates.
- The first request after the local date changes reloads the page instead of answering, which redraws every link. Before it does, it moves the dates in the URL fragment by the same days so the fragment still names the same report.
- Anything but a GET answers `{ok: false, error: "demo"}`, and only a fixed list of routes is served from files.

## Consequences

`tests/autodream-web-data.py` drives this file under node (`test_web_demo_moves_dates_to_the_visitors_today`, `test_web_demo_reloads_when_the_date_changes`), and `tests/ci-scope.sh` treats it as web scope. A new API route the dashboard fetches needs a JSON file in `build.py` and an entry in the route list here, or the demo answers `not_found`.
