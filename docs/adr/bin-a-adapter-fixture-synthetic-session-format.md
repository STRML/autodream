# bin-a: the fixture adapter uses a session format that resembles neither real harness

Status: accepted · Date: 2026-11-21 · Code: `adapters/_fixture/adapter.sh`

## Context

The fixture exists to prove the adapter contract is a contract and not a description of what the claude adapter happens to do. A fixture shaped like a Claude transcript would pass by accident and keep passing if the contract quietly grew a Claude-specific assumption.

## Decision

A session is one JSON object per file (`*.fixture`) with `cwd` and `turns`. The leading underscore keeps it out of the default adapter set (`bin/adapters.sh` skips names starting with `_`), so a nightly run never sees it. It is small on purpose: `slim` is a copy, `engine-bin` is `true`, and the argv subcommands print `true` plus the model. Its write subcommands carry the same atomic-destination shape as the claude adapter (`bin-a-adapter-claude-atomic-destination-write.md`).

## Consequences

Keep the format unlike the real harnesses. `enumerate` ignores the date bounds because fixtures are not time-filtered.
