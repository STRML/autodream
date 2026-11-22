# bin-a: a citation is any standalone 12-hex token, so a stray token is a false alarm and never a false all-clear

Status: accepted · Date: 2026-11-21 · Code: `bin/citation-check.sh` (`hashes` pipeline)

## Context

L2 formats citations in two shapes that vary run to run: backticked (`` `47eba605cf1e` ``) and bare in a comma list (`(c7b79782412d, 98e07eeaad42, ...)`). Matching only the backticked form scored the 2026-08-18 pre-fix report at `citations_total: 0`, a false all-clear, which is the one output this check exists to prevent.

## Decision

A citation is any 12-hex run whose neighbours are not hex. A 40-character commit SHA is not split into citations, and a 7-character short SHA is too short to match.

The bias is deliberate and one-directional: a stray hex token surfaces as unresolved, a false alarm a human dismisses in seconds, and never as a clean report. The substantive-session filter makes the same judgement when it keeps an unparseable session rather than dropping it.

The pipeline replaces every non-hex character with a space, splits to one token per line, and keeps tokens that are exactly 12 hex characters. That gives the boundary rule without `\K`, which BSD `grep` lacks.

## Consequences

Tightening the pattern to the backticked form brings back the false all-clear. `dream-grounding.sh` excludes the same 12-hex spans from its sha claims so the two checks do not overlap (see `bin-a-dream-grounding-fixed-checks-in-code`).
