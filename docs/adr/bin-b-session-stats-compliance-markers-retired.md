# bin-b: the sidecar carries no compliance_markers count

Status: accepted · Date: 2026-11-21 · Code: `bin/session-stats.sh` (the output object)

## Context

The sidecar used to count compliance markers. Retired 2026-10-30 (omp: 2026-08-08): agents follow the retry and delegation rules without typing the marker line, so the count measured silence.

## Decision

The key is absent. `adapters/omp/triage.md` records the same retirement for omp.

## Consequences

Do not add a marker count back as a proxy for rule compliance. Measure the behavior the rule governs.
