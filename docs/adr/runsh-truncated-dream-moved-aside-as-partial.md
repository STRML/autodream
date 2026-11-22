# runsh: a truncated report is moved aside as `.partial-<epoch>` so it cannot become the permanent one

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`: `PARTIAL_REPORT`, the move after the L2 loop)

## Context
Every attempt can leave a marker-less file behind (killed mid-write, each time), and nothing else removes it. The idempotency guard at the top of `run()` tested `-s` alone, so the very next launchd catch-up trigger would see a non-empty report, log "nothing to do" and return: the multi-trigger retry design silently disarmed by the file it exists to replace, with a half-written report standing as the day's output forever. This is the same "non-empty is not complete" error as the other three consumers, at a fourth site, and it is the one that makes the mistake permanent rather than one-night.

## Decision
When L2 was attempted and either delivery was not validated or `report_complete` is false, the file is moved to `$REPORT_PATH.partial-<epoch>`. It is moved rather than deleted: it may hold most of a report, and a partial report is worth reading even though it must not block a retry. The stub written when COUNT=0 returns long before this line, so it is never affected. A failed move is logged: later triggers will treat the date as done. See CLAUDE.md, "Sleep resilience" (idempotency guard, "Finished means the open-questions marker is present").

## Consequences
Never make the guard accept a marker-less report. See `superseded-dream-copies-retired-outside-existence-test` for how partials are retired.
