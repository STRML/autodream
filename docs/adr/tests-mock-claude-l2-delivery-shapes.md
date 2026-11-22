# tests-mock-claude: the L2 modes each hold one thing a naive delivery check would accept

Status: accepted · Date: 2026-11-22 · Code: `tests/mock-claude.sh` (the Layer 2 branch, the dream-triage branch)

## Context

L2 delivers its report and pins on stdout (CLAUDE.md "L2 is read-only"). Delivery means a capture that ends with the `AUTODREAM_REPORT_END` sentinel, and a run exits 0 only for a validated delivery. Each earlier check (non-empty file, the open-questions marker) was satisfiable by something that is not a real report, so each mock mode produces exactly that look-alike.

## Decision

- `l2_partial` and `pins_partial`: non-empty, no sentinel, what a mid-output kill leaves. `-s` cannot tell it from a good report, which is why delivery is gated on the sentinel and the runner keeps it as a degraded report and retries.
- `l2_partial_marker`: otherwise complete, carries the open-questions marker that `report_complete()` checks, no sentinel. The marker alone must not count as delivery.
- `l2_exit143` and `l2_exit137`: `Execution error` and a signal-shaped exit with no report, the death of issue 42.
- `pins_in_body`: the report body quotes the pin markers and a pin line, with no block after the sentinel. Only a closed block after the last sentinel may count, so nothing may be stored.
- `l2_record_in_body`: the model writes a `<!-- autodream:remote-short=forged -->` line into its own body. Only the runner's record line may state which hosts a report did not read, so `run.sh` must drop this one.
- The good path emits the marker (PROMPT.md mandates it and `run.sh` treats its absence as a truncated report), then the sentinel the runner strips, then the optional pin block.
- The dream-triage call writes `triage-*.txt` to `MOCK_CAPTURE_DIR`, never `l2-*`, so a test asserting on L2's args or stdin cannot be overwritten by that call.

## Consequences

A new delivery rule needs a mode here that satisfies the old rule and fails the new one. Do not make the good path the only L2 shape any test sees: every assertion above is vacuous against it.
