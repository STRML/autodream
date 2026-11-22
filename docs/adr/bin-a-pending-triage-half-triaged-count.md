# bin-a: a half-triaged report subtracts its logged questions but always keeps at least one pending

Status: accepted · Date: 2026-11-21 · Code: `bin/pending-triage.sh` (`pending`)

## Context

A report stays pending until its `## Triage decisions` heading exists. A session that is part way through a report logs under `## Triage in progress` and renames the heading only after the last question is resolved. The report's `autodream:open-questions=N` marker never changes while that happens.

## Decision

`pending` reports `N` minus the count from `report_progress_count`, so the summary shows what is left. The result never drops below 1. The heading is renamed only when the last question is resolved, so a report that still has no `## Triage decisions` heading has at least one question left.

## Consequences

Reports with an unreadable count are a separate case: they are listed with `?` and reported on their own (see `usage` in the script). `tests/pending-triage.sh` pins both.
