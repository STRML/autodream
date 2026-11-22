# bin-a: the artifact key is a validated 12-character hex prefix of sha1, and nothing derives it any other way

Status: accepted · Date: 2026-11-21 · Code: `bin/lib-project.sh` (`session_hash`), `bin/preflight.sh` (`need shasum`), `bin/oversized-gate.sh`

## Context

`h=$(printf %s "$p" | shasum -a 1 | cut -c1-12)` has two silent failure modes that end in the same place. `cut` masks `shasum`'s exit status, so a `shasum` that exists (satisfying preflight) but fails at runtime yields an empty hash, and every session then targets the same artifact. A short or non-hex result does the same. A missing `shasum` has the same effect: every session in the night writes to one findings filename, the run ends with one record where it should have had a hundred, and nothing in the existing code notices.

`bin/oversized-gate.sh` had the same hole on the reading side. With `shasum | cut` there, a runtime-failing `shasum` yielded an empty key, so the gate consulted `.stats.json` and `.json` for every session and could undercount errored oversized sessions. It reported GATE CLOSED off a measurement that never happened.

The character set is enumerated, not a range. Verified on the host: under bash 3.2 with an en_US.UTF-8 collation, `A` matches `[0-9a-f]`, and under bash 5.3 it does not. The nightly runs `#!/bin/bash`, which is 3.2, so the range form accepted uppercase exactly where it matters. It is the same collation behavior that made an uppercase adapter basename pass on CI and fail locally.

## Decision

`session_hash` captures the `shasum` output without a pipe so its status is seen, takes the first 12 characters, and prints them only when the prefix is 12 characters long and holds nothing outside `0123456789abcdef` (a negated `case` pattern). Otherwise it returns 1 with nothing on stdout. A caller treats a failure as "this session cannot be keyed": `oversized-gate.sh` counts it as unmeasurable and leaves it out of the ratio. `preflight.sh` makes a missing `shasum` a hard stop, because it is the one dependency whose absence produces no error at all.

## Consequences

Call `session_hash` instead of deriving a hash inline. The hex digits are listed out on purpose; do not replace the list with a range such as `[0-9a-f]` without re-running the bash 3.2 collation check.
