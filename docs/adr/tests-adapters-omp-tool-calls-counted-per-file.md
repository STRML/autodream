# tests-adapters: omp tool calls are counted per file from one source, and the fixtures hold both shapes

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-omp.sh` (the `tool_call_count` and `tools_used` group)

## Context

omp records a tool call in two shapes: a `custom/tool_execution_start` record and a `toolCall` block inside an assistant message. CLAUDE.md "The OMP adapter" states the rule: count the start records and fall back to the blocks only when the file has none. The fixtures matter because each alternative rule passes some real transcripts.

## Decision

- An advisor transcript has only the blocks (measured: 144 of 410 advisor files), so the fallback is exercised by a file with blocks and no start records.
- A main session holds each call as a record and as a block. The fixture holds both, and the assertion is that each call counts once. A union rule counts every main-session call twice.
- The rule is per file, not per call. A file with one start record and an unmatched block (not seen in the wild as a partial write, but 8 of 577 main transcripts hold blocks with no start record) reads the start records only, as it did before the fallback existed.
- An advisor whose every call was answered with `Tool "bash" not available` made attempts, not calls, and those must not clear the noise gate's `tool_call_count >= 5`. A real error from an available tool is still a call.

## Consequences

A fixture with only one shape cannot tell the per-file rule from a union. Keep the mixed and both-shapes files when adding cases.
