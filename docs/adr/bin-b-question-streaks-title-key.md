# bin-b: a question is its exact bolded title, and a report whose parsed count disagrees with its marker touches no state

Status: accepted · Date: 2026-11-21 · Code: `bin/question-streaks.sh` (`key_of`, `titles_of`, `cmd_update`)

## Context

The X bookmarks walk broke on 2026-09-05. Every report to 09-14 said `x_queryid_source: failed`, and the Open questions section asked "Fix the X bookmarks walker, or turn the feature off?" six times, ten nights, with one banner a night that looked like every other. A signal that repeats at constant volume is skimmed. L2 writes "Sixth ask" into its prose, but that is the model counting its own history, and it drifts.

Across five consecutive reports (2026-09-10..14) the body prose was rewritten nightly while the bolded title was byte-identical.

## Decision

- The key is the first 12 hex characters of the sha1 of the title, lowercased with whitespace collapsed and nothing else normalized. Heavier normalization could merge two different questions into one streak, silently.
- `titles_of` reads only the questions block (`report_questions`, the sentinel-bounded section shared with `review.sh` and `notify.sh`) and only numbered items (`1.` or `1)`) with a bold lead-in. PROMPT.md mandates the numbering and `review.sh` walks questions in order, so a bulleted question is broken already. A pattern loose enough to match anything would match sub-bullets. The bold lead-in is required for the same reason; when it was optional, a plain question parsed as nothing while its siblings parsed.
- A streak counts consecutive reports, not calendar days, so a night with no report does not reset one. A question missing from a report that was produced is resolved, including a report with zero questions (which is why `run.sh` calls this on the nothing-triaged path too).
- The report's `autodream:open-questions=N` marker is the report's own count. No marker means the report is incomplete, which is stricter than `run.sh`'s `report_complete`: a truncated L2 report parses as zero questions, and counting it would clear every streak and advance the watermark. A marker that disagrees with the parsed count means the title format moved. State is left alone and a banner says escalation is down.

## Consequences

Freezing every streak at its last value is the failure that would switch the feature off with no sign, the same class as `overlap_measured` and `stats_sidecars_unparseable`, which is why the mismatch is a banner and not only a log line. CLAUDE.md, "Open questions that never get answered", states the same rules.
