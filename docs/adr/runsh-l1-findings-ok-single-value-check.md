# runsh: One jq -s test defines a usable findings JSON

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`L1_FINDINGS_OK`, `l1_missing_count`)

## Context
`jq -e` judges only the LAST value in a file, so a forged object followed by a good one passed the old `.findings | arrays` check and L2 read the first (#167). `merge-chunks.sh --check` is the same rule for chunk answers.

## Decision
`L1_FINDINGS_OK='length == 1 and (.[0] | type == "object" and (.findings | type) == "array")'`, run under `jq -s`: exactly one JSON value, an object, with a `findings` array. It is `export`ed because the worker is a separate `bash -c`. `l1_missing_count` counts a session missing unless `jq -s -e "$L1_FINDINGS_OK"` accepts its findings file, the same check the dispatcher applies on the way out. A session whose artifact hash cannot be derived or validated (`session_hash`: 12 hex characters) is counted missing too. An unvalidated hash would have the session counted missing forever, and the retry loop would re-dispatch it every round.

See CLAUDE.md, "A failed worker leaves its evidence" (Non-empty is not valid).

## Consequences
Every reader of findings validity must use this variable, not a private `jq -e .findings`.
