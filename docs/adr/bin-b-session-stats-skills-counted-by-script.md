# bin-b: skill invocation and authoring are counted by the stats script, as two fields

Status: accepted · Date: 2026-11-21 · Code: `bin/session-stats.sh` (the `$skills_invoked` and `$skills_authored` jq bindings)

## Context

The L1 model used to fill the skill fields in, and a guess ranked as a count is wrong. CLAUDE.md, "Skill fields are measured, not guessed", says the runner now overwrites them from this sidecar. "Wrote five skills, invoked none" is a different finding from "ignored the inventory", so the two cannot share a field.

## Decision

- Invocation is a `Skill` tool call (`input.skill`) or a slash command, which Claude Code records as a user line carrying `<command-name>/name</command-name>`.
- Authoring is a `Write`, `Edit` or `MultiEdit` whose path is a `SKILL.md` under a `skills/` directory.
- Claude Code's own commands (`/clear`, `/model` and the rest of the list in the jq `IN(...)` filter) are not skills. The list is best effort: a command added later counts as a skill until it is named there.

## Consequences

Update the built-in command list when Claude Code adds a command, or a session that only ran it measures as having invoked a skill.
