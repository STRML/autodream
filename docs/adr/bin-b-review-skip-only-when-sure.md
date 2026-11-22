# bin-b: review.sh skips a report only when it is sure, and checks "already triaged" before "no open questions"

Status: accepted · Date: 2026-11-21 · Code: `bin/review.sh` (skip block before the cmux hand-off)

## Context

Most nights the report has no open questions, and launching a session to be told "nothing to do" costs a full session's tokens. A false "nothing to do" silently swallows real questions, while a false launch only wastes tokens.

A report can be both empty and already worked through (an empty-day stub someone closed out), and "already triaged" is the more informative reason of the two.

## Decision

- The skip uses `report_open_questions` (see `bin-b-report-format-marker-strictness.md`), which says `unknown` for any shape it does not recognise. Only an exact `0` skips.
- The triaged check runs first, so the notice names the better reason. `--force` bypasses both.

## Consequences

Do not add a looser "looks empty" test to the skip. Moving the open-questions check ahead of the triaged check changes the notice text the tests assert.
