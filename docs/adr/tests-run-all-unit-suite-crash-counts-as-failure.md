# tests-run-all: a unit suite that dies before printing a total counts as one failure

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (the `for _suite in $_suites` loop)

## Context

`run-all.sh` runs each unit suite as a child and folds its `passed:` and `failed:` totals into its own. A suite that crashes before printing a total prints no `failed:` line, so the parsed failure count is empty. A plain sum reads that crash as zero failures, which is green.

## Decision

When a suite exits non-zero or reports failures, the loop prints the first `FAIL` lines. If the parsed failure count is empty or zero (the crash case), it adds one to `fail` itself: `[ -n "$_f" ] && [ "$_f" -ne 0 ] || fail=$((fail + 1))`. A suite that reported its own nonzero count keeps that count.

## Consequences

Do not simplify the line to `fail=$((fail + ${_f:-0}))`. A crashing suite would then pass the whole run. A new suite needs only a name in `_suites`; it inherits the rule.
