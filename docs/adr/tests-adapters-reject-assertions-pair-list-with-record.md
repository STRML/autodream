# tests-adapters: every loader rejection test pairs an empty list with the refusal record

Status: accepted · Date: 2026-11-22 · Code: `tests/adapters.sh` (the rejection groups, the dispatch-guard group, the `adapter_l1_model` subshell counts)

## Context

An empty `adapters_list` cannot tell "the loader saw this and refused it" from "the glob never matched it". `"$root"/*/` never matched a dot-prefixed directory, so a malformed `.evil` was invisible rather than rejected and `adapters_rejected` reported `none`, which reads as "nothing was refused". It stayed that way until a test asked for the record (`bin-a-adapters-reject-log-is-a-file`).

## Decision

- Each rejection case asserts both an empty list and a named entry in `adapters_rejected`. Every rejection reaches `_adapter_reject` in `bin/adapters.sh`, so every one can say so.
- The dispatching functions (`adapter_run`, `adapter_manifest_get`) are tested with an unsafe name even though every caller today passes a name that came through `adapters_list`. The header of `bin/adapters.sh` argues that identity is the directory basename because dispatch builds a command path from it; that argument holds only if the dispatchers check. The test holds the guarantee for the third-party adapter that arrives later. A valid name is asserted to still work, so the guard is a check and not a blanket refusal.
- The `adapter_l1_model` assertions run in a subshell that writes `pass fail` to a counts file. A missing counts file means the subshell died before reporting and is itself a failure, because the assertions inside never reached the totals.

## Consequences

A new rejection rule needs both assertions. Do not read the counts file with a default of "no failures".
