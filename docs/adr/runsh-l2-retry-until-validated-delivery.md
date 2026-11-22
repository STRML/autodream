# runsh: the L2 aggregator is retried until a validated delivery lands

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`run()`, the `for attempt in $(seq 1 "$L2_ATTEMPTS")` loop)

## Context
The aggregator call can die to a mid-run sleep; this is what left exit 1 and no report overnight. The retry is idempotent: a re-run overwrites the report harmlessly. The comment says to retry "until `$REPORT_PATH` is non-empty"; that is stale. Non-empty was proven insufficient (a truncated or degraded capture is non-empty), and the loop now breaks only on a sentinel-validated capture that also carries the open-questions marker (see `l2-delivery-requires-sentinel`). The heading above it also names "opus", but no model is pinned (see `l2-model-unpinned-by-default`).

## Decision
Up to `AUTODREAM_L2_ATTEMPTS` (default 3) attempts, waiting for the network and sleeping `AUTODREAM_RETRY_WAIT` (default 60s) between them. See CLAUDE.md, "Sleep resilience" (L2 retry loop).

## Consequences
Do not restore a bare `-s "$REPORT_PATH"` break condition: that is the failure mode the delivery gate was built to remove.
