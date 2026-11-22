# bin-b: the in-session triage prompt and skip rule mirror review.sh by hand

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-band/hooks/lib.ts` (`triagePrompt`), `mods/autodream-band/hooks/register.tsx` (`nothingToTriage`)

## Context

`/dream here` walks the open questions in the current session. `bin/review.sh` has its own system prompt for the same walk and its own rule for when there is nothing to triage (already triaged, or no open questions, unless `--force`). CLAUDE.md ("The Claude Code mod") states the prompt is "modelled on review.sh's system prompt but not generated from it".

## Decision

`triagePrompt` copies the review.sh workflow with two deliberate differences: the report is read from its path rather than inlined (CLAUDE.md "The triage prompt is questions-only": never inline a long document into a system prompt), and this session's own permission mode applies, not `bypassPermissions`. `nothingToTriage` repeats review.sh's skip rule, and `force` overrides it in both.

## Consequences

Nothing keeps the copy in step. When review.sh's rules or skip condition change, check the prompt and `nothingToTriage` in the same change.
