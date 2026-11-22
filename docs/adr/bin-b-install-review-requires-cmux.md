# bin-b: the review agent is provisioned only when cmux resolves the way review.sh resolves it

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (`install_schedule`, the `CMUX_FOUND` lookup)

## Context

The review job exists to open a popup in its own cmux workspace. Without cmux a headless inline fallback would run claude with no terminal. macOS GUI installs usually put cmux at `/Applications/cmux.app/Contents/Resources/bin/cmux`, not on PATH, so a PATH-only check would wrongly skip the agent. The launchd PATH is fixed, so a non-default cmux (for example `~/bin/cmux`) would pass the install check and then be unfindable at run time.

## Decision

Resolve in `review.sh`'s order: config `CMUX_BIN` (if executable), then PATH (minus temp entries), then `AUTODREAM_CMUX_DEFAULT` or the app-bundle path. The resolved absolute path is written into the plist as `CMUX_BIN`. A relative path is refused: launchd runs with no working directory, so a relative value that passed `-x` here would fail every trigger. No cmux means the agent is skipped.

## Consequences

If `review.sh` changes how it finds cmux, change this lookup in step. `tests/install-review-agent.sh` pins the order.
