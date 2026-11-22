# tests-review-skip: fixtures copy real report shapes, and the latest-report test sets both mtimes

Status: accepted · Date: 2026-11-22 · Code: `tests/review-skip.sh` (`REPORT_STUB_TRIAGED`, `REPORT_TRIAGED_NUMBERED`, `test_latest_report_default`)

## Context

`review.sh` decides skip or launch from the report text. Two fixtures exist because real reports took shapes the first version did not handle:

- the 2026-06-27 report was an empty day that someone had already closed out, so two skip reasons applied;
- the 2026-07-09 report used a dated heading (`## Triage decisions (2020-01-03)` in the fixture) and a numbered decision list.

`review.sh` picks the newest report with `ls -t`. Two files written in the same instant tie, and BSD `ls` then breaks the tie by name.

## Decision

- `REPORT_STUB_TRIAGED` matches both the empty-day stub and the triaged rules. The test asserts that "already triaged" is the reason printed, with "decision" in the singular for one entry.
- `REPORT_TRIAGED_NUMBERED` keeps the dated heading and the numbered list. The notice must count 3 decisions.
- `test_latest_report_default` stamps both report files with `touch -t`. Writing them in order is not enough, because the tie would pick the wrong report on BSD `ls`.

## Consequences

Do not simplify these fixtures to the plain `## Triage decisions` shape, and do not drop the `touch -t` calls.
