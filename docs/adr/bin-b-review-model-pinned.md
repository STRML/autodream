# bin-b: the triage session always passes --model

Status: accepted · Date: 2026-11-21 · Code: `bin/review.sh` (`AUTODREAM_REVIEW_MODEL`)

## Context

Without `--model`, `claude` inherits the default from the user's `settings.json`. That is rarely the model the triage was meant to run on.

## Decision

`review.sh` passes `--model "$AUTODREAM_REVIEW_MODEL"` (default `opus`) on every launch, and the cmux workspace's inner command carries the value forward.

## Consequences

Changing the triage model is a config or environment change, never a reliance on the user's settings default.
