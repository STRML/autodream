# bin-b: the in-session triage prompt is submitted from a 100 ms timer

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-band/hooks/register.tsx` (`triageHere`), `mods/autodream-band/tests/hooks.test.tsx` (`world`, `landed`)

## Context

`$.prompt.submit` resolves when the new turn starts, and a call begun inside a dispatch (a button press, a slash command) is dropped when that dispatch ends. Awaiting it inside the handler would either block the reply or lose the prompt.

## Decision

`triageHere` returns its reply text at once and schedules the submit with `$.clock.after(100, ...)`, outside the dispatch. A rejected submit is swallowed.

## Consequences

Tests that expect a prompt must let the timer fire: the mock clock exposes `landed()` for that, and a test that skips it sees `sent` empty.
