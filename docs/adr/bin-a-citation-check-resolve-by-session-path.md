# bin-a: a cited 12-hex token with no findings file still resolves when it matches a triaged session path

Status: accepted · Date: 2026-11-21 · Code: `bin/citation-check.sh` (`session_paths`, `by_path`)

## Context

A cited 12-hex token is not always a findings hash. Session filenames are UUIDs and their last group is 12 hex characters, so an aggregator that cites a session by filename tail produces a token that resolves to nothing under the hash rule. Observed on 2026-08-18 with `87b5b1392572`, the tail of a real, triaged session.

Those are genuine citations to genuine sessions. Counting them as unresolved would train the reader to ignore the counter, the failure the check exists to avoid.

## Decision

The script builds one index per run: every `session_path` any findings record claims. A token with no `<hash>.json` is checked by substring against that index. A match counts as `citations_resolved_by_path`; no match counts as unresolved.

## Consequences

The index is built once, before the loop, so cost does not grow with the number of citations. The substring match is permissive on purpose, in line with `bin-a-citation-check-any-12-hex-token`: a path match can only turn an alarm into a resolution when a triaged session really holds that token.
