# runsh: A findings file's error is detected by its top-level key, not by text

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`findings_has_error`)

## Context
The top-level `error` key is what the runner writes for a failed triage and what the L1 prompt tells a worker to write when it cannot fit a transcript. A text match on `"error":` would also fire on a successful file whose evidence quotes one, and with no `.err` to classify it that file would drop out of both sides of the size-attributable share.

## Decision
`findings_has_error` is `jq -e 'type == "object" and has("error")'`.

## Consequences
Do not replace it with `grep`. A parse failure reads as "no error key", which is the caller's separate concern (`L1_FINDINGS_OK`, see `l1-findings-ok-single-value-check`).
