# tests-preflight: the DEGRADED line is asserted directly, and the timeout wrapper follows the workflow's PATH choices

Status: accepted · Date: 2026-11-22 · Code: `tests/preflight.sh` (the python3 DEGRADED case, the `TO` timeout selection); the tool policy itself is in `bin/preflight.sh` (see `bin-a-preflight-hard-stop-versus-degraded.md`)

## Context

- A missing `python3` is a warning, not a stop. A test that only checked "exit 0 and not MISSING" passed on any host that has `python3`: it simulated nothing and proved nothing.
- The flag-without-value case needs a bound, because the failure it guards against is a hang. macOS has no stock `timeout`. The workflow installs coreutils for `gtimeout` only and deliberately keeps gnubin off `PATH`, because the suite depends on BSD `date` and `touch`.

## Decision

- The python3 case forces the tool missing with `AUTODREAM_PREFLIGHT_FORCE_MISSING=python3` and asserts that the output contains a `DEGRADED` line naming python3. The exit-0 and not-MISSING checks stay beside it.
- The hang case picks `timeout`, else `gtimeout`, the same selection `run-all.sh` already uses, and does not depend on gnubin. With neither, it reports the assertion as skipped.

## Consequences

Keep the positive `DEGRADED` assertion: removing it makes the python3 case pass on every host with python3 installed. A new bound in this suite uses the same selection.
