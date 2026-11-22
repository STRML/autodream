# runsh: a session belongs to a report day by the timestamps inside it, with the enumeration's mtime test reduced to a lower bound

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`SESSION_WINDOW`, `ENUM_END`, `WINDOW_ON`, `WIN_START_EPOCH`, `WIN_END_EPOCH` block)

## Context
A session written to again after its day closed (resumed, or still running) used to drop out of every later rebuild of that day, and a transcript spanning several days was read whole for each of them (issue #113). See CLAUDE.md, "Which day a session belongs to (the report-day window, #113)".

## Decision
- The adapter contract is unchanged: `enumerate` keeps its `(root, from, to)` arguments and still filters on mtime. The runner passes it a far upper date (`ENUM_END` = report day plus five years), so the mtime test is a LOWER bound only (a file last written before the day began cannot hold a record from it). `bin/session-window.sh` then keeps the files with a record inside the day and cuts the stats and the worker's read to that day's records.
- "Far" is five years, not a year-9999 sentinel: BSD find on some macOS releases cannot parse a distant date and fails with "Can't parse date/time", so the date is also probed here with the same `find` the adapters run (`find / -maxdepth 0 ! -newermt ...`).
- The window is ON only when every piece works: the helper is found (via `find_lib`, for the partial-install reason in `helper-lookup-survives-partial-install`, and run through `bash`, not gated on `-x`, for the reason preflight.sh is), it turns the report day into epoch bounds, and the far date computes and is accepted by this host's find. Any one missing leaves the original bounded enumeration (`ENUM_END` = next day), so a degraded install reads exactly what it read before and never fails a night over this. `AUTODREAM_WINDOW=0` forces it off.

## Consequences
A session last written more than five years after its report day is not found by a rebuild of that day. Fixtures with timestamps must put them inside the date, since a record outside the day outranks the file's mtime.
