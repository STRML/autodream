# tests-run-all: the project-normalization pass is cut out of run.sh and run alone

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_normalize_project_survives_non_object_findings`), `bin/run.sh` (the `SESSION_ROWS=... python3 -` heredoc)

## Context

`run.sh` validates findings JSONs before the normalization pass, so a full run never hands the pass a non-object. A full-run test would pass even if the pass crashed on `[]` or `null`.

## Decision

The test extracts the pass's Python body from `run.sh` with an `awk` range (from the `SESSION_ROWS="$SESSION_ROWS" python3 -` line to the closing `PY`), asserts the extract is non-empty, and runs it on four files: an array, `null`, a string and an object with a wrong project. The file names sort `a.json < b.json < c.json < d.json`, and the pass walks them in that order. That puts the object last, so exit 0 and a corrected project on `d.json` show that the non-objects did not stop the rest.

## Consequences

Renaming the heredoc's opening line breaks the extraction, and the non-empty assertion says so. Renaming the fixtures so the object sorts first lets a pass that aborts on the first non-object go unnoticed.
