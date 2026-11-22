# bin-b: the mod hands the writer one code point past its cap, counted in code points

Status: accepted · Date: 2026-11-21 · Code: `mods/autodream-focus/hooks/focus-lib.ts` (`TEXT_CAP`, `forWriter`)

## Context

`bin/autodream-focus.sh` cuts a turn at 2,000 characters and marks the cut with an ellipsis, so `TEXT_CAP` mirrors that number. The writer only marks a cut when it sees more than the cap. CLAUDE.md "The focus mod" records that the writer counts code points: a cut in UTF-16 units left an emoji turn under the cap with no ellipsis and could keep half a surrogate pair.

## Decision

`forWriter` returns `TEXT_CAP + 1` code points (`Array.from`) when the text is longer, else the text unchanged.

## Consequences

If the writer's cap changes, change `TEXT_CAP` in the same commit. The test `a long turn is handed over one character past the writer's cap` pins 2,001.
