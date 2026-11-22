# bin-b: the open-questions count is read strictly, completeness loosely, and anything unrecognised is "unknown"

Status: accepted · Date: 2026-11-21 · Code: `bin/report-format.sh` (`report_marker_count`, `report_has_marker`, `report_open_questions`)

## Context

`<!-- autodream:open-questions=N -->` is the last thing `prompts/PROMPT.md` emits. It says how many questions need a human call and that the write reached its end. Callers need different guarantees from it, and reports from before the marker have only prose.

## Decision

- `report_marker_count` is strict: the comment must be well formed and the first one wins. `question-streaks.sh` and `notify.sh` trust nothing looser.
- `report_has_marker` is loose on purpose. `run.sh` asks only whether the write reached its end, so a truncated report that still carries the key counts. A malformed marker passes it and fails the count, which is how `question-streaks.sh` refuses to clear a streak on it.
- `report_open_questions` falls back, for marker-less reports, to the empty-day stub text and to a `## Open questions` section whose first non-blank line starts with "none". Every other shape is `unknown`, and the caller launches the session. A false "nothing to do" swallows real questions, while a false launch only costs tokens.

## Consequences

Do not merge the strict and loose readers. Add a recognised prose shape only when a real legacy report shows one.
