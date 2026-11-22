# tests-run-all: fanout fixture timestamps are chosen to stay inside the local report day in every timezone

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`mk_fanout_fixture`, `test_fanout_stats`)

## Context

A session belongs to a report day by the timestamps inside its transcript, and the day runs from local midnight to local midnight (CLAUDE.md, "Which day a session belongs to"). A fixture timestamp that lands on the next day in some timezone drops out of the window there, so the suite passes in one timezone and fails in another.

## Decision

The orphan fanout workers use `2020-01-02T09:05Z`. That is still 2020-01-02 locally from UTC-5 to UTC+11. The first draft used 18:05Z, which was already the next day in Hong Kong, Tokyo and Sydney, so the window dropped the workers there. 09:05Z also stays hours away from the other fixture sessions, so it does not create overlap.

## Consequences

Fixture timestamps for a report day must stay inside that day across UTC-5 to UTC+11, or the test fails on a developer machine in another zone. Moving the orphan workers toward the other sessions' times changes the overlap counts the test asserts.
