# runsh: the L1 worker body is a single-quoted `bash -c` with no apostrophes, and recomputes the session hash inline

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`dispatch_l1` worker body)

## Context
The worker is one single-quoted string passed to `bash -c`. A `'` anywhere in it, including a comment, silently ends the quoting while `bash -n` still passes. The body runs in a separate process, so functions defined in the parent (`session_hash`) are not in scope. An empty hash would send every worker to the same artifact.

## Decision
The body contains no apostrophes (the comments use "the adapter comment", not possessives). It recomputes the hash inline with the same contract as the parent's `session_hash` (12 hex characters of the sha1 of the path) and exits 0 on anything else, so a failed `shasum` cannot make workers share a file. Data the body needs crosses in the environment (for example `L1_FINDINGS_OK`).

## Consequences
When editing the body, re-run `bash -n` and the suite, and never add an apostrophe. If `session_hash` in the parent changes, change the inline copy with it. See CLAUDE.md, "Self-pollution" ("Watch the apostrophes") and "Which day a session belongs to".
