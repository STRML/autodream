# runsh: Findings JSONs outside this run's worklist are set aside, not deleted

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`reconcile_findings_with_worklist`, `worklist_hashes`)

## Context
Issue #56. L2 reads every findings JSON in the directory, and a forced rerun reuses the directory, so a JSON left by an earlier run for a session this run's worklist no longer owns would reach the report as that day's work. It is silent: a stale `<hash>.json` is a well-formed record.

## Decision
Before the pre-L1 cache snapshot, once per run, each 12-hex `<hash>.json` outside the worklist is moved to `findings/<date>/outside-worklist/`, which L2's glob does not reach, and counted (`FINDINGS_OUTSIDE_WORKLIST`) and named in the log. Moved, not deleted: deleting findings is not this runner's call, and a later rebuild whose worklist owns the session again gets its JSON back before L1 runs (the first loop restores from `outside-worklist/`), so the rerun does not pay for the triage twice. A restore is skipped, with a WARNING, if the findings dir already holds that hash. Never overwrite an earlier set-aside copy: a second one gets a timestamped name (`<hash>.json.<epoch>`).

`worklist_hashes` prints each hash on its own line because `session_hash` prints no trailing newline, and the `grep -x` matching would never match two hashes run together.

See CLAUDE.md, "Which day a session belongs to" (Findings left by an earlier run (#56)).

## Consequences
A clean rebuild still means removing the date's findings directory first if the stale files should go for good.
