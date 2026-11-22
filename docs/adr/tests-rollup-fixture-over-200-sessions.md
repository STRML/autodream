# tests-rollup: the fixture holds 224 sessions and every expected number is a literal derived by construction

Status: accepted · Date: 2026-11-22 · Code: `tests/rollup.sh` (the fixture block and the assertions after it)

## Context

L2's Glob and directory reads stop at 200 entries. On 2026-10-31 the findings dir held 2683 entries (885 findings JSONs, 885 `.served`, 885 sidecars, about 28 side files), so L2 counted from a 90-file sample and never saw `fanouts.tsv`. A fixture under 200 entries would pass against a script that still listed the directory. The production decision is in `bin-b-rollup-counting-outside-l2`.

## Decision

The fixture holds 224 sessions plus every side file that shares the directory (`pins-like.json`, `outside-worklist/`, `.err`, `run-stats.txt`). The totals are worked out from how the fixture is built: 100 + 90 + 20 + 5 + 3 + 1 + 1 + 1 + 1 + 1 + 1 = 224 sessions, with 125 triaged, 95 gated, 1 error and 3 unreadable, so the ungated set the report calls N is 129. No expected value is recomputed with the same `jq` the script uses.

Fixture cases whose purpose is not visible from the code:

- Session 6 carries one category at two severities and counts once in that category's `all` row.
- Session 12's sidecar predates `sandbox_shape_denies` and 13's holds a string. Both read blank, never 0, so a degraded measurement is not a measured zero.
- Gated omp children (221-225) are nested but have no `fanouts.tsv` row, since that file holds ungated rows only.
- Advisors 231-233: `sandbox_friction` is a tool-behavior finding that L1 suppresses for advisors, so it is a triage failure and never a ranked pattern. 232 and 233 both carry `memory_miss:medium`, a content finding that counts once, as the parent's.
- Session 245 is a gated stub whose `findings` is not an array. It is unreadable, because the array check comes before the gate.

## Consequences

Keep the fixture over 200 sessions and keep the expected numbers literal. When a case is added, update the totals line by hand from the construction.
