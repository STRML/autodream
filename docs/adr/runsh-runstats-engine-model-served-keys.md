# runsh: run-stats names who answered L1 (login, served model, verdict, cost) and counts the unmeasured separately

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (the `run-stats.txt` block in `run()`: `login_<src>`, `l1_served_*`, `l1_cost_*`)

## Context
- `l1_model_<src>` is the model each adapter's workers ran and `l1_engine_<src>` the adapter whose engine ran them (which `AUTODREAM_L1_ENGINE_<NAME>` can move off the source), one key per source that had sessions tonight, so a report that reads differently can be traced to the engine that produced it.
- `login_<src>` records who each engine the run used ran as (`engine_login_ok`), and `l1_served_models` records which models answered the L1 calls recorded for this date in `l1-served.tsv`, so a report traces to the login and model behind it. The cost is the engine's own estimate at API prices, not what a subscription bills.
- `l1_served_mismatch` is the adapter verdict (column 6 of `l1-served.tsv`), the same one `AUTODREAM_L1_REQUIRE_SERVED` acts on. A call the engine reported no model for (omp has no `served` verb), or a row written before the verdict existed, is unmeasured: counted on its own line (`l1_served_unmeasured`), never as a match or a mismatch.
- `l1_cost_unmeasured` counts the calls the cost sum leaves out because their engine reported no cost (omp, or a claude call with no result object), so an all-omp night reads `0.0000` beside a count, not alone.

## Decision
Mismatch, unmeasured and cost-unmeasured are separate counters; with no `l1-served.tsv` all of them print their zero/none defaults. See CLAUDE.md, "Who starts the L1 worker" ("What answered, and whether it counts").

## Consequences
Folding unmeasured into match or mismatch would make an omp-only night look verified, or a cost of `0.0000` look measured. The cost number is an API-price estimate: never present it as spend.
