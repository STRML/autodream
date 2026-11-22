# rest: plugin skills are found with find and no maxdepth, because the path shape already bounds the result

Status: accepted · Date: 2026-10-03 · Code: `adapters/omp/skills-inventory.sh` (the `find "$bucket/plugins"` loop)

## Context

Plugin skills live at arbitrary depth under `plugins/`. A `*` glob cannot cross `/`, so `find` with `-path '*/skills/*/SKILL.md'` is used. A fixed `-maxdepth` silently drops deeper skills: measured, 4 plugin `SKILL.md` files nested one level past an `-maxdepth 8` cut.

## Decision

No `-maxdepth`. The `*/skills/*/SKILL.md` path shape already bounds the result set. `find` errors go to `/dev/null`, and the skills are read through a process substitution so `scan_skill` runs in the main shell and sees the dedup state.

## Consequences

Adding a depth cap to speed up the walk loses skills with no error. The cost is a full walk of each plugin tree, which is acceptable for a nightly job.
