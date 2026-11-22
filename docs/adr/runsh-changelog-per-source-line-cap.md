# runsh: each changelog section is capped by line count, and a bad cap falls back to 400

Status: accepted · Date: 2026-11-22 · Code: `bin/run.sh` (`changelog_one`, `AUTODREAM_CHANGELOG_MAX_LINES`)

## Context

One chatty monorepo must not crowd the other harnesses out of L2's context, so the cap is per section: a quiet source is never truncated for a loud one. A non-numeric cap made the `-gt` test error out as false under `set -u` without `-e`, so the section went out uncapped (debate review of e95e2f2). A pattern test is not enough: `00` is all digits and still zero, and `head -n 00` then fails and drops the section's content.

## Decision

`cap` is `AUTODREAM_CHANGELOG_MAX_LINES` (default 400). It is validated by a pattern check that it is digits and then numerically that it is greater than 0; otherwise a log line says it is not a positive integer and 400 is used. When the deduped section exceeds the cap it is cut with `head -n` and an explicit `[...truncated: N lines in window, showing first CAP. Raise AUTODREAM_CHANGELOG_MAX_LINES to see the rest.]` line is appended.

## Consequences

Truncation must stay explicit, never silent. Keep the cap per section. Do not validate the cap by pattern alone. `test_changelog_refuses_foreign_cache_dir` pins that `abc` and `00` fall back to 400.
