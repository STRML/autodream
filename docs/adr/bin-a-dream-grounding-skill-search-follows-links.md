# bin-a: the installed-skill search follows symlinks and stops at depth 7

Status: accepted · Date: 2026-11-21 · Code: `bin/dream-grounding.sh` (skill listing `find -L ... -maxdepth 7`)

## Context

A skill linked in from elsewhere is still installed, so a search that does not follow links reports it as absent. A plugin cache holding many versions can make an unbounded walk a crawl.

## Decision

The skill listing uses `find -L` over each directory in `AUTODREAM_SKILL_DIRS`, with `-maxdepth 7`, matching `SKILL.md` files under a `skills/` path.

## Consequences

A skill nested deeper than seven levels is not listed and would be reported as `absent`. Raise the bound only with a measurement of the cost on a real plugin cache.
