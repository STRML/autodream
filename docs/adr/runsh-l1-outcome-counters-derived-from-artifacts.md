# runsh: L1 outcome counters are derived after the fact from the findings dir, and failures are classified before they are read as size evidence

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run`: `L1_ERRORED*`, `GATED`)

## Context
- A worker that ran to completion but could not fit the transcript writes a findings JSON carrying a top-level `error` key with empty findings. These are not `.json.err` files, so `l1_err_files=0` masked them.
- Each noise-gate decision happens inside an independent xargs subshell with no shared state to increment.
- A provider refusal or a worker that died silently is not evidence about transcript size. See CLAUDE.md, 'A failed worker leaves its evidence, and the failure is classified', and `bin/failure-class.sh`.

## Decision
- In-band failures are counted explicitly (`L1_ERRORED`) by walking the findings JSONs with `findings_has_error`, so the self-audit can alarm on a high extraction-failure rate (slimming should drive it to zero).
- Every stub is counted, then its surviving `.err` is classified (`classify_failure`: silent, provider, unclassified) before the self-audit decides whether the failure says anything about size.
- `GATED` is counted from the findings dir (files containing `"skipped": "below_noise_gate"`) rather than from a shared counter.

## Consequences
- Do not move these counts into the worker subshells; the increments are lost.
- Do not read `l1_err_files` alone as the failure count.
