# rest: the screenshot fixture's older threads are unfinished work past the seven-day dropped cutoff

Status: accepted · Date: 2026-11-16 · Code: `docs/screenshots/fixture.py` (`OLDER_THREADS`), `bin/threads.sh` (`DROPPED_DAYS`)

## Context

An open work thread reads as Dropped when its newest session is older than `AUTODREAM_THREADS_DROPPED_DAYS`, which defaults to 7 in `bin/threads.sh`. The fixture builds threads whose sessions predate the findings it writes, so the screenshot of the Threads view has a Dropped tab with something in it.

## Decision

`OLDER_THREADS` work rows with stored status `open` and an unfinished outcome (`not_achieved`, `partially_achieved` or `unclear_from_transcript`) use an age above seven days (`last_seen` is that many days back), so the read-time rule (`bin/threads-status.jq`) derives Dropped for them. Idea rows stay open at any age, so the fixture's old ideas fill the Ideas tab instead. The fixture never stores `dropped`.

## Consequences

If the default cutoff in `bin/threads.sh` changes, change the ages here or the Dropped tab in the screenshots goes empty.
