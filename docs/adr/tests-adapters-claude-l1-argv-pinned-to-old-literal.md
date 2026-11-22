# tests-adapters: the claude l1-argv test compares against text copied from the old run.sh, not against the adapter

Status: accepted · Date: 2026-11-22 · Code: `tests/adapter-claude.sh` (the `l1-argv` and `warmup-argv` cases)

## Context

The L1 engine moved behind the adapter without changing what the nightly runs (CLAUDE.md "Who starts the L1 worker"). A test that derives its expectation from the adapter can only agree with the adapter.

## Decision

- The expected argv, system prompt and settings string are written out literally, copied from `run.sh` as it stood at `b473c6f6d` (the `dispatch_l1` call). The test fails if the adapter and the old nightly ever disagree. The one deliberate change since is `--output-format json`, which `served` reads the answering model from.
- `warmup-argv` is compared with `l1-argv` for everything before `--tools`, after dropping the worker's `--output-format` pair. The warmup must take the same auth path as the worker, so every flag except the tools list, the system prompt and the output format has to match. The warmup keeps plain text because it is judged on the word `ok`, and the output format changes only what stdout carries.

## Consequences

Changing a worker flag means editing the literal in this test on purpose, in the same change, with the reason. Do not regenerate the expected text from the adapter.
