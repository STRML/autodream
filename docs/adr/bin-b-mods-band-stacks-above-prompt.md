# bin-b: the band stacks under other plugins' rows and is one truncating row

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-band/hooks/register.tsx` (`AbovePrompt` render), `mods/autodream-band/tests/stand-in.tsx`

## Context

Other plugins and the engine draw in the `AbovePrompt` slot too. Replacing their output would silently remove their rows. Buttons next to a long summary wrap into several lines if the summary is allowed to.

## Decision

The render awaits `next(e)` and stacks the band beneath what it returns. The band is one row: the summary sits in a `flexGrow`/`flexShrink` box with `wrap="truncate-end"`, and the buttons in a `flexShrink={0}` box, so the summary takes the room the buttons leave and ends in an ellipsis. `stand-in.tsx` is a second plugin loaded in the `prepend` and `append` tiers to prove both the other row and the engine's row survive.

## Consequences

Tests find the band by `key: 'band'`; keep that key when restructuring the row.
