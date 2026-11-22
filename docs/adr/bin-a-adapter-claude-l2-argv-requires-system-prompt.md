# bin-a: l2-argv exposes only Glob and Read, and produces no argv when the system prompt file is missing

Status: accepted · Date: 2026-11-21 · Code: `adapters/claude/adapter.sh` (`l2-argv`)

## Context

L2 returns the report and the pins on stdout and the runner is the only writer, so an injected L2 cannot rewrite `sessions-source.txt` or forge a pin (CLAUDE.md, "L2 is read-only"). The system prompt, `prompts/L2_SYSTEM.txt`, is what tells the engine where the report goes.

## Decision

Tools are `Glob Read`. The model is optional, and absent means the CLI's own default, so an upgrade of the account upgrades the nightly report with nothing edited here. The system prompt is read through the loader (`bin/l2-prompt.sh`). No file means exit 2 and no argv: an engine started without it would run L2 with no word on where the report goes.

## Consequences

Giving L2 a write tool breaks the read-only guarantee the runner's pin and report handling depends on.
