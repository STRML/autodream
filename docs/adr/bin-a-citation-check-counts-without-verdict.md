# bin-a: citation-check reports counts, never a verdict, and treats anything it cannot confirm as a defect

Status: accepted · Date: 2026-11-21 · Code: `bin/citation-check.sh` (verdict loop, exit codes)

## Context

L2 cites sessions by their 12-hex findings hash. On 2026-08-18 the top-ranked pattern quoted `47eba605cf1e` at "line 439/456/471" with a detailed `kSecUseAuthenticationUISkip` diagnosis. That session was noise-gated, so its findings record was a bare stub (`{"session_path":"...","skipped":"below_noise_gate","findings":[],"project":"-p"}`). The quote lived in `6f38f3cbed43`, a different session in the same project. The analysis was sound and the content real; only the ID was wrong, and an open question inherited it. A gated stub still carries `project`, which is what makes the wrong hash look plausible to the aggregator.

10 of 11 citations that night resolved correctly. That makes it a per-citation defect, the kind that survives review because spot-checking one or two citations passes.

## Decision

- The script counts and prints `KEY: VALUE` lines on stdout (`run.sh` appends them to `run-stats.txt`). It does no gating: the report still ships, and the morning review learns which citations not to trust.
- A cited hash whose findings record is a `below_noise_gate` stub is counted as `citations_to_gated`, the specific failure worth naming: the aggregator cited a session whose content it never received.
- Malformed JSON counts as unresolved, never clean. The point is to avoid a false all-clear.
- Exit 0 whenever the check ran, whatever it found. Exit 2 only when it could not run at all (missing report, missing findings dir, no `jq`), so a silent 0/0/0 cannot be mistaken for a clean report.

## Consequences

Making this check fail the run, or reading a missing `jq` as zero citations, turns a measurement into either a blocker or a false all-clear. `run.sh` records `unmeasured` for the three counters when the script exits non-zero.
