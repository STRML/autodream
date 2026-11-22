# runsh: Superseded report copies are deleted, except ones holding the user's triage decisions

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`drop_stale_report_copies`)

## Context
A forced rebuild moves the old report aside as `<report>.stale-<epoch>`. Once a report is delivered in its place, those copies must leave the `.stale-*` glob so the record lookup (`remote-short-dates-record-in-report`) cannot resurface an old label. A copy with a `## Triage decisions` heading holds the user's own writing.

## Decision
After delivery, every `.stale-*` copy is deleted. A copy with a `## Triage decisions` heading is instead renamed to `<report>.triaged-<epoch>` (with a `.$$` suffix if that name exists), which the record lookup never reads. A copy that cannot be read is kept, not deleted: `grep -q` exit status other than 1 means "found or unreadable", and only status 1 (no match) permits deletion, so an unreadable copy takes the same rename to `.triaged-<epoch>` and leaves the glob. It runs after a stub report is published (`mv` of the `.tmp`) and after an L2 delivery that passes `report_complete`.

## Consequences
Never widen the delete path to copies the grep could not read. A failed `rm` or `mv` logs a WARNING and leaves the copy in place.
