# bin-b: rollup status mirrors run.sh's report N, with one deliberate difference

Status: accepted · Date: 2026-11-21 · Code: `bin/rollup.sh` (`ROW_JQ` status expression); `bin/run.sh` (`compute_fanout_stats`, `fanout_rows`)

## Context

L2 counts the report's N from `rollup.tsv`, and the runner already computed N in `compute_fanout_stats`. Two numbers for one quantity would drift.

## Decision

- `status` is `unreadable` when `findings` is not an array (checked first), `gated` for a `below_noise_gate` stub, `error` when the record has an `error` key, else `triaged`. Every status except `gated` is the set `compute_fanout_stats` calls N.
- One difference remains: a gated stub whose `findings` is not an array is `gated` to `compute_fanout_stats`, which reads the text, and `unreadable` here, because the array check comes first.
- `nested` is the sidecar's `isSidechain` or `nested`, the same test `fanout_rows` applies.
- `parent` comes from `fanouts.tsv`, which lists ungated workers only, so a gated child reads nested with a blank parent.

## Consequences

Change the status expression and `compute_fanout_stats` together, or the report's N and the tallies disagree.
