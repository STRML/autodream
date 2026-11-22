# bin-b: sandbox-shape denies are counted here, anchored to the start of the tool result

Status: accepted · Date: 2026-11-21 · Code: `bin/session-stats.sh` (`$sandbox_shape_denies`)

## Context

L1 stopped scoring the sandbox-shape guard's denies as `sandbox_friction` (#175), so this count is the only place a session that keeps hitting the guard shows up. Each deny is a turn spent on a `dangerouslyDisableSandbox` the guard refused. A Read or grep of a file that mentions the guard holds the same words mid-text; measured 2026-11-03: 52 real denies and 1 such echo in one session. CLAUDE.md names the field under `rollup.tsv`.

## Decision

Count `tool_result` blocks with `is_error` true whose text (a string, or the joined text blocks) matches `\A\s*(<tool_use_error>)?\s*sandbox-shape: `, bare or inside `<tool_use_error>`.

## Consequences

Loosening the anchor makes quoted documentation count as denies. If the guard changes its prefix, change the pattern.
