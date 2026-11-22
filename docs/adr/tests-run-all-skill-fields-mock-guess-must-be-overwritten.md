# tests-run-all: skill-field fixtures lean on the mock worker's empty `skills_invoked`, so the assertions have power

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_skill_fields_dropped_without_a_sidecar`, `test_skill_fields_are_enforced_from_the_sidecar`), `tests/mock-claude.sh` (`write_findings`)

## Context

The runner overwrites `skills_invoked`, `skills_invoked_count`, `skills_invoked_counts` and `skills_authored` in every findings JSON from the stats sidecar. It removes all four when the sidecar is missing or lacks any of them (CLAUDE.md, "Skill fields are measured, not guessed"). A worker's own list is what let a report conclude "zero skills across 3,988 tool calls" on 2026-09-04, when the session had invoked skills.

## Decision

`tests/mock-claude.sh` always writes `skills_invoked:[]` in `write_findings`, which is the worker behavior behind that claim. The tests depend on it:

- The enforcement test builds a session that really invoked skills: two `Skill` calls, one `/triage` slash line and one SKILL.md write. It asserts the findings carry the sidecar's `deslop,triage`, the per-skill counts and the authored skill. A runner that believed the worker's empty list fails every one of those assertions.
- The no-sidecar test asserts all four keys are absent. With no sidecar to overwrite it, the mock's `[]` is a model guess that L2 would rank as a mechanical count.
- It also asserts `skills_unmeasured: 1` in run-stats. A missing field cannot say why it is missing: gated stubs and findings from before the fields existed lack them too, so the runner records the count.

## Consequences

If the mock's default findings carry real skill data, the enforcement assertions pass with the overwrite removed. Keep the mock's list empty, or give the enforcement fixture a session whose measured skills differ from whatever the mock writes.
