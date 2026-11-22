# bin-b: the open-questions section is found by sentinel lines, with a fenced-heading fallback only for legacy dates

Status: accepted · Date: 2026-11-21 · Code: `bin/report-format.sh` (`report_questions`, `report_has_questions_block`, `report_finishes`)

## Context

The section was found by matching a markdown heading, and four consumers (`notify.sh`, `review.sh`, `question-streaks.sh`, `triage-dream.sh`) each approximated that differently. A heading can sit in a code fence, in prose or inside another heading, so the consumers disagreed about where the section ended. See CLAUDE.md, "The triage prompt is questions-only, and that is load-bearing".

## Decision

- `AUTODREAM_QUESTIONS_BEGIN` and `AUTODREAM_QUESTIONS_END` bracket the section, each on a line of its own. The reader takes the text after the FIRST begin up to the LAST end, so a question that quotes the sentinel in a code example does not end the block early. A block counts as closed only when an END follows a BEGIN.
- Reports dated before `AUTODREAM_QUESTIONS_EPOCH` (default `2026-10-27`) predate the block and are read the old way: from `## Open questions` to the next `## ` or horizontal rule. That path keeps fence tracking, because a heading quoted inside a code example is not the end of the section (a review finding when the fallback was written).
- `report_finishes` requires the closed block only for dates on or after the epoch. Dates are compared as strings, which is chronological for ISO dates.

## Consequences

The fallback serves history only. A new report without the block is not finished, so a bad block costs one rebuild instead of a silent wrong read. A consumer must call `report_questions` and never parse markdown itself. Changing a sentinel string means changing `prompts/PROMPT.md` and `bin/report-format.sh` together.
