# bin-b: the jq pre-pass strips tool payloads for both the Claude Code and the OMP schema

Status: accepted · Date: 2026-11-21 · Code: `bin/slim-transcript.sh` (the pre-pass `jq` program)

## Context

Two transcript schemas store tool output in different places: Claude Code in `tool_result` blocks inside `.message.content`, OMP in whole records with `.message.role == "toolResult"` carrying the payload in `.message.details` and `.message.content`, plus a `.message.providerPayload` blob on assistant turns.

Handling only the first is worse than doing nothing. jq still exits 0 and writes a valid file, so the fallback never fires, and the line pass then spends its 400-character budget on about 190 characters of OMP envelope (`id`, `parentId`, `timestamp`, `toolCallId`, `toolName`) and cuts off at `"content":[`. The worker gets ID soup with no payload and no goal, and returns no findings.

## Decision

Both schemas are stripped in the pre-pass. The line-based head/tail/cut pass still runs after it as a safety net, and the script falls back to it when jq is missing or the stream is not parseable JSONL.

## Consequences

A new transcript schema needs its payload location added to the pre-pass, not only a test that jq exits 0. `tests/slim-transcript.sh` covers both schemas.
