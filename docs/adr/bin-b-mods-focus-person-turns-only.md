# bin-b: only a person's own user turns, and any assistant reply, get a focus button

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-focus/hooks/register.tsx` (`isTypedByPerson`, `register`)

## Context

A `UserMessage` row is also a task notification or a peer's message, which are not the person's words and not theirs to tag.

## Decision

A user row gets the button only when `props.origin.kind` is `composer` (typed here) or `bridge` (typed from the phone). Assistant rows always do. A row with no text has nothing to tag either way (`withFocus`).

## Consequences

A new origin kind that carries the person's words (another input surface) must be added to `isTypedByPerson`, or its turns can never be tagged.
