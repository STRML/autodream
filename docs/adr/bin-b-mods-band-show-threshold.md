# bin-b: the band shows a fresh report that is worth stopping for, and refreshes on three triggers

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-band/hooks/lib.ts` (`isFresh`, `shouldShow`), `mods/autodream-band/hooks/register.tsx` (`refresh`, `register`)

## Context

Reports are nightly, so a report two days old is news and a week old is not. PROMPT.md asks for `high|medium|low` severities, but the shipped example report also uses `critical`, which outranks `high`. A band that always showed would be wallpaper; one that stayed after a triage would nag about decided questions. The CLAUDE.md section "The Claude Code mod (`mods/autodream-band`)" lists the four report shapes the mod parses; this ADR records only the display rules built on them.

## Decision

- `isFresh` allows two days of age (the call in `refresh` passes `2`), compared by local calendar day.
- `shouldShow` is true only when the report is not triaged, is not the dismissed date, and has either open questions or a pattern with severity `critical`, `high` or `medium`. `low` and unknown never earn the band.
- A session can outlive the night, so `session.start` also arms a 30-minute `refresh`. A triage ends by logging decisions into the report, so `turn.complete` refreshes too and the band clears on the turn that ends it.

## Consequences

A new severity word in PROMPT.md needs a line in `WORTH_STOPPING_FOR`, or its reports never raise the band. The two-day window is a constant at the call site, not a setting.
