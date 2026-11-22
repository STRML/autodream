# runsh: the L1 engine, model and source of each session come from parent-built environment, never from files under the findings dir

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body, `AUTODREAM_SOURCE_MAP`, `AUTODREAM_L1_MODELS`, `AUTODREAM_L1_ENGINES`)

## Context
An L1 worker holds the Write tool and could rewrite `sessions-source.txt`. The source decides which binary the next worker executes.

## Decision
The worker looks the source up in `AUTODREAM_SOURCE_MAP`, the model by source in `AUTODREAM_L1_MODELS`, and the engine in `AUTODREAM_L1_ENGINES` (usually the same name as the source). All three are built before the first model call. A source or engine that is empty or has a character outside `[a-z0-9_-]` is cleared. An empty engine means the engine override named no accepted adapter. The adapter prints its own argv (`l1-argv`) and environment (`l1-env`), so nothing in the worker names claude or omp.

## Consequences
Reading the findings dir instead fails `test_l1_engine_cannot_be_redirected_by_a_worker`. See CLAUDE.md, "Who starts the L1 worker".
