# runsh: how a run ended is written to a per-token outcome file, and nothing else tells the watcher

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`write_run_outcome`), `bin/autodream-now.sh` (`--watch`)

## Context

`autodream-now.sh --watch` must know whether a report was delivered. The runner is the only one that knows. The log (which also holds model text), the report's mtime (a whole second) and a completeness predicate the watcher evaluates for itself (with another config's epoch) each gave the wrong answer. See CLAUDE.md, "Running on-demand without the 10-min cap".

## Decision

`write_run_outcome <delivered|noop>` appends `<token> <state>` to `logs/run-<date>.outcome`. The token is the watcher's own id for the launch (`AUTODREAM_RUN_TOKEN`), so a line from an earlier run is never mistaken for this one and no clock is involved. A token outside `[0-9A-Za-z._-]` or no token writes nothing, which is every scheduled run. `delivered` means a validated report stands; `noop` means a finished report already existed and nothing was rebuilt. A run that ends any other way writes nothing.

## Consequences

Do not infer readiness in the watcher from the log, the mtime or a re-evaluated predicate. A new way a run can legitimately end with a report must write one of the two states.
