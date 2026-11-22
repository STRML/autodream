# bin-b: triage-dream.sh skips the pass when no timeout binary exists

Status: accepted · Date: 2026-11-21 · Code: `bin/triage-dream.sh` (`TMO`)

## Context

The pass runs at the end of the night, holding the run and its lock. A wedged engine with no bound would hold both indefinitely. macOS ships no `timeout`.

## Decision

The call is wrapped in `timeout` or `gtimeout` (`-k 30`, `AUTODREAM_TRIAGE_TIMEOUT`, default 900). With neither on PATH the script logs why and exits 1 rather than run an unbounded model call, as L1's warmup does.

## Consequences

A host without coreutils never gets a triage file. The exit code 1 says the pass produced nothing, and the log line names the cause.
