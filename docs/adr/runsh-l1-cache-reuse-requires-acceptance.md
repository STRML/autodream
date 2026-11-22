# runsh: A cached L1 result is reused only if this run would accept it now

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`drop_unacceptable_l1_cache`, `l1_record_has_no_engine`, `l1_source_has_engine`, `l1_record_is_runner_only`, `served_verdict`)

## Context
Two reasons to drop cached findings. A no-engine record (`no_engine`, written by `dispatch_l1` when a source had no usable engine: an engine choice naming no accepted adapter, a missing model, a login failing `AUTODREAM_REQUIRE_LOGIN`) is final only for the config that wrote it. And with `AUTODREAM_L1_REQUIRE_SERVED=1`, an answer from a run that did not require the served-model verdict must not be trusted.

## Decision
`drop_unacceptable_l1_cache` runs once, after `reconcile_findings_with_worklist` and before the pre-L1 cache snapshot, so the dispatcher, `l1_missing_count` and `L1_PRECACHED` all see the same set. It counts drops in `L1_CACHE_DROPPED` (run-stats `l1_cache_dropped`) and names them in the log.

- No-engine records are dropped once this run resolves an engine and a model for the session's source (`l1_source_has_engine`). The source comes from `AUTODREAM_SOURCE_MAP`, never from the record, which a worker could have written. Dropping only costs a triage, so the record's shape (`l1_record_has_no_engine`: `no_engine == true` or an error starting `no L1 engine for this session`, with `findings == []`) is enough, and a forged one buys itself a retriage, nothing more.
- With `REQUIRE_SERVED=1`, a findings JSON or chunk answer a model wrote is held to the verdict stored beside it (`<answer>.served`, field 4, from `served_verdict`): no verdict, or any verdict but `match`, is dropped. A record the runner wrote with no model behind it (noise-gate skip, unreadable session, normalize failure, no-engine record, final-round stub) is kept when its `.served` says `runner` and its findings are empty (`l1_record_is_runner_only`). Provenance comes from that marker, which the runner writes, never from the record's keys or shape: a worker can write `error`, `skipped` or `no_engine` as easily as the runner can (#167). The empty findings array is a second guard for a worker that rewrites another session's record in place. A runner record from before the marker is triaged once more and comes back marked.

See CLAUDE.md, "Who starts the L1 worker" (What answered, and whether it counts; No engine is an error for this run's config).

## Consequences
Known limit shared with the match verdict: every `.served` lives in the findings dir, where an unconfined worker with the Write tool can reach it, so a worker that rewrites ANOTHER session's record and its `.served` together is not caught here. The dispatcher replaces each worker's own `.served` after it exits, which covers the worker's own session only. Closing the cross-session case needs provenance a worker cannot write at all, not a better check on these files. (Since #169, a confined worker can write only its staging dir; see `l1-write-confinement-staging`.)
