# bin-a: `--days` is validated, never defaulted

Status: accepted · Date: 2026-11-21 · Code: `bin/cookie-cadence.sh` (argument loop)

## Context

A bare `--days` with no value used to leave the argument loop's `shift 2` refusing to shift. `bin/oversized-gate.sh` was fixed for the same reason, and the loop here follows it.

## Decision

`--days` exits 2 with a message when its value is missing, is not digits, or is zero. It never falls back to a default for a missing value.

## Consequences

Defaulting a missing value would turn a typo into a full-history run. A new numeric option in this script gets the same checks.
