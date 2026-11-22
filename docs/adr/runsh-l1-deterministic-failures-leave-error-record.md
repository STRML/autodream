# runsh: a failure that retrying cannot change leaves a structured error record, not a missing file

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body: unreadable session, normalize refusal, no engine)

## Context
A session path that enumeration found but that is gone or unreadable by dispatch time would send a worker into a cat/wc/Read retry loop. An adapter's normalizer can refuse a transcript (duplicate id, dangling parent, cycle, missing jq). A session can resolve no engine (not executable, no model, no accepted adapter, failed `AUTODREAM_REQUIRE_LOGIN`). In all three a retry in the same run cannot change the answer.

## Decision
The worker writes `{session_path, error, findings: []}` to `$output` plus a runner `.served` marker and exits 0:
- unreadable at dispatch: `session file not readable at dispatch`;
- normalize refused: `session could not be normalized by the <adapter> adapter: <reason>`, where the adapter's reason (first 300 bytes of its stderr) is kept so a refusal can be told from an environment fault by reading the record;
- no engine: the same shape with `no_engine: true`.

The record is skipped by the later rounds and counted by `l1_findings_with_error`. The no-engine case is deterministic for this run only: the engine choice, the model pin and the login check all come from the config, which can change, so `no_engine` marks the record and a later run whose config resolves an engine drops it and triages the session (`drop_unacceptable_l1_cache` in the parent).

## Consequences
Do not "fix" these by deleting the record so the next round retries. For the no-engine marker see CLAUDE.md, "No engine is an error for this run's config, not forever".
