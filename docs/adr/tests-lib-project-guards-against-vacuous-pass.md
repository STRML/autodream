# tests-lib-project: the suite guards against passing with no implementation and against a mutation-blind digest fixture

Status: accepted · Date: 2026-11-22 · Code: `tests/lib-project.sh` (the `declare -F` loop, the collation check, the `session_hash` stub-digest cases)

## Context

Three ways this suite could pass while testing nothing:

- With `encode_project` or `canonical_project` undefined, every comparison is empty-equals-empty and the suite is green against no implementation.
- A check of a hard-coded pattern does not exercise `session_hash`. Putting `[0-9a-f]` back into the function would pass it. Verified on this host: under bash 3.2 with an en_US.UTF-8 collation `A` matches `[0-9a-f]`, and under bash 5.3 it does not. The nightly runs `#!/bin/bash`, which is 3.2. The same behaviour made an uppercase adapter basename pass on CI and never locally (see `bin-a-lib-project-session-hash`).
- Under that collation the order runs `...eEfFgG...`, so `F` sorts after `f` and falls outside `a-f`, while `A` through `E` fall inside. A digest starting `ABCDEF` is rejected by the range form too, for the wrong reason. Verified character by character on this host.

## Decision

- The suite fails at once, and says the rest would be vacuous, when either function is not defined.
- The collation check runs under `/bin/bash` with `LC_ALL=en_US.UTF-8`, the shell and locale that expose the behaviour.
- The function itself is driven through a stub `shasum` whose digest is `ABCDE0123456789abcdef0123456789abcdef012`. It starts `ABCDE` and deliberately not `ABCDEF`, so the range form would accept it and the test fails against the regression it exists to catch. A 3-character digest must fail too: 12 characters is the contract, not a maximum.
- The range form's behaviour is printed as a `note`, not asserted. Asserting that the range is broken would fail the day a shell fixes it. What must hold is that our pattern rejects uppercase.

## Consequences

Do not lengthen the stub digest's uppercase prefix to `ABCDEF` or beyond, and do not turn the note into an assertion. Re-run under `/bin/bash` 3.2 after changing the hex class.
