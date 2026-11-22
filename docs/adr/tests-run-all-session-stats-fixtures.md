# tests-run-all: session-stats fixtures pin retired fields and anchored deny counting

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_session_stats`); `bin/session-stats.sh`

## Context

`compliance_markers` was retired for claude on 2026-10-30 (omp: 2026-08-08). Agents follow the retry rules without typing the line, so the count only measured silence. `sandbox_shape_denies` counts tool results that open with a deny signed by the sandbox-shape guard. Measured 2026-11-03: 52 in one local-llm session, every one anchored.

## Decision

The markers fixture asserts the sidecar has no `compliance_markers` field, so reviving the count fails the test. The shape fixture covers the real deny (a `tool_use_error` with `is_error` true), bare and wrapped, array content, and several blocks in one record. It also holds the non-denies: a Read or grep that shows the string mid-text, an attachment, an assistant line, and the string on a later line of an error. The expected count is 5.

## Consequences

An unanchored match passes the deny cases and fails the non-deny cases. Add a new deny shape as a counted case, not as a fixture with the string anywhere in the text.
