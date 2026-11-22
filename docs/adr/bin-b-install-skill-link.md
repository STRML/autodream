# bin-b: the global /autodream skill is linked only when it cannot break the install or point at nothing

Status: accepted · Date: 2026-11-21 · Code: `install.sh` (the `SKILL` block)

## Context

A skill nobody asked for must not fail the install. Claude Code reads `~/.claude/skills`, and the skill calls the scripts at `~/.claude/autodream` unless `AUTODREAM_DIR` says otherwise. The user may already own an `/autodream` skill.

## Decision

- A custom install directory links the skill only when `AUTODREAM_SKILLS_DIR` says where the user wants it, because a skill linked from a custom target cannot find the scripts. Otherwise the installer prints how to opt in.
- A link or directory already at the skill's place is the user's: only an earlier link to this repo's skill is replaced. Anything else is reported to stderr and left, and a failed link is a warning, not an install failure.

## Consequences

`tests/install-skill.sh` pins each branch. A new skill link should follow the same "not ours, leave it" rule.
