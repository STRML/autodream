# tests-run-all: citation fixtures copy the real 2026-08-18 report shapes

Status: accepted · Date: 2026-11-22 · Code: `tests/run-all.sh` (`test_citation_check_*`, `mk_report`, `mk_findings`); rule in `docs/adr/bin-a-citation-check-any-12-hex-token.md`

## Context

On 2026-08-18 L2 attached a correct Bitwarden finding (in `6f38f3cbed43`) to `47eba605cf1e`, a different session in the same project that was noise-gated. A gated stub still carries `project`, which makes the wrong hash look plausible. 10 of 11 citations that night were sound, so the defect is per citation, and the counters exist to make it measurable.

## Decision

The fixtures keep the shapes that night produced:

- Bare hashes in a parenthesised comma list with no backticks, as the real pre-fix report wrote them. Anchoring only on backticks scored that report `citations_total: 0`, a false all-clear. The test keeps a bare fixture.
- A 40-character commit SHA, to prove boundary matching. Its neighbouring characters are hex, so a 12-hex run inside it is not a citation.
- An omp session file name ending in a UUID whose tail is 12 hex characters (`87b5b1392572` was the tail of `...2026-08-18T15-43-51-432Z_01a0158b-1488-7000-bf4a-87b5b1392572.jsonl`). L2 cites omp sessions by that tail, so it must resolve by session path. Reporting it as unresolved would train the reader to ignore the counter.

## Consequences

Replacing the SHA fixture with a short one, or backticking the bare list, leaves the assertions passing with the boundary and bare-form logic removed.
