# runsh: A question-free report from an empty night still updates the question streaks

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`, `question-streaks.sh update` on the `COUNT -eq 0` path)

## Context
Without the update, the streak store would keep yesterday's questions alive across an empty night, and a question that reappeared two reports later would be called consecutive when it was not. The early return below the stub is why the call cannot live at the usual call site at the top of the report-present block. See CLAUDE.md, 'Open questions that never get answered' ("A zero-question report never cleared anything").

## Decision
After the stub is published, `run` calls `$AUTODREAM_DIR/question-streaks.sh update "$REPORT_PATH" "$FINDINGS_DIR"` (when executable, under `env AUTODREAM_DIR=...`), logging a non-zero return and continuing.

## Consequences
- A change to the early-return path must keep this call, or streaks stop resetting on empty nights.
