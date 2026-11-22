# runsh: changelog lines are deduped by the line and the release header it sits under, with blank lines exempt

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_one`, the `awk` that builds `added`)

## Context

A changelog edited across many commits in one window re-inserts the same lines repeatedly. OMP's log moved 119 commits for 2026-09-08 through 09-10 and emitted `## [18.1.16]` three times with its bullets under each. Blank lines are exempt or the markdown collapses into one paragraph. A window-wide key dropped `### Fixed` and `- Fixed a crash`, which repeat across releases, from the second release, leaving its bullets under no heading or under the first release's (review of https://github.com/STRML/cc-autodream/pull/83).

## Decision

The inserted `+` lines of the patch (minus the `+++` file header) go through `awk '!NF { print; next } /^## \[/ { hdr = $0 } !seen[hdr SUBSEP $0]++'`: every blank line is kept, and any other line is kept once per `## [` release header.

## Consequences

Do not widen the key to the whole window, and do not dedupe blank lines. Output is also capped, see `changelog-per-source-line-cap`.
