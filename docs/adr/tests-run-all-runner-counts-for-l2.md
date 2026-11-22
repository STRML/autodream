# tests-run-all: the roll-up and sandbox-shape tests pin counts the runner computes, because L2 cannot count

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_rollup_written_for_l2`, `test_sandbox_shape_denies_reach_the_rollup`)

## Context

- On 2026-10-31 L2's Glob and directory reads stopped at 200 entries. The findings dir held 2683 entries and the report counted a sample (CLAUDE.md, "Where state lives", `rollup.tsv`).
- #175 stopped L1 scoring sandbox-shape denies as `sandbox_friction`. A session that hit the deny 124 times then became invisible (2026-11-03).

## Decision

- `rollup.sh` writes `rollup.tsv`, `categories.tsv` and `findings.tsv` before L2, and L2 counts from them. `test_rollup_written_for_l2` uses the fanout fixture: 2 ungated top-level sessions, 1 gated and 5 ungated workers, so 8 rows and 7 ungated.
- The runner counts `sandbox_shape_denies` from the transcript and puts the threshold in `run-stats.txt`. The test builds a session with 12 denies and one with none, and asserts the second reads a measured 0, not blank.

## Consequences

The expected row counts are tied to the fanout fixture; change one with the other. Moving a count back into the prompt returns to the sample-based tally this change replaced.
