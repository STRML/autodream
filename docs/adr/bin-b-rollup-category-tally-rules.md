# bin-b: category tallies count an advisor under its parent and drop its tool-behavior findings

Status: accepted · Date: 2026-11-21 · Code: `bin/rollup.sh` (`tally_categories`)

## Context

An advisor sidecar overlaps its parent session by construction. Counting both double-counts a pattern the parent and its advisor both showed, which PROMPT.md rules out. L1 suppresses `sandbox_friction`, `tool_loop` and `missed_skill` for advisors, so one that arrives is a triage failure and not a pattern.

## Decision

- Each category gets a row per severity and a row with severity `all`. A session with a high and a low finding in one category counts once in the `all` row.
- A finding is counted under its owner: the parent when the row is an advisor with a parent, else the session itself. A parent and its advisor with the same finding are one session. The example hashes stay the real ones, capped at 5.
- An advisor's `sandbox_friction`, `tool_loop` and `missed_skill` findings are not counted. L2 reads them from `rollup.tsv` as triage failures.
- Each counted session is real or sandbox by the owner's `sandbox` flag. `weighted` is `sessions_real + floor(sessions_sandbox / 4)`.
- Rows are ordered by the category's total findings (descending), then category, then `all`, `high`, `medium`, `low`.

## Consequences

CLAUDE.md, "Where state lives" (the `categories.tsv` bullet), states the weighting and why L2 ranks by `weighted`. The `advisor_tool_findings` figure on stdout counts what this pass skipped. A new advisor-restricted category needs an entry in both `advisor_tool` in `tally_categories` and the regex in the stdout summary.
