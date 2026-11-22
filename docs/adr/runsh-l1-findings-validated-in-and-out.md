# runsh: a findings JSON is validated both when a worker starts and when it finishes, and a rejected file is moved aside

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, `l1_attempt`, `L1_FINDINGS_OK`)

## Context
`jq -e .findings` is truthy for a string or an object, so `{"findings":"oops"}` counted as a finished session and reached L2 (#167). A non-empty file that is malformed, or has no `.findings` array, is not a completed triage. On the way out, such a file used to take the success branch: diagnostics were deleted and the file left for L2, and by the next round the exit code, stdout capture and reason were gone. A chunk failure with the old file still in place skipped the final stub and the rejected file reached L2, because every later step reads a non-empty `$output` as "this round produced a result".

## Decision
- On the way in, the worker runs `jq -s -e "$L1_FINDINGS_OK"` and exits 0 only for a valid result. The filter comes from the environment (defined once in the parent) because the body is single-quoted, and `l1_missing_count` must run the same check.
- A file that fails is moved to `<hash>.json.rejected` (no `*.json` glob reaches it; removed if the move fails) and its `.served` is deleted.
- On the way out, `l1_attempt` checks the answer with `merge-chunks.sh --check` for a chunk and with `L1_FINDINGS_OK` otherwise. A bad write appends `worker wrote output with no usable .findings key; treating as a failure`, keeps the first 2000 bytes as evidence and removes the file, so the failure keeps its exit code and stdout.

## Consequences
Never loosen the check to `jq -e .findings`. Keep the in-check, the out-check and `l1_missing_count` on one definition. See CLAUDE.md, "Non-empty is not valid".
