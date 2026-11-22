# runsh: which model answered an L1 call is read from the engine result and judged by the adapter, and the verdict is stored with the answer it describes

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`l1_attempt`; `l1-served.tsv`, `<answer>.served`)

## Context
The CLI answers with a canonical id (`claude-haiku-5-5`) for a model requested by alias (`haiku`), and only the adapter knows its CLI's naming, so a string compare in run.sh would be wrong. An engine that reports nothing must not be counted as a match or a mismatch.

## Decision
- After every call, whatever it produced, `adapter.sh served <stdout> <model>` returns the models that answered, a cost estimate and a verdict, `match` or `mismatch`. Any verdict other than those two, or a failure of the verb, is recorded as `unmeasured` (models `unknown` when the verb gave none). The row goes to `l1-served.tsv`.
- With `AUTODREAM_L1_REQUIRE_SERVED=1` a call that wrote findings but whose verdict is not `match` loses them (and its `.served`) and fails with a line in the `.err` that says which, so nothing a substituted or unverifiable model wrote reaches L2.
- The runner writes `<answer>.served` (engine, requested model, models that answered, verdict) after the engine has exited, replacing anything the worker wrote there. A later run reads it before reusing the answer: with `REQUIRE_SERVED=1` a cached findings JSON or chunk answer is reused only when it says `match` (`drop_unacceptable_l1_cache` in the parent).

## Consequences
See CLAUDE.md, "What answered, and whether it counts". `docs/adr/bin-a-adapter-claude-served-verdict.md` covers the claude adapter's `served` verb.
